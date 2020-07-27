<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         CPBU
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 001)
    .Date:          2020-07-27
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function
    - Ken Gould - catchWriter Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.000 (Gary Blake / 2020-07-27) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of downloading the and installing the Cloud Proxy Appliance.

    .EXAMPLE

    .\deployCloudProxy.ps1 -vCenterServer mcw-vc01.cloudy.io -username administrator@vsphere.local -password VMw@re1!
#>

 Param(
    [Parameter(Mandatory=$true)]
        [String]$vCenterServer,
    [Parameter(Mandatory=$true)]
        [String]$username,
    [Parameter(Mandatory=$true)]
        [String]$password,
    [Parameter(Mandatory=$true)]
        [String]$cloudProxyConfig
)

# Statically Defined Variables
$module = "Cloud Proxy Appliance"
$cloudProxyUrl = "https://ci-data-collector.s3.amazonaws.com/VMware-Cloud-Services-Data-Collector.ova"
$cloudProxyOva = "$PSScriptRoot\VMware-Cloud-Services-Data-Collector.ova"

Function LogMessage {

    Param(
        [Parameter(Mandatory=$true)]
            [String]$message,
        [Parameter(Mandatory=$false)]
            [String]$colour,
        [Parameter(Mandatory=$false)]
            [string]$skipnewline
    )

    If (!$colour) {
        $colour = "green"
    }

    $timeStamp = Get-Date -Format "MM-dd-yyyy_hh:mm:ss"

    Write-Host -NoNewline -ForegroundColor White " [$timestamp]"
    If ($skipnewline) {
        Write-Host -NoNewline -ForegroundColor $colour " $message"
    }
    else {
        Write-Host -ForegroundColor $colour " $message"
    }
}

Function catchWriter
{
	Param(
        [Parameter(mandatory=$true)]
        [PSObject]$object
    )

    $lineNumber = $object.InvocationInfo.ScriptLineNumber
	$lineText = $object.InvocationInfo.Line.trim()
	$errorMessage = $object.Exception.Message
	LogMessage "Error at Script Line $lineNumber" Red
	LogMessage "Relevant Command: $lineText" Red
	LogMessage "Error Message: $errorMessage" Red
}

Function downloadCloudProxy
{
    Try {
        LogMessage "Starting the process of obtaining the $module" Cyan
        LogMessage "Checking if the $module has already been downloaded"
        $ovaExists = Test-Path $cloudProxyOva
        if (!$ovaExists) {
            LogMessage "The $module OVA not found on the file system"
            LogMessage "Starting the download of the $module OVA"
            (New-Object System.Net.WebClient).DownloadFile($cloudProxyUrl, $cloudProxyOva)
            LogMessage "Finished downloading the $module OVA"
        }
        else {
            LogMessage "The $module OVA has already been downloaded" Magenta
        }
        LogMessage "Completed the process of obtaining the $module" Cyan
    }
    Catch {
        catchwriter -object $_
    }
}

