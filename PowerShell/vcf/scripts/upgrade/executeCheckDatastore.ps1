# Script to collect all credentials from VMWare Cloud Foundation
# Written by Gary Blake, Senior Staff Solution Architect @ VMware

Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$workloadDomain
    )

    Function Percentcal {
        Param (
            [Parameter (Mandatory = $true)] [Int]$InputNum1,
            [Parameter (Mandatory = $true)] [Int]$InputNum2)
            $InputNum1 / $InputNum2*100
    }

    Clear-Host; Write-Host ""
    # Obtain Authentication Token from SDDC Manager
    Request-VCFToken -fqdn $fqdn -username $username -password $password
    $vcfVcenterDetails = Get-vCenterServerDetail -server $fqdn -user $username -pass $password -domain $workloadDomain
    if (Test-VsphereConnection -server $($vcfVcenterDetails.fqdn)) {
        if (Test-VsphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
            Write-Output "Gathering Datastore Usage for vCenter Server ($($vcfVcenterDetails.fqdn))"
            $datastores = Get-Datastore | Sort-Object Name
            Foreach ($ds in $datastores) {
                if (($ds.Name -match “Shared”) -or ($ds.Name -match “”)) {
                    $PercentFree = Percentcal $ds.FreeSpaceMB $ds.CapacityMB
                    $PercentFree = “{0:N2}” -f $PercentFree
                    $ds | Add-Member -type NoteProperty -name PercentFree -value $PercentFree
                }
            }
            $datastores | Select-Object Name,@{N=”UsedSpaceGB”;E={[Math]::Round(($_.ExtensionData.Summary.Capacity - $_.ExtensionData.Summary.FreeSpace)/1GB,0)}},@{N=”TotalSpaceGB”;E={[Math]::Round(($_.ExtensionData.Summary.Capacity)/1GB,0)}} ,PercentFree | ConvertTo-Html | Out-File .\StorageReport.htm
            Invoke-Item .\StorageReport.htm
        }
    }