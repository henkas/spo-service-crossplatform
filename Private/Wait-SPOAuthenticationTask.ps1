function Wait-SPOAuthenticationTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Threading.Tasks.Task]$Task
    )

    # Poll via Start-Sleep instead of blocking on GetAwaiter().GetResult() so
    # Ctrl+C escapes promptly. The vendor's native thread is otherwise
    # uninterruptible and makes the user sit through OAuthSession's internal
    # timeout if they close the browser tab. GetAwaiter().GetResult() after the
    # loop preserves exception unwrapping (no AggregateException).
    while (-not $Task.IsCompleted) {
        Start-Sleep -Milliseconds 250
    }

    $null = $Task.GetAwaiter().GetResult()
}
