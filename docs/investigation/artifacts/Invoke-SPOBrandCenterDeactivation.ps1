param(
    [Parameter(Mandatory = $true)]
    [uri]$AdminUrl,

    [string]$EnvPath = (Join-Path (Get-Location) '.env'),

    [string]$CertificatePath = (Join-Path (Get-Location) 'app.pfx')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LocalEnvMap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Environment file not found: $Path"
    }

    $map = @{}
    foreach ($line in Get-Content $Path) {
        if ($line -match '^\s*#' -or $line -notmatch '=') {
            continue
        }

        $key, $value = $line -split '=', 2
        $map[$key.Trim()] = $value.Trim()
    }

    foreach ($required in 'ClientId', 'TenantId', 'password') {
        if (-not $map.ContainsKey($required) -or [string]::IsNullOrWhiteSpace($map[$required])) {
            throw "Missing '$required' in $Path"
        }
    }

    return $map
}

if (-not (Test-Path $CertificatePath)) {
    throw "Certificate file not found: $CertificatePath"
}

Import-Module Microsoft.Online.SharePoint.PowerShell -ErrorAction Stop -WarningAction SilentlyContinue
$moduleBase = (Get-Module Microsoft.Online.SharePoint.PowerShell | Select-Object -First 1).ModuleBase
Add-Type -Path (Join-Path $moduleBase 'microsoft.identity.client.dll')

$envMap = Get-LocalEnvMap -Path $EnvPath
$certificatePassword = ConvertTo-SecureString $envMap.password -AsPlainText -Force
$certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath, $certificatePassword)
$resourceScope = "$($AdminUrl.Scheme)://$($AdminUrl.Host)/.default"

$app = [Microsoft.Identity.Client.ConfidentialClientApplicationBuilder]::Create($envMap.ClientId).
    WithAuthority("https://login.microsoftonline.com/$($envMap.TenantId)", $false).
    WithCertificate($certificate).
    Build()

$tokenResult = $app.AcquireTokenForClient([string[]]@($resourceScope)).ExecuteAsync().GetAwaiter().GetResult()
$headers = @{
    Authorization = "Bearer $($tokenResult.AccessToken)"
    Accept        = 'application/json;odata=nometadata'
}

$digestResponse = Invoke-RestMethod -Method Post -Uri "$($AdminUrl.AbsoluteUri.TrimEnd('/'))/_api/contextinfo" -Headers $headers
$digest = $digestResponse.FormDigestValue

$context = [Microsoft.SharePoint.Client.ClientContext]::new($AdminUrl.AbsoluteUri)
$tenant = [Microsoft.Online.SharePoint.TenantAdministration.Tenant]::new($context)
$tenant.DeactivateBrandCenterFeatures()
$request = $context.PendingRequest
$setupQuery = $request.GetType().GetMethod('SetupQuery', [System.Reflection.BindingFlags]'NonPublic,Instance')
$queryBuilder = $setupQuery.Invoke($request, @())
$processQueryBody = $queryBuilder.CreateTextReader().ReadToEnd()

$response = Invoke-WebRequest `
    -Method Post `
    -Uri "$($AdminUrl.AbsoluteUri.TrimEnd('/'))/_vti_bin/client.svc/ProcessQuery" `
    -ContentType 'text/xml' `
    -Body $processQueryBody `
    -Headers (@{
        Authorization   = "Bearer $($tokenResult.AccessToken)"
        'X-RequestDigest' = $digest
    })

$payload = $response.Content | ConvertFrom-Json
$meta = $payload[0]

if ($meta.ErrorInfo -ne $null) {
    if ($meta.ErrorInfo.ErrorMessage -eq 'No active Brand Center features found') {
        [pscustomobject]@{
            Success            = $true
            AlreadyInactive    = $true
            AdminUrl           = $AdminUrl.AbsoluteUri
            TraceCorrelationId = $meta.ErrorInfo.TraceCorrelationId
            LibraryVersion     = $meta.LibraryVersion
        } | ConvertTo-Json -Compress
        return
    }

    throw "Brand Center deactivation failed: $($meta.ErrorInfo | ConvertTo-Json -Depth 8 -Compress)"
}

[pscustomobject]@{
    Success            = $true
    AlreadyInactive    = $false
    AdminUrl           = $AdminUrl.AbsoluteUri
    TraceCorrelationId = $meta.TraceCorrelationId
    LibraryVersion     = $meta.LibraryVersion
} | ConvertTo-Json -Compress
