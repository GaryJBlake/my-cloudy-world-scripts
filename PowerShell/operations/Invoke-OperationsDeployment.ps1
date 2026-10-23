<#
    .SYNOPSIS
    Deployment of VCF Operations and License Server Appliances

    .DESCRIPTION
    The Invoke-OperationsDeployment cmdlet is a single function to deploy and configure VCF Operations and
    License Server.

    .EXAMPLE
    Invoke-OperationsDeployment -jsonFile .\operationsDeploySpec.json
    This example deploy and configure VCF Operations and License Server using the JSON spec supplied.

    .PARAMETER jsonFile
    The path to the JSON specification file to be used.
#>

Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$jsonFile
)

$solutionName = "VCF Operations and License Server"

# Store default preference
$previousProgressPreference = $ProgressPreference
# Suppress native cmdlet progress bars
$ProgressPreference = 'SilentlyContinue'


function Test-VsphereAuthentication {
    param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass
    )

    try {
        Write-Host "[+] Attempting to connect to vCenter: $server" -ForegroundColor Cyan
        Connect-VIServer -Server $server -User $user -pass $pass -ErrorAction SilentlyContinue | Out-Null
        if ($DefaultVIServer.Name -eq $server) {
            Write-Host "[✓] Connected successfully to vCenter: $server" -ForegroundColor Green
            $vsphereAuthentication = $True
            Return $vsphereAuthentication
        } else {
            Write-Host "[x] Unable to authenticate to vCenter: $server" -ForegroundColor Red
            $vsphereAuthentication = $False
            return $vsphereAuthentication
        }
    } catch {
        # Do Nothing
    }
}

function Get-VCFNodeThumbprint {
    param(
        [Parameter(Mandatory = $true)] [string]$fqdn, [int]$port = 443
    )

    try {
        # Establish TCP and SSL Stream
        $tcpClient = New-Object System.Net.Sockets.TcpClient($fqdn, $port)
        $sslStream = New-Object System.Net.Security.SslStream(
            $tcpClient.GetStream(), 
            $false, 
            { $true } # Bypass local validation to inspect raw cert
        )
        
        $sslStream.AuthenticateAsClient($fqdn)
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($sslStream.RemoteCertificate)
        
        # Calculate SHA-256 Thumbprint
        $sha256 = [System.Security.Cryptography.HashAlgorithm]::Create('SHA256')
        $hashBytes = $sha256.ComputeHash($cert.RawData)
        $sha256Formatted = ($hashBytes | ForEach-Object { $_.ToString("X2") }) -join ":"

        return [PSCustomObject]@{
            FQDN           = $fqdn
            SHA1           = $cert.Thumbprint
            SHA256         = $sha256Formatted
            Subject        = $cert.Subject
            ExpirationDate = $cert.NotAfter
        }
    }
    catch {
        Write-Host "[x] Failed to retrieve thumbprint from: ${fqdn} $_" -ForegroundColor Red
    }
    finally {
        if ($sslStream) { $sslStream.Close() }
        if ($tcpClient) { $tcpClient.Close() }
    }
}

