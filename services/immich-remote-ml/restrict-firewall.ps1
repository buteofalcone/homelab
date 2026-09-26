[CmdletBinding()]
param(
    [string]$SilverBrickAddress = '100.91.171.26',
    [string]$HpServerAddress = '100.65.83.35',
    [ValidateRange(1, 65535)]
    [int]$LocalPort = 3003,
    [string]$RuleName = 'Homelab Immich ML from HP Server'
)

$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'This script must be run as Administrator.'
}

Write-Output 'STEP_IMMICH_ML_FIREWALL_AUDIT'

$existingRule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
if ($existingRule) {
    $existingRule | Remove-NetFirewallRule
}

$portRules = Get-NetFirewallPortFilter -Protocol TCP |
    Where-Object { $_.LocalPort -eq "$LocalPort" } |
    Get-NetFirewallRule |
    Where-Object { $_.Direction -eq 'Inbound' -and $_.Enabled -eq 'True' -and $_.Action -eq 'Allow' }

foreach ($rule in $portRules) {
    Write-Output ("DISABLE broad inbound rule: {0}" -f $rule.DisplayName)
    $rule | Disable-NetFirewallRule
}

New-NetFirewallRule `
    -DisplayName $RuleName `
    -Description 'Allow only the HP homelab server to reach unauthenticated Immich Remote ML over Tailscale.' `
    -Direction Inbound `
    -Action Allow `
    -Protocol TCP `
    -LocalAddress $SilverBrickAddress `
    -LocalPort $LocalPort `
    -RemoteAddress $HpServerAddress `
    -Profile Any | Out-Null

$created = Get-NetFirewallRule -DisplayName $RuleName
$port = $created | Get-NetFirewallPortFilter
$address = $created | Get-NetFirewallAddressFilter

Write-Output ("RULE enabled={0} action={1} direction={2}" -f $created.Enabled, $created.Action, $created.Direction)
Write-Output ("RULE protocol={0} local_port={1}" -f $port.Protocol, ($port.LocalPort -join ','))
Write-Output ("RULE local_address={0} remote_address={1}" -f ($address.LocalAddress -join ','), ($address.RemoteAddress -join ','))
Write-Output 'IMMICH_ML_FIREWALL_OK'
