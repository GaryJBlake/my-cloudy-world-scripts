<#
.SYNOPSIS
    Polls the License Manager registration status API until the mode transitions to PRIVATE.

.DESCRIPTION
    This function repeatedly queries the GET /api/license-manager/registration/status?includeXr2
    endpoint until the returned mode matches 'PRIVATE' or until the specified timeout is reached.
    Uses the global $operationsFqdn and $operationsHeaders variables.

.PARAMETER TimeoutSeconds
    Maximum duration in seconds to poll the API before timing out. Default: 300 seconds (5 minutes).

.PARAMETER IntervalSeconds
    Time interval in seconds between consecutive polling requests. Default: 10 seconds.

.PARAMETER SkipCertificateCheck
    Bypasses SSL/TLS certificate validation. Default: Enabled.

.EXAMPLE
    Wait-LicenseRegistrationStatus

.EXAMPLE
    Wait-LicenseRegistrationStatus -TimeoutSeconds 600 -IntervalSeconds 5

.OUTPUTS
    PSCustomObject containing TargetReached, FinalMode, Attempts, ElapsedTimeSec, and StatusResponse.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 300,

    [Parameter(Mandatory = $false)]
    [int]$IntervalSeconds = 10,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCertificateCheck = $true
)

function Wait-LicenseRegistrationStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 300,

        [Parameter(Mandatory = $false)]
        [int]$IntervalSeconds = 10,

        [Parameter(Mandatory = $false)]
        [switch]$SkipCertificateCheck = $true
    )

    process {
        # 1. Define target mode and build request URI using $operationsFqdn
        $targetMode = "PRIVATE"
        $uri = "https://${operationsFqdn}/suite-api/internal/license-manager/registration"

        Write-Host "[+] Polling API endpoint: $uri" -ForegroundColor Cyan
        Write-Host "[+] Target Mode: '$targetMode' | Timeout: ${TimeoutSeconds}s | Interval: ${IntervalSeconds}s" -ForegroundColor Cyan

        $internalHeaders = @{}
        foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
        $internalHeaders["X-Ops-API-use-unsupported"] = "true"
        $internalHeaders["X-vRealizeOps-API-use-internal"] = "true"

        # 2. Setup REST Call Parameters using global $operationsHeaders
        $restParams = @{
            Uri         = $uri
            Method      = 'Get'
            Headers     = $internalHeaders
        }

        if ($SkipCertificateCheck) {
            if ($PSVersionTable.PSVersion.Major -ge 7) {
                $restParams['SkipCertificateCheck'] = $true
            } else {
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            }
        }

        # 3. Polling Loop
        $startTime = Get-Date
        $attempt = 0
        $currentMode = $null
        $lastResponse = $null

        while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
            $attempt++
            $elapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)

            try {
                Write-Verbose "Attempt $attempt (${elapsed}s elapsed): Querying $uri..."
                $response = Invoke-RestMethod @restParams
                $lastResponse = $response

                # Extract mode from response payload across common API property naming structures
                $currentMode = $null
                if ($null -ne $response) {
                    if ($response.PSObject.Properties['mode']) {
                        $currentMode = $response.mode
                    } elseif ($response.PSObject.Properties['registrationStatus'] -and $response.registrationStatus.PSObject.Properties['mode']) {
                        $currentMode = $response.registrationStatus.mode
                    } elseif ($response.PSObject.Properties['registrationMode']) {
                        $currentMode = $response.registrationMode
                    } elseif ($response.PSObject.Properties['status'] -and $response.status.PSObject.Properties['mode']) {
                        $currentMode = $response.status.mode
                    } elseif ($response.PSObject.Properties['licenseMode']) {
                        $currentMode = $response.licenseMode
                    }
                }

                Write-Host ("[{0:HH:mm:ss}] Attempt {1} ({2}s): Current mode = '{3}'" -f (Get-Date), $attempt, $elapsed, $currentMode) -ForegroundColor Yellow

                if ($null -ne $currentMode -and $currentMode.ToString().Equals($targetMode, [System.StringComparison]::OrdinalIgnoreCase)) {
                    Write-Host ("[{0:HH:mm:ss}] [✓] Target mode '$targetMode' reached successfully after {1} attempt(s) ({2}s)!" -f (Get-Date), $attempt, $elapsed) -ForegroundColor Green

                    return [PSCustomObject]@{
                        TargetReached  = $true
                        FinalMode      = $currentMode
                        Attempts       = $attempt
                        ElapsedTimeSec = $elapsed
                        StatusResponse = $response
                    }
                }
            }
            catch {
                Write-Host ("[{0:HH:mm:ss}] Attempt {1} ({2}s): API Request failed: {3}" -f (Get-Date), $attempt, $elapsed, $_.Exception.Message) -ForegroundColor Red
            }

            Start-Sleep -Seconds $IntervalSeconds
        }

        # Timeout reached
        $totalElapsed = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
        $errorMessage = "Timed out after $totalElapsed seconds ($attempt attempts). Mode did not transition to '$targetMode' (Last mode: '$currentMode')."
        Write-Error $errorMessage

        return [PSCustomObject]@{
            TargetReached  = $false
            FinalMode      = $currentMode
            Attempts       = $attempt
            ElapsedTimeSec = $totalElapsed
            StatusResponse = $lastResponse
        }
    }
}

# If the script is executed directly (not dot-sourced), run the function.
if ($MyInvocation.InvocationName -ne '.') {
    Wait-LicenseRegistrationStatus -TimeoutSeconds $TimeoutSeconds `
                                  -IntervalSeconds $IntervalSeconds `
                                  -SkipCertificateCheck:$SkipCertificateCheck
}