function Deploy-VCFOperationsAppliance {
    $TimeoutMinutes  = 15
    $PollIntervalSec = 10

    try {
        # 1. Target Object Validation
        Write-Host "[+] Validating vSphere target objects..." -ForegroundColor Cyan
        $vmHost    = Get-VMHost -Name $jsonInput.vcenter.targetEsx -ErrorAction Stop
        $datastore = Get-Datastore -Name $jsonInput.vcenter.datastore -ErrorAction Stop

        # 2. Check for Name Collisions
        $existingVm = Get-VM -Name ($jsonInput.operations.master.fqdn -replace '\..*$', '') -ErrorAction SilentlyContinue

        if ($existingVm) {
            # Warn and skip import
            Write-Host "[!] VM '$($jsonInput.operations.master.fqdn -replace '\..*$', '')' already exists on this vCenter. Skipping OVA import" -ForegroundColor Yellow
            $importedVm = $existingVm
        } 
        else {
            # 3. Extract OVF configuration & Import (Only run if VM does NOT exist)
            Write-Host "[+] Extracting OVF configuration..." -ForegroundColor Cyan
            $ovfConfig = Get-OvfConfiguration -Ovf $jsonInput.operations.ovaPath

            # Configure network and system properties
            $ovfConfig.Common.root_password.Value                       = $jsonInput.operations.adminPassword
            $ovfConfig.DeploymentOption.Value                           = $jsonInput.operations.size
            $ovfConfig.IpAssignment.IpProtocol.Value                    = "IPv4"
            $ovfConfig.NetworkMapping.Network_1.Value                   = $jsonInput.vcenter.portgroup
            $ovfConfig.Common.VMware_Aria_Operations.domain.Value       = $jsonInput.operations.master.fqdn.Substring($jsonInput.operations.master.fqdn.IndexOf('.') + 1)
            $ovfConfig.Common.VMware_Aria_Operations.searchpath.Value   = $jsonInput.operations.master.fqdn.Substring($jsonInput.operations.master.fqdn.IndexOf('.') + 1)
            $ovfConfig.Common.VMware_Aria_Operations.DNS.Value          = $jsonInput.dnsServers
            $ovfConfig.Common.VMware_Aria_Operations.ipv4_type.Value    = "Static"
            $ovfConfig.Common.VMware_Aria_Operations.ipv4_address.Value = $jsonInput.operations.master.ipAddress
            $ovfConfig.Common.VMware_Aria_Operations.ipv4_gateway.Value = $jsonInput.operations.gateway
            $ovfConfig.Common.VMware_Aria_Operations.ipv4_netmask.Value = $jsonInput.operations.netmask

            Write-Host "[+] Importing vApp '$($jsonInput.operations.master.fqdn -replace '\..*$', '')' from OVA..." -ForegroundColor Cyan

            $importedVm = Import-vApp -Source $jsonInput.operations.ovaPath `
                -OvfConfiguration $ovfConfig `
                -Name ($jsonInput.operations.master.fqdn -replace '\..*$', '') `
                -VMHost $vmHost `
                -Datastore $datastore `
                -ErrorAction Stop

            Write-Host "[✓] Deployment of VM '$($jsonInput.operations.master.fqdn -replace '\..*$', '')' successfully completed" -ForegroundColor Green
        }

        # 4. Power On VM (if not already powered on)
        if ($importedVm.PowerState -ne "PoweredOn") {
            Write-Host "[+] Powering on VM '$($jsonInput.operations.master.fqdn -replace '\..*$', '')'..." -ForegroundColor Cyan
            $importedVm = Start-VM -VM $importedVm -Confirm:$false -ErrorAction Stop
        } else {
            Write-Host "[!] VM '$($jsonInput.operations.master.fqdn -replace '\..*$', '')' is already powered on" -ForegroundColor Yellow
        }

        # 5. Polling Loop with Timeout for Valid IPv4 Address
        Write-Host "[+] Waiting for VMware Tools and IP initialization (Max wait: $TimeoutMinutes minutes)..." -NoNewline -ForegroundColor Cyan

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $timeout   = [TimeSpan]::FromMinutes($TimeoutMinutes)
        $validIp   = $null

        while ($stopwatch.Elapsed -lt $timeout) {
            # Refresh the VM object state from vCenter
            $vm = Get-VM -Name ($jsonInput.operations.master.fqdn -replace '\..*$', '') -ErrorAction SilentlyContinue

            if ($vm.Guest.IPAddress) {
                # Filter array for a valid IPv4 address (excluding APIPA / loopback)
                $validIp = $vm.Guest.IPAddress | Where-Object { 
                    $_ -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' -and 
                    $_ -notlike '169.254.*' -and 
                    $_ -ne '127.0.0.1' 
                } | Select-Object -First 1

                if ($validIp) {
                    break
                }
            }

            Write-Host "." -NoNewline -ForegroundColor Gray
            Start-Sleep -Seconds $PollIntervalSec
        }

        $stopwatch.Stop()
        Write-Host "" # Line break after dots

        # 6. Final Status Check
        if ($validIp) {
            Write-Host "[✓] VM '$($jsonInput.operations.master.fqdn -replace '\..*$', '')' is powered on and reachable at IP: $validIp" -ForegroundColor Green
        } else {
            Write-Warning "[!] Timed out after $TimeoutMinutes minutes waiting for a valid IP address."
            Write-Warning "    - Check if VMware Tools booted properly inside the guest OS."
            Write-Warning "    - Verify DHCP or OVF network settings are correct."
        }

    } catch {
        Write-Error "Deployment failed: $_"
    }
}

function Wait-OperationsApplianceReady {
    param (
        [Parameter(Mandatory=$true)] [string]$IPAddress,
        [int]$TimeoutMinutes = 30,
        [int]$PollIntervalSec = 20
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $timeout   = [TimeSpan]::FromMinutes($TimeoutMinutes)

    # 1. Hide the PowerShell progress bar for the ENTIRE function
    $oldProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'

    try {
        
        # PHASE 1: Wait for TCP Port 443 (Web Gateway listening)
        # --------------------------------------------------------------------------
        Write-Host "[+] Waiting for HTTPS service (Port 443) to open at '$IPAddress'..." -ForegroundColor Cyan

        $portOpen = $false

        # Hide the progress bar for the REST of the script (Phase 2's Invoke-WebRequest)
        $oldProgressPreference = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'

        while ($stopwatch.Elapsed -lt $timeout) {
            $elapsedStr = "$([math]::Floor($stopwatch.Elapsed.TotalMinutes))m $([math]::Round($stopwatch.Elapsed.TotalSeconds % 60))s"
            
            Write-Host "`r[!] Port 443 not responding yet... [Elapsed: $elapsedStr]    " -NoNewline -ForegroundColor Yellow

            # Test raw socket connection to port 443 (Bypasses Test-NetConnection completely)
            try {
                $tcp = New-Object System.Net.Sockets.TcpClient
                $connectTask = $tcp.ConnectAsync($IPAddress, 443)
                
                # Wait up to 2000 milliseconds for a connection. Returns True if successful.
                # If the connection is actively refused, this throws an error caught by the catch block.
                if ($connectTask.Wait(2000)) {
                    $portOpen = $true
                }
            } 
            catch {
                $portOpen = $false
            } 
            finally {
                if ($null -ne $tcp) { $tcp.Dispose() }
            }
            
            if ($portOpen) {
                Write-Host "`n[✓] Port 443 is OPEN! Web server is online at IP: $IPAddress" -ForegroundColor Green
                break
            }

            Start-Sleep -Seconds $PollIntervalSec
        }

        # --------------------------------------------------------------------------
        # PHASE 2: Poll Node API & HTTP Listener Status
        # --------------------------------------------------------------------------
        Write-Host "[+] Polling Node Initialization & Web Readiness..." -NoNewLine -ForegroundColor Cyan

        while ($stopwatch.Elapsed -lt $timeout) {
            $elapsedStr = "$([math]::Floor($stopwatch.Elapsed.TotalMinutes))m $([math]::Round($stopwatch.Elapsed.TotalSeconds % 60))s"

            try {
                $nodeStatus = Invoke-RestMethod -Uri "https://$IPAddress/casa/node/status" `
                    -Method GET -SkipCertificateCheck -TimeoutSec 5 -ErrorAction Stop

                if ($nodeStatus) {
                    $elapsedMin = [math]::Round($stopwatch.Elapsed.TotalMinutes, 1)
                    Write-Host "`n[✓] Node service are online! (Firstboot completed in $elapsedMin minutes)" -ForegroundColor Green
                    return $true
                }
            }
            catch {
                try {
                    $webResponse = Invoke-WebRequest -Uri "https://$IPAddress/" `
                        -Method Head -SkipCertificateCheck -TimeoutSec 5 -ErrorAction Stop

                    if ($webResponse.StatusCode -eq 200 -or $webResponse.StatusCode -eq 302) {
                        Write-Host "`n[✓] Web UI & Setup Wizard are active!" -ForegroundColor Green
                        return $true
                    }
                }
                catch { }
            }

            Write-Host "`r[!] Firstboot in progress (Web/CASA initializing)... [Elapsed: $elapsedStr]    " -NoNewline -ForegroundColor Yellow

            Start-Sleep -Seconds $PollIntervalSec
        }

        Write-Warning "`n[!] Timed out waiting for node services to complete firstboot."
        return $false

    }
    finally {
        # 2. Restore the progress bar preference no matter how the function exits
        $ProgressPreference = $oldProgressPreference
    }
}

function Wait-OperationsFirstbootComplete {
    param (
        [Parameter(Mandatory=$true)] [PSObject]$VM,
        [Parameter(Mandatory=$true)] [String]$GuestUser,
        [Parameter(Mandatory=$true)] [String]$GuestPassword,
        [int]$TimeoutMinutes = 20,
        [int]$PollIntervalSec = 30
    )

    # Single-line command prevents Windows CRLF (\r\n) syntax errors in Linux bash
    $bashScript = "if [ -f /var/log/firstboot/Succeeded ] || [ -f /var/log/firstboot/succeeded ]; then echo 'SUCCESS'; elif [ -f /var/log/firstboot/Failed ] || [ -f /var/log/firstboot/failed ]; then echo 'FAILED'; else echo 'RUNNING'; fi"

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $timeout   = [TimeSpan]::FromMinutes($TimeoutMinutes)

    Write-Host "[+] Polling guest OS firstboot status for VM '$($VM.Name)'..." -NoNewLine -ForegroundColor Cyan

    while ($stopwatch.Elapsed -lt $timeout) {
        $elapsed = "$([math]::Floor($stopwatch.Elapsed.TotalMinutes))m $([math]::Round($stopwatch.Elapsed.TotalSeconds % 60))s"

        try {
            $result = Invoke-VMScript -VM $VM `
                -GuestUser $GuestUser `
                -GuestPassword $GuestPassword `
                -ScriptType Bash `
                -ScriptText $bashScript `
                -ErrorAction Stop

            $output = $result.ScriptOutput

            # Regex match avoids strict string matching failures caused by banners/whitespace
            if ($output -match 'SUCCESS') {
                Write-Host "`n[✓] Firstboot completed successfully in $([math]::Round($stopwatch.Elapsed.TotalMinutes, 1)) minutes!" -ForegroundColor Green
                $stopwatch.Stop()
                return $true
            }
            elseif ($output -match 'FAILED') {
                Write-Host "`n[!] Firstboot FAILED on the appliance. Check /var/log/firstboot/ on the guest OS." -ForegroundColor Red
                $stopwatch.Stop()
                return $false
            }
            else {
                Write-Host "`r[!] Firstboot still in progress... [Elapsed: $elapsed]        " -NoNewline -ForegroundColor Yellow
            }
        }
        catch {
            # VMware Tools / Guest Operations service may not be ready yet
            Write-Host "`r[!]: Waiting for VMware Tools / Guest OS login readiness... [Elapsed: $elapsed]        " -NoNewline -ForegroundColor Gray
        }

        Start-Sleep -Seconds $PollIntervalSec
    }

    $stopwatch.Stop()
    Write-Warning "`n[!] Timed out after $TimeoutMinutes minutes waiting for firstboot to finish."
    return $false
}

