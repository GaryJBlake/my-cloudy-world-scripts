<#
    .NOTES
    ===================================================================================================================
    Created by:		Gary Blake
    Date:			07/10/2022
    Organization:	VMware
    Blog:           my-cloudy-world.com
    Twitter:        @GaryJBlake
    ===================================================================================================================

    .SYNOPSIS
    Delete a certificate from the locker

    .DESCRIPTION
    The Remove-vrslcmLockerCertificate cmdlet deletes a certificate from the vRealize Suite Lifecycle Manager Locker

    .EXAMPLE
    Remove-vrslcmLockerCertificate -vmid
    This example delets the certificate from the locker
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vmid
)

Try {
    $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/certificates/$vmid"
    $response = Invoke-RestMethod $uri -Method 'DELETE' -Headers $vrslcmHeaders
    $response | Select-Object alias, validity, certInfo
}
Catch {
    Invoke-Expression -Command .\vrlscmCatchWriter.ps1
}