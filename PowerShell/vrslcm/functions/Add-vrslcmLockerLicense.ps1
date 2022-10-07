<#
    .NOTES
    ===================================================================================================================
    Created by:		Gary Blake
    Date:			22/07/2021
    Organization:	VMware
    Blog:           my-cloudy-world.com
    Twitter:        @GaryJBlake
    ===================================================================================================================

    .SYNOPSIS
    Add a License to the locker

    .DESCRIPTION
    The Add-vrslcmLockerLicense cmdlet validates and adds a license to the vRealize Suite Lifecycle Manager Locker

    .EXAMPLE
    Add-vrslcmLockerLicense -alias "vRealise Operations Manager" -license "XXXXX-XXXXX-XXXXX-XXXXX-XXXXX"
    This example adds a license to the Locker
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$alias,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$license
)

Try {
    $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/license/validate-and-add"
    $body = '{
        "alias": "'+ $alias +'",
        "serialKey": "'+ $license +'"
    }'
    $response = Invoke-RestMethod $uri -Method 'POST' -Headers $vrslcmHeaders -Body $body
    $response
}
Catch {
    Invoke-Expression -Command .\vrlscmCatchWriter.ps1
}