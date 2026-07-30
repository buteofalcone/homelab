[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Test-Command {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

Write-Output 'STEP_SILVERBRICK_PREREQUISITES'

if (-not (Test-Command 'wsl.exe')) {
    throw 'WSL is missing. Enable WSL2 before installing Docker Desktop.'
}

$wslVersionText = (& wsl.exe --version 2>&1 | Out-String) -replace "`0", ''
if ($LASTEXITCODE -ne 0 -or $wslVersionText -notmatch '2\.(\d+)\.(\d+)') {
    throw 'WSL 2.1.5 or newer is required. Run wsl --update from an elevated PowerShell window.'
}

if (-not (Test-Command 'nvidia-smi.exe')) {
    throw 'The NVIDIA Windows driver is missing.'
}

$driverVersion = (& nvidia-smi.exe --query-gpu=driver_version --format=csv,noheader | Select-Object -First 1).Trim()
if ([version]$driverVersion -lt [version]'545.0') {
    throw "NVIDIA driver $driverVersion is too old; Immich CUDA requires 545 or newer."
}

if (-not (Test-Command 'winget.exe')) {
    throw 'Windows Package Manager (winget) is required for the reproducible Docker Desktop installation.'
}

if (-not (Test-Command 'docker.exe')) {
    Write-Output 'STEP_DOCKER_DESKTOP_INSTALL'
    & winget.exe install --id Docker.DockerDesktop --exact --source winget `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "Docker Desktop installation failed with exit code $LASTEXITCODE."
    }
}

$dockerDesktopCandidates = @(
    (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\Docker Desktop.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Docker\Docker\Docker Desktop.exe')
)
$dockerDesktop = $dockerDesktopCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) {
    if (-not $dockerDesktop) {
        throw 'Docker Desktop was installed, but its executable was not found.'
    }
    Write-Output 'STEP_DOCKER_DESKTOP_START'
    Start-Process -FilePath $dockerDesktop
}

Write-Output 'Docker Desktop may need a first-run confirmation. Wait until it reports that the engine is running.'
Write-Output "SILVERBRICK_DOCKER_INSTALL_OK nvidia_driver=$driverVersion"
