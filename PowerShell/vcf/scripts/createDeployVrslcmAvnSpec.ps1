<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         CPBU
    .Organization:  VMware, Inc.
    .Version:       2.0 (Build 001)
    .Date:          2020-07-10
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.000 (Gary Blake / 2020-05-29) - Initial script creation
    - 1.0.002 (Gary Blake / 2020-06-15) - Minor fixes
    - 2.0.001 (Gary Blake / 2020-07-10) - Updated for VCF 4.0.1 where Named Cells in the Planning and Preparation
                                          Workbook are now available

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of creating the JSON Spec needed for deploying vRealize Suite Lifecycle
	Manager in SDDC Manager. It uses the Planning and Preparation Workbook to obtain the required details needed
    in the JSON file that can then be consumed via the VMware Cloud Foundation Public API or PowerVCF.

    .EXAMPLE

    .\createDeployVrslcmAvnSpec.ps1 -Workbook E:\pnpWorkbook.xlsx -Json E:\MyLab\sfo\sfo-vrslcmDeploy.json 
    -sshPassword VMw@re1! -apiPassword VMw@re1!
#>

 Param(
    [Parameter(Mandatory=$true)]
        [String]$Workbook,
    [Parameter(Mandatory=$true)]
        [String]$Json,
    [Parameter(Mandatory=$true)]
        [String]$sshPassword,
    [Parameter(Mandatory=$true)]
        [String]$apiPassword
)

$module = "Deploy vRealize Suite Lifecycle Manager on AVN JSON Spec"

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

Try {
    LogMessage " Importing ImportExcel Module"
    Import-Module ImportExcel -WarningAction SilentlyContinue -ErrorAction Stop
}
Catch {
    LogMessage " ImportExcel Module not found. Installing"
    Install-Module ImportExcel
}

LogMessage " Starting the Process of Generating the $module" Yellow
LogMessage " Opening the Excel Workbook: $Workbook"
$pnpWorkbook = Open-ExcelPackage -Path $Workbook

LogMessage " Checking Valid Planning and Prepatation Workbook Provided"
if ($pnpWorkbook.Workbook.Names["vcf_version"].Value -ne "v4.0.1") {
    LogMessage " Planning and Prepatation Workbook Provided Not Supported" Red 
    Break
}

LogMessage " Extracting Worksheet Data from the Excel Workbook"
$opsWorksheet = $pnpWorkbook.Workbook.Worksheets[‘Cloud Operations and Automation’] 

LogMessage " Generating the $module"
$resourcesObject = @()
    $resourcesObject += [pscustomobject]@{
        'apiPassword' = $apiPassword
        'fqdn' = $opsWorksheet.Cells['F46'].Value
        'sshPassword' = $sshPassword
    }

LogMessage " Exporting the $module to $Json"
$resourcesObject | ConvertTo-Json | Out-File -FilePath $Json
Close-ExcelPackage $pnpWorkbook -ErrorAction SilentlyContinue
LogMessage " Closing the Excel Workbook: $Workbook"
LogMessage " Completed the Process of Generating the $module" Yellow