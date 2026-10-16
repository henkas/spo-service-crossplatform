function Wait-SPOAuthenticationTask {
    <#
    .SYNOPSIS
        Polls a background sign-in task so Ctrl+C returns the prompt promptly.
    .DESCRIPTION
        The vendor's OAuthSession.SignIn(string) blocks its calling thread until
        sign-in completes or its own 90-second timer fires (it is async in name
        only). Callers therefore run it through BackgroundInvoker.InvokeAsync and
        pass the resulting task here. Polling with Start-Sleep keeps the
        PowerShell thread interruptible: Ctrl+C stops the loop within a quarter
        second. The vendor thread then runs on until its timeout; the vendor
        API exposes no cancellation token, so nothing can stop it sooner.

        GetAwaiter().GetResult() surfaces the original exception rather than an
        AggregateException. When the invoked method itself returned a Task (as
        SignIn does), that inner task is awaited too so its fault surfaces.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Threading.Tasks.Task]$Task
    )

    while (-not $Task.IsCompleted) {
        Start-Sleep -Milliseconds 250
    }

    $result = $Task.GetAwaiter().GetResult()
    if ($result -is [System.Threading.Tasks.Task]) {
        while (-not $result.IsCompleted) {
            Start-Sleep -Milliseconds 250
        }
        $null = $result.GetAwaiter().GetResult()
    }
}
