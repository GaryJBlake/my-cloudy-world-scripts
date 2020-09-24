<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         CPBU
    .Organization:  VMware, Inc.
    .Version:       1.0.000
    .Date:          2020-09-23
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.000 (Gary Blake / 2020-09-23) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION
    This script automates the process of configuring the repository settings in SDDC Manager

    .EXAMPLE
    .\configureRepositorySettings.ps1 -workbook F:\MyLab\WDC003V-K1\02-regiona-pnpWorkbook.xlsx -sddcMgrUsername administrator@vsphere.local -sddcMgrPassword VMw@re1! -depotUsername user@mydomain.com -depotPassword VMw@re1@
#>

    Param (
        [Parameter(Mandatory=$true)]
            [String]$workbook,
        [Parameter(Mandatory=$true)]
            [String]$sddcMgrUsername,
        [Parameter(Mandatory=$true)]
            [String]$sddcMgrPassword,
        [Parameter(Mandatory=$true)]
            [String]$depotUsername,
        [Parameter(Mandatory=$true)]
            [String]$depotPassword
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

Clear-Host

Try {
    LogMessage -message "Starting the Process of Configuring the Repositry Settings for VMware Cloud Foundation" -colour Yellow

    setupLogFile # Create new log
    checkModules # Check PowerShell Modules

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

    LogMessage -message "Gathering Details from the Planning and Preparation Workbook"
    $sddcMgrFqdn = $pnpWorkbook.Workbook.Names["sddc_mgr_fqdn"].Value

    Try {
        LogMessage -message "Attempting to Connect to the SDDC Manager $sddcMgrFqdn"
        Request-VCFToken -fqdn $sddcMgrFqdn -username $sddcMgrUsername -password $sddcMgrPassword | Out-File $logFile -Encoding ASCII -Append
    }
    Catch {
        catchwriter -object $_
    }

    Try {
        LogMessage -message "Checking the Credential Configuration for VMware Cloud Foundation Depot Access"
  	    $vcfDepotCreds = Get-VCFDepotCredential | Out-File $logFile -Encoding ASCII -Append
  	    if (!$vcfDepotCreds.username){
  		    LogMessage -message "Configuring the VMware Cloud Foundation Depot Depot Credentials With: $depotUsername"
  		    Set-VCFDepotCredential -username $depotUsername -password $depotPassword | Out-File $logFile -Encoding ASCII -Append
  		    LogMessage -message "Configuration of VMware Cloud Foundation Depot Credentials Complete"
  	    }
  	    else {
  		    LogMessage -message "VMwware Cloud Foundation Depot Credentials Already Configure With: $($vcfDepotCreds.username)" -colour Magenta
        }
    }
    Catch {
        catchwriter -object $_
    }

    LogMessage -message "Closing the Planning and Preparation Workbook: $workbook"
    Close-ExcelPackage $pnpWorkbook -NoSave -ErrorAction SilentlyContinue

    LogMessage -message "Completed the Process of Configuring the Repositry Settings for VMware Cloud Foundation" -colour Yellow
}
Catch {
    catchwriter -object $_
}