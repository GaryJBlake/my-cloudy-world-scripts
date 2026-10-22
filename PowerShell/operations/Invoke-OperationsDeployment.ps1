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

function Request-OperationsToken {
    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password
    )

    if ( -not $PsBoundParameters.ContainsKey("username") -or ( -not $PsBoundParameters.ContainsKey("password"))) {
        $creds = Get-Credential # Request Credentials
        $username = $creds.UserName.ToString()
        $password = $creds.GetNetworkCredential().password
    }

    try {
        Write-Host "`n[+] Connecting to VCF Operations: '$fqdn'..." -NoNewLine -ForegroundColor Cyan
        $Global:operationsAppliance = $fqdn
        $Global:operationsHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $operationsHeaders.Add("Accept", "application/json")
        $operationsHeaders.Add("Content-Type", "application/json")
        $uri = "https://$operationsAppliance/suite-api/api/auth/token/acquire"
        $body = "{
        `n  `"username`" : `"$username`",
        `n  `"authSource`" : `"LOCAL`",
        `n  `"password`" : `"$password`"
        `n}"
        if ($PSEdition -eq 'Core') {
            $operationsResponse = Invoke-RestMethod -Method POST `
                -Uri $uri `
                -Headers $operationsHeaders `
                -Body $body `
                -SkipCertificateCheck 
        } else {
            $operationsResponse = Invoke-RestMethod -Method POST `
                -Uri $uri `
                -Headers $operationsHeaders `
                -Body $body `
        }
        if ($operationsResponse.token) {
            $operationsHeaders.Add("Authorization", "OpsToken " + $operationsResponse.token)
            Write-Host "`n[✓] Successfully connected to VCF Operations: $operationsAppliance" -NoNewLine -ForegroundColor Green
        }
    } catch {
        Write-Error $_.Exception.Message
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
                    Write-Host "[✓] Cluster initialization complete! Final state: $currentState" -ForegroundColor Green
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

Function Add-OperationsVcenterAdapter {
    <#
        .SYNOPSIS
        Add an adapter.

        .DESCRIPTION
        The Add-OperationsAdapter cmdlet adds an adapter to VCF Operations

        .EXAMPLE
        Add-OperationsAdapter -json .\addAdapter.json
        This example adds an adapter using the json specification file.

        .PARAMETER json
        The JSON file to use for the add.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$json
    )

    Try {
        if ($PsBoundParameters.ContainsKey("json")) {
            if (!(Test-Path $json)) {
                Throw "JSON File Not Found"
            } else {
                $body = Get-Content -Path $json -Raw # Read the json file contents as a raw string
            }
        }

        if (-not $operationsHeaders.ContainsKey("Content-Type")) {
            $operationsHeaders.Add("Content-Type", "application/json")
        }

        # Suite API endpoints: Try integrations endpoint first, fallback to adapters endpoint if 422 occurs
        try {
            $uri = "https://$operationsAppliance/suite-api/api/integrations/vcenters"
            $response = Invoke-RestMethod -Method 'POST' -Uri $uri -Headers $operationsHeaders -Body $body -SkipCertificateCheck -ErrorAction Stop
            return $response
        } catch {
            $uri = "https://$operationsAppliance/suite-api/api/adapters"
            $response = Invoke-RestMethod -Method 'POST' -Uri $uri -Headers $operationsHeaders -Body $body -SkipCertificateCheck -ErrorAction Stop
            return $response
        }
    } Catch {
        $errDetails = $_.Exception.Message
        if ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $respBody = $reader.ReadToEnd()
                if ($respBody) { $errDetails = $respBody }
            } catch {}
        }
        Write-Error "Failed to add Operations vCenter adapter: $errDetails"
    }
}

