<#
.SYNOPSIS
    Generates an RSA Public/Private Key Pair using OpenSSL and combines them into a single PEM keypair file.

.DESCRIPTION
    This script executes OpenSSL commands to:
    1. Generate an RSA Private Key (`openssl genpkey -algorithm RSA -out private_key.pem -pkeyopt rsa_keygen_bits:<Bits>`).
    2. Extract the RSA Public Key (`openssl rsa -pubout -in private_key.pem -out public_key.pem`).
    3. Combine the Private Key and Public Key into a single PEM file (`keypair.pem`).

.PARAMETER OutputDirectory
    Directory where the output PEM files will be created. Defaults to the current working directory.

.PARAMETER PrivateKeyFile
    Filename or path for the generated RSA Private Key. Default is 'private_key.pem'.

.PARAMETER PublicKeyFile
    Filename or path for the generated RSA Public Key. Default is 'public_key.pem'.

.PARAMETER CombinedKeyFile
    Filename or path for the combined Private and Public Key Pair file. Default is 'keypair.pem'.

.PARAMETER KeyBits
    RSA key size in bits. Default is 4096.

.PARAMETER Overwrite
    Overwrites existing key files if set. Without this switch, the script will abort if destination files exist.

.EXAMPLE
    .\New-RsaKeyPair.ps1

    Generates private_key.pem, public_key.pem, and keypair.pem (4096-bit RSA) in the current directory.

.EXAMPLE
    .\New-RsaKeyPair.ps1 -OutputDirectory "./certs" -KeyBits 4096 -Overwrite

    Generates 4096-bit RSA keys in the './certs' directory, overwriting any existing key files.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = ".",

    [Parameter(Mandatory = $false)]
    [string]$PrivateKeyFile = "private_key.pem",

    [Parameter(Mandatory = $false)]
    [string]$PublicKeyFile = "public_key.pem",

    [Parameter(Mandatory = $false)]
    [string]$CombinedKeyFile = "keypair.pem",

    [Parameter(Mandatory = $false)]
    [int]$KeyBits = 4096,

    [Parameter(Mandatory = $false)]
    [switch]$Overwrite,

    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

