# Script to collect all credentials from VMWare Cloud Foundation
# Written by Gary Blake, Senior Staff Solution Architect @ VMware

Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password
    )

    Clear-Host; Write-Host ""
    # Obtain Authentication Token from SDDC Manager
    Request-VCFToken -fqdn $fqdn -username $username -password $password

    Write-Output "Gathering Credentials from SDDC Manager ($fqdn)"
    Get-VCFCredential | Select-Object @{Name="resourceName"; Expression={ $_.resource.resourceName}}, @{Name="resourceIp"; Expression={ $_.resource.resourceIp}}, accountType, username, password, @{Name="domainName"; Expression={ $_.resource.domainName}} | Where-Object {$_.accountType -eq "USER" -or $_.accountType -eq "SYSTEM"} | Sort-Object resourceName| ConvertTo-Html  | Out-File -Path .\passwords.htm
    Invoke-Item .\Passwords.htm