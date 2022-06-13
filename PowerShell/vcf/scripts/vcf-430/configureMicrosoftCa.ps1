<#	SCRIPT DETAILS

    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         CPBU
    .Organization:  my-cloudy-world.com
    .Version:       1.0 (Build 001)
    .Date:          2021-10-26
    ===============================================================================================================

    .CHANGE_LOG

    - 1.0.001   (Gary Blake / 2021-10-26) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of configuring the Microsoft Certificate Authority Server within SDDC
    Manager.

    .EXAMPLE
    .\configureMicrosoftCa.ps1 -Workbook E:\pnpWorkbook.xlsx
#>

Param (
    [Parameter (Mandatory = $true)] [String]$Workbook
)

$module = "Configure Microsoft Certificate Authority"

Try {
    # Setup a Log File
    $scriptName = $MyInvocation.MyCommand.Name
    Start-SetupLogFile -path ".\" -scriptName $scriptName
    Clear-Host; Write-Host ""
}
Catch {
    Debug-CatchWriter -object $_
}

Try {
    # Check the ImportExcel PowerShell Module is Installed
    Write-LogMessage -type INFO -message "Performing Script Prequsisite Validation"
    Write-LogMessage -type INFO -message "Checking if ImportExcel Module is Installed on the System"
    $checkModule = Get-InstalledModule -Name ImportExcel
    if ($checkModule) {
        Write-LogMessage -type INFO -message "ImportExcel Module Version $($checkModule.Version) Installed"
    }
    else {
        Write-LogMessage -type INFO -message "ImportExcel Module Not Found. Trying to Install" -colour Cyan
        Install-Module -Name ImportExcel -Force
    }
}
Catch {
    Debug-CatchWriter -object $_
}

Function configureMicrosoftCa {

  Try {
    LogMessage "Checking Certificate Authority Configuration"
    $vcfCertCa = Get-VCFCertificateAuthConfiguration
    if ($vcfCertCa.id -ne "Microsoft") {
      $serverUrl = "https://$Global:activeDirectory.$Global:rootDomain/certsrv"
      LogMessage "Configuring Microsoft Certificate Authority Connection in SDDC Manager with $serverUrl"
      LogMessage "Using the Service Account named $Global:serviceAccount"
      Set-VCFMicrosoftCA -serverUrl $serverUrl -username $Global:serviceAccount -password $Global:serviceAccountPassword -templateName $Global:caTemplateName | Out-Null
      LogMessage "Configuration of Microsoft Certificate Authority in SDDC Manager Complete"
    }
    else {
      LogMessage "Configuration Certificate Authority Already Done" Magenta
    }
  }
  Catch {
    $ErrorMessage = $_.Exception.Message
    LogMessage "Error was: $ErrorMessage" Red
  }
}
Try {
    Write-LogMessage -type INFO -message "Starting the Process of Generating the $module" -Colour Yellow
    Write-LogMessage -type INFO -message "Opening the Excel Workbook: $Workbook"
    $pnpWorkbook = Open-ExcelPackage -Path $Workbook

    Write-LogMessage -type INFO -message "Checking Valid Planning and Prepatation Workbook Provided"
    if ($pnpWorkbook.Workbook.Names["vcf_version"].Value -ne "v4.3.x") {
        Write-LogMessage -type INFO -message "Planning and Prepatation Workbook Provided Not Supported" -colour Red 
        Break
    }
    Write-LogMessage -type INFO -message "Extracting Worksheet Data from the Excel Workbook"
    $sddcManagerFqdn        = $pnpWorkbook.Workbook.Names["sddc_mgr_fqdn"].Value
    $sddcManagerUser        = $pnpWorkbook.Workbook.Names["sso_default_admin"].Value
    $sddcManagerPass        = $pnpWorkbook.Workbook.Names["administrator_vsphere_local_password"].Value
    $activeDirectory        = "lab01ad01"
    $domain                 = "sddc.local"
    $serviceAccountUser     = "svc-mgr-ca"
    $serviceAccountPass     = "VMw@re1!"
    $caTemplateName         = "VMware"
    $serverUrl              = "https://$activeDirectory.$domain/certsrv"

    Write-LogMessage -type INFO -message "Connecting to SDDC Manager: $sddcManagerFqdn"
    Request-VCFToken -fqdn $sddcManagerFqdn -username $sddcManagerUser -password $sddcManagerPass | Out-Null
    if ($accessToken) {
        Write-LogMessage -type INFO -message "Checking SDDC Manager's Microsoft Certificate Authority Configuration"
        $vcfCertCa = Get-VCFCertificateAuthConfiguration
        if ($vcfCertCa.id -ne "Microsoft") {
            Write-LogMessage -type INFO -message "Configuring Microsoft Certificate Authority Connection in SDDC Manager with $serverUrl"
            Write-LogMessage -type INFO -message "Connecting Using the Service Account: $serviceAccountUser"
            pause
          Set-VCFMicrosoftCA -serverUrl $serverUrl -username $Global:serviceAccount -password $Global:serviceAccountPassword -templateName $Global:caTemplateName | Out-Null
          LogMessage "Configuration of Microsoft Certificate Authority in SDDC Manager Complete"
        }


        
        $checkDepotCreds = Get-VCFDepotCredential
        if (!$checkDepotCreds) {
            $createDepotCreds = Set-VCFDepotCredential -username $username -password $password
            if ($createDepotCreds.vmwareAccount.message -eq "Depot Status: Success") {
                Write-LogMessage -type INFO -message "Configured Repository Credentials Successfully" -colour Green
            }
            else {
                Write-LogMessage -type ERROR -message "Configuration of Repository Credentials Failed, Please Try Again" -colour Red
            }
        }
        else {
            Write-LogMessage -type INFO -message "Configuration of Repository Credentials in SDDC Manager Already Complete" -colour Magenta
        }
        Close-ExcelPackage $pnpWorkbook -ErrorAction SilentlyContinue
        Write-LogMessage -type INFO -message "Closing the Excel Workbook: $Workbook"
        Write-LogMessage -type INFO -message "Completed the Process of Generating the $module" -colour Yellow; Write-Host ""
    }
    else {
        Write-LogMessage -type ERROR -message "Connection to SDDC Manager $sddcManagerFqdn Failed, Check Values in the Planning and Preparation Workbook and Retry" -colour Red
    }
}
Catch {
    Debug-CatchWriter -object $_
}
