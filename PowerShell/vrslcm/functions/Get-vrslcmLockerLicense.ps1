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
    Get licenses in the locker

    .DESCRIPTION
    The Get-vrslcmLockerLicense cmdlet gets a list of licenses available in the vRealize Suite Lifecycle Manager locker

    .EXAMPLE
    Get-vrslcmLockerLicense
    This example gets all license in the vRealize Suite Lifecycle Manager locker

    .EXAMPLE
    Get-vrslcmLockerLicense -vmid 2b54b028-9eba-4d2f-b6ee-66428ea2b297
    This example gets the details of a license based on the vmid

    .EXAMPLE
    Get-vrslcmLockerLicense -alias "vRealize Operations Manager"
    This example gets the details of a license based on the alias name

    .EXAMPLE
    Get-vrslcmLockerLicense -refreshLicense
    This example gets triggers a refresh of the license in your My VMware account
#>

[CmdletBinding(DefaultParametersetName = 'default')][OutputType('System.Management.Automation.PSObject')]

Param (
    [Parameter (Mandatory = $false, ParameterSetName = 'default')]
    [Parameter (Mandatory = $false, ParameterSetName = 'vmid')] [ValidateNotNullOrEmpty()] [String]$vmid,
    [Parameter (Mandatory = $false, ParameterSetName = 'alias')] [ValidateNotNullOrEmpty()] [String]$alias,
    [Parameter (Mandatory = $false, ParameterSetName = 'refreshLicense')] [ValidateNotNullOrEmpty()] [Switch]$refreshLicense
)

Try {
    if ($PsBoundParameters.ContainsKey("vmid")) {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/licenses/detail/$vmid"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
        $response
    } elseif ($PsBoundParameters.ContainsKey("alias")) {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/licenses/alias/$alias"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
        $response
    } elseif ($PsBoundParameters.ContainsKey("refreshLicense")) {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/licenses/refresh"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
        $response
    } else {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/licenses"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
        $response
    }
}
Catch {
    Invoke-Expression -Command .\vrlscmCatchWriter.ps1
}