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
    Delete a password from the locker

    .DESCRIPTION
    The Remove-vrslcmLockerPassword cmdlet deletes a password from the vRealize Suite Lifecycle Manager locker

    .EXAMPLE
    Remove-vrslcmLockerPassword -vmid 50150d69-c441-447c-9dca-cf1918c7942d
    This example deletes the password from the locker
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vmid
)

Try {
    $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/passwords/$vmid"
    $response = Invoke-RestMethod $uri -Method 'DELETE' -Headers $vrslcmHeaders
    $response
}
Catch {
    Invoke-Expression -Command .\vrlscmCatchWriter.ps1
}