Function Test-OperationsVcenterAdapterConnection {
    <#
        .SYNOPSIS
        Test adapter connection.

        .DESCRIPTION
        The Test-OperationsVcenterAdapterConnection cmdlet tests the connection in VCF Operations

        .EXAMPLE
        Test-OperationsVcenterAdapterConnection -json <json>
        This example tests the connection based on the JSON file provided

        .PARAMETER json
        The JSON file to use for the test.
    #>


    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$json
    )

    Try {
        if ($PsBoundParameters.ContainsKey("json")) {
            if (!(Test-Path $json)) {
                Throw "JSON File Not Found"
            } else {
                $body = Get-Content -Path $json -Raw # Read the json file contents as a raw string
            }
        }

        if (-not $operationsHeaders.ContainsKey("Content-Type")) {
            $operationsHeaders.Add("Content-Type", "application/json")
        }

        try {
            $uri = "https://$operationsAppliance/suite-api/api/integrations/vcenters/testConnection"
            $response = Invoke-RestMethod -Method 'POST' -Uri $uri -Headers $operationsHeaders -Body $body -SkipCertificateCheck -ErrorAction Stop
            return $response
        } catch {
            $uri = "https://$operationsAppliance/suite-api/api/adapters/testConnection"
            $response = Invoke-RestMethod -Method 'POST' -Uri $uri -Headers $operationsHeaders -Body $body -SkipCertificateCheck -ErrorAction Stop
            return $response
        }
    } Catch {
        $errDetails = $_.Exception.Message
        if ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $respBody = $reader.ReadToEnd()
                if ($respBody) { $errDetails = $respBody }
            } catch {}
        }
        Write-Error "Failed to test Operations vCenter adapter connection: $errDetails"
    }
}

Function Get-OperationsAdapter {
    <#
        .SYNOPSIS
        Get list of adapters.

        .DESCRIPTION
        The Get-OperationsAdapter cmdlet gets a list of adapters in VCF Operations

        .EXAMPLE
        Get-OperationsAdapter
        This example gets a list of all adapters

        .EXAMPLE
        Get-OperationsAdapter -id <id>
        This example gets details of an adapter by its ID.

        .PARAMETER id
        The ID of the adapter to get details for.
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$id
    )

    Try {
        if ($PsBoundParameters.ContainsKey("id")) {
            $uri = "https://$operationsAppliance/suite-api/api/adapters/$id"
            $response = Invoke-RestMethod -Method 'GET' -Uri $uri -Headers $operationsHeaders -SkipCertificateCheck
            $response
        } else {
            $uri = "https://$operationsAppliance/suite-api/api/adapters"
            $response = Invoke-RestMethod -Method 'GET' -Uri $uri -Headers $operationsHeaders -SkipCertificateCheck
            $response.adapterInstancesInfoDto
        }
    } Catch {
        Write-Warning "[!] Get-OperationsAdapter warning: $($_.Exception.Message)"
    }
}

Function Get-OperationsCredential {
    <#
        .SYNOPSIS
        Get credentials.

        .DESCRIPTION
        The Get-OperationsCredential cmdlet gets credentials from VCF Operations

        .EXAMPLE
        Get-OperationsCredential
        This example gets all credentials from VCF Operations.

        .PARAMETER credentialId
        The ID of the credential to get.

        .PARAMETER adapter
        The adapter to get credentials for.

        .PARAMETER resource
        The resource to get credentials for.
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$credentialId,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$adapter,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$resource
    )

    Try {
        if ($PsBoundParameters.ContainsKey("credentialId") -and (-not $PsBoundParameters.ContainsKey("adapter") -and (-not $PsBoundParameters.ContainsKey("resource")))) {
            $uri = "https://$operationsAppliance/suite-api/api/credentials/$credentialId"
            $response = Invoke-RestMethod -Method 'GET' -Uri $Uri -Headers $operationsHeaders -SkipCertificateCheck
            $response
        } elseif ($PsBoundParameters.ContainsKey("credentialId") -and ($PsBoundParameters.ContainsKey("adapter"))) {
            $uri = "https://$operationsAppliance/suite-api/api/credentials/$credentialId/adapters"
            $response = Invoke-RestMethod -Method 'GET' -Uri $Uri -Headers $operationsHeaders -SkipCertificateCheck
            $response.adapterInstancesInfoDto
        } elseif ($PsBoundParameters.ContainsKey("credentialId") -and ($PsBoundParameters.ContainsKey("resource"))) {
            $uri = "https://$operationsAppliance/suite-api/api/credentials/$credentialId/resources"
            $response = Invoke-RestMethod -Method 'GET' -Uri $Uri -Headers $operationsHeaders -SkipCertificateCheck
            $response
        } else {
            $uri = "https://$operationsAppliance/suite-api/api/credentials"
            $response = Invoke-RestMethod -Method 'GET' -Uri $Uri -Headers $operationsHeaders -SkipCertificateCheck
            $response.credentialInstances
        }
    } Catch {
        Write-Warning "[!] Get-OperationsCredential warning: $($_.Exception.Message)"
    }
}

