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
    - Ken Gould - cidrToMask Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.000 (Gary Blake / 2020-05-29) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of creating the JSON Specs needed for creating a network pool in SDDC 
    Manager. It uses the Planning and Preparation Workbook to obtain the required details needed in the JSON file
    that can then be consumed via the VMware Cloud Foundation Public API or PowerVCF.

    .EXAMPLE

    .\createNetworkPoolSpec.ps1 -workbook E:\pnpWorkbook.xlsx -json E:\MyLab\sfo\sfo-workloadNetworkPool.json
#>
 
 Param(
    [Parameter(Mandatory=$true)]
        [String]$Workbook,
    [Parameter(Mandatory=$true)]
        [String]$Json
)

$module = "Network Pool JSON Spec"

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

Function cidrToMask ($cidr) {
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

LogMessage " Checking Valid Planning and Prepatation Workbook Provided"
$optionsWorksheet = $pnpWorkbook.Workbook.Worksheets[‘Deployment Options’]
if ($optionsWorksheet.Cells['J8'].Value -ne "v4.0.0") {
    LogMessage " Planning and Prepatation Workbook Provided Not Supported" Red 
    Break
}

LogMessage " Extracting Worksheet Data from the Excel Workbook"
$wldWorksheet = $pnpWorkbook.Workbook.Worksheets[‘Workload Domain’]

LogMessage " Generating the $module"
$cidr = $wldWorksheet.Cells['H12'].Value.split("/")
$vsanMask = cidrToMask $cidr[1]
$vsanSubnet = $cidr[0]

$cidr = $wldWorksheet.Cells['H11'].Value.split("/")
$vmotionMask = cidrToMask $cidr[1]
$vmotionSubnet = $cidr[0]

$vmotionIpPoolObject = @()
    $vmotionIpPoolObject += [pscustomobject]@{
        'start' = $wldWorksheet.Cells['H99'].Value;
        'end' = $wldWorksheet.Cells['H100'].Value
    }

$vsanIpPoolObject = @()
    $vsanIpPoolObject += [pscustomobject]@{
        'start' = $wldWorksheet.Cells['H101'].Value;
        'end' = $wldWorksheet.Cells['H102'].Value
    }

$networkObject = @()
    $networkObject += [pscustomobject]@{
        'type' = "VMOTION"
        'vlanId' = $wldWorksheet.Cells['D11'].Value
        'mtu' = $wldWorksheet.Cells['L11'].Value
        'subnet' = $vmotionSubnet
        'mask' = $vmotionMask
        'gateway' = $wldWorksheet.Cells['J11'].Value
        ipPools = $vmotionIpPoolObject
    }
    $networkObject += [pscustomobject]@{
        'type' = "VSAN"
        'vlanId' = $wldWorksheet.Cells['D12'].Value
        'mtu' = $wldWorksheet.Cells['L12'].Value
        'subnet' = $vsanSubnet
        'mask' = $vsanMask
        'gateway' = $wldWorksheet.Cells['J12'].Value
        ipPools = $vsanIpPoolObject
    }

$networkPoolObject = @()
    $networkPoolObject += [pscustomobject]@{
        'name' = $wldWorksheet.Cells['D99'].Value
        networks = $networkObject
    }

LogMessage " Exporting the $module to $json"
$networkPoolObject | ConvertTo-Json -Depth 4 | Out-File -FilePath $Json
LogMessage " Closing the Excel Workbook: $workbook"
Close-ExcelPackage $pnpWorkbook
LogMessage " Completed the Process of Generating the $module" Yellow