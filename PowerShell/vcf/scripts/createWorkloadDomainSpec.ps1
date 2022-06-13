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
    - Ken Gould - cidrToMask Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.000 (Gary Blake / 2020-05-29) - Initial script creation
    - 1.0.001 (Gary Blake / 2020-06-15) - Minor fixes
    - 2.0.001 (Gary Blake / 2020-07-10) - Updated for VCF 4.0.1 where Named Cells in the Planning and Preparation
                                          Workbook are now available

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
LogMessage " Generating the $module"

$cidr = $pnpWorkbook.Workbook.Names["mgmt_mgmt_cidr"].Value.split("/")
$managmentMask = cidrToMask $cidr[1]

$nsxtNode1Object = @()
    $nsxtNode1Object += [pscustomobject]@{
        'ipAddress' = $pnpWorkbook.Workbook.Names["wld_nsxt_mgra_ip"].Value
        'dnsName' = $pnpWorkbook.Workbook.Names["wld_nsxt_mgra_fqdn"].Value
        'gateway' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_gateway"].Value
        'subnetMask' = $managmentMask
    }

$nsxtNode2Object = @()
    $nsxtNode2Object += [pscustomobject]@{
        'ipAddress' = $pnpWorkbook.Workbook.Names["wld_nsxt_mgrb_ip"].Value
        'dnsName' = $pnpWorkbook.Workbook.Names["wld_nsxt_mgrb_fqdn"].Value
        'gateway' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_gateway"].Value
        'subnetMask' = $managmentMask
    }

$nsxtNode3Object = @()
    $nsxtNode3Object += [pscustomobject]@{
        'ipAddress' = $pnpWorkbook.Workbook.Names["wld_nsxt_mgrc_ip"].Value
        'dnsName' = $pnpWorkbook.Workbook.Names["wld_nsxt_mgrc_fqdn"].Value
        'gateway' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_gateway"].Value
        'subnetMask' = $managmentMask
    }

$nsxtManagerObject = @()
    $nsxtManagerObject += [pscustomobject]@{
        'name' = $pnpWorkbook.Workbook.Names["wld_nsxt_mgra_name"].Value
        networkDetailsSpec = ($nsxtNode1Object | Select-Object -Skip 0)
    }
    $nsxtManagerObject += [pscustomobject]@{
        'name' = $pnpWorkbook.Workbook.Names["wld_nsxt_mgrb_name"].Value
        networkDetailsSpec = ($nsxtNode2Object | Select-Object -Skip 0)
    }
    $nsxtManagerObject += [pscustomobject]@{
        'name' = $pnpWorkbook.Workbook.Names["wld_nsxt_mgrc_name"].Value
        networkDetailsSpec = ($nsxtNode3Object | Select-Object -Skip 0)
    }

$nsxtObject = @()
    $nsxtObject += [pscustomobject]@{
        nsxManagerSpecs = $nsxtManagerObject
        'vip' = $pnpWorkbook.Workbook.Names["wld_nsxt_vip_ip"].Value
        'vipFqdn' = $pnpWorkbook.Workbook.Names["wld_nsxt_vip_fqdn"].Value
        'licenseKey' = $pnpWorkbook.Workbook.Names["nsxt_license"].Value
        'nsxManagerAdminPassword' = $nsxtPassword
    }

$vmnicObject = @()
    $vmnicObject += [pscustomobject]@{
        'id' = $pnpWorkbook.Workbook.Names["wld_vss_mgmt_nic"].Value
        'vdsName' = $pnpWorkbook.Workbook.Names["wld_vds_name"].Value
    }
    $vmnicObject += [pscustomobject]@{
        'id' = $pnpWorkbook.Workbook.Names["wld_vds_mgmt_nic"].Value
        'vdsName' = $pnpWorkbook.Workbook.Names["wld_vds_name"].Value
    }

$hostnetworkObject = @()
    $hostnetworkObject += [pscustomobject]@{
        vmNics = $vmnicObject
    }

if ($pnpWorkbook.Workbook.Names["K8S_Result"].Value -eq "Included") {
    $Global:wldEsxiLicenseKey = $pnpWorkbook.Workbook.Names["esx_license_k8s"].Value
}
elseif ($pnpWorkbook.Workbook.Names["K8S_Result"].Value -eq "Excluded") {
    $Global:wldEsxiLicenseKey = $pnpWorkbook.Workbook.Names["esx_license_std"].Value
}

