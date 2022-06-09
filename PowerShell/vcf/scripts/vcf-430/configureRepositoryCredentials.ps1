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

    This script automates the process of configuring the credentials for the repository in SDDC Manager using the
    Planning and Preparation Workbook as the input source.

    Requires Planning and Preparation Workbook for VMware Cloud Foundation 4.3.0 or later

    .EXAMPLE

    .\configureRepositoryCredentials.ps1 -Workbook E:\pnpWorkbook.xlsx
#>

Param(
    [Parameter (Mandatory=$true)] [String]$Workbook
)

$module = "Configure Repository Credentials"

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
    $sddcManagerFqdn    = $pnpWorkbook.Workbook.Names["sddc_mgr_fqdn"].Value
    $sddcManagerUser    = $pnpWorkbook.Workbook.Names["sso_default_admin"].Value
    $sddcManagerPass    = $pnpWorkbook.Workbook.Names["administrator_vsphere_local_password"].Value
    $username           = $pnpWorkbook.Workbook.Names["user_svc_my_vmware"].Value
    $password           = $pnpWorkbook.Workbook.Names["svc_my_vmware_password"].Value

    Write-LogMessage -type INFO -message "Connecting to SDDC Manager: $sddcManagerFqdn"
    Request-VCFToken -fqdn $sddcManagerFqdn -username $sddcManagerUser -password $sddcManagerPass | Out-Null
    if ($accessToken) {
        Write-LogMessage -type INFO -message "Checking SDDC Manager's Existing Repository Credentials"
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



