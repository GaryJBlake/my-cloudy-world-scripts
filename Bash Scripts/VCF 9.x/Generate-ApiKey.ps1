<#
.SYNOPSIS
    Generates a cryptographically secure API Key combining today's date and a high-entropy random byte string.

.DESCRIPTION
    This script generates an API Key composed of:
    1. A configurable prefix (e.g., 'API' or 'SK').
    2. Today's date formatted according to a specified date format (default: 'yyyyMMdd').
    3. A cryptographically secure random string backed by 96 bits (12 bytes) of system entropy using .NET's RandomNumberGenerator.

    Supported encodings for entropy bytes:
    - Hex: 24-character hexadecimal string (96 bits = 12 bytes).
    - Base64Url: 16-character URL-safe base64 string without padding.
    - Base32: 20-character base32 RFC 4648 string (case-insensitive, URL-safe).

.PARAMETER Prefix
    Optional prefix for the API key (e.g., 'API', 'KEY', 'DEV', 'PROD'). Default is 'API'.

.PARAMETER DateFormat
    Date format specifier. Default is 'yyyyMMdd' (e.g., 20261026).

.PARAMETER EntropyBits
    Number of bits of cryptographic entropy to generate. Default is 96 bits (12 bytes).

.PARAMETER Encoding
    Encoding format for the random bytes: 'Hex', 'Base64Url', or 'Base32'. Default is 'Hex'.

.PARAMETER Separator
    Character used to separate the prefix, date, and random string components. Default is '-'.

.EXAMPLE
    .\Generate-ApiKey.ps1

    Output:
    API-20261026-4F8A2B9C1E3D5F7A0B2C4E6F

.EXAMPLE
    .\Generate-ApiKey.ps1 -Prefix "sk_live" -Encoding Base64Url -Separator "_"

    Output:
    sk_live_20261026_oW9-xR3kL2mP8vQn

.EXAMPLE
    Import-Module .\Generate-ApiKey.ps1
    Get-RandomApiKey -EntropyBits 128 -Encoding Hex
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Prefix = "API",

    [Parameter(Mandatory = $false)]
    [string]$DateFormat = "yyyyMMdd",

    [Parameter(Mandatory = $false)]
    [int]$EntropyBits = 96,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Hex", "Base64Url", "Base32")]
    [string]$Encoding = "Hex",

    [Parameter(Mandatory = $false)]
    [string]$Separator = "-"
)

function New-CryptographicBytes {
    param([int]$BitCount)

    # Calculate required bytes (96 bits = 12 bytes)
    $byteCount = [math]::Ceiling($BitCount / 8.0)
    $bytes = [byte[]]::new($byteCount)

    # Use system CSPRNG (BCryptGenRandom / /dev/urandom)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }

    return $bytes
}

function Convert-BytesToBase32 {
    param([byte[]]$Bytes)

    $alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    $output = [System.Text.StringBuilder]::new()
    
    $bitBuffer = 0
    $bitCount = 0

    foreach ($b in $Bytes) {
        $bitBuffer = ($bitBuffer -shl 8) -bor $b
        $bitCount += 8

        while ($bitCount -ge 5) {
            $bitCount -= 5
            $index = ($bitBuffer -shr $bitCount) -band 0x1F
            [void]$output.Append($alphabet[$index])
        }
    }

    if ($bitCount -gt 0) {
        $index = ($bitBuffer -shl (5 - $bitCount)) -band 0x1F
        [void]$output.Append($alphabet[$index])
    }

    return $output.ToString()
}

function Get-RandomApiKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Prefix = "API",

        [Parameter(Mandatory = $false)]
        [string]$DateFormat = "yyyyMMdd",

        [Parameter(Mandatory = $false)]
        [int]$EntropyBits = 96,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Hex", "Base64Url", "Base32")]
        [string]$Encoding = "Hex",

        [Parameter(Mandatory = $false)]
        [string]$Separator = "-"
    )

    process {
        # 1. Obtain cryptographically strong random entropy
        $randomBytes = New-CryptographicBytes -BitCount $EntropyBits

        # 2. Encode the random bytes
        $entropyString = switch ($Encoding) {
            "Hex" {
                [System.BitConverter]::ToString($randomBytes) -replace '-'
            }
            "Base64Url" {
                $base64 = [System.Convert]::ToBase64String($randomBytes)
                $base64.TrimEnd('=').Replace('+', '-').Replace('/', '_')
            }
            "Base32" {
                Convert-BytesToBase32 -Bytes $randomBytes
            }
        }

        # 3. Generate date component
        $dateString = (Get-Date).ToString($DateFormat)

        # 4. Construct final key
        $components = [System.Collections.Generic.List[string]]::new()
        if (-not [string]::IsNullOrWhiteSpace($Prefix)) {
            $components.Add($Prefix)
        }
        $components.Add($dateString)
        $components.Add($entropyString)

        return ($components -join $Separator)
    }
}

# If the script is executed directly (not sourced or imported), output a generated key.
if ($MyInvocation.InvocationName -ne '.') {
    Get-RandomApiKey -Prefix $Prefix -DateFormat $DateFormat -EntropyBits $EntropyBits -Encoding $Encoding -Separator $Separator
}
