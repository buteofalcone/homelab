[CmdletBinding()]
param(
    [string]$SilverBrickAddress = '100.91.171.26'
)

$ErrorActionPreference = 'Stop'

Write-Output 'STEP_SILVERBRICK_DOCKER'
if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) {
    throw 'docker.exe is not available. Install and start Docker Desktop first.'
}
& docker.exe version | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw 'Docker Desktop is installed but its Linux engine is not ready.'
}

Write-Output 'STEP_SILVERBRICK_TAILSCALE'
$tailscaleAddress = (& tailscale.exe ip -4 | Select-Object -First 1).Trim()
if ($tailscaleAddress -ne $SilverBrickAddress) {
    throw "Expected SilverBrick Tailscale address $SilverBrickAddress, found $tailscaleAddress."
}

Write-Output 'STEP_SILVERBRICK_NVIDIA'
$gpu = (& nvidia-smi.exe --query-gpu=name,driver_version,memory.total --format=csv,noheader | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'nvidia-smi failed on Windows.'
}
Write-Output "GPU $gpu"

Write-Output 'STEP_DOCKER_CUDA_SMOKE'
& docker.exe run --rm --gpus all nvidia/cuda:12.3.2-base-ubuntu22.04 nvidia-smi
if ($LASTEXITCODE -ne 0) {
    throw 'The isolated CUDA container could not access the NVIDIA GPU.'
}

Write-Output 'SILVERBRICK_CUDA_AUDIT_OK'
