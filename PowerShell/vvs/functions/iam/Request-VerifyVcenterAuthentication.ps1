
<#
    .SYNOPSIS
    Operational verification of authentication to vCenter Server

    .DESCRIPTION
    The Request-VerifyVcenterAuthentication cmdlet verifies authentication with vCenter Server. The cmdlet connects
    to SDDC Manager using the -server, -user, and -password values:
    - Validates that network connectivity is available to the SDDC Manager instance
    - Validates that network connectivity is available to the vCenter Server instance
    - Gathers a list of Workload Domains
    - Verifies authentication to each vCenter Server in Enhanced Link Mode is succcessful

    .EXAMPLE
    Request-VerifyVcenterAuthentication -server ldn-vcf01.ldn.cloudy.io -user admin@local -pass VMw@re1!VMw@re1! -domainUser cloud-admin@ldn -domainPass VMw@re1!
    This example performs operational verification of authentication to each vCenter Server across the VMware Cloud Instance
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainUser,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainPass
)

Try {
    if (Test-VCFConnection -server $server) {
        if (Test-VCFAuthentication -server $server -user $user -pass $pass) {
            $allWorkloadDomains = (Get-VCFWorkloadDomain)
            $allClustersObject = New-Object System.Collections.ArrayList
            foreach ($domain in $allWorkloadDomains) {
                $vcfVcenterDetails = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain.name
                if (Test-VsphereConnection -server $($vcfVcenterDetails.fqdn) -ErrorAction SilentlyContinue) {
                    # Verify the Authentication to vCenter Server by Using a Local System Account
                    $authStatus = Test-VsphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass -ErrorAction SilentlyContinue
                    if ($authStatus -eq $true) { $alert = "GREEN"} else { $alert = "RED"}
                    $message = "Verify authentication to $($vcfVcenterDetails.fqdn) using a local system account $($vcfVcenterDetails.ssoAdmin)"
                    $customObject = New-Object -TypeName psobject
                    $customObject | Add-Member -NotePropertyName 'Component' -NotePropertyValue "vCenter Server"
                    $customObject | Add-Member -NotePropertyName 'System FQDN' -NotePropertyValue $vcfVcenterDetails.fqdn
                    $customObject | Add-Member -NotePropertyName 'Alert' -NotePropertyValue $alert
                    $customObject | Add-Member -NotePropertyName 'Message' -NotePropertyValue $message
                    if ($DefaultVIServer) { Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null }
                    $allClustersObject += $customObject

                    # Verify Authentication to vCenter Server by Using an Active Directory User Account
                    $authStatus = Test-VsphereAuthentication -server $vcfVcenterDetails.fqdn -user $domainUser -pass $domainPass -ErrorAction SilentlyContinue
                    if ($authStatus -eq $true) { $alert = "GREEN"} else { $alert = "RED"}
                    $message = "Verify authentication to $($vcfVcenterDetails.fqdn) using an Active Directory account $domainUser"
                    $customObject = New-Object -TypeName psobject
                    $customObject | Add-Member -NotePropertyName 'Component' -NotePropertyValue "vCenter Server"
                    $customObject | Add-Member -NotePropertyName 'System FQDN' -NotePropertyValue $vcfVcenterDetails.fqdn
                    $customObject | Add-Member -NotePropertyName 'Alert' -NotePropertyValue $alert
                    $customObject | Add-Member -NotePropertyName 'Message' -NotePropertyValue $message
                    if ($DefaultVIServer) { Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null }
                    $allClustersObject += $customObject
                } else {
                    $alert = "RED"
                    $message = "Unable to communicate with $($vcfVcenterDetails.fqdn)"
                    $customObject = New-Object -TypeName psobject
                    $customObject | Add-Member -NotePropertyName 'Component' -NotePropertyValue "vCenter Server"
                    $customObject | Add-Member -NotePropertyName 'System FQDN' -NotePropertyValue $vcfVcenterDetails.fqdn
                    $customObject | Add-Member -NotePropertyName 'Alert' -NotePropertyValue $alert
                    $customObject | Add-Member -NotePropertyName 'Message' -NotePropertyValue $message
                    $allClustersObject += $customObject
                }
            }
            $allClustersObject
        }
    }
} Catch {
    Debug-CatchWriter -object $_
}