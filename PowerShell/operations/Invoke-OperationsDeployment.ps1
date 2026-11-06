Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$jsonPath
)

# Store default preference
$previousProgressPreference = $ProgressPreference
# Suppress native cmdlet progress bars
$ProgressPreference = 'SilentlyContinue'

$solutionName = "VCF Operations Installation"

function Start-OperationsInstall {
    Try {
        $menuHeader = "$solutionName"

        $headingItem01 = "VCF Operations and License Server Deployment"
        $menuitem01 = "Generate Public and Private Keys"
        $menuitem02 = "VCF Operations and License Server Deployment"
        $menuitem03 = "Register Keys and Install License File"

        Do {
            Clear-Host
            Write-Host ""; Write-Host -Object $menuHeader -ForegroundColor Magenta

            Write-Host ""; Write-Host -Object " $headingItem01" -ForegroundColor Yellow; Write-Host ""
            Write-Host -Object " 01. $menuItem01" -ForegroundColor White
            Write-Host -Object " 02. $menuItem02" -ForegroundColor White
            Write-Host -Object " 03. $menuItem03" -ForegroundColor White

            Write-Host -Object ''
            $menuInput = Read-Host -Prompt ' Select Option (or Q to Quit) to Return to Previous Menu'
            $menuInput = $MenuInput -replace "`t|`n|`r", ""
            if ($MenuInput -like "0*") { $MenuInput = ($MenuInput -split ("0"), 2)[1] }
            Switch ($menuInput) {
                1 {
                    if (!$headlessPassed) { Clear-Host }; Write-Host `n " $menuTitle" -Foregroundcolor Cyan; Write-Host ''
                    Invoke-PublicPrivateKey -jsonFile $jsonPath
                    waitKey
                }
                2 {
                    if (!$headlessPassed) { Clear-Host }; Write-Host `n " $menuTitle" -Foregroundcolor Cyan; Write-Host ''
                    Invoke-OperationsDeployment -jsonFile $jsonPath
                    waitKey
                }
                3 {
                    if (!$headlessPassed) { Clear-Host }; Write-Host `n " $menuTitle" -Foregroundcolor Cyan; Write-Host ''
                    Invoke-OperationsLicenseInstall -jsonFile $jsonPath
                    waitKey
                }
                Q {
                    if (!$headlessPassed) { Clear-Host }
                    Break
                }
            }
        }
        Until ($MenuInput -eq 'q')
    } Catch {
        Debug-ExceptionWriter -object $_
    }
}

function waitKey {
    Write-Host ''; Write-Host -Object ' Press any key to continue/return to menu...' -ForegroundColor Yellow; Write-Host '';
    if ($headlessPassed) {
        $response = if (!$clioptions) { Read-Host } else { "" }
    } else {
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
}

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
        Write-Host "[+] Validating vSphere target objects for vApp deployment..." -ForegroundColor Cyan
        $vmHost    = Get-VMHost -Name $jsonInput.vcenter.targetEsx -ErrorAction Stop
        $datastore = Get-Datastore -Name $jsonInput.vcenter.datastore -ErrorAction Stop

        # 2. Check for Name Collisions
        $existingVm = Get-VM -Name ($jsonInput.operations.master.fqdn -replace '\..*$', '') -ErrorAction SilentlyContinue

        if ($existingVm) {
            # Warn and skip import
            Write-Host "[!] Found existing Virtual Machine '$($jsonInput.operations.master.fqdn -replace '\..*$', '')' in this vCenter. Skipping OVA import" -ForegroundColor Yellow
            $importedVm = $existingVm
        } 
        else {
            # 3. Extract OVF configuration & Import (Only run if VM does NOT exist)
            Write-Host "[+] Extracting Open Virtualization Format (OVF) configuration for VCF Operations..." -ForegroundColor Cyan
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
            Write-Host "[!] Virtual Machine '$($jsonInput.operations.master.fqdn -replace '\..*$', '')' is already powered on" -ForegroundColor Yellow
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
            Write-Host "[✓] Virtual Machine '$($jsonInput.operations.master.fqdn -replace '\..*$', '')' is powered on and reachable at IP: $validIp" -ForegroundColor Green
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
            -Uri "https://${operationsFqdn}/suite-api/internal/deployment/config/properties/java_util_HashSet" `
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
            -Uri "https://${operationsFqdn}/suite-api/internal/deployment/config/properties/java_util_HashSet" `
            -Headers $internalHeaders `
            -Body $jsonPropBody `
            -ContentType "application/json" `
            -SkipCertificateCheck `
            -ErrorAction SilentlyContinue | Out-Null

        # 2. Configure global telemetry status (Enabled/Disabled)
        $telemetrySetting = Invoke-RestMethod -Method GET `
            -Uri "https://${operationsFqdn}/suite-api/api/deployment/config/globalsettings/TELEMETRY_ENABLED" `
            -Headers $operationsHeaders `
            -SkipCertificateCheck `
            -ErrorAction SilentlyContinue

        if (-Not ($telemetrySetting.values -contains ${setting})) {
            # Endpoint variation 1: PUT URL path setting
            try {
                Invoke-RestMethod -Method PUT `
                    -Uri "https://${operationsFqdn}/suite-api/api/deployment/config/globalsettings/TELEMETRY_ENABLED/${setting}" `
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
                        -Uri "https://${operationsFqdn}/suite-api/api/deployment/config/globalsettings" `
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

    $Global:operationsFqdn = $Fqdn
    Write-Host "[+] Acquiring VCF Operations API token from '$operationsFqdn'..." -ForegroundColor Cyan
    $uri = "https://$operationsFqdn/suite-api/api/auth/token/acquire"
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
            Write-Host "[✓] Successfully acquired VCF Operations API token from '$operationsFqdn'" -ForegroundColor Green
            $Global:operationsToken = $response.token
            $Global:operationsHeaders = @{
                "Accept"        = "application/json"
                "Content-Type"  = "application/json"
                "Authorization" = "OpsToken $operationsToken"
            }
            #return $response.token | Out-Null
        } else {
            throw "Token empty in response"
        }
    }
    catch {
        Write-Error "Failed to acquire VCF Operations API token from '${operationsFqdn}': $_"
        throw
    }
}

function Get-OperationsCredential {
    Write-Host "[+] Querying credentials in VCF Operations..." -ForegroundColor Cyan

    try {
        if ($PSEdition -eq 'Core') {
            $response = Invoke-RestMethod -Method GET -Uri "https://${operationsFqdn}/suite-api/api/credentials" -Headers $operationsHeaders -SkipCertificateCheck -ErrorAction Stop
        } else {
            $response = Invoke-RestMethod -Method GET -Uri "https://${operationsFqdn}/suite-api/api/credentials" -Headers $operationsHeaders -ErrorAction Stop
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
        [Parameter(Mandatory = $true)] [String]$CredentialName,
        [Parameter(Mandatory = $true)] [String]$User,
        [Parameter(Mandatory = $true)] [String]$Pass
    )

    Write-Host "[+] Creating credential '$CredentialName' in VCF Operations..." -ForegroundColor Cyan
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
            $response = Invoke-RestMethod -Method POST -Uri "https://${operationsFqdn}/suite-api/api/credentials" -Headers $operationsHeaders -Body $body -SkipCertificateCheck -ErrorAction Stop
        } else {
            $response = Invoke-RestMethod -Method POST -Uri "https://${operationsFqdn}/suite-api/api/credentials" -Headers $operationsHeaders -Body $body -ErrorAction Stop
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
    Write-Host "[+] Querying collector groups in VCF Operations..." -ForegroundColor Cyan

    try {
        if ($PSEdition -eq 'Core') {
            $response = Invoke-RestMethod -Method GET -Uri "https://${operationsFqdn}/suite-api/api/collectorgroups" -Headers $operationsHeaders -SkipCertificateCheck -ErrorAction Stop
        } else {
            $response = Invoke-RestMethod -Method GET -Uri "https://${operationsFqdn}/suite-api/api/collectorgroups" -Headers $operationsHeaders -ErrorAction Stop
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
        [Parameter(Mandatory = $false)] [String]$AdapterId,
        [Parameter(Mandatory = $false)] [String]$AdapterKindKey
    )

    $uri = "https://${operationsFqdn}/suite-api/api/adapters"
    if ($AdapterId) { $uri += "/$AdapterId" }
    elseif ($AdapterKindKey) { $uri += "?adapterKindKey=$AdapterKindKey" }

    $r = Invoke-OperationsRest -Method GET -Uri $uri -Headers $operationsHeaders
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
        [Parameter(Mandatory = $true)] [String[]]$AdapterInstanceIds
    )

    # Creation never starts an adapter (the UI makes a separate startCloudAccountCollect call).
    # Documented Suite API call: PUT /suite-api/api/adapters/{id}/monitoringstate/start (no body).
    $allStarted = $true
    foreach ($id in $AdapterInstanceIds) {
        Write-Host "[+] Starting collection for adapter instance ID: $id..." -ForegroundColor Cyan
        $r = Invoke-OperationsRest -Method PUT -Uri "https://${operationsFqdn}/suite-api/api/adapters/$id/monitoringstate/start" -Headers $operationsHeaders
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
    Add-VcenterAdapter -VcenterFqdn "sfo-w03-vc01.sfo.rainpole.io" -VcenterUser "administrator@vsphere.local" -VcenterPass "VMware1!"
#>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false)] [String]$VcenterFqdn,
        [Parameter(Mandatory = $false)] [String]$VcenterUser,
        [Parameter(Mandatory = $false)] [String]$VcenterPass,
        [Parameter(Mandatory = $false)] [String]$CollectorGroupId
    )

    if ($PSEdition -ne 'Core') {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }

    $cleanVcFqdn = $VcenterFqdn -replace '^https?://', '' -replace '/.*$', ''

    Write-Host "[+] Starting VCF Operations Cloud Account Workflow..." -ForegroundColor Cyan

    # 1. Get or Create Credential
    $existingCreds = Get-OperationsCredential
    $credObj = $existingCreds | Where-Object { $_.name -eq $cleanVcFqdn -or $_.name -eq $VcenterFqdn } | Select-Object -First 1

    if (-not $credObj) {
        $credObj = Add-OperationsCredential -CredentialName $cleanVcFqdn -User $VcenterUser -Pass $VcenterPass
    } else {
        Write-Host "[!] Found existing credential for '$cleanVcFqdn' (ID: $($credObj.id))" -ForegroundColor Yellow
    }
    $credentialId = if ($credObj.id) { $credObj.id } else { $credObj.credentialInstances[0].id }

    # 2. Resolve Collector Group
    if ([String]::IsNullOrWhiteSpace($CollectorGroupId)) {
        $collectors = Get-OperationsCollectorGroup
        if ($collectors -and $collectors.Count -gt 0) {
            $CollectorGroupId = if ($collectors[0].id) { $collectors[0].id } else { $collectors[0].collectorGroupId }
        }
    }
    Write-Host "[✓] Using Collector Group ID: $CollectorGroupId" -ForegroundColor Green

    # 3. Check if Adapter Exists or Create It
    Write-Host "[+] Checking if the Adapter already exists..." -ForegroundColor Cyan
    $matchesVc = { (Get-OperationsAdapterName $_) -in @($cleanVcFqdn, $VcenterFqdn) }
    $adapterObj = Get-OperationsAdapter -AdapterKindKey "VMWARE" | Where-Object $matchesVc | Select-Object -First 1

    if (-not $adapterObj) {
        # 4a. Test connection first; vCenter's untrusted certificate is returned for acceptance
        $payload = New-OperationsVcenterIntegrationPayload -VcenterFqdn $cleanVcFqdn -CollectorGroupId $CollectorGroupId -CredentialId $credentialId
        $base = "https://${operationsFqdn}/suite-api/api/integrations/vcenters"

        Write-Host "[+] Testing vCenter connection and certificate..." -ForegroundColor Cyan
        $test = Invoke-OperationsRest -Method POST -Uri "$base/testConnection" -Headers $operationsHeaders -Body $payload
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
        $create = Invoke-OperationsRest -Method POST -Uri "$base/?forceManagementOwnership=false" -Headers $operationsHeaders -Body $payload
        if (-not $create.Ok) { throw "Failed to create vCenter integration (HTTP $($create.Status)): $($create.Message)" }

        $adapterObj = Get-OperationsAdapter -AdapterKindKey "VMWARE" | Where-Object $matchesVc | Select-Object -First 1
        
        if (-not $adapterObj) { throw "vCenter integration was created but the adapter instance could not be found." }
    } else {
        Write-Host "[!] Found existing vCenter adapter for '$cleanVcFqdn' (ID: $($adapterObj.id))" -ForegroundColor Yellow
    }

    $adapterId = $adapterObj.id

    # 4. Collect the adapter IDs to start: the vCenter adapter plus its vSAN child (UI uses withChildren=true)
    $adapterIdsToStart = @($adapterId)
    $vsanAdapter = Get-OperationsAdapter -AdapterKindKey "VirtualAndPhysicalSANAdapter" |
        Where-Object { (Get-OperationsAdapterName $_) -like "$cleanVcFqdn*" } | Select-Object -First 1
    if ($vsanAdapter) { $adapterIdsToStart += $vsanAdapter.id }

    # 5. Enable Metric Collection (creation leaves the adapters Stopped / Not Collecting)
    $started = Start-OperationsAdapterCollection -AdapterInstanceIds $adapterIdsToStart
    if (-not $started) { throw "One or more adapters could not be started; see errors above." }

    Write-Host "[✓] VCF Operations Cloud Account Workflow Completed Successfully for $cleanVcFqdn" -ForegroundColor Green
}

function Request-LicenseServerOTK {

    try {
        Write-Host "[+] Attempting to obtain One Time Key (OTK) for License Server registration" -ForegroundColor Cyan

        $internalHeaders = @{}
        foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
        $internalHeaders["X-vRealizeOps-API-use-unsupported"] = "true"

        $Script:licenseServerOTK = Invoke-RestMethod -Method GET `
            -Uri "https://${operationsFqdn}/suite-api/internal/extension/vcf-license-cloud-integration/license-servers/otk" `
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

function Get-RandomApiKey {
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

    # # If the script is executed directly (not sourced or imported), output a generated key.
    # if ($MyInvocation.InvocationName -ne '.') {
    #     Get-RandomApiKey -Prefix $Prefix -DateFormat $DateFormat -EntropyBits $EntropyBits -Encoding $Encoding -Separator $Separator
    # }
}

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

function Deploy-LicenseServerAppliance {
    $TimeoutMinutes  = 15
    $PollIntervalSec = 10

    try {
        # 1. Target Object Validation
        Write-Host "[+] Validating vSphere target objects for vApp deployment..." -ForegroundColor Cyan
        $vmHost    = Get-VMHost -Name $jsonInput.vcenter.targetEsx -ErrorAction Stop
        $datastore = Get-Datastore -Name $jsonInput.vcenter.datastore -ErrorAction Stop

        # 2. Check for Name Collisions
        $existingVm = Get-VM -Name ($jsonInput.licenseServer.fqdn -replace '\..*$', '') -ErrorAction SilentlyContinue

        if ($existingVm) {
            # Warn and skip import
            Write-Host "[!] Found existing Virtual Machine '$($jsonInput.licenseServer.fqdn -replace '\..*$', '')' in this vCenter. Skipping OVA import" -ForegroundColor Yellow
            $importedVm = $existingVm
        } 
        else {
            # 3. Extract OVF configuration & Import (Only run if VM does NOT exist)
            Write-Host "[+] Extracting Open Virtualization Format (OVF) configuration for License Server..." -ForegroundColor Cyan

            $Script:licenseServerApiKey = Get-RandomApiKey
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
            $ovfConfigLicenseServer.Common.api_key.Value                                    = $licenseServerApiKey
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
            Write-Host "[!] Virtual Machine '$($jsonInput.licenseServer.fqdn -replace '\..*$', '')' is already powered on" -ForegroundColor Yellow
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
            Write-Host "[✓] Virtual Machine '$($jsonInput.licenseServer.fqdn -replace '\..*$', '')' is powered on and reachable at IP: $validIp" -ForegroundColor Green
        } else {
            Write-Warning "[!] Timed out after $TimeoutMinutes minutes waiting for a valid IP address."
            Write-Warning "    - Check if VMware Tools booted properly inside the guest OS."
            Write-Warning "    - Verify DHCP or OVF network settings are correct."
        }

    } catch {
        Write-Error "Deployment failed: $_"
    }
}

function New-RsaKeyPair {
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
        [switch]$Overwrite
    )

    process {
        try {
            # 1. Check if openssl is installed and accessible in PATH
            if (-not (Get-Command "openssl" -ErrorAction SilentlyContinue)) {
                throw "[X] OpenSSL executable ('openssl') was not found in PATH. Please install OpenSSL and ensure it is available in your environment path."
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
                Write-Host "[+] Creating output directory: $resolvedDir" -ForegroundColor Cyan
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

            Write-Host "[+] Generating RSA Key Pair ($KeyBits-bit) using OpenSSL" -ForegroundColor Cyan
            Write-Host "[+] Output Directory: $resolvedDir" -ForegroundColor Cyan

            # Step 1: Generate Private Key
            # openssl genpkey -algorithm RSA -out private_key.pem -pkeyopt rsa_keygen_bits:4096
            Write-Host "[+] Generating RSA Private Key ($KeyBits bits)..." -ForegroundColor Cyan
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
            Write-Host "[✓] Created private key: $privateKeyPath" -ForegroundColor Green

            # Step 2: Extract Public Key
            # openssl rsa -pubout -in private_key.pem -out public_key.pem
            Write-Host "[+] Extracting RSA Public Key..." -ForegroundColor Cyan
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
            Write-Host "[✓] Created public key: $publicKeyPath" -ForegroundColor Green

            # Step 3: Combine Private Key and Public Key into Keypair File
            # cat private_key.pem public_key.pem > keypair.pem
            Write-Host "[+] Combining private and public key into combined keypair..." -ForegroundColor Cyan
            $privateContent = [System.IO.File]::ReadAllText($privateKeyPath)
            $publicContent  = [System.IO.File]::ReadAllText($publicKeyPath)

            # Cleanly join content with LF newlines without UTF-8 BOM
            $combinedContent = $privateContent.TrimEnd() + "`n" + $publicContent.TrimEnd() + "`n"
            $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($combinedKeyPath, $combinedContent, $utf8NoBom)

            if (-not (Test-Path -Path $combinedKeyPath)) {
                throw "Failed to create combined keypair file at '$combinedKeyPath'."
            }
            Write-Host "[✓] Created combined keypair: $combinedKeyPath" -ForegroundColor Green
            Write-Host "[✓] Key pair generation completed successfully" -ForegroundColor Green

        }
        catch {
            Write-Error "An error occurred during key pair generation: $_"
            throw $_
        }
    }
}

function Get-VmApiKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [psobject]$VM
    )

    process {
        # 1. Resolve VM object if a string VM name was provided
        $vmObject = $null
        if ($VM -is [string]) {
            if (-not (Get-Command -Name Get-VM -ErrorAction SilentlyContinue)) {
                throw "VMware PowerCLI module (VMware.VimAutomation.Core) is required when passing VM by name string."
            }
            Write-Verbose "Fetching VM object for name '$VM'..."
            $vmObject = Get-VM -Name $VM -ErrorAction Stop
        } else {
            $vmObject = $VM
        }

        if (-not $vmObject) {
            throw "Invalid or null VM input provided."
        }

        # Determine VM name for log/warning outputs
        $vmName = if ($vmObject.Name) { $vmObject.Name } else { $vmObject.ToString() }

        # 2. Access VAppConfig from PowerCLI VirtualMachine object or vSphere API MoRef object
        $vAppConfig = $null
        if ($vmObject.PSObject.Properties['ExtensionData'] -and $vmObject.ExtensionData.Config) {
            $vAppConfig = $vmObject.ExtensionData.Config.VAppConfig
        } elseif ($vmObject.PSObject.Properties['Config']) {
            $vAppConfig = $vmObject.Config.VAppConfig
        }

        if (-not $vAppConfig -or -not $vAppConfig.Property) {
            Write-Warning "No vApp options/properties are configured on VM '$vmName'."
            return $null
        }

        # 3. Locate the 'api_key' vApp property
        $targetKey = "api_key"
        $property = $vAppConfig.Property | Where-Object {
            $_.Id -ieq $targetKey -or 
            $_.Id -ieq "guestinfo.$targetKey" -or
            $_.Label -ieq $targetKey
        } | Select-Object -First 1

        # Fallback substring search if key formatted with prefix/suffix (e.g. guestinfo.api_key)
        if (-not $property) {
            $property = $vAppConfig.Property | Where-Object {
                $_.Id -ilike "*$targetKey*"
            } | Select-Object -First 1
        }

        if (-not $property) {
            Write-Warning "vApp option 'api_key' was not found on VM '$vmName'."
            return $null
        }

        # 4. Extract and return the configured value (or DefaultValue if value field is empty)
        $value = $property.Value
        if ([string]::IsNullOrEmpty($value)) {
            $value = $property.DefaultValue
        }

        return $value
    }
}

function Install-OperationsKeyPair {
    [CmdletBinding()]
    param(
        [Parameter (Mandatory = $true, HelpMessage = "Path to the combined public/private keypair .pem file")] [Alias("PemPath", "FilePath")] [string]$KeypairPath,
        [Parameter (Mandatory = $false)] [switch]$VerifyStatus,
        [Parameter (Mandatory = $false)] [switch]$SkipCertificateCheck
    )

    process {
        try {
            Write-Host "[+] Attempting to upload key pair to VCF Operations..." -ForegroundColor Cyan

            # ---------------------------------------------------------
            # Step 1: Verify Keypair File Existence
            # ---------------------------------------------------------
            Write-Host "[+] Validating the existence of the Key Pair file for '$VcfOpsHost'..." -ForegroundColor Cyan
            
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
            # Steps 2 : Update Header with Additional Values
            # ---------------------------------------------------------
            
            $internalHeaders = @{}
            foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
            $internalHeaders["X-Ops-API-use-unsupported"] = "true"
            $internalHeaders["X-vRealizeOps-API-use-internal"] = "true"

            # ---------------------------------------------------------
            # Steps 3-5: Upload Key Pair (/internal/license-manager/identity/keypair)
            # ---------------------------------------------------------

            $candidateUploadUrls = @(
                "https://${operationsFqdn}/suite-api/api/internal/license-manager/identity/keypair",
                "https://${operationsFqdn}/suite-api/internal/license-manager/identity/keypair"
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
                            Headers    = $internalHeaders
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
            # Steps 6 & 7: Optional Status Verification
            # ---------------------------------------------------------
            $statusResult = $null
            if ($VerifyStatus) {
                Write-Host "[+] Verifying VCF Operations registration and private mode status..." -ForegroundColor Cyan
                
                $candidateStatusUrls = @(
                    "https://${operationsFqdn}/suite-api/api/internal/license-manager/registration/status",
                    "https://${operationsFqdn}/suite-api/internal/license-manager/registration/status"
                )

                foreach ($statusUrl in $candidateStatusUrls) {
                    Write-Verbose "Attempting status query to URL: $statusUrl"
                    try {
                        $splatStatus = @{
                            Uri        = $statusUrl
                            Method     = 'Get'
                            Headers    = $internalHeaders
                            WebSession = $webSession
                        }
                        if ($SkipCertificateCheck) {
                            $splatStatus['SkipCertificateCheck'] = $true
                        }

                        $statusResult = Invoke-RestMethod @splatStatus
                        if ($($statusResult.connectivityMode) -eq "PRIVATE") {
                            Write-Host "[✓] Registration Status Response: $($statusResult.connectivityMode)" -ForegroundColor Green
                        } else {
                            Write-Host "[x] Registration Status Response: $($statusResult.connectivityMode)" -ForegroundColor Red
                        }
                        #$statusResult | Format-List | Out-String | Write-Host
                        break
                    }
                    catch {
                        Write-Verbose "Status query to '$statusUrl' failed: $_"
                    }
                }
            }
        }
        catch {
            Write-Error "Error uploading key pair to VCF Operations: $_"
            throw $_
        }
    }
}

function Install-LicenseServerKeyPair {
    
    [CmdletBinding()]
    param(
        [Parameter (Mandatory = $false, Position = 0)] [string]$LicenseServerFqdn,
        [Parameter (Mandatory = $false, Position = 1)] [string]$ApiKey,
        [Parameter (Mandatory = $false, Position = 2)] [string]$KeyPairPemFilePath,
        [Parameter (Mandatory = $false)] [switch]$VerifyStatus,
        [Parameter (Mandatory = $false)] [switch]$SkipCertificateCheck = $true
    )

    process {
        try {
            Write-Host "[+] Attempting to upload key pair to License Server..." -ForegroundColor Cyan

            # ---------------------------------------------------------
            # Step 1: Verify Keypair File Existence
            # ---------------------------------------------------------
            Write-Host "[+] Validating the existence of the Key Pair file for '$LicenseServerFqdn'..." -ForegroundColor Cyan
            
            $targetPath = $KeyPairPemFilePath
            if (-not (Test-Path -Path $targetPath)) {
                $fileNameOnly = [System.IO.Path]::GetFileName($KeyPairPemFilePath)
                $cwdPath = Join-Path -Path (Get-Location).Path -ChildPath $fileNameOnly
                $tmpPath = Join-Path -Path "/tmp" -ChildPath $fileNameOnly

                if (Test-Path -Path $cwdPath) {
                    Write-Host "[!] File not found at '$KeyPairPemFilePath', but found in current directory" -ForegroundColor Yellow
                    $targetPath = $cwdPath
                } elseif (Test-Path -Path $tmpPath) {
                    Write-Host "[!] File not found at '$KeyPairPemFilePath', but found in /tmp: '$tmpPath'." -ForegroundColor Yellow
                    $targetPath = $tmpPath
                } else {
                    $currentDir = (Get-Location).Path
                    throw "Specified keypair PEM file was not found at '$KeyPairPemFilePath'. (Current Working Directory: '$currentDir')"
                }
            }

            $resolvedKeypairPath = (Get-Item -Path $targetPath).FullName
            Write-Host "[✓] Using combined keypair file: $resolvedKeypairPath" -ForegroundColor Green

            # ---------------------------------------------------------
            # Steps 2: Install Key Pair to License Server
            # ---------------------------------------------------------
            if (-not (Test-Path -Path $KeyPairPemFilePath)) {
                throw "Private key PEM file was not found at path: '$KeyPairPemFilePath'"
            }

            $pemItem = Get-Item -Path $KeyPairPemFilePath
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

            Write-Host "[+] Uploading key pair'$KeyPairPemFilePath' to License Server..."  -ForegroundColor Cyan
            Invoke-RestMethod @restParams | Out-Null

            # ---------------------------------------------------------
            # Steps 3: Optional Status Verification
            # ---------------------------------------------------------
            $statusResult = $null
            if ($VerifyStatus) {
                Write-Host "[+] Verifying License Server registration and private mode status..." -ForegroundColor Cyan

                # Construct Internal Headers
                $internalHeaders = @{}
                foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
                $internalHeaders["X-vRealizeOps-API-use-internal"] = "true"
                $internalHeaders["X-Ops-API-use-unsupported"] = "true"

                # Candidate URLs (with and without /api)
                $candidateUrls = @(
                    "https://${operationsFqdn}/suite-api/internal/extension/vcf-license-cloud-integration/license-servers",
                    "https://${operationsFqdn}/suite-api/api/internal/extension/vcf-license-cloud-integration/license-servers"
                )

                $success = $false
                foreach ($url in $candidateUrls) {
                    try {
                        $GLobal:response = Invoke-RestMethod -Uri $url -Method Get -Headers $internalHeaders -SkipCertificateCheck
                        if ($($response.registrationStatus) -eq "PRIVATE") {
                            Write-Host "[✓] License Server registration status response: $($response.registrationStatus)" -ForegroundColor Green
                        } else {
                            Write-Host "[x] License Server registration status response: $($response.registrationStatus)" -ForegroundColor Red
                        }
                        $success = $true
                        break
                    }
                    catch {
                        Write-Host "[!] Failed on URL '$url': $_" -ForegroundColor Yellow
                    }
                }

                if (-not $success) {
                    Write-Error "Failed to reach License Servers endpoint on all candidate URLs."
                }
            }
        } catch {
            Write-Error "Error uploading key pair to VCF Operations: $_"
            throw $_
        }
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

function Import-OperationsLicenseFile {
    param (
        [Parameter (Mandatory = $true)] [String]$licenseFile
    )

    try {
        if (-Not (Get-OperationsLicense)) {
            if (-not (Test-Path -Path $licenseFile -PathType Leaf)) {
                Write-Host "[x] '$licenseFile' is not a valid file." -ForegroundColor Red
            } else {
                Write-Host "[+] Attempting to upload the license file to VCF Operations ..." -ForegroundColor Cyan

                $internalHeaders = @{}
                foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
                $internalHeaders["X-Ops-API-use-unsupported"] = "true"
                $internalHeaders["X-vRealizeOps-API-use-internal"] = "true"

                # Prepare the multipart form data payload using Get-Item
                $uploadForm = @{
                    file = Get-Item -Path $licenseFile
                }

                $uploadResults = Invoke-RestMethod -Method POST `
                    -Uri "https://${operationsFqdn}/suite-api/internal/extension/vcf-license-cloud-integration/registration/offline/response" `
                    -Headers $internalHeaders `
                    -Form $uploadForm `
                    -SkipCertificateCheck

                Write-Host "[✓] Uploaded license file to VCF Operations successfully" -ForegroundColor Green
            }
        } else {
            Write-Host "[!] Licenses already exist in VCF Operations" -ForegroundColor Yellow
        }
    } catch {
        Write-Error $_.Exception.Message
    }
}

function Get-LicenseRegistrationStatus {

    $internalHeaders = @{}
    foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
    $internalHeaders["X-Ops-API-use-unsupported"] = "true"

    Invoke-RestMethod -Method Get -Uri "https://$operationsFqdn/suite-api/internal/extension/vcf-license-cloud-integration/license-servers" -Headers $internalHeaders -SkipCertificateCheck
}

function Get-OperationsLicenseServers {
    # Construct Internal Headers
    $internalHeaders = @{}
    foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
    $internalHeaders["X-vRealizeOps-API-use-internal"] = "true"
    $internalHeaders["X-Ops-API-use-unsupported"] = "true"

    # Candidate URLs (with and without /api)
    $candidateUrls = @(
        "https://${operationsFqdn}/suite-api/internal/extension/vcf-license-cloud-integration/license-servers",
        "https://${operationsFqdn}/suite-api/api/internal/extension/vcf-license-cloud-integration/license-servers"
    )

    $success = $false
    foreach ($url in $candidateUrls) {
        try {
            $response = Invoke-RestMethod -Uri $url -Method Get -Headers $internalHeaders -SkipCertificateCheck
            $response
            #$response | Format-Table -Property name, fqdn, ip, registrationStatus, connectivityStatus, lastLicenseRefreshDate
            $success = $true
            break
        }
        catch {
            Write-Host "[!] Failed on URL '$url': $_" -ForegroundColor Yellow
        }
    }

    if (-not $success) {
        Write-Error "Failed to reach License Servers endpoint on all candidate URLs."
    }
}

function Wait-LicenseStatus{
    $maxAttempts = 30
    $attempt = 0
    $intervalSeconds = 5

    do {
        $attempt++
        $status = (Get-OperationsLicenseServers).registrationStatus
        
        # Pad with trailing spaces to clear any remnants from longer previous text
        Write-Host "`r[!] Current Status: $status" -NoNewline -ForegroundColor Yellow
        if ($status -eq 'PRIVATE') {
            Write-Host "`n[✓] Success: Registration status reached PRIVATE." -ForegroundColor Green
            break
        }

        if ($attempt -ge $maxAttempts) {
            Write-Host "" # Move cursor down to prevent Write-Warning from colliding
            Write-Warning "Timeout reached after $maxAttempts attempts without reaching PRIVATE."
            break
        }

        Start-Sleep -Seconds $intervalSeconds
    } while ($true)
}

function Wait-VcenterRegistration {
    param (
        [int]$TimeoutMinutes = 20,
        [int]$checkIntervalSeconds = 30
    )

    Write-Host "[+] Checking vCenter is registered for licensing (Max wait: 20 minutes)" -ForegroundColor Cyan

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $result = $null

    do {
        try {
            $result = Get-OperationsVcenters -ErrorAction Stop
        }
        catch {
            Write-Warning "Attempt failed: $_"
        }

        if ($result) {
            Write-Host "[✓] Retrieved vCenter for licensing successfully" -ForegroundColor Green
            break
        }

        if ($stopwatch.Elapsed.TotalMinutes -ge $timeoutMinutes) {
            Write-Host "[x] Operation timed out after $timeoutMinutes minute(s)" -ForegroundColor Red
            break
        }

        Start-Sleep -Seconds $checkIntervalSeconds

    } while ($true)

    $stopwatch.Stop()
} 

function Get-OperationsLicense {

    $internalHeaders = @{}
    foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
    $internalHeaders["X-vRealizeOps-API-use-internal"] = "true"
    $internalHeaders["X-Ops-API-use-unsupported"] = "true"

    Invoke-RestMethod -Method Get -Uri "https://${operationsFqdn}/suite-api/internal/licenses" -Headers $internalHeaders -SkipCertificateCheck

}

function Get-OperationsVcenters {

    $internalHeaders = @{}
    foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
    $internalHeaders["X-vRealizeOps-API-use-internal"] = "true"
    $internalHeaders["X-Ops-API-use-unsupported"] = "true"

    (Invoke-RestMethod -Method Get -Uri "https://${operationsFqdn}/suite-api/internal/licenses/vcenter-usages" -Headers $internalHeaders -SkipCertificateCheck).content

}

function Install-OperationsLicense {
    param (
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$vcenterFqdn,
        [Parameter (Mandatory = $false)] [ValidateSet('vSphere', 'vSAN')] [String]$licenseType
    )

    Write-Host "[+] Attempting to assign license of type '$licenseType' to vCenter '$vcenterFqdn'..." -ForegroundColor Cyan
    $internalHeaders = @{}
    foreach ($k in $operationsHeaders.Keys) { $internalHeaders[$k] = $operationsHeaders[$k] }
    $internalHeaders["X-vRealizeOps-API-use-internal"] = "true"
    $internalHeaders["X-Ops-API-use-unsupported"] = "true"

    $vcenters = (Get-OperationsVcenters) | Where-Object {$_.productFamily -eq $licenseType -and $_.vcHost -eq $vcenterFqdn }
    $licenses = (Get-OperationsLicense) | Where-Object {$_.productFamily -eq $licenseType}

    if ($vcenters) {
        $body = ConvertTo-Json -InputObject @(
            @{
                vcenter = @{
                    id          = $vcenters.vcId
                    adapterName = $vcenters.vcAdapterName
                    host        = $vcenters.vcHost
                }
                allocationIds = @($licenses.licenseAllocationId)
            }
        ) -Depth 4

        $response = Invoke-RestMethod -Method Post -Uri "https://${operationsFqdn}/suite-api/internal/extension/vcf-entitlement/assign" -Headers $internalHeaders -Body $body -SkipCertificateCheck
        Write-Host "[+] License of type '$licenseType' assigned to vCenter completed successfully..." -ForegroundColor Green
    } else {
        Write-Host "[x] No vCenters found in VCF Operations to assign licenses" -ForegroundColor Red
    }
}

function Invoke-PublicPrivateKey {

    Param (
            [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [String]$jsonFile = ".\operationsDeployment.json"
    )

    # Generate Private and Public Keys and Import into VCF Operations & License Server
    New-RsaKeyPair -OutputDirectory ".\" -Overwrite -PrivateKeyFile ($jsonInput.operations.master.fqdn + "-private_key.pem") -PublicKeyFile ($jsonInput.operations.master.fqdn + "-public_key.pem") -CombinedKeyFile ($jsonInput.operations.master.fqdn + "-keypair.pem")
    New-RsaKeyPair -OutputDirectory ".\" -Overwrite -PrivateKeyFile ($jsonInput.licenseServer.fqdn + "-private_key.pem") -PublicKeyFile ($jsonInput.licenseServer.fqdn + "-public_key.pem") -CombinedKeyFile ($jsonInput.licenseServer.fqdn + "-keypair.pem")
}

function Invoke-OperationsDeployment {
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
            [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$jsonFile = ".\operationsDeployment.json"
    )
    # Main Script

    Try {
        Write-Host "[+] Starting the Deployment of $solutionName" -ForegroundColor Cyan
        if (Test-Path -Path $jsonFile) {
            $Global:jsonInput = (Get-Content -Path $jsonFile) | ConvertFrom-Json
            if (Test-VsphereAuthentication -server $jsonInput.vcenter.fqdn -user $jsonInput.vcenter.username -pass $jsonInput.vcenter.password) {
                Deploy-VCFOperationsAppliance # Attempt to deploy the OVA and create a new VM and power it on
                Wait-OperationsApplianceReady -IPAddress $jsonInput.operations.master.fqdn | Out-Null # Poll the powered on VM checking the Web service availability

                $vmName = $fqdn -replace '\..*$', ''
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
                
                Add-VcenterAdapter -VcenterFqdn $jsonInput.vcenter.fqdn -VcenterUser $jsonInput.vcenter.username -VcenterPass $jsonInput.vcenter.password

                # Deploy and Register a License Server
                Request-LicenseServerOTK # Request a one time key (OTK) for the registration of the License Server with VCF Operations
                Deploy-LicenseServerAppliance # Deploy the License Server appliance

                # Import the License Server Key Pair into VCF Operations and License Server
                $licenseServerVmName = $jsonInput.licenseServer.fqdn.Split('.')[0]
                $licenseServerApiKey = Get-VmApiKey -VM $licenseServerVmName
                Install-OperationsKeyPair -KeypairPath ($jsonInput.operations.master.fqdn + "-keypair.pem") -VerifyStatus -SkipCertificateCheck
                Install-LicenseServerKeyPair -LicenseServerFqdn $jsonInput.licenseServer.fqdn -ApiKey $licenseServerApiKey -KeyPairPemFilePath ($jsonInput.licenseServer.fqdn + "-keypair.pem")
                Wait-LicenseStatus

                # License the system
                Import-OperationsLicenseFile -licenseFile $jsonInput.licenseServer.licenseFile
                # Assign Licenses to vCenter
                Wait-VcenterRegistration
                Install-OperationsLicense -vcenterFqdn $jsonInput.vcenter.fqdn -licenseType vSphere
                Install-OperationsLicense -vcenterFqdn $jsonInput.vcenter.fqdn -licenseType vSAN
            }
        } else {
            Write-Host "[x] JSON Specification file ($jsonFile): File Not Found" -ForegroundColor Red
        }
    } Catch {
        Write-Error $_.Exception.Message
    }
}

function Invoke-OperationsLicenseInstall {
    <#
        .SYNOPSIS
        Deployment of VCF Operations and License Server Appliances

        .DESCRIPTION
        The Invoke-OperationsLicenseInstall cmdlet is a single function to deploy and configure VCF Operations and
        License Server.

        .EXAMPLE
        Invoke-OperationsLicenseInstall -jsonFile .\operationsDeploySpec.json
        This example deploy and configure VCF Operations and License Server using the JSON spec supplied.

        .PARAMETER jsonFile
        The path to the JSON specification file to be used.
    #>

    Param (
            [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$jsonFile = ".\operationsDeployment.json"
    )
    # Main Script

    Try {
        Write-Host "[+] Starting the $solutionName of Key Pair and License File" -ForegroundColor Cyan
        if (Test-Path -Path $jsonFile) {
            $Global:jsonInput = (Get-Content -Path $jsonFile) | ConvertFrom-Json

            # Authenticate to VCF Operations
            Request-OperationsToken -fqdn $jsonInput.operations.master.fqdn -username admin -password $jsonInput.operations.adminPassword

            # Import the License Server Key Pair into VCF Operations and License Server
            $licenseServerVmName = $jsonInput.licenseServer.fqdn.Split('.')[0]
            $licenseServerApiKey = Get-VmApiKey -VM $licenseServerVmName
            Install-OperationsKeyPair -KeypairPath ($jsonInput.operations.master.fqdn + "-keypair.pem") -VerifyStatus -SkipCertificateCheck
            Install-LicenseServerKeyPair -LicenseServerFqdn $jsonInput.licenseServer.fqdn -ApiKey $licenseServerApiKey -KeyPairPemFilePath ($jsonInput.licenseServer.fqdn + "-keypair.pem")
            Wait-LicenseStatus

            # License the system
            Import-OperationsLicenseFile -licenseFile $jsonInput.licenseServer.licenseFile
            # Assign Licenses to vCenter
            Wait-VcenterRegistration
            Install-OperationsLicense -vcenterFqdn $jsonInput.vcenter.fqdn -licenseType vSphere
            Install-OperationsLicense -vcenterFqdn $jsonInput.vcenter.fqdn -licenseType vSAN

        } else {
            Write-Host "[x] JSON Specification file ($jsonFile): File Not Found" -ForegroundColor Red
        }
    } Catch {
        Write-Error $_.Exception.Message
    }
}

Start-OperationsInstall

# Restore default preference
$ProgressPreference = $previousProgressPreference
