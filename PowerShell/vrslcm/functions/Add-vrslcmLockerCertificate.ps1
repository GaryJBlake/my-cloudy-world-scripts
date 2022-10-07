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
    Add a certificate to the locker

    .DESCRIPTION
    The Add-vrslcmLockerCertificate cmdlet adds a certificate to the vRealize Suite Lifecycle Manager locker

    .EXAMPLE
    Add-vrslcmLockerCertificate -alias ldn-wsa01 -certificateFile .\chain.pem
    This example imports a certificate to the locker

    .EXAMPLE
    Add-vrslcmLockerCertificate -alias ldn-wsa01 -certificateFile .\chain.pem -passPhrase VMw@re1!VMw@re1!
    This example imports a certificate with a passPhrase to the locker
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$alias,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$certificateFile,
    [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$passPhrase
)

Try {
    $newPEMString
    foreach ($line in Get-Content $certificateFile) {
        $stringToAdd = $line + '\n'
        $newPEMString += $stringToAdd
    }
    $chain = [regex]::split($newPEMString, "-----BEGIN RSA PRIVATE KEY-----")[0] -replace ".{2}$"
    $key = [regex]::split($newPEMString, "-----END CERTIFICATE-----")[-1].substring(2)
    if (!$PsBoundParameters.ContainsKey("passPhrase")) {
        $body = '{
            "alias": "'+$alias+'",
            "certificateChain": "'+$chain+'",
            "privateKey": "'+$key+'"
        }'
    } else {
        $body = '{
            "alias": "'+$alias+'",
            "certificateChain": "'+$chain+'",
            "certificatePassphrase": "'+$passPhrase+'",
            "privateKey": "'+$key+'"
        }'
    }
    $uri = "https://$vrslcmAppliance/lcm/locker/api/v2/certificates/import"
    $response = Invoke-RestMethod $uri -Method 'POST' -Headers $vrslcmHeaders -ContentType application/json -body $body
    $response | Select-Object tenant, alias, validity, certInfo
} Catch {
    Invoke-Expression -Command .\vrlscmCatchWriter.ps1
}