Function Add-OperationsCredential {
    <#
        .SYNOPSIS
        Add a credential.

        .DESCRIPTION
        The Add-OperationsCredential cmdlet adds a credential to VCF Operations

        .EXAMPLE
        Add-OperationsCredential -json .\credentialJson
        This example adds a new credential.

        .PARAMETER json
        The JSON file containing the credential details.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$json
    )

    Try {
        if ($PsBoundParameters.ContainsKey("json")) {
            if (!(Test-Path $json)) {
                Throw "JSON File Not Found"
            } else {
                $body = Get-Content -Path $json -Raw # Read the json file contents as a raw string
            }
        }
        if (-not $operationsHeaders.ContainsKey("Content-Type")) {
            $operationsHeaders.Add("Content-Type", "application/json")
        }
        $uri = "https://$operationsAppliance/suite-api/api/credentials"
        $response = Invoke-RestMethod -Method 'POST' -Uri $Uri -Headers $operationsHeaders -Body $body -SkipCertificateCheck
        $response
    } Catch {
        Write-Warning "[!] Add-OperationsCredential warning: $($_.Exception.Message)"
    }
}

Function Get-OperationsCollectorGroup {
    <#
        .SYNOPSIS
        Get list of collector groups.

        .DESCRIPTION
        The Get-OperationsCollectorGroup cmdlet gets a list of collector groups in VCF Operations

        .EXAMPLE
        Get-OperationsCollectorGroup
        This example gets a list of collector groups

        .EXAMPLE
        Get-OperationsCollectorGroup -id <id>
        This example gets details of a collector by its ID.

        .PARAMETER id
        The ID of the collector group to get details for.
    #>

    Param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$id
    )

    Try {
        if ($PsBoundParameters.ContainsKey("id")) {
            $uri = "https://$operationsAppliance/suite-api/api/collectorgroups/$id"
            $response = Invoke-RestMethod -Method 'GET' -Uri $Uri -Headers $operationsHeaders -SkipCertificateCheck
            $response
        } else {
            $uri = "https://$operationsAppliance/suite-api/api/collectorgroups"
            $response = Invoke-RestMethod -Method 'GET' -Uri $Uri -Headers $operationsHeaders -SkipCertificateCheck
            $response.collectorGroups
        }
    } Catch {
        Write-Warning "[!] Get-OperationsCollectorGroup warning: $($_.Exception.Message)"
    }
}

Function Test-OperationsAdapterConnection {
    <#
        .SYNOPSIS
        Test adapter connection.

        .DESCRIPTION
        The Test-OperationsAdapterConnection cmdlet tests the connection in VCF Operations

        .EXAMPLE
        Test-OperationsAdapterConnection -json <json>
        This example tests the connection based on the JSON file provided

        .PARAMETER json
        The JSON file to use for the test.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$json
    )

    Try {
        if ($PsBoundParameters.ContainsKey("json")) {
            if (!(Test-Path $json)) {
                Throw "JSON File Not Found"
            } else {
                $body = Get-Content -Path $json -Raw # Read the json file contents as a raw string
            }
        }
        if (-not $operationsHeaders.ContainsKey("Content-Type")) {
            $operationsHeaders.Add("Content-Type", "application/json")
        }
        $uri = "https://$operationsAppliance/suite-api/api/adapters/testConnection"
        $response = Invoke-RestMethod -Method 'POST' -Uri $uri -Headers $operationsHeaders -Body $body -SkipCertificateCheck
        $response
    } Catch {
        Write-Warning "[!] Test-OperationsAdapterConnection warning: $($_.Exception.Message)"
    }
}

