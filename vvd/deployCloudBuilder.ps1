<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         CPBU
    .Organization:  VMware, Inc.
    .Version:       1.0.000
    .Date:          2020-09-07
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function
    - Ken Gould - cidrToMask Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.000 (Gary Blake / 2020-09-07) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates the deployment of VMware Cloud Builder which is used to boot strap VMware Cloud 
    Foundation.

    .EXAMPLE

    .\deployCloudBuilder.ps1 -workbook F:\MyLab\WDC003V-K1\02-regiona-pnpWorkbook.xlsx -ovaPath F:\PlatformTools-Local\binaries\VMware-Cloud-Builder-4.1.0.0-16814578_OVF10.ova -vcenter w2-vvdinfra-labvc1.eng.vmware.com -vcenterUser administrator@vvd.vmware -vCenterPassword VMware1! -adminPassword VMw@re1! -rootPassword VMw@re1! -targetHost w2-haas01-esx0147.eng.vmware.com -targetCluster labvc1-cl0 -targetDatastore w2-B01-Infra-14TB -targetPortgroup dvPg-WDC003V-3061-MGMT
#>

Param (
    [Parameter(Mandatory=$true)]
        [String]$workbook,
    [Parameter(Mandatory=$true)]
        [String]$ovaPath,   
    [Parameter(Mandatory=$true)]
        [String]$vcenter,
    [Parameter(Mandatory=$true)]
        [String]$vcenterUser,
    [Parameter(Mandatory=$true)]
        [String]$vcenterPassword,
    [Parameter(Mandatory=$true)]
        [String]$adminPassword,
    [Parameter(Mandatory=$true)]
        [String]$rootPassword,
    [Parameter(Mandatory=$true)]
        [String]$targetHost,
    [Parameter(Mandatory=$true)]
        [String]$targetCluster,
    [Parameter(Mandatory=$true)]
        [String]$targetDatastore,
    [Parameter(Mandatory=$true)]
        [String]$targetPortgroup
)

