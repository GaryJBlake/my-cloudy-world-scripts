# Script to cleanup failed tasks in SDDC Manager
# Written by Gary Blake, Senior Staff Solution Architect @ VMware
# Refactored using original script by Brian O'Oconnel, Staff 2 Solution Architect @ VMware

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$username,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vcfUserPassword
)

Clear-Host; Write-Host ""
# Obtain Authentication Token from SDDC Manager
Request-VCFToken -fqdn $fqdn -username $username -password $password
$vcfVcenterDetails = Get-vCenterServerDetail -server $fqdn -user $username -pass $password -domain $workloadDomain
if (Test-VsphereConnection -server $($vcfVcenterDetails.fqdn)) {
    if (Test-VsphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
        $sddcmVmName = $fqdn.Split(".")[0]
        $failedTaskIDs = @()
        $ids = (Get-VCFTask -Status "Failed").id
        Foreach ($id in $ids) {
            $failedTaskIDs += ,$id
        }
        # Cleanup the failed tasks
        Foreach ($taskID in $failedTaskIDs) {
            $scriptCommand = "curl -X DELETE 127.0.0.1/tasks/registrations/$taskID"
            Write-Output "Deleting Failed Task ID $taskID"
            Invoke-VMScript -ScriptText $scriptCommand -VM $sddcmVMName -GuestUser "vcf" -GuestPassword $vcfUserPassword -Server $vcfVcenterDetails.fqdn | Out-Null
        # Verify the task was deleted    
            Try {
            $verifyTaskDeleted = (Get-VCFTask -id $taskID)
            if ($verifyTaskDeleted -eq "Task ID Not Found") {
                Write-Output "Task ID $taskID Deleted Successfully"
            }
        }
            catch {
                Write-Error "Something went wrong. Please check your SDDC Manager state"
            }
        }
        # Retrieve the Management Domain vCenter Server FQDN
        #$vcenterFQDN = ((Get-VCFWorkloadDomain | where-object {$_.type -eq "MANAGEMENT"}).vcenters.fqdn)
        #$vcenterUser = (Get-VCFCredential -resourceType "PSC").username
        ##$vcenterPassword = (Get-VCFCredential -resourceType "PSC").password
        Disconnect-VIServer -Server $vcfVcenterDetails.fqdn -Confirm:$false | Out-Null
    }
}

# Disconnect all connected vCenters to ensure only the desired vCenter is available
#if ($defaultviservers) {
#    $server = $defaultviservers.Name
#    foreach ($server in $defaultviservers) {            
#        Disconnect-VIServer -Server $server -Confirm:$False
#    }
#}



# Retrieve SDDC Manager VM Name
#if ($vcenterFQDN) {
#    Write-Output "Getting SDDC Manager Manager VM Name"
##    Connect-VIServer -server $vcenterFQDN -user $vcenterUser -password $vcenterPassword | Out-Null
#    $sddcmVMName = ((Get-VM * | Where-Object {$_.Guest.Hostname -eq $sddcManagerFQDN}).Name)              
#}

# Retrieve a list of failed tasks

#