function New-VCFClusterPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$IPAddress,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$Thumbprint,
        [Parameter(Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$AdminPassword,
        [Parameter(Mandatory = $false)] [String[]]$NtpServers = @()
    )
    
    Write-Host "[+] Generating JSON payload for cluster initialization..." -ForegroundColor Cyan
    # 1. Sanitize string inputs
    #$cleanIP = $IPAddress.Trim()

    # 2. Ensure NTP servers are explicitly formatted as an array (even if 0 or 1 item passed)
    [string[]]$cleanNtp = @($NtpServers | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    # 3. Construct structured object
    $payloadObj = [ordered]@{
        "master"         = [ordered]@{
            "name"       = $fqdn
            "address"    = $IPAddress
            "thumbprint" = $thumbprint
        }
        "admin_password" = $AdminPassword
        "ntp_servers"    = $cleanNtp
        "init"           = $true
        "dry-run"        = $false
    }

    # 4. Convert to JSON with explicit depth safety
    return ($payloadObj | ConvertTo-Json -Depth 5)
}

function Initialize-Operations {
    param (
        [Parameter(Mandatory=$true)][string]$fqdn,
        [Parameter(Mandatory=$true)][string]$adminPassword,
        [Parameter(Mandatory=$true)][string]$jsonPayload,
        [int]$timeoutMinutes = 30,
        [int]$intervalSeconds = 15
    )

    # 1. Ensure Basic Auth header is set up-front for all requests
    $headers = @{
        "Content-Type" = "application/json;charset=UTF-8"
        "Accept" = "application/json;charset=UTF-8"
    }

    $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("admin:$($adminPassword)"))
    $headers["Authorization"] = "Basic $encodedCreds"

    $targetState = "INITIALIZED"

    # --------------------------------------------------------------------------
    # PRE-FLIGHT CHECK: Is the cluster already configured?
    # --------------------------------------------------------------------------
    Write-Host "[+] Checking current cluster status on '$fqdn'..." -ForegroundColor Cyan
    try {
        $preCheck = Invoke-RestMethod -Method GET `
            -Uri "https://${fqdn}/casa/cluster/status" `
            -Headers $headers `
            -SkipCertificateCheck `
            -TimeoutSec 10 `
            -ErrorAction SilentlyContinue

        if ($preCheck.cluster_state -eq $targetState -or $preCheck.cluster_state -eq "ONLINE") {
            Write-Host "[✓] Cluster is already initialized! Current State: $($preCheck.cluster_state)" -NoNewLine -ForegroundColor Green
            return $true
        }
    }
    catch {
        # If pre-check fails (e.g. uninitialized node returns an error), proceed to POST
    }

    # --------------------------------------------------------------------------
    # TRIGGER INITIALIZATION: Send POST Request
    # --------------------------------------------------------------------------
    Write-Host "[+] Starting VCF Operations cluster initialization..." -ForegroundColor Cyan

    try {
        $postResponse = Invoke-WebRequest -Method POST `
            -Uri "https://${fqdn}/casa/cluster" `
            -Headers $headers `
            -SkipCertificateCheck `
            -Body $jsonPayload `
            -ErrorAction Stop

        $statusCode = $postResponse.StatusCode
    }
    catch {
        # HTTP 409 Conflict indicates cluster setup was already initiated or completed
        if ($_.Exception.Response.StatusCode -eq [System.Net.HttpStatusCode]::Conflict) {
            Write-Host "[!] Cluster initialization endpoint returned 409 Conflict. Cluster is already configured."
            return $true
        }
        
        $errDetails = $_.Exception.Message
        if ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $errResponseBody = $reader.ReadToEnd()
                if ($errResponseBody) { $errDetails = $errResponseBody }
            } catch {}
        }
        throw "Unable to start initial VCF Operations configuration: $errDetails"
    }

    # --------------------------------------------------------------------------
    # MONITORING LOOP: Poll until INITIALIZED
    # --------------------------------------------------------------------------
    if ($statusCode -eq 202 -or $statusCode -eq 200) {
        $startTime = Get-Date
        Write-Host "[+] Monitoring VCF Operations cluster initialization (this normally takes 15-25 minutes)..." -ForegroundColor Cyan

        do {
            $elapsedStr = "$([math]::Floor(((Get-Date) - $startTime).TotalMinutes))m $([math]::Round(((Get-Date) - $startTime).TotalSeconds % 60))s"

            try {
                $response = Invoke-RestMethod -Method GET `
                    -Uri "https://${fqdn}/casa/cluster/status" `
                    -Headers $headers `
                    -SkipCertificateCheck `
                    -TimeoutSec 10 `
                    -ErrorAction Stop

                $currentState = $response.cluster_state
                $onlineState  = $response.online_state

                # Check if target state reached
                if ($currentState -eq $targetState -or $currentState -eq "ONLINE" -or $onlineState -eq "ONLINE" -or $currentState -eq "RUNNING") {
                    Write-Host "`n[✓] Cluster initialization complete! Final state: $currentState" -ForegroundColor Green
                    return $true
                }

                # Catch permanent failure states early
                if ($currentState -match "FAILED|ERROR") {
                    throw "Cluster configuration failed with state: $currentState"
                }

                $statusDisplay = "Current status: $currentState"
                if ($onlineState -and $onlineState -ne "NONE") { $statusDisplay += " (Online: $onlineState)" }
                $msg = "[!] $statusDisplay... [Elapsed: $elapsedStr]"
                Write-Host "`r$($msg.PadRight(85))" -NoNewline -ForegroundColor Yellow
            }
            catch {
                $msg = "[!] Waiting for CASA API service to respond... [Elapsed: $elapsedStr]"
                Write-Host "`r$($msg.PadRight(85))" -NoNewline -ForegroundColor Gray
            }

            # Check timeout limit
            if ((Get-Date) -gt $startTime.AddMinutes($timeoutMinutes)) {
                throw "`n[!] Timed out waiting for cluster status to reach '$targetState' after $timeoutMinutes minutes"
            }

            Start-Sleep -Seconds $intervalSeconds

        } while ($true)
    } 
    else {
        Write-Host "[x] Unable to start initial VCF Operations configuration (HTTP $statusCode)"
        return $false
    }
}

function Set-EulaSetting {

    try {
        Write-Host "[+] Accepting End User License Agreement" -ForegroundColor Cyan

        $bodyData = @{
            keyValues = @(
                @{
                    key    = "configurationWizardFirstConfigDone"
                    values = @( "true" )
                }
            )
        }
        $jsonBody = $bodyData | ConvertTo-Json -Depth 5

        $internalHeaders = @{}
        foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
        $internalHeaders["X-vRealizeOps-API-use-unsupported"] = "true"

        Invoke-RestMethod -Method POST `
            -Uri "https://${operationsAppliance}/suite-api/internal/deployment/config/properties/java_util_HashSet" `
            -Headers $internalHeaders `
            -Body $jsonBody `
            -ContentType "application/json" `
            -SkipCertificateCheck `
        | Out-Null

        Write-Host "[✓] End User License Agreement accepted successfully" -ForegroundColor Green

    } catch {
        Write-Error $_.Exception.Message
    }
}

