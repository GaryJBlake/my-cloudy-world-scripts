# Script to execute as system precheck for a Workloda Domain
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

    $jsonSpec = '{
        "resources" : [ {
        "resourceId" : "'+ (Get-VCFWorkloadDomain | Where-Object {$_.name -eq $workloadDomain}).id+'",
        "type" : "DOMAIN"
        } ]
    }'

    Write-Output "Starting System Precheck for Workload Domain ($workloadDomain)"
    $task = Start-VCFSystemPrecheck -json $jsonSpec
    Write-Output "Waiting for Task ($($task.name)) with Task Id ($($task.id)) to complete"
    Do { $status = Get-VCFSystemPrecheckTask -id $task.id } While ($status.status -eq "IN_PROGRESS")
    Write-Output "Task ($($task.name)) with Task Id ($($task.id)) completed with status ($($status.status))"