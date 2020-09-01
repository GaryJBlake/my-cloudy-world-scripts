<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         CPBU
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 001)
    .Date:          2020-09-01
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.000 (Gary Blake / 2020-09-01) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates performing the prerequisite configugration tasks for each ESXi Hosts that is consumed by
    SDDC Manager. It uses the Planning and Preparation Workbook to obtain the required details.

    .EXAMPLE

    .\configureEsxiPreRreqs.ps1 -fqdn sfo01-m01-esx01.sfo.rainpole.io -rootPassword VMw@re1! -dnsServer1 172.20.11.4 -dnsServer2 172.20.11.5 -ntpServer ntp.sfo.rainpole.io -managamentVlan 3072
#>

Param(
    [Parameter(Mandatory=$true)]
        [String]$fqdn,
    [Parameter(Mandatory=$true)]
        [String]$rootPassword,
    [Parameter(Mandatory=$true)]
        [String]$dnsServer1,
    [Parameter(Mandatory=$false)]
        [String]$dnsServer2,
    [Parameter(Mandatory=$true)]
        [String]$ntpserver,
    [Parameter(Mandatory=$true)]
        [Int32]$managementVlan
)

$module = "Configure ESXi Host Prerequisites"

$hostname = $fqdn.Split(".")[0]
$pos = $fqdn.IndexOf(".")
$domain = $fqdn.Substring($pos+1)
$scriptName = ($MyInvocation.MyCommand.Name).Trim(".ps1")

Function setupLogFile
{
    $filetimeStamp = Get-Date -Format "MM-dd-yyyy_hh_mm_ss"   
    $Global:logFile  = $PSScriptRoot+'\logs\'+$scriptName+'-'+$filetimeStamp+'.log'
    $logFolder = $PSScriptRoot+'\logs'
    $logFolderExists = Test-Path $logFolder
    if (!$logFolderExists) {
        New-Item -ItemType Directory -Path $logFolder
    }
    New-Item -type File -path $logFile | Out-Null
	$logContent = '['+$filetimeStamp+'] Beginning of Log File'
	Add-Content -path $logFile $logContent
}

Function LogMessage 
{
    Param (
        [Parameter(Mandatory=$true)]
            [String]$message,
        [Parameter(Mandatory=$false)]
            [String]$colour,
        [Parameter(Mandatory=$false)]
            [string]$skipNewLine
    )

    If (!$colour) {
        $colour = "Cyan"
    }

    $timeStamp = Get-Date -Format "MM-dd-yyyy_HH:mm:ss"

    Write-Host -NoNewline -ForegroundColor White " [$timeStamp]"
    If ($skipNewLine) {
        Write-Host -NoNewline -ForegroundColor $colour " $message"        
    }
    else {
        Write-Host -ForegroundColor $colour " $message" 
    }
    $logContent = '['+$timeStamp+'] '+$message
	Add-Content -path $logFile $logContent
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
	LogMessage -message " Error at Script Line $lineNumber" -colour Red
	LogMessage -message " Relevant Command: $lineText" -colour Red
	LogMessage -message " Error Message: $errorMessage" -colour Red
}

Clear-Host

