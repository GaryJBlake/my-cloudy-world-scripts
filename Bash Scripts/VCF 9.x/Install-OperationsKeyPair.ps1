<#
.SYNOPSIS
    Uploads a combined keypair .pem file to VCF Operations License Manager via REST API.

.DESCRIPTION
    This function automates the following steps:
    1. Verifies that the provided combined keypair .pem file exists locally.
    2. Authenticates with the VCF Operations Suite API to acquire an access token.
    3. Uploads the keypair .pem file to VCF Operations via POST /suite-api/api/internal/license-manager/identity/keypair.
    4. Optionally verifies the registration status via GET /suite-api/api/internal/license-manager/registration/status.

.PARAMETER VcfOpsHost
    The FQDN or IP address of the VCF Operations instance (e.g., vcf-ops.domain.com).

.PARAMETER Credential
    PSCredential object containing VCF Operations login credentials.

.PARAMETER KeypairPath
    Path to the existing combined .pem keypair file (containing both PRIVATE KEY and PUBLIC KEY blocks).

.PARAMETER VerifyStatus
    Switch parameter to verify that VCF Operations is in private mode and check connectivity status post-upload.

.PARAMETER SkipCertificateCheck
    Bypasses SSL/TLS certificate validation for self-signed or internal certificates.

.EXAMPLE
    $cred = Get-Credential
    Install-OperationsKeyPair -VcfOpsHost "vcf-ops.example.com" `
                              -Credential $cred `
                              -KeypairPath "/tmp/keypair.pem" `
                              -VerifyStatus `
                              -SkipCertificateCheck