function Set-CeipSetting {
    param (
        [Parameter (Mandatory = $true)] [ValidateSet("ENABLED", "DISABLED")] [String]$status
    )

    try {
        Write-Host "[+] Attempting to configure Broadcom's Customer Experience Improvement Program (CEIP)" -ForegroundColor Cyan

        if ($status -eq "ENABLED") {
            $setting = "true"
        } elseif ($status -eq "DISABLED") {
            $setting = "false"
        }

        # 1. Mark CEIP first-login wizard/modal as completed in internal properties
        # This prevents the initial CEIP prompt dialog from appearing in the Web UI on first login
        $ceipPropData = @{
            keyValues = @(
                @{
                    key    = "ceipWizardFirstConfigDone"
                    values = @( "true" )
                }
            )
        }
        $jsonPropBody = $ceipPropData | ConvertTo-Json -Depth 5

        $internalHeaders = @{}
        foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
        $internalHeaders["X-vRealizeOps-API-use-unsupported"] = "true"

        Invoke-RestMethod -Method POST `
            -Uri "https://${operationsAppliance}/suite-api/internal/deployment/config/properties/java_util_HashSet" `
            -Headers $internalHeaders `
            -Body $jsonPropBody `
            -ContentType "application/json" `
            -SkipCertificateCheck `
            -ErrorAction SilentlyContinue | Out-Null

        # 2. Configure global telemetry status (Enabled/Disabled)
        $telemetrySetting = Invoke-RestMethod -Method GET `
            -Uri "https://${operationsAppliance}/suite-api/api/deployment/config/globalsettings/TELEMETRY_ENABLED" `
            -Headers $operationsHeaders `
            -SkipCertificateCheck `
            -ErrorAction SilentlyContinue

        if (-Not ($telemetrySetting.values -contains ${setting})) {
            # Endpoint variation 1: PUT URL path setting
            try {
                Invoke-RestMethod -Method PUT `
                    -Uri "https://${operationsAppliance}/suite-api/api/deployment/config/globalsettings/TELEMETRY_ENABLED/${setting}" `
                    -Headers $operationsHeaders `
                    -SkipCertificateCheck `
                    -ErrorAction SilentlyContinue | Out-Null
            } catch {
                # Endpoint variation 2: PUT global settings JSON payload
                try {
                    $telemetryBody = @{
                        "key"    = "TELEMETRY_ENABLED"
                        "values" = @($setting)
                    } | ConvertTo-Json -Depth 5

                    Invoke-RestMethod -Method PUT `
                        -Uri "https://${operationsAppliance}/suite-api/api/deployment/config/globalsettings" `
                        -Headers $operationsHeaders `
                        -Body $telemetryBody `
                        -ContentType "application/json" `
                        -SkipCertificateCheck `
                        -ErrorAction SilentlyContinue | Out-Null
                } catch {}
            }
            Write-Host "[✓] Broadcom's Customer Experience Improvement Program successfully ${status}" -ForegroundColor Green
        } else {
            Write-Host "[!] Broadcom's Customer Experience Improvement Program already ${status}" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[✓] Broadcom's Customer Experience Improvement Program successfully ${status}" -ForegroundColor Green
    }
}

function Request-OperationsToken {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [String]$Fqdn,
        [Parameter(Mandatory = $true)] [String]$Username,
        [Parameter(Mandatory = $true)] [String]$Password
    )

    Write-Host "[+] Acquiring VCF Operations API token from '$Fqdn'..." -ForegroundColor Cyan
    $uri = "https://$Fqdn/suite-api/api/auth/token/acquire"
    $headers = @{
        "Accept"       = "application/json"
        "Content-Type" = "application/json"
    }
    $body = @{
        "username"   = $Username
        "authSource" = "LOCAL"
        "password"   = $Password
    } | ConvertTo-Json

    try {
        if ($PSEdition -eq 'Core') {
            $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body $body -SkipCertificateCheck -ErrorAction Stop
        } else {
            $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $headers -Body $body -ErrorAction Stop
        }

        if ($response.token) {
            Write-Host "[✓] Successfully acquired OpsToken" -ForegroundColor Green
            return $response.token
        } else {
            throw "Token empty in response"
        }
    }
    catch {
        Write-Error "Failed to acquire OpsToken: $_"
        throw
    }
}

function Get-OperationsCredential {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [String]$Fqdn,
        [Parameter(Mandatory = $true)] [Hashtable]$Headers
    )

    Write-Host "[+] Querying credentials in VCF Operations..." -ForegroundColor Cyan
    $uri = "https://$Fqdn/suite-api/api/credentials"
    try {
        if ($PSEdition -eq 'Core') {
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $Headers -SkipCertificateCheck -ErrorAction Stop
        } else {
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $Headers -ErrorAction Stop
        }
        return $response.credentialInstances
    }
    catch {
        Write-Warning "[!] Get-OperationsCredential warning: $_"
        return @()
    }
}

function Add-OperationsCredential {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [String]$Fqdn,
        [Parameter(Mandatory = $true)] [Hashtable]$Headers,
        [Parameter(Mandatory = $true)] [String]$CredentialName,
        [Parameter(Mandatory = $true)] [String]$User,
        [Parameter(Mandatory = $true)] [String]$Pass
    )

    Write-Host "[+] Creating credential '$CredentialName' in VCF Operations..." -ForegroundColor Cyan
    $uri = "https://$Fqdn/suite-api/api/credentials"
    $body = @{
        "name"              = $CredentialName
        "adapterKindKey"    = "VMWARE"
        "credentialKindKey" = "PRINCIPALCREDENTIAL"
        "fields"            = @(
            @{ "name" = "USER"; "value" = $User },
            @{ "name" = "PASSWORD"; "value" = $Pass }
        )
    } | ConvertTo-Json -Depth 5

    try {
        if ($PSEdition -eq 'Core') {
            $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $Headers -Body $body -SkipCertificateCheck -ErrorAction Stop
        } else {
            $response = Invoke-RestMethod -Method POST -Uri $uri -Headers $Headers -Body $body -ErrorAction Stop
        }
        Write-Host "[✓] Credential '$CredentialName' created successfully" -ForegroundColor Green
        return $response
    }
    catch {
        Write-Error "Failed to add credential '$CredentialName': $_"
        throw
    }
}

function Get-OperationsCollectorGroup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [String]$Fqdn,
        [Parameter(Mandatory = $true)] [Hashtable]$Headers
    )

    Write-Host "[+] Querying collector groups in VCF Operations..." -ForegroundColor Cyan
    $uri = "https://$Fqdn/suite-api/api/collectorgroups"
    try {
        if ($PSEdition -eq 'Core') {
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $Headers -SkipCertificateCheck -ErrorAction Stop
        } else {
            $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $Headers -ErrorAction Stop
        }
        return $response.collectorGroups
    }
    catch {
        Write-Warning "[!] Get-OperationsCollectorGroup warning: $_"
        return @()
    }
}


function Invoke-OperationsRest {
    # Single REST wrapper. Returns @{ Ok; Status; Body } and never throws, so callers can inspect
    # 400 bodies (untrusted certificate lists) and are never silently swallowing failures.
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]  [String]$Method,
        [Parameter(Mandatory = $true)]  [String]$Uri,
        [Parameter(Mandatory = $true)]  [Hashtable]$Headers,
        [Parameter(Mandatory = $false)] [Object]$Body
    )

    $params = @{ Method = $Method; Uri = $Uri; Headers = $Headers; ErrorAction = 'Stop' }
    if ($null -ne $Body) {
        $params.Body = if ($Body -is [String]) { $Body } else { $Body | ConvertTo-Json -Depth 10 }
    }
    if ($PSEdition -eq 'Core') { $params.SkipCertificateCheck = $true }

    try {
        $response = Invoke-RestMethod @params
        return @{ Ok = $true; Status = 200; Body = $response }
    }
    catch {
        $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        $text = $_.ErrorDetails.Message
        if (-not $text -and $_.Exception.Response -and $_.Exception.Response.GetResponseStream) {
            try { $text = (New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())).ReadToEnd() } catch {}
        }
        $parsed = $null
        if ($text) { try { $parsed = $text | ConvertFrom-Json } catch { $parsed = $text } }
        return @{ Ok = $false; Status = $status; Body = $parsed; Message = "$($_.Exception.Message) $text" }
    }
}

