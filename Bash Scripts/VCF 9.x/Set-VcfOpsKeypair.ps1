<#
.SYNOPSIS
    Combines public and private keys into a single .pem file and uploads them to VCF Operations License Manager via REST API.

.DESCRIPTION
    This function automates the following steps:
    1. Combines a Private Key and Public Key into a single formatted .pem file.
    2. Authenticates with the VCF Operations Suite API to acquire an access token.
    3. Uploads the keypair .pem file to VCF Operations via POST /suite-api/internal/license-manager/identity/keypair.
    4. Optionally verifies the registration status via GET /suite-api/internal/license-manager/registration/status.

.PARAMETER VcfOpsHost
    The FQDN or IP address of the VCF Operations instance (e.g., vcf-ops.domain.com).

.PARAMETER Credential
    PSCredential object containing VCF Operations login credentials.

.PARAMETER PrivateKeyPath
    Path to the file containing the Private Key (or raw private key string).

.PARAMETER PublicKeyPath
    Path to the file containing the Public Key (or raw public key string).

.PARAMETER PemPath
    Path to an existing combined .pem keypair file (if not combining separate keys).

.PARAMETER OutputFile
    Path where the combined .pem file will be saved when combining keys. Defaults to '/tmp/keypair.pem'.

.PARAMETER VerifyStatus
    Switch parameter to verify that VCF Operations is in private mode and check connectivity status post-upload.

.PARAMETER SkipCertificateCheck
    Bypasses SSL/TLS certificate validation for self-signed or internal certificates.

.EXAMPLE
    $cred = Get-Credential
    Set-VcfOpsKeypair -VcfOpsHost "vcf-ops.example.com" `
                      -Credential $cred `
                      -PrivateKeyPath "./private.key" `
                      -PublicKeyPath "./public.key" `
                      -OutputFile "/tmp/keypair.pem" `
                      -VerifyStatus `
                      -SkipCertificateCheck

.EXAMPLE
    $cred = Get-Credential
    Set-VcfOpsKeypair -VcfOpsHost "vcf-ops.example.com" `
                      -Credential $cred `
                      -PemPath "/tmp/keypair.pem" `
                      -VerifyStatus `
                      -SkipCertificateCheck
