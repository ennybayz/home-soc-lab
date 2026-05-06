<#
.SYNOPSIS
    First-time bring-up of home-soc-lab on Windows (no WSL needed).

.DESCRIPTION
    PowerShell equivalent of bootstrap.sh. Generates SSL certificates, builds
    the custom ubuntu-target image, and starts the Wazuh + targets stack.
    Re-running is safe: cert generation skips already-issued material.

.EXAMPLE
    .\scripts\setup\bootstrap.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoRoot  = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$DockerDir = Join-Path $RepoRoot 'docker'

Write-Host "==> [1/4] Checking prerequisites" -ForegroundColor Cyan
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker is not on PATH. Install Docker Desktop from https://docker.com/products/docker-desktop"
}
$composeProbe = & docker compose version 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Docker Compose v2 is not available. Update Docker Desktop."
}

Push-Location $DockerDir
try {
    Write-Host "==> [2/4] Preparing .env" -ForegroundColor Cyan
    if (-not (Test-Path .env)) {
        Copy-Item .env.example .env
        Write-Host "    .env copied from .env.example - edit it to rotate the demo passwords" -ForegroundColor Yellow
    } else {
        Write-Host "    .env already exists, leaving it alone"
    }

    Write-Host "==> [3/4] Generating SSL certificates" -ForegroundColor Cyan
    docker compose -f generate-certs.yml run --rm generator
    if ($LASTEXITCODE -ne 0) { throw "Certificate generation failed" }
    Write-Host "    certs written to $DockerDir\wazuh\config\wazuh_indexer_ssl_certs\"

    Write-Host "==> [4/4] Building images and starting stack" -ForegroundColor Cyan
    docker compose pull --ignore-buildable
    if ($LASTEXITCODE -ne 0) { throw "docker compose pull failed" }
    docker compose build
    if ($LASTEXITCODE -ne 0) { throw "docker compose build failed" }
    docker compose up -d
    if ($LASTEXITCODE -ne 0) { throw "docker compose up failed" }
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "Stack is starting. Give it ~2 minutes for the indexer to become healthy." -ForegroundColor Green
Write-Host "  Dashboard:    https://localhost                   (admin / value of INDEXER_PASSWORD)"
Write-Host "  DVWA:         http://localhost:8080               (admin / password)"
Write-Host "  Ubuntu host:  ssh -p 2222 labuser@localhost       (password: Password1)"
Write-Host ""
Write-Host "Tip: tail the indexer logs while you wait:" -ForegroundColor Gray
Write-Host "  docker logs -f wazuh.indexer" -ForegroundColor Gray