Function deployCloudProxy 
{
    Try {
        $configJsonExists = Test-Path $cloudProxyConfig
        LogMessage "Starting the process of deploying the $module" Cyan
        LogMessage "Checking if the $module configuration JSON exists"
        If (!$configJsonExists) {
            LogMessage "The configuration JSON for $module does not exist" Red
            break
        }
        else {
            LogMessage "Reading the $module configuration JSON"
            $cloudProxyObject = (Get-Content -Raw $cloudProxyConfig) | ConvertFrom-Json
            $ovfConfig = Get-OvfConfiguration -Ovf $cloudProxyOva

            $ovfConfig.Common.ONE_TIME_KEY.Value = $cloudProxyObject.ONE_TIME_KEY
            $ovfConfig.Common.itfm_root_password.Value = $cloudProxyObject.itfm_root_password
            $ovfConfig.Common.rdc_name.Value = $cloudProxyObject.rdc_name
            $ovfConfig.Common.network_proxy_hostname_or_ip.Value = $cloudProxyObject.network_proxy_hostname_or_ip
            $ovfConfig.Common.network_proxy_port.Value = $cloudProxyObject.network_proxy_port
            $ovfConfig.Common.network_proxy_username.Value = $cloudProxyObject.network_proxy_username
            $ovfConfig.Common.network_proxy_password.Value = $cloudProxyObject.network_proxy_password
            $ovfConfig.IpAssignment.IpProtocol.Value = $cloudProxyObject.IpProtocol
            $ovfConfig.NetworkMapping.Network_1.Value = $cloudProxyObject.Network_1
            $ovfConfig.vami.VMware_Cloud_Services_Data_Collector.gateway.Value = $cloudProxyObject.gateway
            $ovfConfig.vami.VMware_Cloud_Services_Data_Collector.domain.Value = $cloudProxyObject.domain
            $ovfConfig.vami.VMware_Cloud_Services_Data_Collector.searchpath.Value = $cloudProxyObject.searchpath
            $ovfConfig.vami.VMware_Cloud_Services_Data_Collector.DNS.Value = $cloudProxyObject.DNS
            $ovfConfig.vami.VMware_Cloud_Services_Data_Collector.ip0.Value = $cloudProxyObject.ip0
            $ovfConfig.vami.VMware_Cloud_Services_Data_Collector.netmask0.Value = $cloudProxyObject.netmask0

            $cloudProxyExists = Get-VM -Name $cloudProxyObject.rdc_name -ErrorAction SilentlyContinue
            if ($cloudProxyExists) {
                LogMessage "A virtual machine called $($cloudProxyObject.rdc_name) already exists on host" Yellow
                LogMessage "Do you wish to delete the detected $module instance? (Y/N): " Yellow skipnewline
                $response = Read-Host
                if (($response -eq 'Y') -OR ($response -eq 'y')) {
                    LogMessage "Deleting discovered $module Instance"
                    Try {
                        if ($cloudProxyExists.PowerState -eq "PoweredOn") {
                            Stop-VM -VM $cloudProxyExists -Kill -Confirm:$false | Out-Null
                        }
                        Remove-VM $cloudProxyExists -DeletePermanently -confirm:$false | Out-Null
                        deployCloudProxy
                    }
                    Catch {
                        catchwriter -object $_
                    }
                }
                else {
                    #nothing, script will continue
                }
            }
            else {
                LogMessage "No instance of $($cloudProxyObject.rdc_name) found. Proceeding with deployment"
                LogMessage "Deploying the $module named $($cloudProxyObject.rdc_name)"
                Import-VApp -Source $cloudProxyOva -OvfConfiguration $ovfConfig -Name $cloudProxyObject.rdc_name -VMHost $cloudProxyObject.vmHost -Location $cloudProxyObject.cluster -Datastore $cloudProxyObject.datastore -DiskStorageFormat $cloudProxyObject.diskFormat -Confirm:$false | Out-Null
                LogMessage "Powering on the $module named $($cloudProxyObject.rdc_name)"
                Start-VM -VM $cloudProxyObject.rdc_name -Confirm:$false -RunAsync | Out-Null
                LogMessage "Completed the process of deploying the $module" Cyan
            }
        }
    }
    Catch {
        catchwriter -object $_
    }
}

Function connectVserver
{
    Try {
        LogMessage "Connecting to vCenter Server $vCenterServer" Yellow
        Connect-VIServer $vCenterServer -user $username -pass $password -ErrorAction SilentlyContinue | Out-Null
    }
    Catch {
        catchwriter -object $_
    }

}

Function disconnectVserver
{
    Try {
        LogMessage "Disconnecting from vCenter Server $vCenterServer" Yellow
        Disconnect-VIServer * -Force -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
    }
    Catch {
        catchwriter -object $_
    }

}

# Execute Functions
connectVserver
downloadCloudProxy
deployCloudProxy
disconnectVserver