<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Blog:          http:/my-cloudy-world.com
    .Twitter:       @GaryJBlake
    .Version:       1.0 (Build 002)
    .Date:          2020-12-12
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.001 (Gary Blake / 2020-12-11) - Initial script creation
    - 1.0.002 (Gary Blake / 2020-12-12) - Updated all variables to be obtained from management domain spec

    ===============================================================================================================
    .DESCRIPTION
    This scripts executes a number of steps in order to perform the reconfiguration of ESXi Hosts that have a
    single active vmnic. It uses the managementDomain.json as the input and then performs the following steps:
    - Migrates the vCenter from vDS to vSS Portgroup
    - Configures the Advanced Setting in vCenter Server to Network Rollback
    - Reboots the vCenter Server
    - Migrates the First ESXi Host vmk0 and vmnic to the vDS from vSS
    - Migrates the vCenter Server from vSS to vDS Portgroup
    - Migrates the vmk0 and vmnic to the vDS from vSS for the remaining ESXi Hosts

    .EXAMPLE
    .\configureVcfSingleVmnic.ps1 -json managementDomain.json
#>

Param (
    [Parameter(mandatory=$true)]
        [String]$json
)

Clear-Host

$jsonPath = $PSScriptRoot+"\"+$json
Write-LogMessage  -Message "Reading the Management Domain JSON Spec" -Colour Yellow
$Global:cbJson = (Get-Content -Raw $jsonPath) | ConvertFrom-Json

$esxiHostUser = $cbJson.hostSpecs.credentials.username[0]
$esxiHostPassword = $cbJson.hostSpecs.credentials.password[0]
$esxiHost0 = $cbJson.hostSpecs.hostname[0]+"."+$cbJson.dnsSpec.subdomain
$esxiHost1 = $cbJson.hostSpecs.hostname[1]+"."+$cbJson.dnsSpec.subdomain
$esxiHost2 = $cbJson.hostSpecs.hostname[2]+"."+$cbJson.dnsSpec.subdomain
$esxiHost3 = $cbJson.hostSpecs.hostname[3]+"."+$cbJson.dnsSpec.subdomain

$vCenterFqdn = $cbJson.vcenterSpec.vcenterHostname+'.'+$cbJson.dnsSpec.subdomain
$vCenterAdminUser = "administrator@vsphere.local"
$vCenterAdminPassword = $cbJson.pscSpecs.adminUserSsoPassword
$vmName = $cbJson.vcenterSpec.vcenterHostname
$portgroup1 = $cbJson.networkSpecs.portGroupKey[0]
$portgroup2 = "VM Network"

