# Script to collect all ESXi core dump configuration from VMWare Cloud Foundation
# Written by Gary Blake, Senior Staff Solution Architect @ VMware

Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$workloadDomain
    )

    Clear-Host; Write-Host ""
    # Obtain Authentication Token from SDDC Manager
    Request-VCFToken -fqdn $fqdn -username $username -password $password
    $vcfVcenterDetails = Get-vCenterServerDetail -server $fqdn -user $username -pass $password -domain $workloadDomain
    if (Test-VsphereConnection -server $($vcfVcenterDetails.fqdn)) {
        if (Test-VsphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
            Write-Output "Gathering ESXi Core Dump Configurtion for vCenter Server ($($vcfVcenterDetails.fqdn))"
            $coreDumpObject = New-Object -TypeName psobject
            $allHostObject = New-Object System.Collections.ArrayList
            $esxiHosts = Get-VMHost 
            Foreach ($esxiHost in $esxiHosts) {
                $coreDumpObject = New-Object -TypeName psobject
                $esxcli = Get-EsxCli -VMhost $esxiHost.Name -V2
                $coreDumpConfig = $esxcli.system.coredump.partition.get.invoke()
                $coreDumpObject | Add-Member -notepropertyname 'ESXi Host Fqdn' -notepropertyvalue $esxiHost.Name
                $coreDumpObject | Add-Member -notepropertyname 'Active Core Dump' -notepropertyvalue $coreDumpConfig.Active
                $coreDumpObject | Add-Member -notepropertyname 'Configured Core Dump' -notepropertyvalue $coreDumpConfig.Configured
                $allHostObject += $coreDumpObject
            }
            $allHostObject | ConvertTo-Html | Out-File .\esxiCoreDump-Report.htm
            Invoke-Item .\esxiCoreDump-Report.htm
        }
    }