function Find-OperationsCertificate {
    # Recursively collects certificate objects (anything carrying a thumbprint) from a response body.
    param ([Parameter(Mandatory = $false)] [Object]$Node)

    if ($null -eq $Node -or $Node -is [String]) { return }
    if ($Node -is [System.Collections.IEnumerable]) { foreach ($n in $Node) { Find-OperationsCertificate -Node $n }; return }
    if ($Node.PSObject.Properties['thumbprint'] -and $Node.PSObject.Properties['certificateDetails']) { $Node; return }
    foreach ($prop in $Node.PSObject.Properties) { Find-OperationsCertificate -Node $prop.Value }
}

function Get-OperationsAdapter {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]  [String]$Fqdn,
        [Parameter(Mandatory = $true)]  [Hashtable]$Headers,
        [Parameter(Mandatory = $false)] [String]$AdapterId,
        [Parameter(Mandatory = $false)] [String]$AdapterKindKey
    )

    $uri = "https://$Fqdn/suite-api/api/adapters"
    if ($AdapterId) { $uri += "/$AdapterId" }
    elseif ($AdapterKindKey) { $uri += "?adapterKindKey=$AdapterKindKey" }

    $r = Invoke-OperationsRest -Method GET -Uri $uri -Headers $Headers
    if (-not $r.Ok) { Write-Warning "[!] Get-OperationsAdapter failed ($($r.Status)): $($r.Message)"; return @() }
    if ($AdapterId) { return $r.Body } else { return $r.Body.adapterInstancesInfoDto }
}

function Get-OperationsAdapterName {
    param ([Object]$Adapter)
    if ($Adapter.resourceKey.name) { $Adapter.resourceKey.name } else { $Adapter.name }
}

function New-OperationsVcenterIntegrationPayload {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]  [String]$VcenterFqdn,
        [Parameter(Mandatory = $true)]  [String]$CollectorGroupId,
        [Parameter(Mandatory = $true)]  [String]$CredentialId,
        [Parameter(Mandatory = $false)] [Object[]]$Certificates
    )

    # Mirrors the UI saveCloudAccount call: vCenter adapter plus its vSAN child.
    $payload = [ordered]@{
        "name"                = $VcenterFqdn
        "description"         = "vCenter Adapter - $VcenterFqdn"
        "collectorGroupId"    = $CollectorGroupId
        "credentialInstanceId" = $CredentialId
        "resourceIdentifiers" = @(
            @{ "name" = "VCURL"; "value" = $VcenterFqdn },
            @{ "name" = "AUTODISCOVERY"; "value" = "true" },
            @{ "name" = "PROCESSCHANGEEVENTS"; "value" = "true" }
        )
        "vsanConfig"          = @{ "enabled" = $true; "smartDataCollectionEnabled" = $false }
    }
    if ($Certificates) { $payload["certificates"] = @($Certificates) }
    return $payload
}

function Start-OperationsAdapterCollection {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)] [String]$Fqdn,
        [Parameter(Mandatory = $true)] [Hashtable]$Headers,
        [Parameter(Mandatory = $true)] [String[]]$AdapterInstanceIds
    )

    # Creation never starts an adapter (the UI makes a separate startCloudAccountCollect call).
    # Documented Suite API call: PUT /suite-api/api/adapters/{id}/monitoringstate/start (no body).
    $allStarted = $true
    foreach ($id in $AdapterInstanceIds) {
        Write-Host "[+] Starting collection for adapter instance ID: $id..." -ForegroundColor Cyan
        $r = Invoke-OperationsRest -Method PUT -Uri "https://$Fqdn/suite-api/api/adapters/$id/monitoringstate/start" -Headers $Headers
        if ($r.Ok) {
            Write-Host "[✓] Start requested for adapter ID: $id" -ForegroundColor Green
        } else {
            $allStarted = $false
            Write-Host "[!] Failed to start adapter ID $id (HTTP $($r.Status)): $($r.Message)" -ForegroundColor Red
        }
    }
    return $allStarted
}


