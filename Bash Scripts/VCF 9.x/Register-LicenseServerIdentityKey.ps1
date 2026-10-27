<#
.SYNOPSIS
    Uploads/registers a private key PEM file to the VCF License Server identity key endpoint.

.DESCRIPTION
    This script/function posts a private key file to the VCF License Server identity API endpoint
    (/lss/external/api/v1/identity/key) using X-API-Key authentication header.

.PARAMETER LicenseServerFqdn
    The FQDN of the License Server. Default: "sfo-lc01.sfo.rainpole.io".

.PARAMETER ApiKey
    The API key for authentication via the X-API-Key header. Default: "API-20261027-CD0EA41F964A2C23ADD560A6".

.PARAMETER PrivateKeyPemFilePath
    Path to the private key PEM file. Default: "./sfo-lc01.sfo.rainpole.io-private_key.pem".

.PARAMETER SkipCertificateCheck
    Switch parameter to bypass SSL/TLS certificate validation. Default: Enabled.

.EXAMPLE
    Register-LicenseServerIdentityKey

.EXAMPLE
    Register-LicenseServerIdentityKey -LicenseServerFqdn "sfo-lc01.sfo.rainpole.io" `
                                      -ApiKey "API-20261027-CD0EA41F964A2C23ADD560A6" `
                                      -PrivateKeyPemFilePath "./sfo-lc01.sfo.rainpole.io-private_key.pem"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$LicenseServerFqdn = "sfo-lc01.sfo.rainpole.io",

    [Parameter(Mandatory = $false, Position = 1)]
    [string]$ApiKey = "API-20261027-CD0EA41F964A2C23ADD560A6",

    [Parameter(Mandatory = $false, Position = 2)]
    [string]$PrivateKeyPemFilePath = "./sfo-lc01.sfo.rainpole.io-private_key.pem",

    [Parameter(Mandatory = $false)]
    [switch]$SkipCertificateCheck = $true
)

function Register-LicenseServerIdentityKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$LicenseServerFqdn = "sfo-lc01.sfo.rainpole.io",

        [Parameter(Mandatory = $false, Position = 1)]
        [string]$ApiKey = "API-20261027-CD0EA41F964A2C23ADD560A6",

        [Parameter(Mandatory = $false, Position = 2)]
        [string]$PrivateKeyPemFilePath = "./sfo-lc01.sfo.rainpole.io-private_key.pem",

        [Parameter(Mandatory = $false)]
        [switch]$SkipCertificateCheck = $true
    )

    process {
        if (-not (Test-Path -Path $PrivateKeyPemFilePath)) {
            throw "Private key PEM file was not found at path: '$PrivateKeyPemFilePath'"
        }

        $pemItem = Get-Item -Path $PrivateKeyPemFilePath
        $licenseServerHeaders = @{
            "X-API-Key" = $ApiKey
        }

        $uri = "https://${LicenseServerFqdn}/lss/external/api/v1/identity/key"

        $restParams = @{
            Uri     = $uri
            Method  = "Post"
            Headers = $licenseServerHeaders
            Form    = @{ file = $pemItem }
        }

        if ($SkipCertificateCheck) {
            $restParams["SkipCertificateCheck"] = $true
        }

        Write-Verbose "Uploading private key '$PrivateKeyPemFilePath' to '$uri'..."
        return Invoke-RestMethod @restParams
    }
}

# If the script is executed directly (not dot-sourced), execute the function.
if ($MyInvocation.InvocationName -ne '.') {
    Register-LicenseServerIdentityKey -LicenseServerFqdn $LicenseServerFqdn `
                                      -ApiKey $ApiKey `
                                      -PrivateKeyPemFilePath $PrivateKeyPemFilePath `
                                      -SkipCertificateCheck:$SkipCertificateCheck
}
