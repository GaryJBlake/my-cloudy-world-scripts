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
    Get paginated list of Passwords available in the Store

    .DESCRIPTION
    The Get-vrslcmLockerPassword cmdlet gets a paginated list of passwords available in the Locker

    .EXAMPLE
    Get-vrslcmLockerPassword
    This example gets all passwords in the Locker

    .EXAMPLE
    Get-vrslcmLockerPassword -vmid 83abd0fd-c92d-4d8f-a5e8-9a1fc4fa6009
    This example gets the details of a password based on the vmid
#>

Param (
    [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$vmid,
    [Parameter (Mandatory = $false)] [ValidateSet("True","False")] [String]$referenced
)

Try {
    if ($PsBoundParameters.ContainsKey("vmid")) {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/passwords/$vmid"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
        $response
    }
    elseif ($PsBoundParameters.ContainsKey("referenced")) {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/passwords"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
        $response.passwords | Where-Object {$_.referenced -like $referenced}
    }
    else {
        $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/passwords"
        $response = Invoke-RestMethod $uri -Method 'GET' -Headers $vrslcmHeaders
        $response.passwords
    }
}
Catch {
    Write-Error $_.Exception.Message
}