$vcfVersion = "v4.1.0"
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
	Param (
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

Function checkModules
{
    Try {
        $powershellModuleName = "ImportExcel"
        LogMessage -message "Prerequisite Validation - Checking for PowerShell Module: $powershellModuleName"
        $checkImportExcel = Get-InstalledModule -Name ImportExcel -ErrorAction SilentlyContinue
        if (!$checkImportExcel) {
            LogMessage -message "PowerShell Module Not Installed: $powershellModuleName" -colour Red
            LogMessage -message "Attempting to Install PowerShell Module: $powershellModuleName"
            Install-Module ImportExcel -Force -Confirm:$false | Out-File $logFile -Encoding ASCII -Append
        }
        else {
            LogMessage -message "PowerShell Module Found: $powershellModuleName"
            LogMessage -message "Attempting to Import Module Found: $powershellModuleName"
            Import-Module ImportExcel | Out-File $logFile -Encoding ASCII -Append
            LogMessage -message "Imported PowerShell Module: $powershellModuleName Succesfully" -colour Green
        }
    }
    Catch {
        catchwriter -object $_
    }

    Try {
        $powershellModuleName = "PowerVCF"
        $powershellModuleVersion = "2.1.0"
        LogMessage -message "Prerequisite Validation - Checking for PowerShell Module: $powershellModuleName"
        $checkPowerVcf = Get-InstalledModule -Name PowerVCF -ErrorAction SilentlyContinue
        if ($checkPowerVcf.Version -eq $powershellModuleVersion) {
            LogMessage -message "PowerShell Module Found: $powershellModuleName"
            LogMessage -message "Attempting to Import Module Found: $powershellModuleName"
            Import-Module PowerVCF | Out-File $logFile -Encoding ASCII -Append
            LogMessage -message "Imported PowerShell Module: $powershellModuleName Succesfully" -colour Green
        }
        else {
            LogMessage -message "PowerShell Module Not Installed: $powershellModuleName" -colour Red
            LogMessage -message "Attempting to Install PowerShell Module: $powershellModuleName"
            Install-PackageProvider NuGet -Force | Out-File $logFile -Encoding ASCII -Append
            Set-PSRepository PSGallery -InstallationPolicy Trusted | Out-File $logFile -Encoding ASCII -Append
            Install-Module PowerVCF -MinimumVersion $powershellModuleVersion -Force -Confirm:$false | Out-File $logFile -Encoding ASCII -Append  
        }
    }
    Catch{
        catchwriter -object $_
    }
}

Function cidrToMask ($cidr)
{
    $subnetMasks = @(
        ($32 = @{ cidr = "32"; mask = "255.255.255.255" }),
        ($31 = @{ cidr = "31"; mask = "255.255.255.254" }),
        ($30 = @{ cidr = "30"; mask = "255.255.255.252" }),
        ($29 = @{ cidr = "29"; mask = "255.255.255.248" }),
        ($28 = @{ cidr = "28"; mask = "255.255.255.240" }),
        ($27 = @{ cidr = "27"; mask = "255.255.255.224" }),
        ($26 = @{ cidr = "26"; mask = "255.255.255.192" }),
        ($25 = @{ cidr = "25"; mask = "255.255.255.128" }),
        ($24 = @{ cidr = "24"; mask = "255.255.255.0" }),
        ($23 = @{ cidr = "23"; mask = "255.255.254.0" }),
        ($22 = @{ cidr = "22"; mask = "255.255.252.0" }),
        ($21 = @{ cidr = "21"; mask = "255.255.248.0" }),
        ($20 = @{ cidr = "20"; mask = "255.255.240.0" }),
        ($19 = @{ cidr = "19"; mask = "255.255.224.0" }),
        ($18 = @{ cidr = "18"; mask = "255.255.192.0" }),
        ($17 = @{ cidr = "17"; mask = "255.255.128.0" }),
        ($16 = @{ cidr = "16"; mask = "255.255.0.0" }),
        ($15 = @{ cidr = "15"; mask = "255.254.0.0" }),
        ($14 = @{ cidr = "14"; mask = "255.252.0.0" }),
        ($13 = @{ cidr = "13"; mask = "255.248.0.0" }),
        ($12 = @{ cidr = "12"; mask = "255.240.0.0" }),
        ($11 = @{ cidr = "11"; mask = "255.224.0.0" }),
        ($10 = @{ cidr = "10"; mask = "255.192.0.0" }),
        ($9 = @{ cidr = "9"; mask = "255.128.0.0" }),
        ($8 = @{ cidr = "8"; mask = "255.0.0.0" }),
        ($7 = @{ cidr = "7"; mask = "254.0.0.0" }),
        ($6 = @{ cidr = "6"; mask = "252.0.0.0" }),
        ($5 = @{ cidr = "5"; mask = "248.0.0.0" }),
        ($4 = @{ cidr = "4"; mask = "240.0.0.0" }),
        ($3 = @{ cidr = "3"; mask = "224.0.0.0" }),
        ($2 = @{ cidr = "2"; mask = "192.0.0.0" }),
        ($1 = @{ cidr = "1"; mask = "128.0.0.0" }),
        ($0 = @{ cidr = "0"; mask = "0.0.0.0" })			
    )
    $foundMask = $subnetMasks | where-object {$_.'cidr' -eq $cidr}
    return $foundMask.mask
}

Clear-Host

Try {
    LogMessage -message "Starting the Process of Deploying VMware Cloud Builder" -colour Yellow

    setupLogFile # Create new log
    checkModules # Check PowerShell Modules

    LogMessage -message "Checking the VMware Cloud Builder OVA Path: $ovaPath is Valid"
    if (!(Test-Path -Path $ovaPath)) {
        LogMessage -message "Path to VMware Cloud Builder OVA: $ovaPath Does Not Exist" -colour Red 
        Break
    }
    else {
        LogMessage -message "Validated the Path to VMware Cloud Builder OVA: $ovaPath Successfully" -colour Green
    }

    LogMessage -message "Checking the Path to the Planning and Preparation Workbook: $workbook is Valid"
    if (!(Test-Path -Path $workbook)) {
        LogMessage -message "Path to Planning and Preparation Workbook: $workbook Does Not Exist" -colour Red 
        Break
    }
    else {
        LogMessage -message "Validated the Path to the Planning and Preparation Workbook: $workbook Successfully" -colour Green
        LogMessage -message "Opening the Planning and Preparation Workbook: $workbook"
        $pnpWorkbook = Open-ExcelPackage -Path $workbook
    }

    LogMessage -message "Checking a Valid Planning and Preparation Workbook Has Been Provided"
    $optionsWorksheet = $pnpWorkbook.Workbook.Worksheets["Deployment Options"]
    if ($pnpWorkbook.Workbook.Names["vcf_version"].Value -ne $vcfVersion) {
        LogMessage -message "Planning and Preparation Workbook Provided: $workbook is Not Supported" -colour Red 
        Break
    }
    else {
        LogMessage -message "Planning and Preparation Workbook Provided: $workbook is Supported" -colour Green
    }

    LogMessage -message "Attempting to Connect to the Infrastructure vCenter Server $vcenter"
    Connect-VIServer -Server $vcenter -User $vcenterUser -Pass $vcenterPassword -ErrorAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
    if ($global:DefaultVIServers.Count -ne "1") {
        LogMessage -message "Connection to the Infrastructure vCenter Server $vcenter Failed" -colour Red
        Break
    }
    else {
        LogMessage -message "Connection to the Infrastructure vCenter Server $vcenter Successfully" -colour Green
    }

    LogMessage -message "Gathering Details from the Planning and Preparation Workbook"

    $cidr = $pnpWorkbook.Workbook.Names["mgmt_az1_mgmt_cidr"].Value.split("/")
    $managmentMask = cidrToMask $cidr[1]

    $Global:ovfConfig = Get-OvfConfiguration -Ovf $ovaPath
    $ovfConfig.Common.guestinfo.ADMIN_PASSWORD.Value = $adminPassword
    $ovfConfig.Common.guestinfo.ROOT_PASSWORD.Value = $rootPassword
    $ovfConfig.Common.guestinfo.hostname.Value = $pnpWorkbook.Workbook.Names["cloudbuilder_hostname"].Value
    $ovfConfig.Common.guestinfo.ip0.Value = $pnpWorkbook.Workbook.Names["cloudbuilder_ip"].Value
    $ovfConfig.Common.guestinfo.netmask0.Value = $managmentMask
    $ovfConfig.Common.guestinfo.gateway.Value = $pnpWorkbook.Workbook.Names["mgmt_az1_mgmt_gateway"].Value
    $ovfConfig.Common.guestinfo.DNS.Value = $pnpWorkbook.Workbook.Names["region_dns1_ip"].Value + "," + $pnpWorkbook.Workbook.Names["region_dns2_ip"].Value
    $ovfConfig.Common.guestinfo.domain.Value = $pnpWorkbook.Workbook.Names["region_ad_child_fqdn"].Value
    $ovfConfig.Common.guestinfo.searchpath.Value = $pnpWorkbook.Workbook.Names["region_ad_child_fqdn"].Value + "," + $pnpWorkbook.Workbook.Names["region_ad_parent_fqdn"].Value
    if ($pnpWorkbook.Workbook.Names["region_ntp2_ip"].Value -eq "n/a") {
        $ovfConfig.Common.guestinfo.ntp.Value = $pnpWorkbook.Workbook.Names["region_ntp1_ip"].Value
    }
    else {
        $ovfConfig.Common.guestinfo.ntp.Value = $pnpWorkbook.Workbook.Names["region_ntp1_ip"].Value + "," + $pnpWorkbook.Workbook.Names["region_ntp2_ip"].Value
    }
    $ovfConfig.IpAssignment.IpProtocol.Value = "IPv4"
    $ovfConfig.NetworkMapping.Network_1.Value = $targetPortgroup
    $cloudBuildervmName = $pnpWorkbook.Workbook.Names["cloudbuilder_hostname"].Value
    $diskFormat = "thin"

    $cloudBuilderExists = Get-VM -Name $cloudBuilderVmName -ErrorAction SilentlyContinue
    if ($cloudBuilderExists) {
        LogMessage -message "A Virtual Machine Called $cloudBuilderVmName Already Exists on the Host" -colour Yellow
        LogMessage -message "Do you wish to delete the detected VMware Cloud Builder instance? (Y/N): " -colour Yellow skipnewline
        $response = Read-Host
        if (($response -eq 'Y') -OR ($response -eq 'y')) {
            LogMessage -message "Deleting Discovered VMware Cloud Builder Instance"
            Try {
                if ($cloudBuilderExists.PowerState -ne "PoweredOff") {
                    Stop-VM -VM $cloudBuilderExists -Kill -Confirm:$false | Out-File $logFile -Encoding ASCII -Append
                }
                Remove-VM $cloudBuilderExists -DeletePermanently -confirm:$false | Out-File $logFile -Encoding ASCII -Append
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
        LogMessage -message "No Virtual Machine Named $cloudBuilderVmName Found. Proceeding with Deployment"
    }

    LogMessage -message "This Will Take at Least 5 Minutes and Maybe Significantly Longer Depending on the Environment. Please be Patient"
    Import-VApp -Source $ovaPath -OvfConfiguration $ovfConfig -Name $cloudBuildervmName -VMHost $targetHost -Location $targetCluster -Datastore $targetDatastore -DiskStorageFormat $diskFormat -Confirm:$false | Out-File $logFile -Encoding ASCII -Append
    Start-VM -VM $cloudBuildervmName -Confirm:$false -RunAsync | Out-File $logFile -Encoding ASCII -Append

    $cloudBuilderExists = Get-VM -Name $cloudBuilderVmName -ErrorAction SilentlyContinue
    if ($cloudBuilderExists) {
        $Timeout = 500 ## seconds
        $CheckEvery = 10 ## second
        Try {
            ## Start the timer
            $timer = [Diagnostics.Stopwatch]::StartNew()
            LogMessage -message "Checking the Deployment Status of VMware Cloud Builder Appliance: $cloudBuilderVmName"
            LogMessage -message "Waiting for $($ovfConfig.Common.guestinfo.ip0.Value) to Become Pingable." -colour Yellow
            While (-not (Test-Connection -ComputerName $ovfConfig.Common.guestinfo.ip0.Value -Quiet -Count 1)) {
                ## If the timer has waited greater than or equal to the timeout, throw an exception exiting the loop
                if ($timer.Elapsed.TotalSeconds -ge $Timeout) {
                    Throw "Timeout Exceeded. Giving Up on Ping Availability to $($ovfConfig.Common.guestinfo.ip0.Value)"
                }
                ## Stop the loop every $CheckEvery seconds
                Start-Sleep -Seconds $CheckEvery
            }
        }
        Catch {
            LogMessage -message "ERROR: Failed to Get a Response from $cloudBuilderVmName" -colour Red
        }
        Finally {
            ## Stop the timer
            $timer.Stop()
        }

        $scriptCommand = 'systemctl is-active vcf-bringup-ui'
        $checkService = Invoke-VMScript -VM $cloudBuilderVmName -ScriptText $scriptCommand -GuestUser root -GuestPassword $rootPassword -ErrorAction SilentlyContinue
        LogMessage -message "Initial Connection Made, Waiting for $($ovfConfig.Common.guestinfo.ip0.Value) Services to Start (~4 mins)" -colour Yellow
        Do {
            Start-Sleep 20
            $checkService = Invoke-VMScript -VM $cloudBuilderVmName -ScriptText $scriptCommand -GuestUser root -GuestPassword $rootPassword -ErrorAction SilentlyContinue
        }
        Until ($checkService.ScriptOutput -Match "active")
        LogMessage -message "VMware Cloud Builder Services Started"
        LogMessage -message "Completed Deployment of $cloudBuilderVmName using $ovaPath Successfully" -colour Green
    }
    else {
        LogMessage -message "VMware Cloud Builder VM Failed to Deploy. Please Check for Errors in $logFile" -colour Red    
    }

    LogMessage -message "Closing the Planning and Preparation Workbook: $workbook"
    Close-ExcelPackage $pnpWorkbook -NoSave -ErrorAction SilentlyContinue

    LogMessage -message "Disconnecting from the Infrastructure vCenter Server $vcenter"
    Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-File $logFile -encoding ASCII -append

    LogMessage -message "Completed the Process of Deploying VMware Cloud Builder" -colour Yellow
}
Catch {
    catchwriter -object $_
}