<#
    .NOTES
    ===================================================================================================================
    Created by:		Gary Blake
    Date:			2022/11/25
    Organization:	VMware
    Blog:           my-cloudy-world.com
    Twitter:        @GaryJBlake
    ===================================================================================================================
    
    .SYNOPSIS
    Connects to the specified NSX Manager

    .DESCRIPTION
    The Request-NsxtToken cmdlet connects to the specified NSX Manager with the supplied credentials

    .EXAMPLE
    Request-NsxtToken -fqdn sfo-w01-nsx01.sfo.rainpole.io -username admin -password VMware1!VMw@re1!
        This example shows how to connect to NSX Manager
#>

Param (
    [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()][String]$fqdn,
    [Parameter (Mandatory = $false)] [String]$username,
    [Parameter (Mandatory = $false)] [String]$password,
    [Parameter (ValueFromPipeline, Mandatory = $false)] [psobject]$inputObject,
    [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$skipCertificateCheck
)

if (!$PsBoundParameters.ContainsKey("username") -or (!$PsBoundParameters.ContainsKey("password"))) {
    # Request Credentials
    $creds = Get-Credential
    $username = $creds.UserName.ToString()
    $password = $creds.GetNetworkCredential().password
}
if (!$PsBoundParameters.ContainsKey("fqdn")) {
    $fqdn = Read-Host "NSX Manager FQDN not found, please enter a value e.g. sfo-m01-nsx01.sfo.rainpole.io"
}

if ($PsBoundParameters.ContainsKey("skipCertificateCheck")) {
    if (-not("placeholder" -as [type])) {
        add-type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class Placeholder {
    public static bool ReturnTrue(object sender,
        X509Certificate certificate,
        X509Chain chain,
        SslPolicyErrors sslPolicyErrors) { return true; }

    public static RemoteCertificateValidationCallback GetDelegate() {
        return new RemoteCertificateValidationCallback(Placeholder.ReturnTrue);
    }
}
"@
} 
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = [placeholder]::GetDelegate()
}

# Validate credentials by executing an API call
$Global:nsxtmanager = $fqdn
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $password))) # Create Basic Authentication Encoded Credentials
$Global:nsxtHeaders = @{"Accept" = "application/json" }
$nsxtHeaders.Add("Authorization", "Basic $base64AuthInfo")
$nsxtHeaders.Add("Content-Type", "application/json")
$uri = "https://$nsxtmanager/api/v1/logical-ports"

Try {
    # Checking against the NSX Managers API
    # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
    if ($PSEdition -eq 'Core') {
        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $nsxtHeaders -SkipCertificateCheck
    } else {
        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $nsxtHeaders
    }
    if ($response) {
        if ($inputObject) {
            Write-Output "Successfully Requested New API Token for NSX Manager $nsxtmanager via SDDC Manager $sddcManager"
        } else {
            Write-Output "Successfully Requested New API Token for NSX Manager $nsxtmanager"
        }
    }
} Catch {
    Write-Error $_.Exception.Message
}