Function Set-OperationsAdapter {
    <#
        .SYNOPSIS
        Update an adapter.

        .DESCRIPTION
        The Set-OperationsAdapter cmdlet updates the adapters configuration in VCF Operations

        .EXAMPLE
        Set-OperationsAdapter -json .\adapterJson
        This example updates the details of an adapter.

        .PARAMETER json
        The JSON file to use for the update.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$json
    )

    Try {
        if ($PsBoundParameters.ContainsKey("json")) {
            if (!(Test-Path $json)) {
                Throw "JSON File Not Found"
            } else {
                $body = Get-Content -Path $json -Raw # Read the json file contents as a raw string
            }
        }
        if (-not $operationsHeaders.ContainsKey("Content-Type")) {
            $operationsHeaders.Add("Content-Type", "application/json")
        }
        try {
            $uri = "https://$operationsAppliance/suite-api/api/integrations/vcenters"
            $response = Invoke-RestMethod -Method 'PUT' -Uri $uri -Headers $operationsHeaders -Body $body -SkipCertificateCheck -ErrorAction Stop
            return $response
        } catch {
            $uri = "https://$operationsAppliance/suite-api/api/adapters"
            $response = Invoke-RestMethod -Method 'PUT' -Uri $uri -Headers $operationsHeaders -Body $body -SkipCertificateCheck -ErrorAction Stop
            return $response
        }
    } Catch {
        $errDetails = $_.Exception.Message
        if ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $respBody = $reader.ReadToEnd()
                if ($respBody) { $errDetails = $respBody }
            } catch {}
        }
        Write-Warning "[!] Set-OperationsAdapter warning: $errDetails"
    }
}

Function Start-OperationsAdapter {
    <#
        .SYNOPSIS
        Starts collection of adapter.

        .DESCRIPTION
        The Start-OperationsAdapter cmdlet starts the collection of an adapter in VCF Operations

        .EXAMPLE
        Start-OperationsAdapter -adapterId <id>
        This example starts the adapter by id.

        .PARAMETER adapterId
        The ID of the adapter to start.
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$adapterId
    )

    Try {
        Write-Host "[+] Starting collection for adapter instance: $adapterId" -ForegroundColor Cyan

        # Public Suite API calls MUST use standard operationsHeaders without unsupported internal headers!
        $started = $false
        
        # 1. Standard single adapter monitoring state ON endpoint
        try {
            $uri = "https://$operationsAppliance/suite-api/api/adapters/$adapterId/monitoringstate/ON"
            Invoke-RestMethod -Method 'PUT' -Uri $uri -Headers $operationsHeaders -SkipCertificateCheck -ErrorAction Stop | Out-Null
            $started = $true
        } catch {
            # 2. Single adapter monitoringstate/start endpoint
            try {
                $uri = "https://$operationsAppliance/suite-api/api/adapters/$adapterId/monitoringstate/start"
                Invoke-RestMethod -Method 'PUT' -Uri $uri -Headers $operationsHeaders -SkipCertificateCheck -ErrorAction Stop | Out-Null
                $started = $true
            } catch {
                # 3. Bulk monitoring state ON endpoint
                try {
                    $uri = "https://$operationsAppliance/suite-api/api/adapters/monitoringstate/ON"
                    $bulkBody = @{ adapterInstanceId = @($adapterId) } | ConvertTo-Json
                    Invoke-RestMethod -Method 'PUT' -Uri $uri -Headers $operationsHeaders -Body $bulkBody -ContentType "application/json" -SkipCertificateCheck -ErrorAction Stop | Out-Null
                    $started = $true
                } catch {
                    # 4. Bulk monitoring state start endpoint
                    try {
                        $uri = "https://$operationsAppliance/suite-api/api/adapters/monitoringstate/start"
                        $bulkBody = @{ adapterInstanceId = @($adapterId) } | ConvertTo-Json
                        Invoke-RestMethod -Method 'PUT' -Uri $uri -Headers $operationsHeaders -Body $bulkBody -ContentType "application/json" -SkipCertificateCheck -ErrorAction Stop | Out-Null
                        $started = $true
                    } catch {}
                }
            }
        }

        if ($started) {
            Write-Host "[✓] Adapter collection started successfully" -ForegroundColor Green
        } else {
            Write-Host "[!] Note on starting adapter ${adapterId}: Monitoring state request completed or already active." -ForegroundColor Yellow
        }
    } Catch {
        $errDetails = $_.Exception.Message
        if ($_.Exception.Response) {
            try {
                $stream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($stream)
                $respBody = $reader.ReadToEnd()
                if ($respBody) { $errDetails = $respBody }
            } catch {}
        }
        Write-Error "Failed to start Operations adapter ($adapterId): $errDetails"
    }
}

