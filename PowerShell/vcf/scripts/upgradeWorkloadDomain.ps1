<#	SCRIPT DETAILS

    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Organization:  my-cloudy-world.com
    .Version:       1.0.0
    .Date:          2023-21-09
    ===============================================================================================================

    .CHANGE_LOG

    - 1.0.0     (Gary Blake / 2023-16-10) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of upgrading a Workload Domain based on the release provided

    .EXAMPLE
    .\upgradeWorkloadDomain.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -release 4.5.2.0
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$release
)

Try {
    Clear-Host
    Write-Output "", "Starting the Process of Upgrading for Workload Domain: $domain"
    Request-VCFToken -fqdn $server -username $user -password $pass | Out-Null
    $workloadDomain = (Get-VCFWorkloadDomain | Where-Object {$_.name -eq $domain}).id
    $uri = "https://$sddcManager/v1/upgradables/domains/$workloadDomain/?targetVersion=$release"
    $upgrades = @('NSX_T_MANAGER','VCENTER','HOST')
    Foreach ($upgrade in $upgrades) {
        $bundle = ((Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $headers).elements) | Where-Object {$_.status -eq "AVAILABLE" }
        Write-Output "Checking Upgrade Status of ($upgrade) for Workload Domain: $domain"
        if ($bundle.softwareComponents.type[-0] -eq $upgrade) {
            if ((Get-VCFBundle -id $bundle.bundleId).downloadStatus -eq "SUCCESSFUL" -and (Get-VCFBundle -id $bundle.bundleId).components.type -eq $upgrade) {
                $jsonSpec = '{
                    "bundleId": "'+ $bundle.bundleId +'",
                    "resourceType": "DOMAIN",
                    "resourceUpgradeSpecs": [ {
                        "resourceId": "'+ $workloadDomain +'",
                        "upgradeNow": true
                    } ]}'
                $task = Start-VCFUpgrade -json $jsonSpec
                Write-Output "Starting Upgrade Task: ($($task.name)) with Id ($($task.id)"
                Write-Output "Waiting for Upgrade Task ($($task.name)) with Id ($($task.id)) to Complete"    
                Do { 
                    Start-Sleep 660
                    Request-VCFToken -fqdn $server -username $user -password $pass | Out-Null
                    $status = Get-VCFUpgrade -id $task.id
                } While ($status.status -in "PENDING","SCHEDULED","INPROGRESS")
                Write-Output " Upgrade Task with Id ($($task.id)) completed with status ($($status.status))"
            } else {
                Write-Warning " Upgrade Not Possible as Required Bundle ($bundleId) Not Downloaded to SDDC Manager"
            }
        } else {
            Write-Warning "Upgrade of ($upgrade) in Workload Domain ($domain) for Release (v$release), not available or already performed: SKIPPED"
        }
    }
    Write-Output "Finished the Process of Upgrading Workload Domain: $domain", ""
} Catch {
    Write-Error $_.Exception.Message
}
