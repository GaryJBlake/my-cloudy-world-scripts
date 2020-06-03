<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         HCI BU
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 001)
    .Date:          2020-05-29
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.000 (Gary Blake / 2020-05-29) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of creating the JSON Specs needed for commissioning ESXi Hosts in SDDC 
    Manager. It uses the Planning and Preparation Workbook to obtain the required details needed in the JSON file
    that can then be consumed via the VMware Cloud Foundation Public API or PowerVCF.

    .EXAMPLE

    .\.\createCommissionHostSpec.ps1 -Workbook E:\pnpWorkbook.xlsx -Json E:\MyLab\sfo\sfo-workloadCommissionHosts.json
#>

 Param(
    [Parameter(Mandatory=$true)]
        [String]$Workbook,
    [Parameter(Mandatory=$true)]
        [String]$Json
)

$module = "Commission Host JSON Spec"

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
    Import-Module ImportExcel
}
Catch {
    LogMessage " ImportExcel Module not found. Installing"
    Install-Module ImportExcel
}

LogMessage " Stating the Process of Generating the $module" Yellow
LogMessage " Opening the Excel Workbook: $Workbook"
$pnpWorkbook = Open-ExcelPackage -Path $Workbook
LogMessage " Extracting Worksheet Data from the Excel Workbook"
$wldWorksheet = $pnpWorkbook.Workbook.Worksheets[‘Workload Domain’]
$Global:networkPoolName = $wldWorksheet.Cells['D99'].Value 

LogMessage " Generating the $module"
$resourcesObject = @()
    $resourcesObject += [pscustomobject]@{
        'fqdn' = $wldWorksheet.Cells['F78'].Value
        'username' = "root"
        'storageType' = "VSAN"
        'password' = "VMw@re1!"
        'networkPoolName' = $networkPoolName
        'networkPoolId' = "POOL-ID"
    }
    $resourcesObject += [pscustomobject]@{
        'fqdn' = $wldWorksheet.Cells['F79'].Value
        'username' = "root"
        'storageType' = "VSAN"
        'password' = "VMw@re1!"
        'networkPoolName' = $networkPoolName
        'networkPoolId' = "POOL-ID"
    }
    $resourcesObject += [pscustomobject]@{
        'fqdn' = $wldWorksheet.Cells['F80'].Value
        'username' = "root"
        'storageType' = "VSAN"
        'password' = "VMw@re1!"
        'networkPoolName' = $networkPoolName
        'networkPoolId' = "POOL-ID"
    }
    $resourcesObject += [pscustomobject]@{
        'fqdn' = $wldWorksheet.Cells['F81'].Value
        'username' = "root"
        'storageType' = "VSAN"
        'password' = "VMw@re1!"
        'networkPoolName' = $networkPoolName
        'networkPoolId' = "POOL-ID"
    }

LogMessage " Exporting the $module to $Json"
$resourcesObject | ConvertTo-Json | Out-File -FilePath $Json
Close-ExcelPackage $pnpWorkbook
LogMessage " Closing the Excel Workbook: $Workbook"
LogMessage " Completed the Process of Generating the $module" Yellow