#>
function Install-OperationsKeyPair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "VCF Operations FQDN or IP address")]
        [string]$VcfOpsHost,

        [Parameter(Mandatory = $true, HelpMessage = "VCF Operations Credentials")]
        [System.Management.Automation.PSCredential]$Credential,

        [Parameter(Mandatory = $true, HelpMessage = "Path to the combined public/private keypair .pem file")]
        [Alias("PemPath", "FilePath")]
        [string]$KeypairPath,

        [Parameter(Mandatory = $false)]
        [switch]$VerifyStatus,

        [Parameter(Mandatory = $false)]
        [switch]$SkipCertificateCheck
    )

    begin {
        if ($SkipCertificateCheck) {
            # Register a C# certificate validator type if not already present
            if (-not ([System.Management.Automation.PSTypeName]'VcfOpsTrustAllCerts').Type) {
                $code = @"
                    using System.Net;
                    using System.Net.Security;
                    using System.Security.Cryptography.X509Certificates;
                    public class VcfOpsTrustAllCerts {
                        public static bool Validate(object sender, X509Certificate certificate, X509Chain chain, SslPolicyErrors sslPolicyErrors) {
                            return true;
                        }
                    }
"@
                Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
            }

            if ($PSVersionTable.PSVersion.Major -ge 6) {
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            } else {
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = [System.Net.Security.RemoteCertificateValidationCallback]::new([VcfOpsTrustAllCerts]::Validate)
            }
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls
        }
    }

    process {
        try {
            # ---------------------------------------------------------
            # Step 1: Verify Keypair File Existence
            # ---------------------------------------------------------
            Write-Host "[+] Validating the existence of the Key Pair file..." -ForegroundColor Cyan
            
            $targetPath = $KeypairPath
            if (-not (Test-Path -Path $targetPath)) {
                $fileNameOnly = [System.IO.Path]::GetFileName($KeypairPath)
                $cwdPath = Join-Path -Path (Get-Location).Path -ChildPath $fileNameOnly
                $tmpPath = Join-Path -Path "/tmp" -ChildPath $fileNameOnly

                if (Test-Path -Path $cwdPath) {
                    Write-Host "[!] File not found at '$KeypairPath', but found in current directory" -ForegroundColor Yellow
                    $targetPath = $cwdPath
                } elseif (Test-Path -Path $tmpPath) {
                    Write-Host "[!] File not found at '$KeypairPath', but found in /tmp: '$tmpPath'." -ForegroundColor Yellow
                    $targetPath = $tmpPath
                } else {
                    $currentDir = (Get-Location).Path
                    throw "Specified keypair PEM file was not found at '$KeypairPath'. (Current Working Directory: '$currentDir')"
                }
            }

            $resolvedKeypairPath = (Get-Item -Path $targetPath).FullName
            Write-Host "[✓] Using combined keypair file: $resolvedKeypairPath" -ForegroundColor Green

            # Normalize and validate PEM keypair format (ensure 5 dashes, LF line endings, no UTF-8 BOM)
            $pemRawContent = [System.IO.File]::ReadAllText($resolvedKeypairPath)
            $pemCleanContent = $pemRawContent.Trim()

            # Fix headers/footers to standard 5-dash PEM format if needed
            $pemCleanContent = $pemCleanContent -replace "(?m)^-+\s*BEGIN\s+PRIVATE\s+KEY\s*-+", "-----BEGIN PRIVATE KEY-----"
            $pemCleanContent = $pemCleanContent -replace "(?m)^-+\s*END\s+PRIVATE\s+KEY\s*-+", "-----END PRIVATE KEY-----"
            $pemCleanContent = $pemCleanContent -replace "(?m)^-+\s*BEGIN\s+PUBLIC\s+KEY\s*-+", "-----BEGIN PUBLIC KEY-----"
            $pemCleanContent = $pemCleanContent -replace "(?m)^-+\s*END\s+PUBLIC\s+KEY\s*-+", "-----END PUBLIC KEY-----"
            $pemCleanContent = $pemCleanContent -replace "(?m)^-+\s*BEGIN\s+CERTIFICATE\s*-+", "-----BEGIN CERTIFICATE-----"
            $pemCleanContent = $pemCleanContent -replace "(?m)^-+\s*END\s+CERTIFICATE\s*-+", "-----END CERTIFICATE-----"

            # Standardize line endings to LF (\n)
            $pemCleanContent = $pemCleanContent -replace "\r\n", "`n" -replace "\r", "`n" + "`n"

            # Check for essential PEM markers
            $hasPrivateKey = $pemCleanContent -match "-----BEGIN (RSA )?PRIVATE KEY-----"
            $hasPublicKey  = $pemCleanContent -match "-----BEGIN (PUBLIC KEY|CERTIFICATE)-----"

            if (-not $hasPrivateKey) {
                Write-Host "[!] Warning: PEM file is missing '-----BEGIN PRIVATE KEY-----' header." -ForegroundColor Yellow
            }
            if (-not $hasPublicKey) {
                Write-Host "[!] Warning: PEM file is missing '-----BEGIN PUBLIC KEY-----' or '-----BEGIN CERTIFICATE-----' header." -ForegroundColor Yellow
            }

            # Save clean PEM file with original filename without UTF-8 BOM to temporary location
            $originalFileName = [System.IO.Path]::GetFileName($resolvedKeypairPath)
            $uploadPemPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $originalFileName
            $utf8NoBOM = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($uploadPemPath, $pemCleanContent, $utf8NoBOM)

            # ---------------------------------------------------------
            # Steps 2 & 3: Acquire Auth Token (Authorize / Log in)
            # ---------------------------------------------------------
            Write-Host "[+] Authenticating with VCF Operations ($VcfOpsHost)..." -ForegroundColor Cyan
            $authUrl = "https://$VcfOpsHost/suite-api/api/auth/token/acquire"

            $authBody = @{
                username = $Credential.UserName
                password = $Credential.GetNetworkCredential().Password
            } | ConvertTo-Json

            $webSession = [Microsoft.PowerShell.Commands.WebRequestSession]::new()

            $splatAuth = @{
                Uri         = $authUrl
                Method      = 'Post'
                ContentType = 'application/json'
                Headers     = @{ 'Accept' = 'application/json' }
                Body        = $authBody
                WebSession  = $webSession
            }
            if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
                $splatAuth['SkipCertificateCheck'] = $true
            }

            $authResponse = Invoke-RestMethod @splatAuth

            if (-not $authResponse.token) {
                throw "Failed to retrieve authentication token from VCF Operations."
            }

            $token = $authResponse.token
            Write-Host "[✓] Authentication successful." -ForegroundColor Green

            $authHeaders = @{
                'Authorization'                 = "vRealizeOpsToken $token"
                'vRealizeOpsToken'              = $token
                'X-vRealizeOps-API-use-internal' = 'true'
                'X-Ops-API-use-unsupported'     = 'true'
                'Accept'                        = 'application/json, text/plain, */*'
            }

            # ---------------------------------------------------------
            # Steps 4-6: Upload Key Pair (/internal/license-manager/identity/keypair)
            # ---------------------------------------------------------
            Write-Host "[+] Uploading key pair to VCF Operations License Manager..." -ForegroundColor Cyan
            
            $candidateUploadUrls = @(
                "https://$VcfOpsHost/suite-api/api/internal/license-manager/identity/keypair",
                "https://$VcfOpsHost/suite-api/internal/license-manager/identity/keypair"
            )

            $uploadSuccess = $false
            $uploadResult = $null
            $lastUploadError = $null

            foreach ($uploadUrl in $candidateUploadUrls) {
                Write-Verbose "Attempting upload to URL: $uploadUrl"
                try {
                    if ($PSVersionTable.PSVersion.Major -ge 6) {
                        # PowerShell 6+ (PowerShell Core / PS7): Use native Invoke-RestMethod -Form and -WebSession
                        $splatUpload = @{
                            Uri        = $uploadUrl
                            Method     = 'Post'
                            Headers    = $authHeaders
                            Form       = @{
                                file = Get-Item -Path $uploadPemPath
                            }
                            WebSession = $webSession
                        }
                        if ($SkipCertificateCheck) {
                            $splatUpload['SkipCertificateCheck'] = $true
                        }

                        $uploadResult = Invoke-RestMethod @splatUpload
                    } else {
                        # Windows PowerShell 5.1: Use HttpClient with custom C# SSL callback
                        $handler = New-Object System.Net.Http.HttpClientHandler
                        if ($SkipCertificateCheck) {
                            $handler.ServerCertificateCustomValidationCallback = [System.Net.Security.RemoteCertificateValidationCallback]::new([VcfOpsTrustAllCerts]::Validate)
                        }

                        $httpClient = New-Object System.Net.Http.HttpClient($handler)
                        $httpClient.DefaultRequestHeaders.Add("Authorization", "vRealizeOpsToken $token")
                        $httpClient.DefaultRequestHeaders.Add("vRealizeOpsToken", $token)
                        $httpClient.DefaultRequestHeaders.Add("X-vRealizeOps-API-use-internal", "true")
                        $httpClient.DefaultRequestHeaders.Add("X-Ops-API-use-unsupported", "true")
                        $httpClient.DefaultRequestHeaders.Add("Accept", "application/json, text/plain, */*")

                        if ($webSession.Cookies.Count -gt 0) {
                            $cookieContainer = New-Object System.Net.CookieContainer
                            foreach ($cookie in $webSession.Cookies.GetCookies([System.Uri]$uploadUrl)) {
                                $cookieContainer.Add($cookie)
                            }
                            $handler.CookieContainer = $cookieContainer
                        }

                        $multipartContent = New-Object System.Net.Http.MultipartFormDataContent
                        $fileStream = [System.IO.File]::OpenRead($uploadPemPath)
                        $fileContent = New-Object System.Net.Http.StreamContent($fileStream)
                        $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/x-pem-file")
                        
                        $fileName = [System.IO.Path]::GetFileName($uploadPemPath)
                        $multipartContent.Add($fileContent, "file", $fileName)

                        $responseTask = $httpClient.PostAsync($uploadUrl, $multipartContent)
                        $responseTask.Wait()
                        $response = $responseTask.Result

                        $fileStream.Close()
                        $fileStream.Dispose()
                        $httpClient.Dispose()

                        if (-not $response.IsSuccessStatusCode) {
                            $errorResponse = $response.Content.ReadAsStringAsync().Result
                            throw "Upload failed with status code $($response.StatusCode): $errorResponse"
                        }

                        $uploadResult = $response.Content.ReadAsStringAsync().Result
                    }

                    $uploadSuccess = $true
                    Write-Host "[✓] Key pair successfully uploaded to VCF Operations!" -ForegroundColor Green
                    break
                }
                catch {
                    $lastUploadError = $_
                    Write-Verbose "Upload to '$uploadUrl' failed: $_"
                }
            }

            if (-not $uploadSuccess) {
                throw "Keypair upload failed on all candidate endpoints. Last error: $lastUploadError"
            }

            # ---------------------------------------------------------
            # Steps 7 & 8: Optional Status Verification
            # ---------------------------------------------------------
            $statusResult = $null
            if ($VerifyStatus) {
                Write-Host "[+] Verifying registration and private mode status..." -ForegroundColor Cyan
                
                $candidateStatusUrls = @(
                    "https://$VcfOpsHost/suite-api/api/internal/license-manager/registration/status",
                    "https://$VcfOpsHost/suite-api/internal/license-manager/registration/status"
                )

                foreach ($statusUrl in $candidateStatusUrls) {
                    Write-Verbose "Attempting status query to URL: $statusUrl"
                    try {
                        $splatStatus = @{
                            Uri        = $statusUrl
                            Method     = 'Get'
                            Headers    = $authHeaders
                            WebSession = $webSession
                        }
                        if ($SkipCertificateCheck -and $PSVersionTable.PSVersion.Major -ge 6) {
                            $splatStatus['SkipCertificateCheck'] = $true
                        }

                        $statusResult = Invoke-RestMethod @splatStatus
                        Write-Host "[✓] Registration Status Response:" -ForegroundColor Yellow
                        $statusResult | Format-List | Out-String | Write-Host
                        break
                    }
                    catch {
                        Write-Verbose "Status query to '$statusUrl' failed: $_"
                    }
                }
            }

            return [PSCustomObject]@{
                VcfOpsHost         = $VcfOpsHost
                PemFile            = $resolvedKeypairPath
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