Try {
    setupLogFile # Create new log

    LogMessage -message "Starting the Process of Configuring ESXi Prerequisites for VMware Cloud Foundation" -colour Yellow
    
    # Attempt to make a connection to the ESXi Host
    Try {   
        LogMessage -message "Attempting to Connect to ESXi Host $fqdn"
        $esxiConnection = Connect-VIServer -Server $fqdn -User root -Password $rootPassword -ErrorVariable errorOutput -ErrorAction SilentlyContinue -WarningAction SilentlyContinue 
        if (!$esxiConnection) {
            LogMessage -message "Failed to Connect to ESXi Host $fqdn has With Error $errorOutput" -colour Red
            Break
        }
        else {
            LogMessage -message "Connected to ESXi Host $fqdn Successfully" -colour Green
        }
    }
    Catch {
        catchwriter -object $_
    }

    # Attempt to configure ESXi Host Advanced Setting for CEIP to ENABLED
    Try {     
        LogMessage -message "Attempting to Configure Advanced System Setting 'UserVars.HostClientCEIPOptIn' to Enabled on $fqdn"
        LogMessage -message "Checking Current Configuration for Advanced System Setting 'UserVars.HostClientCEIPOptIn' on $fqdn"
        $ceipSetting = (Get-AdvancedSetting -Entity $fqdn -Name UserVars.HostClientCEIPOptIn).Value
        if ($ceipSetting -eq "2") {     
            LogMessage -message "Advanced System Setting 'UserVars.HostClientCEIPOptIn' Already Configured on $fqdn, nothing to do" -colour Magenta
        }
        else {
            LogMessage -message "Setting Advanced System Setting 'UserVars.HostClientCEIPOptIn' to Enabled on $fqdn"
            Get-AdvancedSetting -Entity $fqdn -Name UserVars.HostClientCEIPOptIn | Set-AdvancedSetting -Value 2 -Confirm:$false -ErrorVariable errorOutput | Out-File $logFile -Encoding ASCII -Append
            LogMessage -message "Configured Advanced System Setting 'UserVars.HostClientCEIPOptIn' $fqdn Successfully" -colour Green
        }
    }
    Catch {
        catchwriter -object $_
    }

    # Attempt to configure ESXi Host Name and DNS Server Configuration
    Try {
        LogMessage -message "Attempting to Configure DNS Server Configuration on $fqdn"
        if ($dnsServer2 -eq "") {
            LogMessage -message "Setting DNS Server $dnsServer1 on $fqdn"
            Get-VMHost | Get-VMHostNetwork -ErrorAction SilentlyContinue | Set-VMHostNetwork -HostName $hostname -DomainName $domain -SearchDomain $domain -DnsAddress $dnsServer1 -Confirm:$false | Out-File $logFile -Encoding ASCII -Append
        }
        else {
            LogMessage -message "Setting DNS Server $dnsServer1 and $dnsServer2 on $fqdn"
            Get-VMHost | Get-VMHostNetwork -ErrorAction SilentlyContinue | Set-VMHostNetwork -HostName $hostname -DomainName $domain -SearchDomain $domain -DnsAddress $dnsServer1,$dnsServer2 -Confirm:$false | Out-File $logFile -Encoding ASCII -Append
        }
    }
    Catch {
        catchwriter -object $_
    }

    # Attempt to configure ESXi Host 'VM Network' with VLAN Configuration
    Try {
        $portGroupName = "VM Network"
        LogMessage -message "Attempting to Configure VLAN ID on Portgroup 'VM Network' on $fqdn"
        LogMessage -message "Checking Portgroup 'VM Network' is Present on $fqdn"
        $portGroupExists = Get-VirtualPortGroup | Where {$_.name -eq $portGroupName}
        if (!$portGroupExists) {
            LogMessage -message "Portgoup 'VM Network' is Not Present on $fqdn" -colour Red
            Break
        }
        else {
            LogMessage -message "Setting VLAN ID $managementVlan for Portgroup 'VM Network' on $fqdn"
            Set-VirtualPortGroup -VirtualPortGroup $portGroupExists -VLanId $managementVlan -Confirm:$false -ErrorVariable errorOutput | Out-File $logFile -Encoding ASCII -Append
            LogMessage -message "Configured VLAN ID for Portgroup 'VM Network' on $fqdn Successfully" -colour Green
        }
    }
    Catch {
        catchwriter -object $_
    }
    
    # Attempt to enable SSH Service on ESXi Host
    Try {
        LogMessage -message "Attempting to Configure the SSH Service on $fqdn"
        LogMessage -message "Setting SSH Startup Policy to 'Start and Stop with Host' on $fqdn"
        Set-VMHostService -HostService (Get-VMHostservice | Where {$_.key -eq "TSM-SSH"}) -Policy "On" -Confirm:$false | Out-File $logFile -Encoding ASCII -Append
        LogMessage -message "Setting the Status of the SSH Service to Started on $fqdn"
        Get-VMHostService | Where {$_.key -eq 'TSM-SSH'} | Start-VMHostService -Confirm:$false | Out-File $logFile -Encoding ASCII -Append
        LogMessage -message "Configured SSH Service on $fqdn Successfully" -colour Green
    }
    Catch {
        catchwriter -object $_
    }

    # Attempt to configure NTP Servers on ESXi Host
    Try {
        LogMessage -message "Attempting to Configure NTP Servers on $fqdn"
        $currentNTPServerList = Get-VMHostNtpServer -VMHost $fqdn
        if ($currentNTPServerList -ne "") {
            ForEach ($ntpServer in $currentNTPServerList){
                Remove-VMHostNtpServer -VMHost $fqdn -NtpServer $ntpServer -Confirm:$false -ErrorAction silentlyContinue | Out-File $logFile -encoding ASCII -append
                LogMessage -message "Removed NTP Server $ntpServer on $fqdn"
            }
        }
        LogMessage -message "Setting NTP Server $ntpServer on $fqdn"
        Add-VMHostNtpServer -VMHost $fqdn -NtpServer $ntpServer -Confirm:$false | Out-File $logFile -encoding ASCII -append
        LogMessage -message "Restarting NTP Service on $fqdn"
        Get-VMHostService | Where {$_.key -eq 'ntpd'} | Stop-VMHostService -Confirm:$false | Out-File $logFile -encoding ASCII -append 
        Get-VMHostService | Where {$_.key -eq 'ntpd'} | Start-VMHostService -Confirm:$false | Out-File $logFile -encoding ASCII -append 
        LogMessage -message "Setting NTP Startup Policy to 'Start and Stop with Host' on $fqdn"
        Set-VMHostService -HostService (Get-VMHostservice | Where {$_.key -eq "ntpd"}) -Policy "On" | Out-File $logFile -encoding ASCII -append 
        LogMessage -message "Configured NTP Service and Startup Policy on $fqdn Successfully" -colour Green
        
    }
    Catch {
        catchwriter -object $_
    }
    
    # Disconnecting from the ESXi Host
    Try {   
        LogMessage -message "Attempting to Disconnect from ESXi Host $fqdn"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
        LogMessage -message "Disconnected from ESXi Host $fqdn Successfully" -colour Green
    }
    Catch {
        catchwriter -object $_
    }

    LogMessage -message "Completed the Process of Configuring ESXi Prerequisites for VMware Cloud Foundation" -colour Yellow  
}
Catch {
    catchwriter -object $_
}