#>
function Set-VcfOpsKeypair {
    [CmdletBinding(DefaultParameterSetName = 'SeparateKeys')]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "VCF Operations FQDN or IP address")]
        [string]$VcfOpsHost,

        [Parameter(Mandatory = $true, HelpMessage = "VCF Operations Credentials")]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $true, ParameterSetName = 'SeparateKeys', HelpMessage = "Path to private key file or key string")]
        [string]$PrivateKeyPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'SeparateKeys', HelpMessage = "Path to public key file or key string")]
        [string]$PublicKeyPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'CombinedPem', HelpMessage = "Path to already existing combined .pem file")]
        [string]$PemPath,

        [Parameter(Mandatory = $false)]
        [string]$OutputFile = "/tmp/keypair.pem",

        [Parameter(Mandatory = $false)]
        [switch]$VerifyStatus,

        [Parameter(Mandatory = $false)]
        [switch]$SkipCertificateCheck
    )

    begin {
        # Configure SSL / TLS bypass if requested for Windows PowerShell 5.1
        if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -lt 6) {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        }
    }

    process {
        try {
            # ---------------------------------------------------------
            # Step 1: Combine Public & Private key in single .pem file
            # ---------------------------------------------------------
            if ($PSCmdlet.ParameterSetName -eq 'SeparateKeys') {
                Write-Verbose "Reading private and public key inputs..."

                if (Test-Path -Path $PrivateKeyPath) {
                    $privateKey = Get-Content -Path $PrivateKeyPath -Raw
                } else {
                    $privateKey = $PrivateKeyPath
                }

                if (Test-Path -Path $PublicKeyPath) {
                    $publicKey = Get-Content -Path $PublicKeyPath -Raw
                } else {
                    $publicKey = $PublicKeyPath
                }

                # Standardize PEM headers and footers (ensure 5 dashes)
                $privateKey = $privateKey.Trim()
                if (-not ($privateKey -match "^\s*-----BEGIN PRIVATE KEY-----")) {
                    $privateKey = $privateKey -replace "^---BEGIN PRIVATE KEY---", "" -replace "---END PRIVATE KEY---$", ""
                    $privateKey = "-----BEGIN PRIVATE KEY-----`n" + $privateKey.Trim() + "`n-----END PRIVATE KEY-----"
                }

                $publicKey = $publicKey.Trim()
                if (-not ($publicKey -match "^\s*-----BEGIN PUBLIC KEY-----")) {
                    $publicKey = $publicKey -replace "^---BEGIN PUBLIC KEY---", "" -replace "---END PUBLIC KEY---$", ""
                    $publicKey = "-----BEGIN PUBLIC KEY-----`n" + $publicKey.Trim() + "`n-----END PUBLIC KEY-----"
                }

                # Concatenate in specified format (Private Key followed by Public Key)
                $combinedPemContent = "$privateKey`n$publicKey`n"

                Write-Host "Saving combined PEM file to: $OutputFile" -ForegroundColor Cyan
                $outputDir = [System.IO.Path]::GetDirectoryName($OutputFile)
                if (-not [string]::IsNullOrEmpty($outputDir) -and -not (Test-Path $outputDir)) {
                    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
                }
                [System.IO.File]::WriteAllText($OutputFile, $combinedPemContent)
                $targetPemPath = $OutputFile
            } else {
                $targetPemPath = $PemPath
            }

            if (-not (Test-Path $targetPemPath)) {
                throw "PEM file not found at path: $targetPemPath"
            }

            # Prepare Base REST API URL
            $baseUrl = "https://$VcfOpsHost/suite-api"

            # ---------------------------------------------------------
            # Steps 2 & 3: Acquire Auth Token (Authorize / Log in)
            # ---------------------------------------------------------
            Write-Host "Authenticating with VCF Operations ($VcfOpsHost)..." -ForegroundColor Cyan
            $authUrl = "$baseUrl/api/auth/token/acquire"

            $authBody = @{
                username = $Credential.UserName
                password = $Credential.GetNetworkCredential().Password
            } | ConvertTo-Json

            $splatAuth = @{
                Uri         = $authUrl
                Method      = 'Post'
                ContentType = 'application/json'
                Headers     = @{ 'Accept' = 'application/json' }
                Body        = $authBody
            }
            if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
                $splatAuth['SkipCertificateCheck'] = $true
            }

            $authResponse = Invoke-RestMethod @splatAuth

            if (-not $authResponse.token) {
                throw "Failed to retrieve authentication token from VCF Operations."
            }

            $token = $authResponse.token
            Write-Host "Authentication successful." -ForegroundColor Green

            $authHeaders = @{
                'Authorization' = "vRealizeOpsToken $token"
                'Accept'        = 'application/json'
            }

            # ---------------------------------------------------------
            # Steps 4-6: Upload Key Pair (/internal/license-manager/identity/keypair)
            # ---------------------------------------------------------
            Write-Host "Uploading key pair to VCF Operations License Manager (/internal/license-manager/identity/keypair)..." -ForegroundColor Cyan
            $uploadUrl = "$baseUrl/internal/license-manager/identity/keypair"

            # Cross-platform HttpClient for multipart form-data upload
            $handler = New-Object System.Net.Http.HttpClientHandler
            if ($SkipCertificateCheck) {
                $handler.ServerCertificateCustomValidationCallback = { $true }
            }

            $httpClient = New-Object System.Net.Http.HttpClient($handler)
            $httpClient.DefaultRequestHeaders.Add("Authorization", "vRealizeOpsToken $token")
            $httpClient.DefaultRequestHeaders.Add("Accept", "application/json")

            $multipartContent = New-Object System.Net.Http.MultipartFormDataContent
            $fileStream = [System.IO.File]::OpenRead($targetPemPath)
            $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
            $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/x-pem-file")
            
            $fileName = [System.IO.Path]::GetFileName($targetPemPath)
            $multipartContent.Add($fileContent, "file", $fileName)

            $responseTask = $httpClient.PostAsync($uploadUrl, $multipartContent)
            $responseTask.Wait()
            $response = $responseTask.Result

            $fileStream.Close()
            $fileStream.Dispose()
            $httpClient.Dispose()

            if (-not $response.IsSuccessStatusCode) {
                $errorResponse = $response.Content.ReadAsStringAsync().Result
                throw "Keypair upload failed with status code $($response.StatusCode): $errorResponse"
            }

            $uploadResult = $response.Content.ReadAsStringAsync().Result
            Write-Host "Key pair successfully uploaded to VCF Operations!" -ForegroundColor Green

            # ---------------------------------------------------------
            # Steps 7 & 8: Optional Status Verification
            # ---------------------------------------------------------
            $statusResult = $null
            if ($VerifyStatus) {
                Write-Host "Verifying registration and private mode status (/internal/license-manager/registration/status)..." -ForegroundColor Cyan
                $statusUrl = "$baseUrl/internal/license-manager/registration/status"

                $splatStatus = @{
                    Uri     = $statusUrl
                    Method  = 'Get'
                    Headers = $authHeaders
                }
                if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
                    $splatStatus['SkipCertificateCheck'] = $true
                }

                $statusResult = Invoke-RestMethod @splatStatus
                Write-Host "Registration Status Response:" -ForegroundColor Yellow
                $statusResult | Format-List | Out-String | Write-Host
            }

            return [PSCustomObject]@{
                VcfOpsHost         = $VcfOpsHost
                PemFile            = $targetPemPath
                UploadStatus       = "Success"
                UploadResponse     = $uploadResult
                RegistrationStatus = $statusResult
            }
        }
        catch {
            Write-Error "Error uploading key pair to VCF Operations: $_"
            throw $_
        }
    }
}
