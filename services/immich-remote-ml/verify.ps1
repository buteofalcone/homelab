[CmdletBinding()]
param(
    [string]$ContainerName = 'immich_remote_machine_learning'
)

$ErrorActionPreference = 'Stop'

Write-Output 'STEP_IMMICH_ML_CONTAINER'
$status = (& docker.exe inspect $ContainerName --format '{{.State.Status}}').Trim()
$health = (& docker.exe inspect $ContainerName --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}').Trim()
if ($status -ne 'running') {
    throw "Remote ML container is not running: $status"
}

$deadline = (Get-Date).AddMinutes(10)
while ($health -notin @('healthy', 'none')) {
    if ((Get-Date) -ge $deadline) {
        & docker.exe logs --tail 100 $ContainerName | Out-Host
        throw "Remote ML container did not become healthy: $health"
    }
    Start-Sleep -Seconds 5
    $health = (& docker.exe inspect $ContainerName --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}').Trim()
}
Write-Output "CONTAINER status=$status health=$health"

Write-Output 'STEP_IMMICH_ML_CUDA_PROVIDER'
$providerOutput = & docker.exe exec $ContainerName python -c "import onnxruntime as ort; print(ort.get_available_providers())"
if ($LASTEXITCODE -ne 0 -or ($providerOutput -join "`n") -notmatch 'CUDAExecutionProvider') {
    & docker.exe logs --tail 100 $ContainerName | Out-Host
    throw 'CUDAExecutionProvider is unavailable inside Immich Remote ML.'
}
$providerOutput | Out-Host

Write-Output 'IMMICH_REMOTE_ML_VERIFY_OK'
