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
    Get passwords in the locker

    .DESCRIPTION
    The Get-vrslcmLockerPassword cmdlet gets a list of passwords available in the vRealize Suite Lifecycle Manager
    locker

    .EXAMPLE
    Get-vrslcmLockerPassword
    This example gets all passwords in the vRealize Suite Lifecycle Manager locker

    .EXAMPLE
    Get-vrslcmLockerPassword -vmid 83abd0fd-c92d-4d8f-a5e8-9a1fc4fa6009
    This example gets the password by the vmid

    .EXAMPLE
    Get-vrslcmLockerPassword -alias xint-env-admin
    This example gets the password by alias name

    .EXAMPLE
    Get-vrslcmLockerPassword -referenced True
    This example gets all passwords that are referenced by a component
#>

[CmdletBinding(DefaultParametersetName = 'default')][OutputType('System.Management.Automation.PSObject')]

Param (
    [Parameter (Mandatory = $false, ParameterSetName = 'default')]
    [Parameter (Mandatory = $false, ParameterSetName = 'vmid')] [ValidateNotNullOrEmpty()] [String]$vmid,
    [Parameter (Mandatory = $false, ParameterSetName = 'alias')] [ValidateNotNullOrEmpty()] [String]$alias,
    [Parameter (Mandatory = $false, ParameterSetName = 'referenced')] [ValidateSet("True","False")] [String]$referenced
)

Try {
    if ($PsBoundParameters.ContainsKey('vmid')) {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/passwords/$vmid"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
        $response
    } elseif ($PsBoundParameters.ContainsKey('alias')) {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/passwords?aliasQuery=$alias"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
        $response.passwords
    } elseif ($PsBoundParameters.ContainsKey('referenced')) {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/passwords"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
        $response.passwords | Where-Object {$_.referenced -match $referenced}
    } else {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/passwords"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
        $response.passwords
    }
}
Catch {
    Invoke-Expression -Command .\vrlscmCatchWriter.ps1
}