Function checkPowershellModules
{
    Try {
        Write-LogMessage -Message "Importing Posh-SSH Module"
        Import-Module -Name Posh-SSH -warningaction silentlycontinue | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Write-LogMessage -Message "POSH-SSH Module not found. Installing"
        Install-PackageProvider NuGet -Force | Out-File $logFile -Encoding ASCII -Append
        Set-PSRepository PSGallery -InstallationPolicy Trusted | Out-File $logFile -Encoding ASCII -Append
        if (([System.Environment]::OSVersion.Version.Build) -ge "17763") {
            $getPackageManagementModule =  Get-InstalledModule -name PackageManagement -erroraction SilentlyContinue
            if (!$getPackageManagementModule) {
                Write-LogMessage -Message "In order to install the correct version of POSH-SSH, PackageManagement and PowerShellGet need to be installed first" -colour Yellow
                Write-LogMessage -Message "Installing PackageManagement"
                Install-Module -Name PackageManagement -Repository PSGallery -Force | Out-File $logFile -Encoding ASCII -Append
                Write-LogMessage -Message "Installing PowerShellGet"
                Install-Module -Name PowerShellGet -Repository PSGallery -Force | Out-File $logFile -Encoding ASCII -Append
                Write-LogMessage -Message "Installing PowerShellGet requires that you close this powershell session and open a new one. This will only happen once." -colour Yellow
                Exit    
            }
            Install-Module -Name Posh-SSH -AllowPrerelease | Out-File $logFile -Encoding ASCII -Append
        }
        else {
            Install-Module -Name Posh-SSH -maximumversion 2.2 | Out-File $logFile -Encoding ASCII -Append
        }
    }

    Write-LogMessage -Message "Importing PowerCLI Modules"
    Try {
        Import-Module -Name VMware.VimAutomation.Common | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Install-Module -Name VMware.VimAutomation.Common -confirm:$false | Out-File $logFile -Encoding ASCII -Append
    }
    Try {
        Import-Module -Name VMware.VimAutomation.Core | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Install-Module -Name VMware.VimAutomation.Core -confirm:$false | Out-File $logFile -Encoding ASCII -Append
    }
    Try {
        Import-Module -Name VMware.VimAutomation.License | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Install-Module -Name VMware.VimAutomation.License -confirm:$false | Out-File $logFile -Encoding ASCII -Append
    }
    Try {
        Import-Module -Name VMware.VimAutomation.Nsxt | Out-File $logFile -Encoding ASCII -Append    
    }
    Catch {
        Install-Module -Name VMware.VimAutomation.Nsxt -confirm:$false | Out-File $logFile -Encoding ASCII -Append
    }
    Try {
        Import-Module -Name VMware.VimAutomation.Storage | Out-File $logFile -Encoding ASCII -Append    
    }
    Catch {
        Install-Module -Name VMware.VimAutomation.Storage -confirm:$false | Out-File $logFile -Encoding ASCII -Append
    }
    Try {
        Import-Module -Name VMware.VimAutomation.Vds | Out-File $logFile -Encoding ASCII -Append   
    }
    Catch {
        Install-Module -Name VMware.VimAutomation.Vds -confirm:$false | Out-File $logFile -Encoding ASCII -Append
    }

    Try
    {
        LogMessage -message "Checking for PowerVCF Module"
        $powerVcf = Get-InstalledModule -Name PowerVCF -ErrorAction SilentlyContinue
        if ($powerVcf.Version -eq "2.1.0") {
            LogMessage -message "PowerVCF Found"
        }
        else {
            LogMessage -message "PowerVCF Module not found. Installing."
            Install-PackageProvider NuGet -Force | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null
            Set-PSRepository PSGallery -InstallationPolicy Trusted | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null
            Install-Module PowerVCF -MinimumVersion 2.1.0 -Force -confirm:$false | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null   
        }
    }
    Catch
    {
        catchwriter -object $_
    }

    Write-LogMessage -Message "Configuring PowerShell CEIP Setting"
    $setCLIConfigurationCEIP = Set-PowerCLIConfiguration -Scope AllUsers -ParticipateInCEIP $false -Confirm:$false -warningaction SilentlyContinue -InformationAction SilentlyContinue 2>&1 | Out-File $logFile -Encoding ASCII -Append
    Write-LogMessage -Message "Configuring PowerShell Certifcate Setting"
    $setCLIConfigurationCerts = Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$False -Scope AllUsers -warningaction SilentlyContinue -InformationAction SilentlyContinue 2>&1 | Out-File $logFile -Encoding ASCII -Append
    Write-LogMessage -Message "Permitting Multiple Default VI Servers"
    $setCLIConfigurationVIServers = Set-PowerCLIConfiguration -DefaultVIServerMode multiple -Confirm:$false -Scope AllUsers -warningaction SilentlyContinue -InformationAction SilentlyContinue 2>&1 | Out-File $logFile -Encoding ASCII -Append
}

Start-SetupLogFile -Path $PSScriptRoot -ScriptName "configureSingleVmnic" # Create new log

