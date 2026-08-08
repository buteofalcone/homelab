[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must be run as Administrator.'
}

Write-Output 'STEP_WINDOWS_HYPERVISOR_BOOT_AUDIT'
$entryBefore = (& bcdedit.exe /enum '{current}' | Out-String)
if ($LASTEXITCODE -ne 0) {
    throw 'Could not read the current Windows boot entry.'
}

$currentSetting = if ($entryBefore -match '(?im)^hypervisorlaunchtype\s+(\S+)') { $Matches[1] } else { 'Auto (default)' }
Write-Output "HYPERVISOR_LAUNCH_BEFORE value=$currentSetting"

if ($currentSetting -eq 'Off') {
    & bcdedit.exe /set '{current}' hypervisorlaunchtype Auto | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not enable Windows hypervisor launch.'
    }
}

$entryAfter = (& bcdedit.exe /enum '{current}' | Out-String)
if ($entryAfter -notmatch '(?im)^hypervisorlaunchtype\s+Auto\s*$') {
    throw 'Windows boot entry does not report hypervisorlaunchtype Auto.'
}

Write-Output 'WINDOWS_HYPERVISOR_AUTO_RESTART_REQUIRED'
