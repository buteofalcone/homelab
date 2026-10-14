[CmdletBinding()]
param(
    [string]$LmStudioAddress = '100.91.171.26',
    [string]$HpServerAddress = '100.65.83.35',
    [ValidateRange(1, 65535)]
    [int]$LocalPort = 1234,
    [string]$RuleName = 'Homelab LM Studio from HP Server',
    [string]$LogPath = 'C:\tmp\lm-studio-firewall.log'
)

$ErrorActionPreference = 'Stop'
Start-Transcript -LiteralPath $LogPath -Force | Out-Null

try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'This script must be run as Administrator.'
    }

    Write-Output 'STEP_FIREWALL_AUDIT'

    $existingRule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
    if ($existingRule) {
        $existingRule | Remove-NetFirewallRule
    }

    $enabledAllowRules = Get-NetFirewallRule -Direction Inbound -Enabled True -Action Allow
    $lmStudioRules = $enabledAllowRules | Where-Object DisplayName -Like '*LM Studio*'
    $apiPortRules = Get-NetFirewallPortFilter -Protocol TCP |
        Where-Object { $_.LocalPort -eq "$LocalPort" } |
        Get-NetFirewallRule |
        Where-Object { $_.Direction -eq 'Inbound' -and $_.Enabled -eq 'True' -and $_.Action -eq 'Allow' }

    $broadRules = @($lmStudioRules) + @($apiPortRules) |
        Sort-Object Name -Unique |
        ForEach-Object {
            $rule = $_
            $portFilter = $rule | Get-NetFirewallPortFilter
            $appFilter = $rule | Get-NetFirewallApplicationFilter
            [pscustomobject]@{
                Rule = $rule
                DisplayName = $rule.DisplayName
                Program = $appFilter.Program
                Protocol = $portFilter.Protocol
                LocalPort = $portFilter.LocalPort
            }
        }

    foreach ($item in $broadRules) {
        Write-Output ("DISABLE broad inbound rule: {0}; program={1}; protocol={2}; port={3}" -f `
            $item.DisplayName, $item.Program, $item.Protocol, ($item.LocalPort -join ','))
        $item.Rule | Disable-NetFirewallRule
    }

    New-NetFirewallRule `
        -DisplayName $RuleName `
        -Description 'Allow the HP homelab server to use the authenticated LM Studio API over Tailscale.' `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalAddress $LmStudioAddress `
        -LocalPort $LocalPort `
        -RemoteAddress $HpServerAddress `
        -Profile Any | Out-Null

    $rule = Get-NetFirewallRule -DisplayName $RuleName
    $port = $rule | Get-NetFirewallPortFilter
    $address = $rule | Get-NetFirewallAddressFilter

    Write-Output ("RULE name={0}" -f $rule.DisplayName)
    Write-Output ("RULE enabled={0} action={1} direction={2} profile={3}" -f `
        $rule.Enabled, $rule.Action, $rule.Direction, $rule.Profile)
    Write-Output ("RULE protocol={0} local_port={1}" -f $port.Protocol, ($port.LocalPort -join ','))
    Write-Output ("RULE local_address={0} remote_address={1}" -f `
        ($address.LocalAddress -join ','), ($address.RemoteAddress -join ','))
    Write-Output 'LM_STUDIO_FIREWALL_OK'
}
finally {
    Stop-Transcript | Out-Null
}