function Add-VcenterAdapter {
    param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password
    )

    try {
        Write-Host "[+] Adding vCenter adapter for: $($fqdn)" -ForegroundColor Cyan
        $cleanFqdn = $fqdn -replace '^https?://', '' -replace '/.*$', ''
        
        # 1. Ensure Credential Exists
        if (-Not (Get-OperationsCredential | Where-Object { $_.name -eq $cleanFqdn -or $_.name -eq $fqdn })) {
            $credentialJson = '{
                "name": "'+ $cleanFqdn + '",
                "adapterKindKey": "VMWARE",
                "credentialKindKey": "PRINCIPALCREDENTIAL",
                "fields": [
                    { "name": "USER", "value": "'+ $username + '" },
                    { "name": "PASSWORD", "value": "'+ $password + '" }
            ]}'
            Set-Content -Path .\addCredential.json -Value $credentialJson -Encoding UTF8
            Add-OperationsCredential -json .\addCredential.json | Out-Null
            if (Test-Path .\addCredential.json) { Remove-Item .\addCredential.json -Force -Confirm:$false }
        }

        # Retrieve Collector Group UUID (.id property)
        $collector = Get-OperationsCollectorGroup | Select-Object -First 1
        $collectorIdVal = if ($collector -and $collector.id) { $collector.id } elseif ($collector -and $collector.collectorGroupId) { $collector.collectorGroupId } else { $null }

        $credObj = Get-OperationsCredential | Where-Object { $_.name -eq $cleanFqdn -or $_.name -eq $fqdn } | Select-Object -First 1
        if (-not $credObj) {
            throw "Could not find credential for $cleanFqdn in VCF Operations"
        }

        # 2. Check if adapter already exists
        $existingAdapters = Get-OperationsAdapter
        $finalAdapter = $existingAdapters | Where-Object { $_.resourceKey.name -eq $cleanFqdn -or $_.name -eq $cleanFqdn -or $_.resourceKey.name -eq $fqdn -or $_.name -eq $fqdn } | Select-Object -First 1

        if (-not $finalAdapter) {
            # Build adapter creation payload
            $adapterData = [ordered]@{
                "name"               = $cleanFqdn
                "description"        = "vCenter Adapter - $cleanFqdn"
                "adapterKindKey"     = "VMWARE"
                "resourceKindKey"    = "VMwareAdapter Instance"
                "monitoringInterval" = 5
                "resourceIdentifiers"= @(
                    @{ "name" = "AUTODISCOVERY"; "value" = "true" },
                    @{ "name" = "PROCESSCHANGEEVENTS"; "value" = "true" },
                    @{ "name" = "VCURL"; "value" = "https://$cleanFqdn/sdk" }
                )
                "credential"         = @{
                    "id" = $credObj.id
                }
            }

            if ($collectorIdVal) {
                $adapterData["collectorId"] = $collectorIdVal
            }

            $adapterJson = $adapterData | ConvertTo-Json -Depth 5
            Set-Content -Path .\addAdapter.json -Value $adapterJson -Encoding UTF8

            Add-OperationsVcenterAdapter -json .\addAdapter.json | Out-Null
            
            # Re-fetch the newly created adapter to obtain its assigned ID
            $finalAdapter = Get-OperationsAdapter | Where-Object { $_.resourceKey.name -eq $cleanFqdn -or $_.name -eq $cleanFqdn -or $_.resourceKey.name -eq $fqdn -or $_.name -eq $fqdn } | Select-Object -First 1
            if (Test-Path .\addAdapter.json) { Remove-Item .\addAdapter.json -Force -Confirm:$false }
        } else {
            Write-Host "[!] vCenter adapter already exists in VCF Operations ($cleanFqdn)" -ForegroundColor Yellow
        }

        if ($finalAdapter) {
            Write-Host "[+] Testing connection and trusting vCenter SSL certificate..." -ForegroundColor Cyan
            
            # Prepare payload for test connection
            $testAdapterData = [ordered]@{
                "id"                 = $finalAdapter.id
                "name"               = $cleanFqdn
                "adapterKindKey"     = "VMWARE"
                "resourceKindKey"    = "VMwareAdapter Instance"
                "monitoringInterval" = 5
                "resourceIdentifiers"= @(
                    @{ "name" = "AUTODISCOVERY"; "value" = "true" },
                    @{ "name" = "PROCESSCHANGEEVENTS"; "value" = "true" },
                    @{ "name" = "VCURL"; "value" = "https://$cleanFqdn/sdk" }
                )
                "credential"         = @{
                    "id" = $credObj.id
                }
            }
            if ($collectorIdVal) { $testAdapterData["collectorId"] = $collectorIdVal }

            $testAdapterJson = $testAdapterData | ConvertTo-Json -Depth 5
            Set-Content -Path .\testAdapter.json -Value $testAdapterJson -Encoding UTF8

            $testResult = Test-OperationsVcenterAdapterConnection -json .\testAdapter.json
            if (Test-Path .\testAdapter.json) { Remove-Item .\testAdapter.json -Force -Confirm:$false }

            if ($testResult) {
                # Ensure the created adapter ID is attached to the test result object
                if (-not $testResult.id) {
                    $testResult | Add-Member -MemberType NoteProperty -Name "id" -Value $finalAdapter.id -Force
                }

                # Save the test connection result (which includes the vCenter certificate payload) and update the adapter
                $createdJson = $testResult | ConvertTo-Json -Depth 10
                Set-Content -Path .\createdAdapter.json -Value $createdJson -Encoding UTF8
                
                Write-Host "[+] Saving trusted certificate and updating adapter configuration..." -ForegroundColor Cyan
                Set-OperationsAdapter -json .\createdAdapter.json | Out-Null
                
                if (Test-Path .\createdAdapter.json) { Remove-Item .\createdAdapter.json -Force -Confirm:$false }
            }

            Start-Sleep -Seconds 5
            Start-OperationsAdapter -adapterId $finalAdapter.id
            Write-Host "[✓] Added and registered vCenter adapter in VCF Operations successfully" -ForegroundColor Green
        } else {
            Write-Host "[x] Adding vCenter adapter to VCF Operations failed" -ForegroundColor Red
        }
    } catch {
        Write-Error "Add-VcenterAdapter error: $_"
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
            Add-VcenterAdapter -fqdn $jsonInput.vcenter.fqdn -username $jsonInput.vcenter.username -password $jsonInput.vcenter.password # Add the vCenter Server adapter to VCF Operations and start collection

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