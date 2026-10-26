<#
.SYNOPSIS
    Uploads a combined keypair .pem file to VCF Operations License Manager via REST API.

.DESCRIPTION
    This function automates the following steps in PowerShell Core (PS 7+):
    1. Verifies that the provided combined keypair .pem file exists locally.
    2. Normalizes PEM formatting (5-dash headers, LF line breaks, UTF-8 without BOM).
    3. Authenticates with the VCF Operations Suite API to acquire an access token.
    4. Uploads the keypair .pem file to VCF Operations via POST /suite-api/api/internal/license-manager/identity/keypair.
    5. Optionally verifies the registration status via GET /suite-api/api/internal/license-manager/registration/status.

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
            $pemCleanContent = $pemCleanContent -replace "(?m)^\s*-+\s*BEGIN\s+PRIVATE\s+KEY\s*-+", "-----BEGIN PRIVATE KEY-----"
            $pemCleanContent = $pemCleanContent -replace "(?m)^\s*-+\s*END\s+PRIVATE\s+KEY\s*-+", "-----END PRIVATE KEY-----"
            $pemCleanContent = $pemCleanContent -replace "(?m)^\s*-+\s*BEGIN\s+RSA\s+PRIVATE\s+KEY\s*-+", "-----BEGIN RSA PRIVATE KEY-----"
            $pemCleanContent = $pemCleanContent -replace "(?m)^\s*-+\s*END\s+RSA\s+PRIVATE\s+KEY\s*-+", "-----END RSA PRIVATE KEY-----"
            $pemCleanContent = $pemCleanContent -replace "(?m)^\s*-+\s*BEGIN\s+PUBLIC\s+KEY\s*-+", "-----BEGIN PUBLIC KEY-----"
            $pemCleanContent = $pemCleanContent -replace "(?m)^\s*-+\s*END\s+PUBLIC\s+KEY\s*-+", "-----END PUBLIC KEY-----"
            $pemCleanContent = $pemCleanContent -replace "(?m)^\s*-+\s*BEGIN\s+CERTIFICATE\s*-+", "-----BEGIN CERTIFICATE-----"
            $pemCleanContent = $pemCleanContent -replace "(?m)^\s*-+\s*END\s+CERTIFICATE\s*-+", "-----END CERTIFICATE-----"

            # Standardize line endings to LF (\n)
            $pemCleanContent = ($pemCleanContent -split "\r?\n" | Where-Object { $_ -match "\S" -or $_ -match "-----" }) -join "`n" + "`n"

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
            if ($SkipCertificateCheck) {
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

            # Candidate form field keys expected by backend API (Spring controller)
            $candidateFormKeys = @("file", "keypair", "keyPair")

            $uploadSuccess = $false
            $uploadResult = $null
            $lastUploadError = $null

            foreach ($uploadUrl in $candidateUploadUrls) {
                foreach ($formKey in $candidateFormKeys) {
                    Write-Verbose "Attempting upload to URL: $uploadUrl (Form field: $formKey)"
                    try {
                        $splatUpload = @{
                            Uri        = $uploadUrl
                            Method     = 'Post'
                            Headers    = $authHeaders
                            Form       = @{
                                $formKey = Get-Item -Path $uploadPemPath
                            }
                            WebSession = $webSession
                        }
                        if ($SkipCertificateCheck) {
                            $splatUpload['SkipCertificateCheck'] = $true
                        }

                        $uploadResult = Invoke-RestMethod @splatUpload
                        $uploadSuccess = $true
                        Write-Host "[✓] Key pair successfully uploaded to VCF Operations!" -ForegroundColor Green
                        break
                    }
                    catch {
                        $lastUploadError = $_
                        if ($_.Exception.Response) {
                            try {
                                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                                $resBody = $reader.ReadToEnd()
                                $reader.Close()
                                if ($resBody) { $lastUploadError = $resBody }
                            } catch {}
                        }
                        Write-Verbose "Upload to '$uploadUrl' with form field '$formKey' failed: $lastUploadError"
                    }
                }
                if ($uploadSuccess) { break }
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
                        if ($SkipCertificateCheck) {
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
