Function Request-vrslcmToken {
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			22/06/2021
        Organization:	VMware
        Blog:           my-cloudy-world.com
        Twitter:        @GaryJBlake
        ===========================================================================
        
        .SYNOPSIS
        Obtains a vRealize Suite Lifecycle Manager session token

        .DESCRIPTION
        The Request-vrslcmToken cmdlet connects to the specified vRealize Suite Lifecycle Manager and 
        obtains an authorization token. It is required once per session before running all other cmdlets.

        .EXAMPLE
        Request-vrslcmToken -fqdn xreg-vrslcm.rainpole.io -username admin@local -password VMware1!
        This example shows how to connect to the vRealize Suite Lifecycle Manager applaince
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

    
    #$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $password))) # Create Basic Authentication Encoded Credentials
    #$Global:vrslcmHeaders = @{"Accept" = "application/json" }
    #$vrslcmHeaders.Add("Authorization", "Basic $base64AuthInfo")
    #$vrslcmHeaders.Add("Content-Type", "application/json")

    Try {
        # Validate credentials by executing an API call
        $uri = "https://$vrslcmAppliance/lcmversion"
        if ($PSEdition -eq 'Core') {
            $response = Invoke-WebRequest -Method GET -Uri $uri -Headers $vrslcmHeaders -SkipCertificateCheck # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
        }
        else {
            $response = Invoke-WebRequest -Method GET -Uri $uri -Headers $vrslcmHeaders
        }
        if ($response.StatusCode -eq 200) {
            Write-Output "Successfully connected to the vRealize Suite Lifecycle Manager Appliance: $vrslcmAppliance"
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}