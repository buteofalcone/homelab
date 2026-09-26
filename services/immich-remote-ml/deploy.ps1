[CmdletBinding()]
param(
    [string]$SilverBrickAddress = '100.91.171.26'
)

$ErrorActionPreference = 'Stop'
$serviceDirectory = $PSScriptRoot
$composeFile = Join-Path $serviceDirectory 'compose.yaml'
$env:SILVERBRICK_TAILSCALE_IP = $SilverBrickAddress

if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) {
    throw 'docker.exe is not available.'
}

Write-Output 'STEP_IMMICH_ML_COMPOSE_VALIDATE'
& docker.exe compose -f $composeFile config --quiet
if ($LASTEXITCODE -ne 0) {
    throw 'Immich Remote ML Compose validation failed.'
}

Write-Output 'STEP_IMMICH_ML_PULL'
& docker.exe compose -f $composeFile pull
if ($LASTEXITCODE -ne 0) {
    throw 'Immich Remote ML image pull failed.'
}

Write-Output 'STEP_IMMICH_ML_START'
& docker.exe compose -f $composeFile up -d
if ($LASTEXITCODE -ne 0) {
    throw 'Immich Remote ML start failed.'
}

Write-Output 'IMMICH_REMOTE_ML_DEPLOY_OK'
