<#	SCRIPT DETAILS

    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Organization:  my-cloudy-world.com
    .Version:       1.0.0
    .Date:          2023-31-08
    ===============================================================================================================

    .CHANGE_LOG

    - 1.0.0     (Gary Blake / 2023-31-08) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of upgrading SDDC Manager based on the release provided

    .EXAMPLE
    .\upgradeSddcManager.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -release 4.5.2.0
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$release
)

Try {
    Clear-Host
    Write-Output "", "Starting the Process of Upgrading SDDC Manager"
    Request-VCFToken -fqdn $server -username $user -password $pass | Out-Null
    $vcfVersion = (((Get-VCFManager).version -Split ("-"))[-0] | Out-String).Trim()
    $workloadDomain = (Get-VCFWorkloadDomain | Where-Object {$_.type -eq "MANAGEMENT"}).id
    $upgrades = @('Upgrade','Drift') 
    Foreach ($upgrade in $upgrades) {
        $uri = "https://$sddcManager/v1/upgradables/domains/$workloadDomain/?targetVersion=$release"
        $bundle = ((Invoke-RestMethod -Method GET -URI $uri -ContentType application/json -headers $headers).elements)
        if ($bundle.bundleType -eq "SDDC_MANAGER") {
            if ((Get-VCFBundle -id $bundle.bundleId).downloadStatus -eq "SUCCESSFUL" -and (Get-VCFBundle -id $bundle.bundleId).type -eq "SDDC_MANAGER") {
                $jsonSpec = '{
                    "bundleId": "'+ $bundle.bundleId +'",
                    "resourceType": "DOMAIN",
                    "resourceUpgradeSpecs": [ {
                        "resourceId": "'+ $workloadDomain +'",
                        "upgradeNow": true
                    } ]}'
                $task = Start-VCFUpgrade -json $jsonSpec
                Write-Output "Starting Upgrade Task: ($($task.name)) with Id ($($task.id)) to Complete"
                Write-Output "Wiating for Upgrade Task with ID: ($($task.id)) to Complete"    
                Do {
                    Start-Sleep 60
                    Request-VCFToken -fqdn $server -username $user -password $pass | Out-Null
                    $status = Get-VCFUpgrade -id $task.id
                } While ($status.status -in "PENDING","SCHEDULED","INPROGRESS")
                Write-Output "Upgrade Task with Id ($($task.id)) completed with status ($($status.status))"
            } else {
                Write-Warning "Upgrade Not Possible as Required Bundle ($($bundle.bundleId)) Not Downloaded to SDDC Manager"
            }
        } else {
            Write-Warning "SDDC Manager $upgrade for Release (v$release), already completed: SKIPPED"
        }
    }
    Write-Output "Finished the Process of Upgrading SDDC Manager", ""
} Catch {
    Write-Error $_.Exception.Message
}

