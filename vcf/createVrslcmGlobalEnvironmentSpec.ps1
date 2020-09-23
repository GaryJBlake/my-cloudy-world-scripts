 <#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         CPBU
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 001)
    .Date:          2020-09-18
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

$module = "vRealize Suite Lifecycle Manager Global Environment JSON Spec"

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

$cidr = $pnpWorkbook.Workbook.Names["xreg_seg01_cidr"].Value.split("/")
$vregSegMask = cidrToMask $cidr[1]

$globalEnvironmentObject = @{}

$infraPropertiesObject = New-Object -TypeName psobject
$infraPropertiesObject | Add-Member -NotePropertyName 'acceptEULA' -NotePropertyValue "true"
$infraPropertiesObject | Add-Member -NotePropertyName 'enableTelemetry' -NotePropertyValue "true"
$infraPropertiesObject | Add-Member -NotePropertyName 'adminEmail' -NotePropertyValue $pnpWorkbook.Workbook.Names["xreg_configamdin_email"].Value
$infraPropertiesObject | Add-Member -NotePropertyName 'masterVidmEnabled' -NotePropertyValue "true"
$infraPropertiesObject | Add-Member -NotePropertyName 'dataCenterName' -NotePropertyValue $pnpWorkbook.Workbook.Names["vrslcm_xreg_dc"].Value
$infraPropertiesObject | Add-Member -NotePropertyName 'vCenterName' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_vc_fqdn"].Value
$infraPropertiesObject | Add-Member -NotePropertyName 'vCenterHost' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_vc_fqdn"].Value
$infraPropertiesObject | Add-Member -NotePropertyName 'vcUsername' -NotePropertyValue $pnpWorkbook.Workbook.Names["user_svc_vrslcm_vsphere"].Value
$infraPropertiesObject | Add-Member -NotePropertyName 'vcPassword' -NotePropertyValue "locker:password:8c5cf725-d121-44e1-befd-496ae22a016d:svc-vrslcm-vsphere"
$infraPropertiesObject | Add-Member -NotePropertyName 'cluster' -NotePropertyValue ($pnpWorkbook.Workbook.Names["mgmt_datacenter"].Value+"#"+$pnpWorkbook.Workbook.Names["mgmt_cluster"].Value)
$infraPropertiesObject | Add-Member -NotePropertyName 'network' -NotePropertyValue $pnpWorkbook.Workbook.Names["xreg_seg01_name"].Value
$infraPropertiesObject | Add-Member -NotePropertyName 'netmask' -NotePropertyValue $vregSegMask
$infraPropertiesObject | Add-Member -NotePropertyName 'gateway' -NotePropertyValue $pnpWorkbook.Workbook.Names["xreg_seg01_gateway"].Value
$infraPropertiesObject | Add-Member -NotePropertyName 'dns' -NotePropertyValue $pnpWorkbook.Workbook.Names["xregion_dns1_ip"].Value
$infraPropertiesObject | Add-Member -NotePropertyName 'domain' -NotePropertyValue $pnpWorkbook.Workbook.Names["region_ad_parent_fqdn"].Value
$infraPropertiesObject | Add-Member -NotePropertyName 'searchpath' -NotePropertyValue $pnpWorkbook.Workbook.Names["region_ad_parent_fqdn"].Value
$infraPropertiesObject | Add-Member -NotePropertyName 'ntp' -NotePropertyValue $pnpWorkbook.Workbook.Names["region_ntp1_ip"].Value
$infraPropertiesObject | Add-Member -NotePropertyName 'storage' -NotePropertyValue $pnpWorkbook.Workbook.Names["mgmt_vsan_datastore"].Value
$infraPropertiesObject | Add-Member -NotePropertyName 'diskMode' -NotePropertyValue "thin"
$infraPropertiesObject | Add-Member -NotePropertyName 'folderName' -NotePropertyValue $pnpWorkbook.Workbook.Names["xreg_wsa_vm_folder"].Value
$infraPropertiesObject | Add-Member -NotePropertyName 'resourcePool' -NotePropertyValue ""
$infraPropertiesObject | Add-Member -NotePropertyName 'defaultPassword' -NotePropertyValue "locker:password:44b6b50a-f1ea-4025-9986-64503e60b903:global-env-admin"
$infraPropertiesObject | Add-Member -NotePropertyName 'certificate' -NotePropertyValue "locker:certificate:0e259994-a378-470d-b324-7239c565ee20:xreg-wsa01.rainpole.io"

$infrastructureObject = New-Object -TypeName psobject
$infrastructureObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $infraPropertiesObject

$vipPart1 = New-Object System.Collections.ArrayList
$vipPart1.Add(@{"hostName"=$pnpWorkbook.Workbook.Names["xreg_wsa_virtual_fqdn"].Value;"lockerCertificate"="locker:certificate:0e259994-a378-470d-b324-7239c565ee20:xreg-wsa01.rainpole.io"})
$vipPart1Properties = New-Object -TypeName psobject
$vipPart1Properties | Add-Member -NotePropertyName 'type' -NotePropertyValue "vidm-lb"
$vipPart1Properties | Add-Member -NotePropertyName 'properties' -NotePropertyValue ($vipPart1 | Select-Object -Skip 0)

