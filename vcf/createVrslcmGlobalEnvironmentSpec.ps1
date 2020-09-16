 <#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         CPBU
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 001)
    .Date:          2020-09-16
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function
    - Ken Gould - cidrToMask Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.000 (Gary Blake / 2020-06-01) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of creating the JSON Spec needed for creating the Global Environment in  
    vRSLCM. It uses the Planning and Preparation Workbook to obtain the required details needed in the JSON file
    that can then be consumed via the vRealize Suite Lifecycle Manager Public API.

    .EXAMPLE

    .\createVrslcmGlobalEnvironmentSpec.ps1 -Workbook F:\pnpWorkbook.xlsx -Json F:\MyLab\vrslcmGlobalEnvironmentSpec.json
#>
 
 Param(
    [Parameter(Mandatory=$true)]
        [String]$Workbook,
    [Parameter(Mandatory=$true)]
        [String]$Json
)

$module = "vRSLCM Global Environment JSON Spec"

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
$Global:pnpWorkbook = Open-ExcelPackage -Path $Workbook

LogMessage " Checking Valid Planning and Prepatation Workbook Provided"
if ($pnpWorkbook.Workbook.Names["vcf_version"].Value -ne "v4.1.0") {
    LogMessage " Planning and Prepatation Workbook Provided Not Supported" Red 
    Break
}

LogMessage " Extracting Worksheet Data from the Excel Workbook"
LogMessage " Generating the $module"



$nodesObject = @()
$nodesObject += [pscustomobject]@{

}

$clusterVIPObject = @()
$clusterVIPObject += [pscustomobject]@{

}

$prodPropertiesObject = @()
$prodPropertiesObject += [pscustomobject]@{
    'syncGroupMembers' = "true"
    'vidmAdminPassword' = "locker:password:387773c5-2c8f-4518-b4c7-78a5d9fbb6d7:xreg-wsa01-admin"
    'defaultConfigurationUsername' = $pnpWorkbook.Workbook.Names["xreg_configamdin_user"].Value
    'defaultConfigurationPassword' = "locker:password:ed20dcdb-dacc-4663-a137-64e21b908979:xreg-wsa01-configadmin"
}

$productsObject = @()
$productsObject += [pscustomobject]@{
    'id' = "vidm"
    'version' = "3.2.2"
    'clusterVIP' = $clusterVIPObject
    'nodes' = $nodesObject
    'properties' = ($prodPropertiesObject | Select-Object -Skip 0)
}

$infraPropertiesObject = @()
$infraPropertiesObject += [pscustomobject]@{
    'acceptEULA' = "true"
    'enableTelemetry' = "true"
    'adminEmail' = "cloud@rainpole.io"
    'masterVidmEnabled' = "true"
    'dataCenterName' = $pnpWorkbook.Workbook.Names["vrslcm_xreg_dc"].Value
    'vCenterName' =  "sfo-m01-vc01.sfo.rainpole.io"
    'vCenterHost' = "sfo-m01-vc01.sfo.rainpole.io"
    'vcUsername' = "svc-vrslcm-vsphere"
    'vcPassword' = "locker:password:8c5cf725-d121-44e1-befd-496ae22a016d:svc-vrslcm-vsphere"
    'cluster' = "sfo-m01-dc01#sfo-m01-cl01"
    'network' = "xreg-m01-seg01"
    'netmask' = "255.255.255.0"
    'gateway' = $pnpWorkbook.Workbook.Names["vrslcm_xreg_dc"].Value
    'dns' = $pnpWorkbook.Workbook.Names["xregion_dns1_ip"].Value
    'domain' = "rainpole.io"
    'searchpath' = "rainpole.io"
    'ntp' = "ntp.sfo.rainpole.io"
    'storage' = "sfo-m01-cl01-ds-vsan01"
    'diskMode' = "thin"
    'folderName' = ""
    'resourcePool' = ""
    'defaultPassword' = "locker:password:44b6b50a-f1ea-4025-9986-64503e60b903:global-env-admin"
    'certificate' = "locker:certificate:0e259994-a378-470d-b324-7239c565ee20:xreg-wsa01.rainpole.io"
}

$infrastructureObject = @()
$infrastructureObject += [pscustomobject]@{
    properties = ($infraPropertiesObject | Select-Object -Skip 0)
}

$globalEnvironmentObject = @()
$globalEnvironmentObject += [pscustomobject]@{
    'environmentName' = "globalenvironement"
    infrastructure  = ($infraPropertiesObject | Select-Object -Skip 0)
    products = ($productsObject | Select-Object -Skip 0)
}

LogMessage " Exporting the $module to $Json"

$globalEnvironmentObject | ConvertTo-Json -Depth 11 | Out-File -FilePath $Json
LogMessage " Closing the Excel Workbook: $workbook"
#Close-ExcelPackage $pnpWorkbook -ErrorAction SilentlyContinue
LogMessage " Completed the Process of Generating the $module" Yellow