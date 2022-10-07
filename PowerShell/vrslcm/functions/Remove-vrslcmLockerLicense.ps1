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
    Delete a license from the locker

    .DESCRIPTION
    The Remove-vrlsmcLockerLicense cmdlet deletes a license from the vRealize Suite Lifecycle Manager Locker

    .EXAMPLE
    Remove-vrlsmcLockerLicense -vmid
    This example delets the certificate from the locker
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vmid
)

Try {
    $uri = "https://$vrslcmAppliance/lcm/locker/api/licenses/$vmid"
    $response = Invoke-RestMethod $uri -Method 'DELETE' -Headers $vrslcmHeaders
    $response
}
Catch {
    Invoke-Expression -Command .\vrlscmCatchWriter.ps1
}