function Add-VcenterAdapter {
<#
    .SYNOPSIS
    Pure REST API automation for VCF Operations Cloud Account creation and collection activation.

    .DESCRIPTION
    The Add-VcenterAdapter cmdlet uses standard VCF / Aria Operations Suite API endpoints
    (`/suite-api/api/...`) to authenticate, manage credentials, test & trust SSL certificates,
    register vCenter cloud accounts, and start metric collection.

    .EXAMPLE
    Add-VcenterAdapter -VcfOpsFqdn "sfo-ops01.sfo.rainpole.io" `
                       -Username "admin" `
                       -Password "VMware1!" `
                       -VcenterFqdn "sfo-w03-vc01.sfo.rainpole.io" `
                       -VcenterUser "administrator@vsphere.local" `
                       -VcenterPass "VMware1!"
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)] [String]$VcfOpsFqdn = "sfo-ops01.sfo.rainpole.io",
        [Parameter(Mandatory = $false)] [String]$Username = "admin",
        [Parameter(Mandatory = $false)] [String]$Password = "VMware1!",
        [Parameter(Mandatory = $false)] [String]$VcenterFqdn = "sfo-w03-vc01.sfo.rainpole.io",
        [Parameter(Mandatory = $false)] [String]$VcenterUser = "administrator@vsphere.local",
        [Parameter(Mandatory = $false)] [String]$VcenterPass = "VMware1!",
        [Parameter(Mandatory = $false)] [String]$CollectorGroupId = ""
    )

    if ($PSEdition -ne 'Core') {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }

    $cleanVcFqdn = $VcenterFqdn -replace '^https?://', '' -replace '/.*$', ''

    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host "Starting Pure REST API VCF Operations Cloud Account Workflow" -ForegroundColor Green
    Write-Host "VCF Operations Appliance : $VcfOpsFqdn" -ForegroundColor Green
    Write-Host "Target vCenter           : $cleanVcFqdn" -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Green

    # 1. Acquire Ops Token
    $opsToken = Request-OperationsToken -Fqdn $VcfOpsFqdn -Username $Username -Password $Password
    $apiHeaders = @{
        "Accept"        = "application/json"
        "Content-Type"  = "application/json"
        "Authorization" = "OpsToken $opsToken"
    }

    # 2. Get or Create Credential
    $existingCreds = Get-OperationsCredential -Fqdn $VcfOpsFqdn -Headers $apiHeaders
    $credObj = $existingCreds | Where-Object { $_.name -eq $cleanVcFqdn -or $_.name -eq $VcenterFqdn } | Select-Object -First 1

    if (-not $credObj) {
        $credObj = Add-OperationsCredential -Fqdn $VcfOpsFqdn -Headers $apiHeaders -CredentialName $cleanVcFqdn -User $VcenterUser -Pass $VcenterPass
    } else {
        Write-Host "[✓] Found existing credential for '$cleanVcFqdn' (ID: $($credObj.id))" -ForegroundColor Green
    }
    $credentialId = if ($credObj.id) { $credObj.id } else { $credObj.credentialInstances[0].id }

    # 3. Resolve Collector Group
    if ([String]::IsNullOrWhiteSpace($CollectorGroupId)) {
        $collectors = Get-OperationsCollectorGroup -Fqdn $VcfOpsFqdn -Headers $apiHeaders
        if ($collectors -and $collectors.Count -gt 0) {
            $CollectorGroupId = if ($collectors[0].id) { $collectors[0].id } else { $collectors[0].collectorGroupId }
        }
    }
    Write-Host "[✓] Using Collector Group ID: $CollectorGroupId" -ForegroundColor Green

    # 4. Check if Adapter Exists or Create It
    $matchesVc = { (Get-OperationsAdapterName $_) -in @($cleanVcFqdn, $VcenterFqdn) }
    $adapterObj = Get-OperationsAdapter -Fqdn $VcfOpsFqdn -Headers $apiHeaders -AdapterKindKey "VMWARE" | Where-Object $matchesVc | Select-Object -First 1

    if (-not $adapterObj) {
        # 4a. Test connection first; vCenter's untrusted certificate is returned for acceptance
        $payload = New-OperationsVcenterIntegrationPayload -VcenterFqdn $cleanVcFqdn -CollectorGroupId $CollectorGroupId -CredentialId $credentialId
        $base = "https://$VcfOpsFqdn/suite-api/api/integrations/vcenters"

        Write-Host "[+] Testing vCenter connection and certificate..." -ForegroundColor Cyan
        $test = Invoke-OperationsRest -Method POST -Uri "$base/testConnection" -Headers $apiHeaders -Body $payload
        $certs = @(Find-OperationsCertificate -Node $test.Body)
        if (-not $test.Ok -and $certs.Count -eq 0) {
            throw "vCenter testConnection failed (HTTP $($test.Status)): $($test.Message)"
        }

        # 4b. Create the integration, trusting the presented certificate(s) in the same call (as the UI does)
        if ($certs.Count -gt 0) {
            Write-Host "[+] Trusting $($certs.Count) vCenter SSL certificate(s)..." -ForegroundColor Cyan
            $payload = New-OperationsVcenterIntegrationPayload -VcenterFqdn $cleanVcFqdn -CollectorGroupId $CollectorGroupId -CredentialId $credentialId -Certificates $certs
        }
        Write-Host "[+] Registering vCenter adapter in VCF Operations..." -ForegroundColor Cyan
        $create = Invoke-OperationsRest -Method POST -Uri $base -Headers $apiHeaders -Body $payload
        if (-not $create.Ok) { throw "Failed to create vCenter integration (HTTP $($create.Status)): $($create.Message)" }

        $adapterObj = Get-OperationsAdapter -Fqdn $VcfOpsFqdn -Headers $apiHeaders -AdapterKindKey "VMWARE" | Where-Object $matchesVc | Select-Object -First 1
        if (-not $adapterObj) { throw "vCenter integration was created but the adapter instance could not be found." }
    } else {
        Write-Host "[✓] Found existing vCenter adapter for '$cleanVcFqdn' (ID: $($adapterObj.id))" -ForegroundColor Green
    }

    $adapterId = $adapterObj.id

    # 5. Collect the adapter IDs to start: the vCenter adapter plus its vSAN child (UI uses withChildren=true)
    $adapterIdsToStart = @($adapterId)
    $vsanAdapter = Get-OperationsAdapter -Fqdn $VcfOpsFqdn -Headers $apiHeaders -AdapterKindKey "VirtualAndPhysicalSANAdapter" |
        Where-Object { (Get-OperationsAdapterName $_) -like "$cleanVcFqdn*" } | Select-Object -First 1
    if ($vsanAdapter) { $adapterIdsToStart += $vsanAdapter.id }

    # 6. Enable Metric Collection (creation leaves the adapters Stopped / Not Collecting)
    $started = Start-OperationsAdapterCollection -Fqdn $VcfOpsFqdn -Headers $apiHeaders -AdapterInstanceIds $adapterIdsToStart
    if (-not $started) { throw "One or more adapters could not be started; see errors above." }

    Write-Host "`n================================================================================" -ForegroundColor Green
    Write-Host "✅ Pure API Workflow Completed Successfully for $cleanVcFqdn" -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Green

    return [PSCustomObject]@{
        AdapterID    = $adapterId
        CredentialID = $credentialId
        CollectorID  = $CollectorGroupId
    }

}

function Request-LicenseServerOTK {

    try {
        Write-Host "[+] Attempting to obtain One Time Key (OTK) for License Server registration" -ForegroundColor Cyan

        $internalHeaders = @{}
        foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
        $internalHeaders["X-vRealizeOps-API-use-unsupported"] = "true"

        $Script:licenseServerOTK = Invoke-RestMethod -Method GET `
            -Uri "https://${operationsAppliance}/suite-api/internal/extension/vcf-license-cloud-integration/license-servers/otk" `
            -Headers $internalHeaders `
            -SkipCertificateCheck

        if ($licenseServerOTK) {
            Write-Host "[✓] Obtained One Time Key (OTK) successfully" -ForegroundColor Green
        } else {
            Write-Host "[x] Obtaining One Time Key (OTK) failed" -ForegroundColor Red
        }
    } catch {

    }
}

function Deploy-LicenseServerAppliance {
    $TimeoutMinutes  = 15
    $PollIntervalSec = 10

    try {
        # 1. Target Object Validation
        Write-Host "[+] Validating vSphere target objects..." -ForegroundColor Cyan
        $vmHost    = Get-VMHost -Name $jsonInput.vcenter.targetEsx -ErrorAction Stop
        $datastore = Get-Datastore -Name $jsonInput.vcenter.datastore -ErrorAction Stop

        # 2. Check for Name Collisions
        $existingVm = Get-VM -Name ($jsonInput.licenseServer.fqdn -replace '\..*$', '') -ErrorAction SilentlyContinue

        if ($existingVm) {
            # Warn and skip import
            Write-Host "[!] VM '$($jsonInput.licenseServer.fqdn -replace '\..*$', '')' already exists on this vCenter. Skipping OVA import" -ForegroundColor Yellow
            $importedVm = $existingVm
        } 
        else {
            # 3. Extract OVF configuration & Import (Only run if VM does NOT exist)
            Write-Host "[+] Extracting OVF configuration..." -ForegroundColor Cyan
            $ovfConfigLicenseServer = Get-OvfConfiguration -Ovf $jsonInput.licenseServer.ovaPath

            # Configure network and system properties
            $ovfConfigLicenseServer.Common.hostname.Value                                   = $jsonInput.licenseServer.fqdn
            $ovfConfigLicenseServer.Common.OTK.Value                                        = $licenseServerOTK
            $ovfConfigLicenseServer.Common.gateway.VCF_License_Server_Appliance.Value       = $jsonInput.licenseServer.gateway
            $ovfConfigLicenseServer.Common.domain.VCF_License_Server_Appliance.Value        = $jsonInput.licenseServer.fqdn.Substring($jsonInput.licenseServer.fqdn.IndexOf('.') + 1)
            $ovfConfigLicenseServer.Common.searchpath.VCF_License_Server_Appliance.Value    = $jsonInput.licenseServer.fqdn.Substring($jsonInput.licenseServer.fqdn.IndexOf('.') + 1)
            $ovfConfigLicenseServer.Common.dns.VCF_License_Server_Appliance.Value           = $jsonInput.dnsServers
            $ovfConfigLicenseServer.Common.ip0.VCF_License_Server_Appliance.Value           = $jsonInput.licenseServer.ipAddress
            $ovfConfigLicenseServer.Common.netmask0.VCF_License_Server_Appliance.Value      = $jsonInput.licenseServer.netmask
            $ovfConfigLicenseServer.NetworkMapping.Network_1.Value                          = $jsonInput.vcenter.portgroup

            Write-Host "[+] Importing vApp '$($jsonInput.licenseServer.fqdn -replace '\..*$', '')' from OVA..." -ForegroundColor Cyan

            $importedVm = Import-vApp -Source $jsonInput.licenseServer.ovaPath `
                -OvfConfiguration $ovfConfigLicenseServer `
                -Name ($jsonInput.licenseServer.fqdn -replace '\..*$', '') `
                -VMHost $vmHost `
                -Datastore $datastore `
                -Force `
                -Confirm:$false `
                -ErrorAction Stop

            Write-Host "[✓] Deployment of VM '$($jsonInput.licenseServer.fqdn -replace '\..*$', '')' successfully completed" -ForegroundColor Green
        }

        # 4. Power On VM (if not already powered on)
        if ($importedVm.PowerState -ne "PoweredOn") {
            Write-Host "[+] Powering on VM '$($jsonInput.licenseServer.fqdn -replace '\..*$', '')'..." -ForegroundColor Cyan
            $importedVm = Start-VM -VM $importedVm -Confirm:$false -ErrorAction Stop
        } else {
            Write-Host "[!] VM '$($jsonInput.licenseServer.fqdn -replace '\..*$', '')' is already powered on" -ForegroundColor Yellow
        }

        # 5. Polling Loop with Timeout for Valid IPv4 Address
        Write-Host "[+] Waiting for VMware Tools and IP initialization (Max wait: $TimeoutMinutes minutes)..." -NoNewline -ForegroundColor Cyan

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $timeout   = [TimeSpan]::FromMinutes($TimeoutMinutes)
        $validIp   = $null

        while ($stopwatch.Elapsed -lt $timeout) {
            # Refresh the VM object state from vCenter
            $vm = Get-VM -Name ($jsonInput.licenseServer.fqdn -replace '\..*$', '') -ErrorAction SilentlyContinue

            if ($vm.Guest.IPAddress) {
                # Filter array for a valid IPv4 address (excluding APIPA / loopback)
                $validIp = $vm.Guest.IPAddress | Where-Object { 
                    $_ -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' -and 
                    $_ -notlike '169.254.*' -and 
                    $_ -ne '127.0.0.1' 
                } | Select-Object -First 1

                if ($validIp) {
                    break
                }
            }

            Write-Host "." -NoNewline -ForegroundColor Gray
            Start-Sleep -Seconds $PollIntervalSec
        }

        $stopwatch.Stop()
        Write-Host "" # Line break after dots

        # 6. Final Status Check
        if ($validIp) {
            Write-Host "[✓] VM '$($jsonInput.licenseServer.fqdn -replace '\..*$', '')' is powered on and reachable at IP: $validIp" -ForegroundColor Green
        } else {
            Write-Warning "[!] Timed out after $TimeoutMinutes minutes waiting for a valid IP address."
            Write-Warning "    - Check if VMware Tools booted properly inside the guest OS."
            Write-Warning "    - Verify DHCP or OVF network settings are correct."
        }

    } catch {
        Write-Error "Deployment failed: $_"
    }
}

