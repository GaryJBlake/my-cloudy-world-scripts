<#
    .NOTES
    ===================================================================================================================
    Created by:		Gary Blake
    Date:			22/06/2021
    Organization:	VMware
    Blog:           my-cloudy-world.com
    Twitter:        @GaryJBlake
    ===================================================================================================================

    .SYNOPSIS
    Get paginated list of Certificates available in the Store

    .DESCRIPTION
    The Get-vrslcmLockerCertificate cmdlet gets a paginated list of certificates available in the Locker

    .EXAMPLE
    Get-vrslcmLockerCertificate
    This example gets all certificates in the Locker

    .EXAMPLE
    Get-vrslcmLockerCertificate -vmid 0520f921-59e7-49cb-9d34-e4539f01cbd7
    This example gets the details of a certificate based on the vmid

    .EXAMPLE
    Get-vrslcmLockerCertificate -alias xint-wsa01
    This example gets the details of a certificate based on the vmid
#>

Param (
    [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$vmid,
    [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$alias
)

Try {
    if ($PsBoundParameters.ContainsKey("vmid")) {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/certificates/$vmid"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
        $response
    }
    elseif ($PsBoundParameters.ContainsKey("alias")) {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/certificates"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
        $response.certificates | Where-Object {$_.alias -eq $alias}
    }
    else {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/certificates"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
        $response.certificates
    }
}
Catch {
    Write-Error $_.Exception.Message
}