$hostObject = @()
    $hostObject += [pscustomobject]@{
        'id' = "HOST-1"
        'licenseKey' = $wldEsxiLicenseKey
        hostNetworkSpec = ($hostnetworkObject | Select-Object -Skip 0)
    }
    $hostObject += [pscustomobject]@{
        'id' = "HOST-2"
        'licenseKey' = $wldEsxiLicenseKey
        hostNetworkSpec = ($hostnetworkObject | Select-Object -Skip 0)
    }
    $hostObject += [pscustomobject]@{
        'id' = "HOST-3"
        'licenseKey' = $wldEsxiLicenseKey
        hostNetworkSpec = ($hostnetworkObject | Select-Object -Skip 0)
    }
    $hostObject += [pscustomobject]@{
        'id' = "HOST-4"
        'licenseKey' = $wldEsxiLicenseKey
        hostNetworkSpec = ($hostnetworkObject | Select-Object -Skip 0)
    }

$portgroupObject = @()
    $portgroupObject += [pscustomobject]@{
        'name' = $pnpWorkbook.Workbook.Names["wld_mgmt_pg"].Value
        'transportType' = "MANAGEMENT"
    }
    $portgroupObject += [pscustomobject]@{
        'name' = $pnpWorkbook.Workbook.Names["wld_vmotion_pg"].Value
        'transportType' = "VMOTION"
    }
    $portgroupObject += [pscustomobject]@{
        'name' = $pnpWorkbook.Workbook.Names["wld_vsan_pg"].Value
        'transportType' = "VSAN"
    }

$vdsObject = @()
    $vdsObject += [pscustomobject]@{
        'name' = $pnpWorkbook.Workbook.Names["wld_vds_name"].Value
        portGroupSpecs = $portgroupObject
    }

$nsxTClusterObject = @()
    $nsxTClusterObject += [pscustomobject]@{
        'geneveVlanId' = $pnpWorkbook.Workbook.Names["wld_host_overlay_vlan"].Value
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
        'licenseKey' = $pnpWorkbook.Workbook.Names["vsan_license"].Value
        'datastoreName' = $pnpWorkbook.Workbook.Names["wld_vsan_datastore"].Value
    }

$vsanObject = @()
    $vsanObject += [pscustomobject]@{
        vsanDatastoreSpec = ($vsanDatastoreObject | Select-Object -Skip 0)
    }

$clusterObject = @()
    $clusterObject += [pscustomobject]@{
        'name' = $pnpWorkbook.Workbook.Names["wld_cluster"].Value
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
        'ipAddress' = $pnpWorkbook.Workbook.Names["wld_vc_ip"].Value
        'dnsName' = $pnpWorkbook.Workbook.Names["wld_vc_fdqn"].Value
        'gateway'= $pnpWorkbook.Workbook.Names["mgmt_mgmt_gateway"].Value
        'subnetMask' = $managmentMask
    }

$vcenterObject = @()
    $vcenterObject += [pscustomobject]@{
        'name' = $pnpWorkbook.Workbook.Names["wld_vc_name"].Value
        networkDetailsSpec = ($vcenterNetworkObject | Select-Object -Skip 0)
        'rootPassword' = $vCenterPassword
        'datacenterName' = $pnpWorkbook.Workbook.Names["wld_datacenter"].Value
    }

$workloadDomainObject = @()
    $workloadDomainObject += [pscustomobject]@{
        'domainName' = $pnpWorkbook.Workbook.Names["wld_sddc_domain"].Value
        'orgName' = $pnpWorkbook.Workbook.Names["wld_sddc_org"].Value
        vcenterSpec = ($vcenterObject | Select-Object -Skip 0)
        computeSpec = ($computeObject | Select-Object -Skip 0)
        nsxTSpec = ($nsxtObject | Select-Object -Skip 0)
    }

LogMessage " Exporting the $module to $Json"

$workloadDomainObject | ConvertTo-Json -Depth 11 | Out-File -FilePath $Json
LogMessage " Closing the Excel Workbook: $workbook"
Close-ExcelPackage $pnpWorkbook -ErrorAction SilentlyContinue
LogMessage " Completed the Process of Generating the $module" Yellow