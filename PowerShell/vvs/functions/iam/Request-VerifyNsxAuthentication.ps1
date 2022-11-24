<#
    .SYNOPSIS
    Operational verification of authentication to VMware NSX

    .DESCRIPTION
    The Request-VerifyNsxAuthentication cmdlet verifies authentication with VMware NSX. The cmdlet connects to SDDC
    Manager using the -server, -user, and -password values:
    - Validates that network connectivity is available to the SDDC Manager instance
    - Validates that network connectivity is available to the VMware NSX instance
    - Gathers a list of Workload Domains
    - Verifies authentication to each VMware NSX instance is succcessful

    .EXAMPLE
    Request-VerifyNsxAuthentication -server ldn-vcf01.ldn.cloudy.io -user admin@local -pass VMw@re1!VMw@re1! -domainUser cloud-admin@ldn.cloudy.io -domainPass VMw@re1!
    This example performs operational verification of authentication to each VMware NSX instance across the VMware Cloud Instance
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
            $allObject = New-Object System.Collections.ArrayList
            foreach ($domain in $allWorkloadDomains) {
                $vcfNsxDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain.name -ErrorAction Ignore -ErrorVariable ErrMsg
                if (Test-NSXTConnection -server $($vcfNsxDetails.fqdn) -ErrorAction SilentlyContinue) {
                    # Verify the Authentication to NSX-T Data Center by Using a Local System Account
                    $authStatus = Test-NSXTAuthentication -server $vcfNsxDetails.fqdn -user $vcfNsxDetails.adminUser -pass $vcfNsxDetails.adminPass
                    if ($authStatus -eq $true) { $alert = "GREEN"} else { $alert = "RED"}
                    $message = "Verify authentication to $($vcfNsxDetails.fqdn) using a local system account $($vcfNsxDetails.adminUser)"
                    $customObject = New-Object -TypeName psobject
                    $customObject | Add-Member -NotePropertyName 'Component' -NotePropertyValue "NSX Manager"
                    $customObject | Add-Member -NotePropertyName 'System FQDN' -NotePropertyValue $vcfNsxDetails.fqdn
                    $customObject | Add-Member -NotePropertyName 'Alert' -NotePropertyValue $alert
                    $customObject | Add-Member -NotePropertyName 'Message' -NotePropertyValue $message
                    $allObject += $customObject

                    # Verify Authentication to NSX-T Data Center by Using an Active Directory User Account
                    $authStatus = Test-NSXTAuthentication -server $vcfNsxDetails.fqdn -user $domainUser -pass $domainPass -ErrorAction Ignore -ErrorVariable ErrMsg
                    if ($authStatus -eq $true) { $alert = "GREEN"} else { $alert = "RED"}
                    $message = "Verify authentication to $($vcfNsxDetails.fqdn) using an Active Directory account $domainUser"
                    $customObject = New-Object -TypeName psobject
                    $customObject | Add-Member -NotePropertyName 'Component' -NotePropertyValue "NSX Manager"
                    $customObject | Add-Member -NotePropertyName 'System FQDN' -NotePropertyValue $vcfNsxDetails.fqdn
                    $customObject | Add-Member -NotePropertyName 'Alert' -NotePropertyValue $alert
                    $customObject | Add-Member -NotePropertyName 'Message' -NotePropertyValue $message
                    $allObject += $customObject
                } else {
                    $alert = "RED"
                    $message = "Unable to communicate with $($vcfNsxDetails.fqdn)"
                    $customObject = New-Object -TypeName psobject
                    $customObject | Add-Member -NotePropertyName 'Component' -NotePropertyValue "NSX Manager"
                    $customObject | Add-Member -NotePropertyName 'System FQDN' -NotePropertyValue $vcfNsxDetails.fqdn
                    $customObject | Add-Member -NotePropertyName 'Alert' -NotePropertyValue $alert
                    $customObject | Add-Member -NotePropertyName 'Message' -NotePropertyValue $message
                    $allObject += $customObject
                }
            }
            $allObject
        }
    }
} Catch {
    Debug-CatchWriter -object $_
}