function Get-RegistrationFile {
    
    try {
        Write-Host "[+] Attempting to download VCF Operations registration file for offline licensing..." -ForegroundColor Cyan

        $internalHeaders = @{}
        foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
        $internalHeaders["X-Ops-API-use-unsupported"] = "true"

        $requestResults = Invoke-RestMethod -Method POST `
                -Uri "https://${operationsAppliance}/suite-api/internal/extension/vcf-license-cloud-integration/registration/offline/request" `
                -Headers $internalHeaders `
                -SkipCertificateCheck

        # Extract properties directly from the response object
        $registrationData     = $requestResults.jwsEncodedData
        $registrationFilename  = $requestResults.fileName

        Write-Host "[+] Obtaining VCF Operations registration file: $registrationFilename ..." -ForegroundColor Cyan

        # Save the extracted string to the file
        Set-Content -Path $registrationFilename -Value $registrationData -Encoding UTF8

        Write-Host "[✓] Downloaded the registration file successfully" -ForegroundColor Green
    } catch {

    }
}

function Import-VerificationFile {
    param ( [Parameter (Mandatory = $false)]  [String]$verificationFile
    )

    # If no file was passed, build an interactive selection menu
    if ([string]::IsNullOrEmpty($verificationFile)) {
        Write-Host "No verification file specified. Searching for available files..." -ForegroundColor Cyan
        
        # We wrap this in @() to ensure it's treated as an array even if only 1 file is found
        $matchingFiles = @(Get-ChildItem -Path ".\verification*" -File)
        
        if ($matchingFiles.Count -eq 0) {
            Write-Host "No files found matching 'verification*' in the current directory." -ForegroundColor Yellow
            return 
        }

        # Display the numbered menu
        Write-Host "`nPlease select a verification file to upload:" -ForegroundColor Cyan
        for ($i = 0; $i -lt $matchingFiles.Count; $i++) {
            Write-Host "  [$($i + 1)] $($matchingFiles[$i].Name) ($($matchingFiles[$i].Length) bytes)"
        }

        # Prompt the user for a choice
        $selection = Read-Host "`nEnter the number of the file to select"
        
        $selectedIndex = 0
        # Validate that the input is a number and falls within the valid range of our list
        if ([int]::TryParse($selection, [ref]$selectedIndex) -and $selectedIndex -ge 1 -and $selectedIndex -le $matchingFiles.Count) {
            # Arrays are 0-indexed, so we subtract 1 from their choice
            $verificationFile = $matchingFiles[$selectedIndex - 1].FullName
            Write-Host "Selected: $verificationFile`n" -ForegroundColor Green
        } else {
            Write-Host "[x] Invalid selection. Canceling operation." -ForegroundColor Red
            return
        }
    }

    try {
        # Ensure the file exists before attempting the upload
        if (-Not (Test-Path -Path $verificationFile -PathType Leaf)) {
            Write-Host "[x] '$verificationFile' is not a valid file." -ForegroundColor Red
        } else {

            Write-Host "[+] Uploading licensing verification file to VCF Operations..."

            $internalHeaders = @{}
            foreach ($k in $operationsHeaders.Keys) {
                if ($k -ne "Content-Type") {
                    $internalHeaders[$k] = $operationsHeaders[$k]
                }
            }
            $internalHeaders["X-Ops-API-use-unsupported"] = "true"

            # Build the multipart form payload matching the curl '-F verification=@...' parameter
            $uploadForm = @{
                verification = Get-Item -Path $verificationFile
            }

            # Execute the request
            $response = Invoke-RestMethod -Method POST `
                -Uri "https://${operationsAppliance}/suite-api/internal/license-manager/license-servers/verification?_no_links=true" `
                -Headers $internalHeaders `
                -Form $uploadForm `
                -SkipCertificateCheck

            Write-Host "[✓] Uploaded verification file to VCF Operations successfully" -ForegroundColor Green
        }
    } catch {
        Write-Error $_.Exception.Message
    }
}

