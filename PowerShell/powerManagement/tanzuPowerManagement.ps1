<#
    .NOTES
    ===================================================================================================================
    Created by:		Gary Blake
    Date:			06/10/2022
    Organization:	VMware
    Blog:           my-cloudy-world.com
    Twitter:        @GaryJBlake
    ===================================================================================================================

    .SYNOPSIS
    Connects to the specified SDDC Manager and shutdowns/starts up a Tanzu Workload Domain

    .DESCRIPTION
    This script connects to the specified SDDC Manager and either shutdowns or startups a Tanzu Workload Domain

    .EXAMPLE
    .\tanzuPowerManagement.ps1 -server ldn-vcf01.cloudy.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain ldn-w01 -powerState Shutdown
    Initiates a shutdown of the Tanzu Workload Domain 'sfo-w01'

    .EXAMPLE
    .\tanzuPowerManagement.ps1 -server ldn-vcf01.cloudy.io -user administrator@vsphere.local -pass VMw@re1! -sddcDomain ldn-w01 -powerState Startup
    Initiates the startup of the Tanzu Workload Domain 'sfo-w01'
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcDomain,
    [Parameter (Mandatory = $true)] [ValidateSet("Shutdown", "Startup")] [String]$powerState
)


Function Set-VamiServiceStatus {
<#
    .SYNOPSIS
    Starts/Stops the service on a given vCenter Server
        
    .DESCRIPTION
    The Set-VamiServiceStatus cmdlet starts or stops the service on a given vCenter Server.
        
    .EXAMPLE
    Set-VAMIServiceStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re1! -service wcp -action STOP
    This example connects to a vCenter Server and attempts to STOP the wcp service

    .EXAMPLE
    Set-VAMIServiceStatus -server sfo-m01-vc01.sfo.rainpole.io -user administrator@vsphere.local  -pass VMw@re1! -service wcp -action START
    This example connects to a vCenter Server and attempts to START the wcp service
#>
    
    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateSet("analytics", "applmgmt", "certificateauthority", "certificatemanagement", "cis-license", "content-library", "eam", "envoy", "hvc", "imagebuilder", "infraprofile", "lookupsvc", "netdumper", "observability-vapi", "perfcharts", "pschealth", "rbd", "rhttpproxy", "sca", "sps", "statsmonitor", "sts", "topologysvc", "trustmanagement", "updatemgr", "vapi-endpoint", "vcha", "vlcm", "vmcam", "vmonapi", "vmware-postgres-archiver", "vmware-vpostgres", "vpxd", "vpxd-svcs", "vsan-health", "vsm", "vsphere-ui", "vstats", "vtsdb", "wcp")] [String]$service,
        [Parameter (Mandatory = $true)] [ValidateSet("START", "STOP")] [String]$action
    )

    Try {
        Write-LogMessage -Type INFO -Message "Starting run of Set-VAMIServiceStatus cmdlet" -Colour Yellow
        if ((Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded) {
            Write-LogMessage -Type INFO -Message "Connecting to '$server' ..."
            if ($action -eq "START") { $requestedState = "STARTED" } elseif ($action -eq "STOP") { $requestedState = "STOPPED" }
            if ($DefaultCisServers) {
                Disconnect-CisServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            Connect-CisServer -Server $server -User $user -Password $pass -ErrorAction SilentlyContinue | Out-Null
            if ($DefaultCisServers.Name -eq $server) {
                $vMonAPI = Get-CisService 'com.vmware.appliance.vmon.service'
                $serviceStatus = $vMonAPI.Get($service, 0)                
                if ($serviceStatus.state -match $requestedState) {
                    Write-LogMessage -Type INFO -Message "The service $service is already set to '$requestedState'" -Colour Green
                }
                else {
                    if ($action -eq "START") {
                        Write-LogMessage -Type INFO -Message "Attempting to START the '$service' service"
                        $vMonAPI.start($service)
                    }
                    elseif ($action -eq "STOP") {
                        Write-LogMessage -Type INFO -Message "Attempting to STOP the '$service' service"
                        $vMonAPI.stop($service)
                    }
                    Do {
                        $serviceStatus = $vMonAPI.Get($service, 0)
                    } Until ($serviceStatus -match $requestedState)
                    if ($serviceStatus.state -match $requestedState) {
                        Write-LogMessage -Type INFO -Message "Service '$service' has been '$requestedState' Successfully" -Colour Green
                    }
                    else {
                        Write-LogMessage -Type ERROR -Message "Service '$service' has NOT been '$requestedState'. Actual status: $($serviceStatus.state)" -Colour Red
                    }
                }
                # Write-PowerManagementLogMessage -Type INFO -Message "Disconnecting from server '$server'"
                Disconnect-CisServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            }
            else {
                Write-LogMessage -Type ERROR -Message  "Unable to connect to server $server, Please check and retry." -Colour Red
            }
        }
        else {
            Write-LogMessage -Type ERROR -Message  "Testing a connection to server $server failed, please check your details and try again" -Colour Red
        }
        Write-LogMessage -Type INFO -Message "Finishing run of Get-VAMIServiceStatus cmdlet" -Colour Yellow
    } 
    Catch {
        Debug-CatchWriterForPowerManagement -object $_
    }
}

Clear-Host; Write-Host ""

Start-SetupLogFile -Path $filePath -ScriptName $MyInvocation.MyCommand.Name
Write-LogMessage -Type INFO -Message "Starting the Process of Automating the Power Management of Tanzu Running on Workload Domain '$sddcDomain' ($powerState Requested)" -Colour Yellow
Write-LogMessage -Type INFO -Message "Setting up the log file to path $logfile"

Try {
    Write-LogMessage -Type INFO -Message "Attempting to Validate Communication with SDDC Manager ($server):"
    if (!(Test-NetConnection -ComputerName $server -Port 443).TcpTestSucceeded) {
        Write-LogMessage -Type ERROR "Validate Communication with SDDC Manager ($server), check fqdn/ip address: FAILED"
        Exit
    }
    else {
        Write-LogMessage -Type INFO -Message "Validate communication with SDDC Manager ($server): SUCCESSFUL" -Colour Green
        Write-LogMessage -Type INFO -Message "Attempting to Connect to SDDC Manager ($server) to Gather System Details"
        $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
        if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message $StatusMsg } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red; Exit }
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Gather details from SDDC Manager
Try {
    # Write-LogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to Gather System Details"
    # $StatusMsg = Request-VCFToken -fqdn $server -username $user -password $pass -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
    # if ( $StatusMsg ) { Write-PowerManagementLogMessage -Type INFO -Message $StatusMsg } if ( $WarnMsg ) { Write-PowerManagementLogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-PowerManagementLogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
    if ($accessToken) {
        Write-LogMessage -Type INFO -Message "Gathering System Details from SDDC Manager Inventory"
        # Gather Details from SDDC Manager
        $workloadDomain = Get-VCFWorkloadDomain | Where-Object { $_.Name -eq $sddcDomain }
        $cluster = Get-VCFCluster | Where-Object { $_.id -eq ($workloadDomain.clusters.id) }

        # Gather vCenter Server Details and Credentials
        $vcServer = (Get-VCFvCenter | Where-Object { $_.domain.id -eq ($workloadDomain.id) })
        $vcUser = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).username
        $vcPass = (Get-VCFCredential | Where-Object { $_.accountType -eq "SYSTEM" -and $_.credentialType -eq "SSO" }).password

        # Gather ESXi Host Details for the Tanzu Domain
        $esxiWorkloadDomain = @()
        foreach ($esxiHost in (Get-VCFHost | Where-Object { $_.domain.id -eq $workloadDomain.id }).fqdn) {
            $esxDetails = New-Object -TypeName PSCustomObject
            $esxDetails | Add-Member -Type NoteProperty -Name fqdn -Value $esxiHost
            $esxDetails | Add-Member -Type NoteProperty -Name username -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER" })).username
            $esxDetails | Add-Member -Type NoteProperty -Name password -Value (Get-VCFCredential | Where-Object ({ $_.resource.resourceName -eq $esxiHost -and $_.accountType -eq "USER" })).password 
            $esxiWorkloadDomain += $esxDetails
        } 
    }
    else {
        Write-LogMessage -Type ERROR -Message "Unable to obtain access token from SDDC Manager ($server), check credentials" -Colour Red
        Exit
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Shutdown procedures
Try {
    if ($powerState -eq "Shutdown") {
        # Change the DRS Automation Level to Partially Automated for the VI Workload Domain Clusters
        Write-LogMessage -Type INFO -Message "Attempting to Change the DRS Automation Level to Partially Automated for the Workload Domain Cluster '$($cluster.name)'"
        Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level PartiallyAutomated

        # Stop the WCP service
        Write-LogMessage -Type INFO -Message "Attempting to Stop the WCP Service on vCenter Server '$($vcServer.fqdn)'"
        Set-VamiServiceStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -service wcp -action STOP

        # Stop the Supervisor Control Plane Virtual Machines
        Write-LogMessage -Type INFO -Message "Attempting to Stop the Supervisor Control Plane Virtual Machines"
        $clusterPattern = "^SupervisorControlPlaneVM.*"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 300
        }

        # Stop the Tanzu Cluster Virtual Machines
        $clusterPattern = "^.*-tkc01-.*"
        Write-LogMessage -Type INFO -Message "Attempting to Stop the Tanzu Cluster Virtual Machines (Using Pattern '$clusterPattern')"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 300
        }

        # Stop the Harbour Registry Virtual Machines
        $clusterPattern = "^harbor.*"
        Write-LogMessage -Type INFO -Message "Attempting to Stop the Harbour Registry Virtual Machines (Using Pattern '$clusterPattern')"
        foreach ($esxiNode in $esxiWorkloadDomain) {
            Stop-CloudComponent -server $esxiNode.fqdn -pattern $clusterPattern -user $esxiNode.username -pass $esxiNode.password -timeout 300 -noWait
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}

# Startup procedures
Try {
    if ($powerState -eq "Startup") {
        # Startup the vSphere with Tanzu Virtual Machines
        Write-LogMessage -Type INFO -Message "Attempting to Start the the WCP Service on vCenter Server '$($vcServer.fqdn)'"
        Set-VamiServiceStatus -server $vcServer.fqdn -user $vcUser -pass $vcPass -service wcp -action START
        Write-LogMessage -Type INFO -Message "Workload Management will be started automatically by the WCP service, this will take some time"

        # Change the DRS Automation Level to Fully Automated for the VI Workload Domain Clusters
        Write-LogMessage -Type INFO -Message "Attempting to Change the DRS Automation Level to Fully Automated for the Workload Domain Cluster '$($cluster.name)'"
        Set-DrsAutomationLevel -server $vcServer.fqdn -user $vcUser -pass $vcPass -cluster $cluster.name -level FullyAutomated
    }
}
Catch {
    Debug-CatchWriter -object $_
}