process {
    try {
        # Helper function to output status messages unless -Quiet is specified
        function Write-Status {
            param(
                [string]$Message,
                [System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::White
            )
            if (-not $Quiet) {
                Write-Host $Message -ForegroundColor $ForegroundColor
            }
        }

        # 1. Check if openssl is installed and accessible in PATH
        if (-not (Get-Command "openssl" -ErrorAction SilentlyContinue)) {
            throw "OpenSSL executable ('openssl') was not found in PATH. Please install OpenSSL and ensure it is available in your environment path."
        }

        # Determine the execution folder of the script (where script file resides)
        $scriptDir = if ($PSScriptRoot) {
            $PSScriptRoot
        } elseif ($MyInvocation.MyCommand.Path) {
            Split-Path -Parent $MyInvocation.MyCommand.Path
        } else {
            $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.Path
        }

        $system32Path = [System.IO.Path]::GetFullPath((Join-Path -Path $env:SystemRoot -ChildPath "System32"))

        # Helper function to prevent any path from being directed to System32
        function Resolve-SafeFilePath {
            param(
                [string]$FileNameOrPath,
                [string]$DefaultDirectory
            )

            if ([string]::IsNullOrWhiteSpace($FileNameOrPath)) {
                return $null
            }

            $resolved = if ([System.IO.Path]::IsPathRooted($FileNameOrPath)) {
                $FileNameOrPath
            } else {
                Join-Path -Path $DefaultDirectory -ChildPath $FileNameOrPath
            }

            $fullPath = [System.IO.Path]::GetFullPath($resolved)

            if ($fullPath.StartsWith($system32Path, [System.StringComparison]::OrdinalIgnoreCase)) {
                $fileNameOnly = [System.IO.Path]::GetFileName($fullPath)
                $redirected = Join-Path -Path $scriptDir -ChildPath $fileNameOnly
                Write-Host "[!] Target file '$fullPath' was directed to System32. Redirecting to script execution folder: '$redirected'" -ForegroundColor Yellow
                return [System.IO.Path]::GetFullPath($redirected)
            }

            return $fullPath
        }

        # 2. Resolve output directory base folder
        $targetBaseDir = $scriptDir
        if (-not [string]::IsNullOrWhiteSpace($OutputDirectory) -and $OutputDirectory -ne ".") {
            $candidateDir = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) {
                $OutputDirectory
            } else {
                Join-Path -Path $scriptDir -ChildPath $OutputDirectory
            }
            $candidateDir = [System.IO.Path]::GetFullPath($candidateDir)

            if ($candidateDir.StartsWith($system32Path, [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host "[!] OutputDirectory '$candidateDir' resolved to System32. Forcing output to script execution folder: '$scriptDir'" -ForegroundColor Yellow
                $targetBaseDir = $scriptDir
            } else {
                $targetBaseDir = $candidateDir
            }
        }

        $resolvedDir = [System.IO.Path]::GetFullPath($targetBaseDir)
        if (-not (Test-Path -Path $resolvedDir)) {
            Write-Status "[+] Creating output directory: $resolvedDir" -ForegroundColor Cyan
            [void](New-Item -ItemType Directory -Path $resolvedDir -Force)
        }

        # 3. Construct absolute target file paths, enforcing execution directory over System32
        $privateKeyPath  = Resolve-SafeFilePath -FileNameOrPath $PrivateKeyFile  -DefaultDirectory $resolvedDir
        $publicKeyPath   = Resolve-SafeFilePath -FileNameOrPath $PublicKeyFile   -DefaultDirectory $resolvedDir
        $combinedKeyPath = Resolve-SafeFilePath -FileNameOrPath $CombinedKeyFile -DefaultDirectory $resolvedDir

        # Ensure target parent directories exist
        foreach ($filePath in @($privateKeyPath, $publicKeyPath, $combinedKeyPath)) {
            $parentDir = [System.IO.Path]::GetDirectoryName($filePath)
            if ($parentDir -and -not (Test-Path -Path $parentDir)) {
                [void](New-Item -ItemType Directory -Path $parentDir -Force)
            }
        }

        # 4. Check for existing files unless -Overwrite is specified
        $existingFiles = @($privateKeyPath, $publicKeyPath, $combinedKeyPath) | Where-Object { Test-Path -Path $_ }
        if ($existingFiles.Count -gt 0 -and -not $Overwrite) {
            throw "The following target file(s) already exist:`n$($existingFiles -join "`n")`nUse -Overwrite parameter to allow replacing existing files."
        }

        Write-Status "==========================================================" -ForegroundColor Cyan
        Write-Status " Generating RSA Key Pair ($KeyBits-bit) using OpenSSL" -ForegroundColor Cyan
        Write-Status " Output Directory: $resolvedDir" -ForegroundColor Cyan
        Write-Status "==========================================================" -ForegroundColor Cyan

        # Step 1: Generate Private Key
        # openssl genpkey -algorithm RSA -out private_key.pem -pkeyopt rsa_keygen_bits:4096
        Write-Status "[+] Step 1: Generating RSA Private Key ($KeyBits bits)..." -ForegroundColor Cyan
        $genPkeyArgs = @(
            "genpkey",
            "-algorithm", "RSA",
            "-out", $privateKeyPath,
            "-pkeyopt", "rsa_keygen_bits:$KeyBits"
        )
        Write-Verbose "Executing: openssl $($genPkeyArgs -join ' ')"
        $genPkeyOutput = & openssl @genPkeyArgs 2>&1

        if ($LASTEXITCODE -ne 0) {
            $errDetail = ($genPkeyOutput | Out-String).Trim()
            throw "OpenSSL failed to generate private key. OpenSSL returned exit code $LASTEXITCODE. Details: $errDetail"
        }
        if (-not (Test-Path -Path $privateKeyPath)) {
            throw "OpenSSL returned exit code 0, but the expected private key file was not created at '$privateKeyPath'."
        }
        Write-Status "[✓] Created private key: $privateKeyPath" -ForegroundColor Green

        # Step 2: Extract Public Key
        # openssl rsa -pubout -in private_key.pem -out public_key.pem
        Write-Status "[+] Step 2: Extracting RSA Public Key..." -ForegroundColor Cyan
        $rsaPubArgs = @(
            "rsa",
            "-pubout",
            "-in", $privateKeyPath,
            "-out", $publicKeyPath
        )
        Write-Verbose "Executing: openssl $($rsaPubArgs -join ' ')"
        $rsaPubOutput = & openssl @rsaPubArgs 2>&1

        if ($LASTEXITCODE -ne 0) {
            $errDetail = ($rsaPubOutput | Out-String).Trim()
            throw "OpenSSL failed to extract public key. OpenSSL returned exit code $LASTEXITCODE. Details: $errDetail"
        }
        if (-not (Test-Path -Path $publicKeyPath)) {
            throw "OpenSSL returned exit code 0, but the expected public key file was not created at '$publicKeyPath'."
        }
        Write-Status "[✓] Created public key: $publicKeyPath" -ForegroundColor Green

        # Step 3: Combine Private Key and Public Key into Keypair File
        # cat private_key.pem public_key.pem > keypair.pem
        Write-Status "[+] Step 3: Combining private and public key into combined keypair..." -ForegroundColor Cyan
        $privateContent = [System.IO.File]::ReadAllText($privateKeyPath)
        $publicContent  = [System.IO.File]::ReadAllText($publicKeyPath)

        # Cleanly join content with LF newlines without UTF-8 BOM
        $combinedContent = $privateContent.TrimEnd() + "`n" + $publicContent.TrimEnd() + "`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($combinedKeyPath, $combinedContent, $utf8NoBom)

        if (-not (Test-Path -Path $combinedKeyPath)) {
            throw "Failed to create combined keypair file at '$combinedKeyPath'."
        }
        Write-Status "[✓] Created combined keypair: $combinedKeyPath" -ForegroundColor Green

        Write-Status "`n[✓] Key pair generation completed successfully!" -ForegroundColor Green

        # Return result object
        return [PSCustomObject]@{
            PrivateKeyPath  = $privateKeyPath
            PublicKeyPath   = $publicKeyPath
            CombinedKeyPath = $combinedKeyPath
            KeyBits         = $KeyBits
            Timestamp       = (Get-Date)
        }
    }
    catch {
        Write-Error "An error occurred during key pair generation: $_"
        throw $_
    }
}
