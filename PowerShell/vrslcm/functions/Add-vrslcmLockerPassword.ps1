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
    Add a password to the locker

    .DESCRIPTION
    The Add-vrslcmLockerPassword cmdlet adds a password to the vRealize Suite Lifecycle Manager Locker

    .EXAMPLE
    Add-vrslcmLockerPassword -userName admin -alias xint-admin -password VMw@re1! -description "Password for Cross-Instance Admin"
    This example adds the admin user for the xint-admin alias to the vRealize Suite Lifecycle Manager locker
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$userName,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$alias,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password,
    [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$description
)

Try {
    $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/passwords"
    if ($PsBoundParameters.ContainsKey("description")) {
        $body = '{
            "alias": "'+ $alias +'",
            "password": "'+ $password +'",
            "passwordDescription": "'+ $description +'",
            "userName": "'+ $userName +'"
        }'
    } else {
        $body = '{
            "alias": "'+ $alias +'",
            "password": "'+ $password +'",
            "userName": "'+ $userName +'"
        }'           
    }
    $response = Invoke-RestMethod $uri -Method 'POST' -Headers $vrslcmHeaders -Body $body
    $response
}
Catch {
    Invoke-Expression -Command .\vrlscmCatchWriter.ps1
}
