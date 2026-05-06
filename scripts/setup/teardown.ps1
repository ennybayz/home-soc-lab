<#
.SYNOPSIS
    Stops the home-soc-lab stack on Windows. Use -Wipe to also delete volumes
    and generated certificates.

.EXAMPLE
    .\scripts\setup\teardown.ps1
    .\scripts\setup\teardown.ps1 -Wipe
#>

[CmdletBinding()]
param(
    [switch]$Wipe
)

$ErrorActionPreference = 'Stop'

$RepoRoot  = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$DockerDir = Join-Path $RepoRoot 'docker'

Push-Location $DockerDir
try {
    if ($Wipe) {
        Write-Host "==> Removing containers and volumes" -ForegroundColor Cyan
        docker compose down -v
        Write-Host "==> Removing generated certs" -ForegroundColor Cyan
        $certDir = Join-Path $DockerDir 'wazuh\config\wazuh_indexer_ssl_certs'
        if (Test-Path $certDir) {
            Get-ChildItem $certDir -Force | Remove-Item -Recurse -Force
        }
    } else {
        Write-Host "==> Removing containers (keeping volumes)" -ForegroundColor Cyan
        docker compose down
        Write-Host "    pass -Wipe to also delete volumes and certs" -ForegroundColor Gray
    }
}
finally {
    Pop-Location
}
