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

    This script automates the process of creating the JSON Spec needed for creating a Workload Domain in SDDC 
    Manager. It uses the Planning and Preparation Workbook to obtain the required details needed in the JSON file
    that can then be consumed via the VMware Cloud Foundation Public API or PowerVCF.

    .EXAMPLE

    .\createWorkloadDomainSpec.ps1 -workbook E:\pnpWorkbook.xlsx -json E:\MyLab\sfo\sfo-workloadDomain.json -vCenterPassword VMw@re1! -nsxtPassword VMw@re1!
#>
 
 Param(
    [Parameter(Mandatory=$true)]
        [String]$Workbook,
    [Parameter(Mandatory=$true)]
        [String]$Json,
    [Parameter(Mandatory=$true)]
        [String]$nsxtPassword,
    [Parameter(Mandatory=$true)]
        [String]$vCenterPassword
)

$module = "Workload Domain JSON Spec"

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
LogMessage " Extracting Worksheet Data from the Excel Workbook"
$wldWorksheet = $pnpWorkbook.Workbook.Worksheets[‘Workload Domain’]
$mgmtWorksheet = $pnpWorkbook.Workbook.Worksheets[‘Management Domain’]

LogMessage " Generating the $module"

$cidr = $wldWorksheet.Cells['H10'].Value.split("/")
$managmentMask = cidrToMask $cidr[1]

$nsxtNode1Object = @()
    $nsxtNode1Object += [pscustomobject]@{
        'ipAddress' = $wldWorksheet.Cells['H83'].Value
        'dnsName' = $wldWorksheet.Cells['F83'].Value
        'gateway' = $wldWorksheet.Cells['J9'].Value
        'subnetMask' = $managmentMask
    }

$nsxtNode2Object = @()
    $nsxtNode2Object += [pscustomobject]@{
        'ipAddress' = $wldWorksheet.Cells['H84'].Value
        'dnsName' = $wldWorksheet.Cells['F84'].Value
        'gateway' = $wldWorksheet.Cells['J9'].Value
        'subnetMask' = $managmentMask
    }

$nsxtNode3Object = @()
    $nsxtNode3Object += [pscustomobject]@{
        'ipAddress' = $wldWorksheet.Cells['H85'].Value
        'dnsName' = $wldWorksheet.Cells['F85'].Value
        'gateway' = $wldWorksheet.Cells['J9'].Value
        'subnetMask' = $managmentMask
    }

$nsxtManagerObject = @()
    $nsxtManagerObject += [pscustomobject]@{
        'name' = $wldWorksheet.Cells['D83'].Value
        networkDetailsSpec = ($nsxtNode1Object | Select-Object -Skip 0)
    }
    $nsxtManagerObject += [pscustomobject]@{
        'name' = $wldWorksheet.Cells['D84'].Value
        networkDetailsSpec = ($nsxtNode2Object | Select-Object -Skip 0)
    }
    $nsxtManagerObject += [pscustomobject]@{
        'name' = $wldWorksheet.Cells['D85'].Value
        networkDetailsSpec = ($nsxtNode3Object | Select-Object -Skip 0)
    }

$nsxtObject = @()
    $nsxtObject += [pscustomobject]@{
        nsxManagerSpecs = $nsxtManagerObject
        'vip' = $wldWorksheet.Cells['H82'].Value
        'vipFqdn' = $wldWorksheet.Cells['F82'].Value
        'licenseKey' = $mgmtWorksheet.Cells['C130'].Value
        'nsxManagerAdminPassword' = $nsxtPassword
    }

$vmnicObject = @()
    $vmnicObject += [pscustomobject]@{
        'id' = $wldWorksheet.Cells['G136'].Value
		'vdsName' = $wldWorksheet.Cells['G138'].Value
    }
    $vmnicObject += [pscustomobject]@{
        'id' = $wldWorksheet.Cells['G137'].Value
		'vdsName' = $wldWorksheet.Cells['G138'].Value
    }

$hostnetworkObject = @()
    $hostnetworkObject += [pscustomobject]@{
        vmNics = $vmnicObject
    }

