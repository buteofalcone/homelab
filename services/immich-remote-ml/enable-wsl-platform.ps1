[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must be run as Administrator.'
}

Write-Output 'STEP_WINDOWS_VIRTUALIZATION_FEATURES'
$restartNeeded = $false
$featureNames = @(
    'Microsoft-Windows-Subsystem-Linux',
    'VirtualMachinePlatform'
)

foreach ($featureName in $featureNames) {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName
    Write-Output ("FEATURE name={0} state={1}" -f $feature.FeatureName, $feature.State)
    if ($feature.State -ne 'Enabled') {
        $result = Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart
        $restartNeeded = $restartNeeded -or [bool]$result.RestartNeeded
        Write-Output ("FEATURE_ENABLED name={0} restart_needed={1}" -f $featureName, $result.RestartNeeded)
    }
}

if ($restartNeeded) {
    Write-Output 'WSL_PLATFORM_ENABLED_RESTART_REQUIRED'
} else {
    Write-Output 'WSL_PLATFORM_ENABLED_OK'
}