function Get-ConfirmationFile {
    try {
        Write-Host "[+] Requesting confirmation file from VCF Operations..."

        $internalHeaders = @{}
        foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
        $internalHeaders["X-Ops-API-use-unsupported"] = "true"

        # Execute the GET request to retrieve the data
        $response = Invoke-RestMethod -Method GET `
            -Uri "https://${operationsAppliance}/suite-api/internal/license-manager/registration/request" `
            -Headers $internalHeaders `
            -SkipCertificateCheck

        $confirmationData     = $response.jwsEncodedData
        $confirmationFilename = $response.fileName

        # Fallback filename if the API doesn't provide one
        if ([string]::IsNullOrWhiteSpace($confirmationFilename)) {
            $dateStamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
            $confirmationFilename = "confirm-${operationsAppliance}_$dateStamp.confirmation"
            
            # If the API returns raw bytes or string directly instead of a JSON object with jwsEncodedData:
            if ($null -eq $confirmationData) {
                $confirmationData = $response
            }
        }

        Write-Host "[+] Obtaining VCF Operations confirmation file: $confirmationFilename ..." -ForegroundColor Cyan

        # Save the extracted string/data to the file
        Set-Content -Path $confirmationFilename -Value $confirmationData -Encoding UTF8

        Write-Host "[✓] Downloaded the confirmation file successfully" -ForegroundColor Green

    } catch {
        Write-Error $_.Exception.Message
    }
}

function Import-LicenseFile {
    param (
        [Parameter (Mandatory = $true)] [String]$licenseFile
    )

    try {
        if (-not (Test-Path -Path $licenseFile -PathType Leaf)) {
            Write-Host "[x] '$licenseFile -PathType' is not a valid file." -ForegroundColor Red
        } else {
            Write-Host "[+] Attempting to upload the license file to VCF Operations ..."

            $internalHeaders = @{}
            foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
            $internalHeaders["X-Ops-API-use-unsupported"] = "true"

            # Prepare the multipart form data payload using Get-Item
            $uploadForm = @{
                file = Get-Item -Path $licenseFile
            }

            # Upload the file
            $uploadResults = Invoke-RestMethod -Method POST `
                -Uri "https://${operationsAppliance}/suite-api/internal/extension/vcf-license-cloud-integration/registration/offline/response" `
                -Headers $internalHeaders `
                -Form $uploadForm `
                -SkipCertificateCheck

            Write-Host "[✓] Uploaded license file to VCF Operations successfully" -ForegroundColor Green
        }
    } catch {
        Write-Error $_.Exception.Message
    }
}

function Import-PublicPrivateKey {
    [CmdletBinding()]
    param (
        [Parameter (Mandatory=$true)] [string]$Hostname,
        [Parameter (Mandatory=$true)] [string]$PublicKeyFile,
        [Parameter (Mandatory=$true)] [string]$PrivateKeyFile
    )

    # Check if key files exist
    if (Test-Path -Path $PublicKeyFile) {
        if (Test-Path -Path $PrivateKeyFile) {
            # Create a temporary file for the combined keypair (using .pem extension for accurate MIME typing)
            $tempDir = [System.IO.Path]::GetTempPath()
            $keypairFile = New-Item -Path $tempDir -Name "keypair_$([guid]::NewGuid()).pem" -ItemType File -Force

            # Combine private and public keys into the temporary file (Private first, exactly like the bash script)
            Get-Content -Path $PrivateKeyFile | Set-Content -Path $keypairFile.FullName
            Get-Content -Path $PublicKeyFile | Add-Content -Path $keypairFile.FullName
            
            try {
                $internalHeaders = @{}
                foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
                $internalHeaders["X-Ops-API-use-unsupported"] = "true"

                Write-Host "[+] Attempting to upload key pair for $Hostname..." -ForegroundColor Cyan

                # Prepare multipart/form-data payload (similar to curl -F)
                $form = @{
                    keypair = Get-Item -Path $keypairFile.FullName
                }

                $uploadResponse = Invoke-RestMethod -Method Post `
                    -Uri "https://$operationsAppliance/suite-api/internal/extension/vcf-license-cloud-integration/identity/keypair" `
                    -Headers $internalHeaders `
                    -Form $form `
                    -SkipCertificateCheck

                Write-Host ""
                if ($null -eq $uploadResponse -or [string]::IsNullOrWhiteSpace($uploadResponse)) {
                    Write-Host "[✓] Uploaded key pair for $Hostname successfully" -ForegroundColor Green
                } else {
                    Write-Host "[x] Upload Response:" -ForegroundColor Red
                    $uploadResponse | ConvertTo-Json -Depth 5 | Write-Host
                }
            }
            catch {
                Write-Error "An error occurred during execution: $($_.Exception.Message)"
            }
            finally {
                # Clean up temporary file
                if (Test-Path -Path $keypairFile.FullName) {
                    Remove-Item -Path $keypairFile.FullName -Force
                }
            }
        } else {
            Write-Host "[x] Error: Private key file not found: $PrivateKeyFile"  -ForegroundColor Red
        }
    } else {
        Write-Host "[x] Error: Public key file not found: $PublicKeyFile" -ForegroundColor Red
    }

}

# Main Script

Try {
    Write-Host "[+] Starting the Deployment of $solutionName" -ForegroundColor Cyan
    if (Test-Path -Path $jsonFile) {
        $Global:jsonInput = (Get-Content -Path $jsonFile) | ConvertFrom-Json
        if (Test-VsphereAuthentication -server $jsonInput.vcenter.fqdn -user $jsonInput.vcenter.username -pass $jsonInput.vcenter.password) {
            Deploy-VCFOperationsAppliance # Attempt to deploy the OVA and create a new VM and power it on
            Wait-OperationsApplianceReady -IPAddress $jsonInput.operations.master.fqdn | Out-Null # Poll the powered on VM checking the Web service availability

            #$vmName = $fqdn -replace '\..*$', ''
            $vm = Get-VM -Name ($jsonInput.operations.master.fqdn -replace '\..*$', '') -ErrorAction SilentlyContinue
            Wait-OperationsFirstbootComplete -VM $vm -GuestUser root -GuestPassword $jsonInput.operations.rootPassword  | Out-Null

            # Retrieve VCF Operations SHA-256 Thumbprint
            $thumbprintInfo = Get-VCFNodeThumbprint -FQDN $jsonInput.operations.master.fqdn
            $thumbprint = $thumbprintInfo.SHA256

            # Call New-VCFClusterPayload to create the JSON payload for the VCF Operations initialization
            $jsonPayload = New-VCFClusterPayload -fqdn $jsonInput.operations.master.fqdn -IPAddress $jsonInput.operations.master.ipAddress -thumbprint $thumbprint -AdminPassword $jsonInput.operations.adminPassword -NtpServers $jsonInput.ntpServers

            # Initialize VCF Operations 
            Initialize-Operations -fqdn $jsonInput.operations.master.fqdn -adminPassword $jsonInput.operations.adminPassword -jsonPayload $jsonPayload | Out-Null
            
            Request-OperationsToken -fqdn $jsonInput.operations.master.fqdn -username admin -password $jsonInput.operations.adminPassword
            Set-EulaSetting # Accept the EULA
            Set-CeipSetting -status DISABLED # Disable the CEIP setting
            Add-VcenterAdapter -VcfOpsFqdn $jsonInput.operations.master.fqdn -Username "admin" -Password $jsonInput.operations.adminPassword -VcenterFqdn $jsonInput.vcenter.fqdn -VcenterUser $jsonInput.vcenter.username -VcenterPass $jsonInput.vcenter.password

            # Deploy and Register a License Server
            Request-LicenseServerOTK # Request a one time key (OTK) for the registration of the License Server with VCF Operations
            Deploy-LicenseServerAppliance # Deploy the License Server appliance

            # License the system
            # Get-RegistrationFile # Download the license registration file from VCF Operations
            # Write-Host "Manually upload the registration file to Business Console and download the verification file"
            # pause
            # Import-VerificationFile
            # Get-ConfirmationFile

        }
    } else {
        Write-Host "[x] JSON Specification file ($jsonFile): File Not Found" -ForegroundColor Red
    }
} Catch {
    Write-Error $_.Exception.Message
}

# Restore default preference
$ProgressPreference = $previousProgressPreference