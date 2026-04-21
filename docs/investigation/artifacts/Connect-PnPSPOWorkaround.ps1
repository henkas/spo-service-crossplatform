Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LocalEnvMap {
    param(
        [string]$Path = (Join-Path (Get-Location) '.env')
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

function Connect-PnPSPOWorkaround {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$Url,

        [string]$EnvPath = (Join-Path (Get-Location) '.env'),

        [string]$CertificatePath = (Join-Path (Get-Location) 'app.pfx'),

        [switch]$ReturnConnection
    )

    if (-not (Test-Path $CertificatePath)) {
        throw "Certificate file not found: $CertificatePath"
    }

    Import-Module PnP.PowerShell -ErrorAction Stop

    $envMap = Get-LocalEnvMap -Path $EnvPath
    $certificatePassword = ConvertTo-SecureString $envMap.password -AsPlainText -Force

    Connect-PnPOnline `
        -Url $Url.AbsoluteUri `
        -ClientId $envMap.ClientId `
        -Tenant $envMap.TenantId `
        -CertificatePath $CertificatePath `
        -CertificatePassword $certificatePassword

    if ($ReturnConnection) {
        return Get-PnPConnection
    }
}
