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
    Import an already existing Certificate

    .DESCRIPTION
    The Add-vrslcmLockerCertificate cmdlet add as new passwords to the Locker

    .EXAMPLE
    Add-vrslcmLockerCertificate -certificateChain ..\chain.pem -alias my-cert -passwordPhrase VMw@re1!
    This example imports a certificate using the pem fule
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$alias,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$certificateChain,
    [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$passPhrase
)

Try {
    $certdata = Get-Content ($certificateChain) -Raw
    $chain = [regex]::split($certdata, "-----BEGIN RSA PRIVATE KEY-----")[0]
    $chain = $chain.Trim()
    $privateKey = [regex]::split($certdata, "-----END CERTIFICATE-----")[-1]
    $privateKey = $privateKey.Trim()

    $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/certificates/import"
    $body = '{
        "alias": "'+ $alias +'",
        "certificateChain": "'+ $chain +'",
        "passphrase": "'+ $passphrase +'",
        "privateKey": "'+ $privateKey +'"
    }'
    $response = Invoke-RestMethod $uri -Method 'POST' -Headers $vrslcmHeaders -Body $body
    $response
}
Catch {
    Write-Error $_.Exception.Message
}