$hostObject = @()
    $hostObject += [pscustomobject]@{
        'id' = "HOST-1"
        'licenseKey' = $wldWorksheet.Cells['G135'].Value
        hostNetworkSpec = ($hostnetworkObject | Select-Object -Skip 0)
    }
    $hostObject += [pscustomobject]@{
        'id' = "HOST-2"
        'licenseKey' = $wldWorksheet.Cells['G135'].Value
        hostNetworkSpec = ($hostnetworkObject | Select-Object -Skip 0)
    }
    $hostObject += [pscustomobject]@{
        'id' = "HOST-3"
        'licenseKey' = $wldWorksheet.Cells['G135'].Value
        hostNetworkSpec = ($hostnetworkObject | Select-Object -Skip 0)
    }
    $hostObject += [pscustomobject]@{
        'id' = "HOST-4"
        'licenseKey' = $wldWorksheet.Cells['G135'].Value
        hostNetworkSpec = ($hostnetworkObject | Select-Object -Skip 0)
    }

$portgroupObject = @()
    $portgroupObject += [pscustomobject]@{
        'name' = $wldWorksheet.Cells['F10'].Value
		'transportType' = "MANAGEMENT"
    }
    $portgroupObject += [pscustomobject]@{
        'name' = $wldWorksheet.Cells['F10'].Value
		'transportType' = "VSAN"
    }
    $portgroupObject += [pscustomobject]@{
        'name' = $wldWorksheet.Cells['F10'].Value
		'transportType' = "VMOTION"
    }

$vdsObject = @()
    $vdsObject += [pscustomobject]@{
        'name' = $wldWorksheet.Cells['G138'].Value
        portGroupSpecs = $portgroupObject
    }

$nsxTClusterObject = @()
    $nsxTClusterObject += [pscustomobject]@{
        'geneveVlanId' = $wldWorksheet.Cells['D13'].Value
    }

$nsxTClusterObject = @()
    $nsxTClusterObject += [pscustomobject]@{
        'geneveVlanId' = $wldWorksheet.Cells['D13'].Value
    }

$nsxClusterObject = @()
    $nsxClusterObject += [pscustomobject]@{
        nsxTClusterSpec = ($nsxTClusterObject | Select-Object -Skip 0)
    }

$networkObject = @()
    $networkObject += [pscustomobject]@{
        vdsSpecs = $vdsObject
        nsxClusterSpec = ($nsxClusterObject | Select-Object -Skip 0)
    }

$vsanDatastoreObject = @()
    $vsanDatastoreObject += [pscustomobject]@{
        'failuresToTolerate' = "1"
		'licenseKey' = $mgmtWorksheet.Cells['C129'].Value
        'datastoreName' = $wldWorksheet.Cells['G145'].Value
    }

$vsanObject = @()
    $vsanObject += [pscustomobject]@{
        vsanDatastoreSpec = ($vsanDatastoreObject | Select-Object -Skip 0)
    }

$clusterObject = @()
    $clusterObject += [pscustomobject]@{
        'name' = $wldWorksheet.Cells['G147'].Value
        hostSpecs = $hostObject
        datastoreSpec = ($vsanObject | Select-Object -Skip 0)
        networkSpec = ($networkObject | Select-Object -Skip 0)
    }

$computeObject = @()
    $computeObject += [pscustomobject]@{
        clusterSpecs = $clusterObject
    }

$vcenterNetworkObject = @()
    $vcenterNetworkObject += [pscustomobject]@{
        'ipAddress' = $wldWorksheet.Cells['H77'].Value
        'dnsName' = $wldWorksheet.Cells['F77'].Value
        'gateway'= $wldWorksheet.Cells['J9'].Value
        'subnetMask' = $managmentMask
    }

$vcenterObject = @()
    $vcenterObject += [pscustomobject]@{
        'name' = $wldWorksheet.Cells['D77'].Value
        networkDetailsSpec = ($vcenterNetworkObject | Select-Object -Skip 0)
        'rootPassword' = $vCenterPassword
        'datacenterName' = $wldWorksheet.Cells['G146'].Value
    }

$workloadDomainObject = @()
    $workloadDomainObject += [pscustomobject]@{
        'domainName' = $wldWorksheet.Cells['G128'].Value
        'orgName' = $wldWorksheet.Cells['G129'].Value
        vcenterSpec = ($vcenterObject | Select-Object -Skip 0)
        computeSpec = ($computeObject | Select-Object -Skip 0)
        nsxTSpec = ($nsxtObject | Select-Object -Skip 0)
    }

LogMessage " Exporting the $module to $Json"

    $workloadDomainObject | ConvertTo-Json -Depth 11 | Out-File -FilePath $Json
LogMessage " Closing the Excel Workbook: $workbook"
Close-ExcelPackage $pnpWorkbook
LogMessage " Completed the Process of Generating the $module" Yellow