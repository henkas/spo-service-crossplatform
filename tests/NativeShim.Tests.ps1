<#
    Native shim contract that PowerShell can verify without a tenant. Needs the
    built shim (as CI does) but not the vendor module.

    BackgroundInvoker exists because the vendor's OAuthSession.SignIn(string) is
    async in name only: it blocks the calling thread until sign-in completes or
    its 90-second timer fires. Invoking it on the thread pool lets the
    PowerShell thread poll with an interruptible sleep, so Ctrl+C returns the
    prompt instead of waiting out the vendor.
#>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$script:ModuleRoot = $repo
. (Join-Path $repo 'Private/Assert-NativeShim.ps1')
. (Join-Path $repo 'Private/Wait-SPOAuthenticationTask.ps1')
Assert-NativeShim
$failures = [System.Collections.Generic.List[string]]::new()

$invoker = 'SPOService.CrossPlatform.BackgroundInvoker' -as [type]
if (-not $invoker) { throw 'Shim is missing SPOService.CrossPlatform.BackgroundInvoker.' }

# A method that blocks the calling thread for a while, like the vendor sign-in.
$sleep = [System.Threading.Thread].GetMethod('Sleep', [type[]]@([int]))

# 1. The outer task is not complete on return: the caller can poll instead of blocking.
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$task = $invoker::InvokeAsync($sleep, $null, [object[]]@(1500))
$returnedAfterMs = $sw.ElapsedMilliseconds
if ($task -isnot [System.Threading.Tasks.Task]) { $failures.Add('InvokeAsync must return a Task.') }
if ($returnedAfterMs -gt 500) { $failures.Add("InvokeAsync blocked the caller for ${returnedAfterMs}ms; it must return immediately.") }
if ($task.IsCompleted) { $failures.Add('The task must still be running right after InvokeAsync returns for a blocking method.') }
if (-not $task.Wait(10000)) { $failures.Add('The blocking method never completed on the background thread.') }

# 2. The wait helper drives the same task to completion and returns normally.
$task2 = $invoker::InvokeAsync($sleep, $null, [object[]]@(300))
Wait-SPOAuthenticationTask -Task $task2
if (-not $task2.IsCompletedSuccessfully) { $failures.Add('Wait-SPOAuthenticationTask should leave a successful task completed.') }

# 3. The wait helper unwraps a nested Task result, as the vendor returns a completed Task.
$fromResult = [System.Threading.Tasks.Task].GetMethod('FromResult').MakeGenericMethod([int])
$task3 = $invoker::InvokeAsync($fromResult, $null, [object[]]@(42))
Wait-SPOAuthenticationTask -Task $task3   # must not throw
if (-not $task3.IsCompletedSuccessfully) { $failures.Add('Nested completed Task result should be accepted.') }

# 4. Exceptions surface as the original type, not TargetInvocationException.
$throwing = [System.IO.File].GetMethod('ReadAllText', [type[]]@([string]))
$missing = Join-Path ([IO.Path]::GetTempPath()) ('spo-shim-test-' + [guid]::NewGuid().ToString('N') + '.txt')
$task4 = $invoker::InvokeAsync($throwing, $null, [object[]]@([string]$missing))
try {
    Wait-SPOAuthenticationTask -Task $task4
    $failures.Add('A throwing method should surface its exception through the wait helper.')
} catch {
    $ex = $_.Exception
    while ($ex -is [System.Management.Automation.MethodInvocationException] -and $ex.InnerException) { $ex = $ex.InnerException }
    if ($ex -isnot [System.IO.FileNotFoundException]) { $failures.Add("Expected FileNotFoundException, got $($ex.GetType().FullName): $($ex.Message)") }
}

# 5. A null method is rejected up front.
try { $null = $invoker::InvokeAsync($null, $null, [object[]]@()); $failures.Add('Null method should be rejected.') }
catch { if ($_.Exception.Message -notmatch 'method') { $failures.Add("Null method rejection had an unexpected message: $($_.Exception.Message)") } }

# 6/7. Older shims are refused with actionable advice, not a later
#      type-resolution error. A stand-in DLL named like the real shim, without
#      BackgroundInvoker, plays the older build in two child sessions:
#      6 loads it first (an rc1 session upgraded in place); 7 finds it on disk
#      as the first candidate (a stale bin/net10.0 copy).
$staleRoot = Join-Path ([IO.Path]::GetTempPath()) ('spo-stale-shim-' + [guid]::NewGuid().ToString('N'))
$staleDll = Join-Path $staleRoot 'bin/net10.0/SPOService.CrossPlatform.dll'
$null = New-Item -ItemType Directory -Force -Path (Split-Path $staleDll)
& pwsh -NoProfile -NonInteractive -Command "Add-Type -TypeDefinition 'namespace SPOService.CrossPlatform { public class HttpClientExecutorFactory { } }' -OutputAssembly '$staleDll' -OutputType Library" 2>&1 | Out-Null
$helperPath = Join-Path $repo 'Private/Assert-NativeShim.ps1'
function Invoke-ShimChild([string]$Preload, [string]$Root) {
    $child = @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
`$preload = '$Preload'
if (`$preload) { Add-Type -Path `$preload }
`$script:ModuleRoot = '$Root'
. '$helperPath'
try { Assert-NativeShim; 'NO-ERROR' } catch { `$_.Exception.Message }
"@
    & pwsh -NoProfile -NonInteractive -Command $child 2>&1 | Out-String
}
$olderOut = Invoke-ShimChild -Preload $staleDll -Root $repo
$staleOut = Invoke-ShimChild -Preload '' -Root $staleRoot
Remove-Item -Recurse -Force -LiteralPath $staleRoot -ErrorAction SilentlyContinue
$olderOk = $olderOut -match 'older SPOService\.CrossPlatform\.dll is already loaded' -and $olderOut -match 'new pwsh session'
$staleOk = $staleOut -match 'out of date' -and $staleOut -match [regex]::Escape('bin/net10.0/SPOService.CrossPlatform.dll')
$failures.AddRange([string[]]@(@("An older loaded shim should be refused with new-session advice; got: $olderOut") | Where-Object { -not $olderOk }))
$failures.AddRange([string[]]@(@("A stale shim DLL on disk should be refused after loading; got: $staleOut") | Where-Object { -not $staleOk }))

if ($failures.Count) { throw ("Native shim contract failed:`n" + ($failures -join "`n")) }
Write-Information 'Native shim contract: background invoke is pollable, wait helper completes, unwraps nested tasks, surfaces original exceptions, refuses an older loaded or stale on-disk shim.' -InformationAction Continue
