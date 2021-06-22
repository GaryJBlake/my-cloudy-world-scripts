Function Request-WSAToken {
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			01/04/2020
        Organization:	VMware
        Blog:           my-cloudy-world.com
        Twitter:        @GaryJBlake
        ===========================================================================
        
		.SYNOPSIS
    	Obtains a session token

    	.DESCRIPTION
    	The Request-WSAToken cmdlet connects to the specified Workspace ONE Access instance and requests a session token

    	.EXAMPLE
    	Request-WSAToken -fqdn sfo-wsa01.sfo.rainpole.io -username admin -password VMware1!
        This example shows how to connect to a Workspace ONE Access instance and request a session token
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$password
    )

    if ( -not $PsBoundParameters.ContainsKey("username") -or ( -not $PsBoundParameters.ContainsKey("password"))) {
        # Request Credentials
        $creds = Get-Credential
        $username = $creds.UserName.ToString()
        $password = $creds.GetNetworkCredential().password
    }
    
    # Validate credentials by executing an API call
    $headers = @{"Content-Type" = "application/json"}
    $headers.Add("Accept", "application/json; charset=utf-8")
    $uri = "https://$fqdn/SAAS/API/1.0/REST/auth/system/login"
    $body = '{"username": "' + $username + '", "password": "' + $password + '", "issueToken": "true"}'
    
    Try {
        # Checking against the API
        # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
        if ($PSEdition -eq 'Core') {
            $response = Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body -SkipCertificateCheck
            $Global:accessToken = "HZN " + $response.sessionToken
        }
        else {
            $response = Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body
            $Global:accessToken = "HZN " + $response.sessionToken
        }
        if ($response.sessionToken) {
            Write-Output "Successfully Requested New Session Token From Workspace ONE Access instance: $fqdn"
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}