Function Set-UpdatePortgroup {
    Param (
        [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$vmName,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$oldPortgroup,
        [Parameter (Mandatory=$false)]
            [ValidateNotNullOrEmpty()]
            [string]$newPortgroup
    )

    Get-VM -Name $vmName | Get-NetworkAdapter | Where {$_.NetworkName -eq $oldPortgroup} | Set-NetworkAdapter -Portgroup $newPortgroup -Confirm:$False
}

Function vCenterVss {
    Try {
        # Reconfigure vCenter Server Port Group from vSphere Distributed Switch back to vSphere Stadnard Switch
        Write-LogMessage -Message "Connecting to ESXi Server $esxiHost"
        Connect-VIServer -Server $esxiHost -User $esxiHostUser -Password $esxiHostPassword | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Reconfigure vCenter Serer $vCenterFqdn Port Group from $portgroup1 to $portgroup2"
        Set-UpdatePortgroup -vmName $vmName -oldPortgroup $portgroup1 -newPortgroup $portgroup2 | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Disconnecting from ESXi Server $esxiHost"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function rollbackFalse {
    Try {
        Write-LogMessage -Message "Connecting to vCenter Server $vCenterFqdn"
        Connect-VIServer -Server $vCenterFqdn -User $vCenterAdminUser -Password $vCenterAdminPassword | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Setting vCenter Server $vCenterFqdn Advanced Setting"
        Get-AdvancedSetting -Entity $vCenterFqdn -Name config.vpxd.network.rollback | Set-AdvancedSetting -Value 'false' -Confirm:$false | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Disconnecting from vCenter Server $vCenterFqdn"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function vcenterReboot {
    Try {
        Write-LogMessage -Message "Connecting to vCenter Server $vCenterFqdn to Reboot"
        Connect-CisServer -Server $vCenterFqdn -User $vCenterAdminUser -Password $vCenterAdminPassword | Out-Null
        $vamiShudownApi = Get-CisService -Server $vCenterFqdn -Name "com.vmware.appliance.shutdown"
        $vamiShudownApi.reboot(1,'Change Advanced Setting: config.vpxd.network.rollback')

        Write-LogMessage -Message "Waiting for $vCenterFqdn to go down after after reboot"
        do{}Until (!(Test-Connection -computername $vCenterFqdn -Quiet -Count 1))
        Write-LogMessage -Message "IP connectivity to $vCenterFqdn lost (expected)"

        #Monitor for vCenter backup
        Write-LogMessage -Message "Waiting for $vCenterFqdn to come back up after reboot"
        do{}Until (Test-Connection -computername $vCenterFqdn -Quiet -Count 1)
        Write-LogMessage -Message "IP connectivity to $vCenterFqdn established"

        #Keep attempting to connect to vCenter until its it responds correctly (services may not be started first time)
        Write-LogMessage -Message "Waiting for vCenter services to start on $vCenterFqdn (may take some time)"
        Do {}Until (Connect-VIServer -Server $vCenterFqdn -User $vCenterAdminUser -Pass $vCenterAdminPassword -ErrorAction SilentlyContinue)
        Write-LogMessage -Message "PowerCLI connection to $vCenterFqdn established"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-Null
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function migrateNetworking {
    Try {
        Write-LogMessage -Message "Connecting to vCenter Server $vCenterFqdn"
        Connect-VIServer -Server $vCenterFqdn -User $vCenterAdminUser -Password $vCenterAdminPassword | Out-File $logFile -Encoding ASCII -Append
        
        $vds = Get-View -ViewType DistributedVirtualSwitch
        $dvsId = $vds.MoRef.Type+"-"+$vds.MoRef.Value
        $dvsPortgroup = Get-View -ViewType DistributedVirtualPortgroup -Filter @{"Name"="DVUplinks"}
        $mgmtPortgroup = Get-View -ViewType DistributedVirtualPortgroup -Filter @{"Name"=$portgroup1}
        
        #---------------QueryAvailableDvsSpec---------------
        $recommended = $true
        $_this = Get-View -Id 'DistributedVirtualSwitchManager-DVSManager'
        $_this.QueryAvailableDvsSpec($recommended) | Out-File $logFile -Encoding ASCII -Append

        #---------------FetchDVPorts---------------
        
        $criteria = New-Object VMware.Vim.DistributedVirtualSwitchPortCriteria
        $criteria.UplinkPort = $true
        $_this = Get-View -Id $dvsId
        $_this.FetchDVPorts($criteria) | Out-File $logFile -Encoding ASCII -Append

        #---------------UpdateNetworkConfig---------------
        $hostDetail0 = Get-View -ViewType HostSystem -Filter @{"Name"=$esxiHost0}
        $hostId0 = 'HostNetworkSystem-networkSystem-'+$hostDetail0.MoRef.Value.Split("-")[1]

        $config = New-Object VMware.Vim.HostNetworkConfig
        $config.Vswitch = New-Object VMware.Vim.HostVirtualSwitchConfig[] (1)
        $config.Vswitch[0] = New-Object VMware.Vim.HostVirtualSwitchConfig
        $config.Vswitch[0].Name = 'vSwitch0'
        $config.Vswitch[0].ChangeOperation = 'edit'
        $config.Vswitch[0].Spec = New-Object VMware.Vim.HostVirtualSwitchSpec
        $config.Vswitch[0].Spec.NumPorts = 128
        $config.Vswitch[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vswitch[0].Spec.Policy.Security = New-Object VMware.Vim.HostNetworkSecurityPolicy
        $config.Vswitch[0].Spec.Policy.Security.AllowPromiscuous = $false
        $config.Vswitch[0].Spec.Policy.Security.ForgedTransmits = $false
        $config.Vswitch[0].Spec.Policy.Security.MacChanges = $false
        $config.Vswitch[0].Spec.Policy.OffloadPolicy = New-Object VMware.Vim.HostNetOffloadCapabilities
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.TcpSegmentation = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.ZeroCopyXmit = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.CsumOffload = $true
        $config.Vswitch[0].Spec.Policy.ShapingPolicy = New-Object VMware.Vim.HostNetworkTrafficShapingPolicy
        $config.Vswitch[0].Spec.Policy.ShapingPolicy.Enabled = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming = New-Object VMware.Vim.HostNicTeamingPolicy
        $config.Vswitch[0].Spec.Policy.NicTeaming.NotifySwitches = $true
        $config.Vswitch[0].Spec.Policy.NicTeaming.RollingOrder = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria = New-Object VMware.Vim.HostNicFailureCriteria
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.FullDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Percentage = 0
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckErrorPercent = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckBeacon = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Speed = 10
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckSpeed = 'minimum'
        $config.Vswitch[0].Spec.Policy.NicTeaming.Policy = 'loadbalance_srcid'
        $config.Vswitch[0].Spec.Policy.NicTeaming.ReversePolicy = $true
        $config.Portgroup = New-Object VMware.Vim.HostPortGroupConfig[] (1)
        $config.Portgroup[0] = New-Object VMware.Vim.HostPortGroupConfig
        $config.Portgroup[0].ChangeOperation = 'remove'
        $config.Portgroup[0].Spec = New-Object VMware.Vim.HostPortGroupSpec
        $config.Portgroup[0].Spec.VswitchName = ''
        $config.Portgroup[0].Spec.VlanId = -1
        $config.Portgroup[0].Spec.Name = 'Management Network'
        $config.Portgroup[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vnic = New-Object VMware.Vim.HostVirtualNicConfig[] (1)
        $config.Vnic[0] = New-Object VMware.Vim.HostVirtualNicConfig
        $config.Vnic[0].Portgroup = ''
        $config.Vnic[0].Device = 'vmk0'
        $config.Vnic[0].ChangeOperation = 'edit'
        $config.Vnic[0].Spec = New-Object VMware.Vim.HostVirtualNicSpec
        $config.Vnic[0].Spec.DistributedVirtualPort = New-Object VMware.Vim.DistributedVirtualSwitchPortConnection
        $config.Vnic[0].Spec.DistributedVirtualPort.SwitchUuid =  $vds.Uuid
        $config.Vnic[0].Spec.DistributedVirtualPort.PortgroupKey = $mgmtPortgroup.Key
        $config.ProxySwitch = New-Object VMware.Vim.HostProxySwitchConfig[] (1)
        $config.ProxySwitch[0] = New-Object VMware.Vim.HostProxySwitchConfig
        $config.ProxySwitch[0].Uuid =  $vds.Uuid
        $config.ProxySwitch[0].ChangeOperation = 'edit'
        $config.ProxySwitch[0].Spec = New-Object VMware.Vim.HostProxySwitchSpec
        $config.ProxySwitch[0].Spec.Backing = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicBacking
        $config.ProxySwitch[0].Spec.Backing.PnicSpec = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec[] (1)
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].PnicDevice = 'vmnic0'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortKey = '16'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortgroupKey = $dvsPortgroup.Key
        $changeMode = 'modify'
        
        $_this = Get-View -Id $hostId0
        Write-LogMessage -Message "Migrating Network Configuration for $esxiHost0"
        $_this.UpdateNetworkConfig($config, $changeMode) | Out-File $logFile -Encoding ASCII -Append

        Write-LogMessage -Message "Disconnecting from vCenter Server $vCenterFqdn"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function vCenterVds {
    Try {
        # Reconfigure vCenter Server Port Group from vSphere Distributed Switch back to vSphere Stadnard Switch
        Write-LogMessage -Message "Connecting to ESXi Server $esxiHost"
        Connect-VIServer -Server $esxiHost -User $esxiHostUser -Password $esxiHostPassword | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Reconfigure vCenter Serer $vCenterFqdn Port Group from $portgroup2 to $portgroup1"
        Set-UpdatePortgroup -vmName $vmName -oldPortgroup $portgroup2 -newPortgroup $portgroup1 | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Disconnecting from ESXi Server $esxiHost"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function migrateAllHosts {
    Try {
        Write-LogMessage -Message "Connecting to vCenter Server $vCenterFqdn"
        Connect-VIServer -Server $vCenterFqdn -User $vCenterAdminUser -Password $vCenterAdminPassword | Out-File $logFile -Encoding ASCII -Append
        
        $vds = Get-View -ViewType DistributedVirtualSwitch
        $dvsId = $vds.MoRef.Type+"-"+$vds.MoRef.Value
        $dvsPortgroup = Get-View -ViewType DistributedVirtualPortgroup -Filter @{"Name"="DVUplinks"}
        $mgmtPortgroup = Get-View -ViewType DistributedVirtualPortgroup -Filter @{"Name"=$portgroup1}
        
        
        #---------------QueryAvailableDvsSpec---------------
        $recommended = $true
        $_this = Get-View -Id 'DistributedVirtualSwitchManager-DVSManager'
        $_this.QueryAvailableDvsSpec($recommended) | Out-File $logFile -Encoding ASCII -Append

        #---------------FetchDVPorts---------------
        
        $criteria = New-Object VMware.Vim.DistributedVirtualSwitchPortCriteria
        $criteria.UplinkPort = $true
        $_this = Get-View -Id $dvsId
        $_this.FetchDVPorts($criteria) | Out-File $logFile -Encoding ASCII -Append

        #---------------UpdateNetworkConfig---------------
        $hostDetail1 = Get-View -ViewType HostSystem -Filter @{"Name"=$esxiHost1}
        $hostId1 = 'HostNetworkSystem-networkSystem-'+$hostDetail1.MoRef.Value.Split("-")[1]

        $config = New-Object VMware.Vim.HostNetworkConfig
        $config.Vswitch = New-Object VMware.Vim.HostVirtualSwitchConfig[] (1)
        $config.Vswitch[0] = New-Object VMware.Vim.HostVirtualSwitchConfig
        $config.Vswitch[0].Name = 'vSwitch0'
        $config.Vswitch[0].ChangeOperation = 'edit'
        $config.Vswitch[0].Spec = New-Object VMware.Vim.HostVirtualSwitchSpec
        $config.Vswitch[0].Spec.NumPorts = 128
        $config.Vswitch[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vswitch[0].Spec.Policy.Security = New-Object VMware.Vim.HostNetworkSecurityPolicy
        $config.Vswitch[0].Spec.Policy.Security.AllowPromiscuous = $false
        $config.Vswitch[0].Spec.Policy.Security.ForgedTransmits = $false
        $config.Vswitch[0].Spec.Policy.Security.MacChanges = $false
        $config.Vswitch[0].Spec.Policy.OffloadPolicy = New-Object VMware.Vim.HostNetOffloadCapabilities
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.TcpSegmentation = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.ZeroCopyXmit = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.CsumOffload = $true
        $config.Vswitch[0].Spec.Policy.ShapingPolicy = New-Object VMware.Vim.HostNetworkTrafficShapingPolicy
        $config.Vswitch[0].Spec.Policy.ShapingPolicy.Enabled = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming = New-Object VMware.Vim.HostNicTeamingPolicy
        $config.Vswitch[0].Spec.Policy.NicTeaming.NotifySwitches = $true
        $config.Vswitch[0].Spec.Policy.NicTeaming.RollingOrder = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria = New-Object VMware.Vim.HostNicFailureCriteria
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.FullDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Percentage = 0
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckErrorPercent = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckBeacon = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Speed = 10
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckSpeed = 'minimum'
        $config.Vswitch[0].Spec.Policy.NicTeaming.Policy = 'loadbalance_srcid'
        $config.Vswitch[0].Spec.Policy.NicTeaming.ReversePolicy = $true
        $config.Portgroup = New-Object VMware.Vim.HostPortGroupConfig[] (1)
        $config.Portgroup[0] = New-Object VMware.Vim.HostPortGroupConfig
        $config.Portgroup[0].ChangeOperation = 'remove'
        $config.Portgroup[0].Spec = New-Object VMware.Vim.HostPortGroupSpec
        $config.Portgroup[0].Spec.VswitchName = ''
        $config.Portgroup[0].Spec.VlanId = -1
        $config.Portgroup[0].Spec.Name = 'Management Network'
        $config.Portgroup[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vnic = New-Object VMware.Vim.HostVirtualNicConfig[] (1)
        $config.Vnic[0] = New-Object VMware.Vim.HostVirtualNicConfig
        $config.Vnic[0].Portgroup = ''
        $config.Vnic[0].Device = 'vmk0'
        $config.Vnic[0].ChangeOperation = 'edit'
        $config.Vnic[0].Spec = New-Object VMware.Vim.HostVirtualNicSpec
        $config.Vnic[0].Spec.DistributedVirtualPort = New-Object VMware.Vim.DistributedVirtualSwitchPortConnection
        $config.Vnic[0].Spec.DistributedVirtualPort.SwitchUuid =  $vds.Uuid
        $config.Vnic[0].Spec.DistributedVirtualPort.PortgroupKey = $mgmtPortgroup.Key
        $config.ProxySwitch = New-Object VMware.Vim.HostProxySwitchConfig[] (1)
        $config.ProxySwitch[0] = New-Object VMware.Vim.HostProxySwitchConfig
        $config.ProxySwitch[0].Uuid =  $vds.Uuid
        $config.ProxySwitch[0].ChangeOperation = 'edit'
        $config.ProxySwitch[0].Spec = New-Object VMware.Vim.HostProxySwitchSpec
        $config.ProxySwitch[0].Spec.Backing = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicBacking
        $config.ProxySwitch[0].Spec.Backing.PnicSpec = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec[] (2)
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].PnicDevice = 'vmnic2'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortKey = '19'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortgroupKey = $dvsPortgroup.Key
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].PnicDevice = 'vmnic0'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].UplinkPortKey = '18'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].UplinkPortgroupKey = $dvsPortgroup.Key
        $changeMode = 'modify'
        
        $_this = Get-View -Id $hostId1
        Write-LogMessage -Message "Migrating Network Configuration for $esxiHost1"
        $_this.UpdateNetworkConfig($config, $changeMode) | Out-File $logFile -Encoding ASCII -Append

        #---------------UpdateNetworkConfig---------------
        $hostDetail2 = Get-View -ViewType HostSystem -Filter @{"Name"=$esxiHost2}
        $hostId2 = 'HostNetworkSystem-networkSystem-'+$hostDetail2.MoRef.Value.Split("-")[1]

        $config = New-Object VMware.Vim.HostNetworkConfig
        $config.Vswitch = New-Object VMware.Vim.HostVirtualSwitchConfig[] (1)
        $config.Vswitch[0] = New-Object VMware.Vim.HostVirtualSwitchConfig
        $config.Vswitch[0].Name = 'vSwitch0'
        $config.Vswitch[0].ChangeOperation = 'edit'
        $config.Vswitch[0].Spec = New-Object VMware.Vim.HostVirtualSwitchSpec
        $config.Vswitch[0].Spec.NumPorts = 128
        $config.Vswitch[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vswitch[0].Spec.Policy.Security = New-Object VMware.Vim.HostNetworkSecurityPolicy
        $config.Vswitch[0].Spec.Policy.Security.AllowPromiscuous = $false
        $config.Vswitch[0].Spec.Policy.Security.ForgedTransmits = $false
        $config.Vswitch[0].Spec.Policy.Security.MacChanges = $false
        $config.Vswitch[0].Spec.Policy.OffloadPolicy = New-Object VMware.Vim.HostNetOffloadCapabilities
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.TcpSegmentation = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.ZeroCopyXmit = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.CsumOffload = $true
        $config.Vswitch[0].Spec.Policy.ShapingPolicy = New-Object VMware.Vim.HostNetworkTrafficShapingPolicy
        $config.Vswitch[0].Spec.Policy.ShapingPolicy.Enabled = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming = New-Object VMware.Vim.HostNicTeamingPolicy
        $config.Vswitch[0].Spec.Policy.NicTeaming.NotifySwitches = $true
        $config.Vswitch[0].Spec.Policy.NicTeaming.RollingOrder = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria = New-Object VMware.Vim.HostNicFailureCriteria
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.FullDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Percentage = 0
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckErrorPercent = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckBeacon = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Speed = 10
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckSpeed = 'minimum'
        $config.Vswitch[0].Spec.Policy.NicTeaming.Policy = 'loadbalance_srcid'
        $config.Vswitch[0].Spec.Policy.NicTeaming.ReversePolicy = $true
        $config.Portgroup = New-Object VMware.Vim.HostPortGroupConfig[] (1)
        $config.Portgroup[0] = New-Object VMware.Vim.HostPortGroupConfig
        $config.Portgroup[0].ChangeOperation = 'remove'
        $config.Portgroup[0].Spec = New-Object VMware.Vim.HostPortGroupSpec
        $config.Portgroup[0].Spec.VswitchName = ''
        $config.Portgroup[0].Spec.VlanId = -1
        $config.Portgroup[0].Spec.Name = 'Management Network'
        $config.Portgroup[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vnic = New-Object VMware.Vim.HostVirtualNicConfig[] (1)
        $config.Vnic[0] = New-Object VMware.Vim.HostVirtualNicConfig
        $config.Vnic[0].Portgroup = ''
        $config.Vnic[0].Device = 'vmk0'
        $config.Vnic[0].ChangeOperation = 'edit'
        $config.Vnic[0].Spec = New-Object VMware.Vim.HostVirtualNicSpec
        $config.Vnic[0].Spec.DistributedVirtualPort = New-Object VMware.Vim.DistributedVirtualSwitchPortConnection
        $config.Vnic[0].Spec.DistributedVirtualPort.SwitchUuid =  $vds.Uuid
        $config.Vnic[0].Spec.DistributedVirtualPort.PortgroupKey = $mgmtPortgroup.Key
        $config.ProxySwitch = New-Object VMware.Vim.HostProxySwitchConfig[] (1)
        $config.ProxySwitch[0] = New-Object VMware.Vim.HostProxySwitchConfig
        $config.ProxySwitch[0].Uuid =  $vds.Uuid
        $config.ProxySwitch[0].ChangeOperation = 'edit'
        $config.ProxySwitch[0].Spec = New-Object VMware.Vim.HostProxySwitchSpec
        $config.ProxySwitch[0].Spec.Backing = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicBacking
        $config.ProxySwitch[0].Spec.Backing.PnicSpec = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec[] (2)
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].PnicDevice = 'vmnic2'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortKey = '21'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortgroupKey = $dvsPortgroup.Key
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].PnicDevice = 'vmnic0'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].UplinkPortKey = '20'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].UplinkPortgroupKey = $dvsPortgroup.Key
        $changeMode = 'modify'
        
        $_this = Get-View -Id $hostId2
        Write-LogMessage -Message "Migrating Network Configuration for $esxiHost2"
        $_this.UpdateNetworkConfig($config, $changeMode) | Out-File $logFile -Encoding ASCII -Append

        #---------------UpdateNetworkConfig---------------
        $hostDetail3 = Get-View -ViewType HostSystem -Filter @{"Name"=$esxiHost3}
        $hostId3 = 'HostNetworkSystem-networkSystem-'+$hostDetail3.MoRef.Value.Split("-")[1]

        $config = New-Object VMware.Vim.HostNetworkConfig
        $config.Vswitch = New-Object VMware.Vim.HostVirtualSwitchConfig[] (1)
        $config.Vswitch[0] = New-Object VMware.Vim.HostVirtualSwitchConfig
        $config.Vswitch[0].Name = 'vSwitch0'
        $config.Vswitch[0].ChangeOperation = 'edit'
        $config.Vswitch[0].Spec = New-Object VMware.Vim.HostVirtualSwitchSpec
        $config.Vswitch[0].Spec.NumPorts = 128
        $config.Vswitch[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vswitch[0].Spec.Policy.Security = New-Object VMware.Vim.HostNetworkSecurityPolicy
        $config.Vswitch[0].Spec.Policy.Security.AllowPromiscuous = $false
        $config.Vswitch[0].Spec.Policy.Security.ForgedTransmits = $false
        $config.Vswitch[0].Spec.Policy.Security.MacChanges = $false
        $config.Vswitch[0].Spec.Policy.OffloadPolicy = New-Object VMware.Vim.HostNetOffloadCapabilities
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.TcpSegmentation = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.ZeroCopyXmit = $true
        $config.Vswitch[0].Spec.Policy.OffloadPolicy.CsumOffload = $true
        $config.Vswitch[0].Spec.Policy.ShapingPolicy = New-Object VMware.Vim.HostNetworkTrafficShapingPolicy
        $config.Vswitch[0].Spec.Policy.ShapingPolicy.Enabled = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming = New-Object VMware.Vim.HostNicTeamingPolicy
        $config.Vswitch[0].Spec.Policy.NicTeaming.NotifySwitches = $true
        $config.Vswitch[0].Spec.Policy.NicTeaming.RollingOrder = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria = New-Object VMware.Vim.HostNicFailureCriteria
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.FullDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Percentage = 0
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckErrorPercent = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckDuplex = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckBeacon = $false
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.Speed = 10
        $config.Vswitch[0].Spec.Policy.NicTeaming.FailureCriteria.CheckSpeed = 'minimum'
        $config.Vswitch[0].Spec.Policy.NicTeaming.Policy = 'loadbalance_srcid'
        $config.Vswitch[0].Spec.Policy.NicTeaming.ReversePolicy = $true
        $config.Portgroup = New-Object VMware.Vim.HostPortGroupConfig[] (1)
        $config.Portgroup[0] = New-Object VMware.Vim.HostPortGroupConfig
        $config.Portgroup[0].ChangeOperation = 'remove'
        $config.Portgroup[0].Spec = New-Object VMware.Vim.HostPortGroupSpec
        $config.Portgroup[0].Spec.VswitchName = ''
        $config.Portgroup[0].Spec.VlanId = -1
        $config.Portgroup[0].Spec.Name = 'Management Network'
        $config.Portgroup[0].Spec.Policy = New-Object VMware.Vim.HostNetworkPolicy
        $config.Vnic = New-Object VMware.Vim.HostVirtualNicConfig[] (1)
        $config.Vnic[0] = New-Object VMware.Vim.HostVirtualNicConfig
        $config.Vnic[0].Portgroup = ''
        $config.Vnic[0].Device = 'vmk0'
        $config.Vnic[0].ChangeOperation = 'edit'
        $config.Vnic[0].Spec = New-Object VMware.Vim.HostVirtualNicSpec
        $config.Vnic[0].Spec.DistributedVirtualPort = New-Object VMware.Vim.DistributedVirtualSwitchPortConnection
        $config.Vnic[0].Spec.DistributedVirtualPort.SwitchUuid =  $vds.Uuid
        $config.Vnic[0].Spec.DistributedVirtualPort.PortgroupKey = $mgmtPortgroup.Key
        $config.ProxySwitch = New-Object VMware.Vim.HostProxySwitchConfig[] (1)
        $config.ProxySwitch[0] = New-Object VMware.Vim.HostProxySwitchConfig
        $config.ProxySwitch[0].Uuid =  $vds.Uuid
        $config.ProxySwitch[0].ChangeOperation = 'edit'
        $config.ProxySwitch[0].Spec = New-Object VMware.Vim.HostProxySwitchSpec
        $config.ProxySwitch[0].Spec.Backing = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicBacking
        $config.ProxySwitch[0].Spec.Backing.PnicSpec = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec[] (2)
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].PnicDevice = 'vmnic2'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortKey = '23'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[0].UplinkPortgroupKey = $dvsPortgroup.Key
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1] = New-Object VMware.Vim.DistributedVirtualSwitchHostMemberPnicSpec
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].PnicDevice = 'vmnic0'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].UplinkPortKey = '22'
        $config.ProxySwitch[0].Spec.Backing.PnicSpec[1].UplinkPortgroupKey = $dvsPortgroup.Key
        $changeMode = 'modify'
        
        $_this = Get-View -Id $hostId3
        Write-LogMessage -Message "Migrating Network Configuration for $esxiHost3"
        $_this.UpdateNetworkConfig($config, $changeMode) | Out-File $logFile -Encoding ASCII -Append

        Write-LogMessage -Message "Disconnecting from vCenter Server $vCenterFqdn"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

checkPowershellModules
vCenterVss
rollbackFalse
vcenterReboot
migrateNetworking
vCenterVds
PAUSE
migrateAllHosts