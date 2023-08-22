<#	SCRIPT DETAILS

    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Organization:  my-cloudy-world.com
    .Version:       1.0.0
    .Date:          2023-22-08
    ===============================================================================================================

    .CHANGE_LOG

    - 1.0.0   (Gary Blake / 2023-22-08) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of geerating the JSON for downloading the bundles to SDDC Manager based on a
    version.

    .EXAMPLE
    startSystemPrecheck.ps1 -server lax-vcf01.lax.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -workloadDomain lax-m01
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$workloadDomain
)

Try {
    Clear-Host
    Request-VCFToken -fqdn $server -username $user -password $pass | Out-Null
    Write-Output "", " Starting a System Pre-Check on SDDC Manager $server for Workload Domain $workloadDomain"
    $jsonSpec = '{ "resources" : [ { "resourceId" : "'+ (Get-VCFWorkloadDomain | Where-Object {$_.name -eq $workloadDomain}).id+'", "type" : "DOMAIN" } ] }'
    $task = Start-VCFSystemPrecheck -json $jsonSpec
    Write-Output " Waiting for Upgrade Precheck Task ($($task.name)) with Id ($($task.id)) to Complete"
    Do { $status = Get-VCFSystemPrecheckTask -id $task.id } While ($status.status -eq "IN_PROGRESS")
    Write-Output " Task ($($task.name)) with Task Id ($($task.id)) completed with status ($($status.status))", ""
    $status.subtasks | Select-Object name, status
} Catch {
    Write-Error $_.Exception.Message
}