$vipPart2 = New-Object System.Collections.ArrayList
$vipPart2.Add(@{"ip"=$pnpWorkbook.Workbook.Names["xreg_wsa_delegate_ip"].Value})
$vipPart2Properties = New-Object -TypeName psobject
$vipPart2Properties | Add-Member -NotePropertyName 'type' -NotePropertyValue "vidm-delegate"
$vipPart2Properties | Add-Member -NotePropertyName 'properties' -NotePropertyValue ($vipPart2 | Select-Object -Skip 0)

$clusterVips = New-Object System.Collections.ArrayList
[Array]$clusterVips = $vipPart1Properties,$vipPart2Properties

$clusterVIP = New-Object -TypeName psobject
$clusterVIP | Add-Member -NotePropertyName 'clusterVips' -NotePropertyValue $clusterVips

$nodeA = New-Object System.Collections.ArrayList
$nodeA.Add(@{"hostName"=$pnpWorkbook.Workbook.Names["xreg_wsa_nodea_fqdn"].Value;"cluster"=$pnpWorkbook.Workbook.Names["mgmt_cluster"].Value;"vmName"=$pnpWorkbook.Workbook.Names["xreg_wsa_nodea_hostname"].Value;"ip"=$pnpWorkbook.Workbook.Names["xreg_wsa_nodea_ip"].Value})
$nodeAProperties = New-Object -TypeName psobject
$nodeAProperties | Add-Member -NotePropertyName 'type' -NotePropertyValue "vidm-primary"
$nodeAProperties | Add-Member -NotePropertyName 'properties' -NotePropertyValue ($nodeA | Select-Object -Skip 0)

$nodeB = New-Object System.Collections.ArrayList
$nodeB.Add(@{"hostName"=$pnpWorkbook.Workbook.Names["xreg_wsa_nodeb_fqdn"].Value;"cluster"=$pnpWorkbook.Workbook.Names["mgmt_cluster"].Value;"vmName"=$pnpWorkbook.Workbook.Names["xreg_wsa_nodeb_hostname"].Value;"ip"=$pnpWorkbook.Workbook.Names["xreg_wsa_nodeb_ip"].Value})
$nodeBProperties = New-Object -TypeName psobject
$nodeBProperties | Add-Member -NotePropertyName 'type' -NotePropertyValue "vidm-secondary"
$nodeBProperties | Add-Member -NotePropertyName 'properties' -NotePropertyValue ($nodeB | Select-Object -Skip 0)

$nodeC = New-Object System.Collections.ArrayList
$nodeC.Add(@{"hostName"=$pnpWorkbook.Workbook.Names["xreg_wsa_nodec_fqdn"].Value;"cluster"=$pnpWorkbook.Workbook.Names["mgmt_cluster"].Value;"vmName"=$pnpWorkbook.Workbook.Names["xreg_wsa_nodec_hostname"].Value;"ip"=$pnpWorkbook.Workbook.Names["xreg_wsa_nodec_ip"].Value})
$nodeCProperties = New-Object -TypeName psobject
$nodeCProperties | Add-Member -NotePropertyName 'type' -NotePropertyValue "vidm-secondary"
$nodeCProperties | Add-Member -NotePropertyName 'properties' -NotePropertyValue ($nodeC | Select-Object -Skip 0)

$nodes = New-Object System.Collections.ArrayList
[Array]$nodes = $nodeAProperties,$nodeBProperties,$nodeCProperties

$prodPropertiesObject = New-Object -TypeName psobject
$prodPropertiesObject | Add-Member -NotePropertyName 'syncGroupMembers' -NotePropertyValue "true"
$prodPropertiesObject | Add-Member -NotePropertyName 'vidmAdminPassword' -NotePropertyValue "locker:password:387773c5-2c8f-4518-b4c7-78a5d9fbb6d7:xreg-wsa01-admin"
$prodPropertiesObject | Add-Member -NotePropertyName 'defaultConfigurationUsername' -NotePropertyValue $pnpWorkbook.Workbook.Names["xreg_configamdin_user"].Value
$prodPropertiesObject | Add-Member -NotePropertyName 'defaultConfigurationPassword' -NotePropertyValue "locker:password:ed20dcdb-dacc-4663-a137-64e21b908979:xreg-wsa01-configadmin"

$productsObject = New-Object -TypeName psobject
$productsObject | Add-Member -NotePropertyName 'id' -NotePropertyValue "vidm"
$productsObject | Add-Member -NotePropertyName 'version' -NotePropertyValue "3.2.2"
$productsObject | Add-Member -NotePropertyName 'clusterVIP' -NotePropertyValue ($clusterVIP | Select-Object -Skip 0)
$productsObject | Add-Member -NotePropertyName 'nodes' -NotePropertyValue $nodes
$productsObject | Add-Member -NotePropertyName 'properties' -NotePropertyValue $prodPropertiesObject

$globalEnvironmentObject | Add-Member -NotePropertyName 'environmentName' -NotePropertyValue "globalenvironement"
$globalEnvironmentObject | Add-Member -NotePropertyName 'infrastructure' -NotePropertyValue $infrastructureObject
$globalEnvironmentObject | Add-Member -NotePropertyName 'products' -NotePropertyValue $productsObject

LogMessage " Exporting the $module to $Json"

$globalEnvironmentObject | ConvertTo-Json -Depth 11 | Out-File -FilePath $Json
LogMessage " Closing the Excel Workbook: $workbook"
#Close-ExcelPackage $pnpWorkbook -ErrorAction SilentlyContinue
LogMessage " Completed the Process of Generating the $module" Yellow