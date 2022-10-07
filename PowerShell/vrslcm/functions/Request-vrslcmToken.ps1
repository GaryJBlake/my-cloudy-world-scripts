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
    Obtains a vRealize Suite Lifecycle Manager authorization token

    .DESCRIPTION
    The Request-vrslcmToken cmdlet connects to the specified vRealize Suite Lifecycle Manager and  obtains an
    authorization token. It is required once per session before running all other cmdlets.

    .EXAMPLE
    Request-vrslcmToken -fqdn xint-vrslcm01.cloudy.io -username vcfadmin@local -password VMw@re1!
    This example shows how to obtain an authorization token to from the vRealize Suite Lifecycle Manager appliance
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
    [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$username,
    [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$password
)

if ( -not $PsBoundParameters.ContainsKey("username") -or ( -not $PsBoundParameters.ContainsKey("password"))) {
    $creds = Get-Credential # Request Credentials
    $username = $creds.UserName.ToString()
    $password = $creds.GetNetworkCredential().password
}

$Global:vrslcmAppliance = $fqdn
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $password))) # Create Basic Authentication Encoded Credentials
$headers = @{"Accept" = "application/json" }
$headers.Add("Authorization", "Basic $base64AuthInfo")
$headers.Add("Content-Type", "application/json")
$Global:vrslcmHeaders = $headers

Try {
    # Validate credentials by executing an API call
    $uri = "https://$vrslcmAppliance/lcm/health/api/v2/status"
    if ($PSEdition -eq 'Core') {
        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $vrslcmHeaders -SkipCertificateCheck
    }
    else {
        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $vrslcmHeaders
    }
    if ($response) {
        Write-Output "Successfully connected to vRealize Suite Lifecycle Manager Appliance: $vrslcmAppliance"
    }
}
Catch {
    if ($_.Exception.Message -match "401") {
        Write-Error "Incorrect credentials provided to connect to vRealize Suite Lifecycle Manager Appliance: $vrslcmAppliance"
    }
}
