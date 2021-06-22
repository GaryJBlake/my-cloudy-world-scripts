Function Request-vcToken {
     <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/06/2021
        Organization:	VMware
        Blog:           my-cloudy-world.com
        Twitter:        @GaryJBlake
        ===========================================================================
        
        .SYNOPSIS
        Connects to the specified vCenter Server API and stores the credentials in a base64 string

        .DESCRIPTION
        The Request-vcToken cmdlet connects to the specified vCenter Server and stores the credentials
        in a base64 string. It is required once per session before running all other cmdlets

        .EXAMPLE
        Request-vcToken -fqdn sfo-m01-vc01.sfo.rainpole.io -username administrator@vsphere.local -password VMw@re1!
        This example shows how to connect to the vCenter Server API
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

    $Global:vcenterFqdn = $fqdn
    
    $vcenterHeader = @{"Authorization" = "Basic "+[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($username+":"+$password))}
    $contentType = "application/json"
    $uri = "https://$vcenterFqdn/api/session"

    Try {
        # Checking authentication with vCenter Server API
        if ($PSEdition -eq 'Core') {
            $Global:vcToken = Invoke-RestMethod -Uri $uri -Headers $vcenterHeader -Method POST -ContentType $contentType -SkipCertificateCheck # PS Core has -SkipCertificateCheck implemented
        }
        else {
            $Global:vcToken = Invoke-RestMethod -Uri $uri -Headers $vcenterHeader -Method POST -ContentType $contentType
        }
        if ($vcToken) {
            Write-Output "Successfully connected to the vCenter Server API: $vcenterFqdn"
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}