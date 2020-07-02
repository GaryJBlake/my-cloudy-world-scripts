 <#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         HCI BU
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 001)
    .Date:          2020-06-015
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function
    - Ken Gould - cidrToMask Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.000 (Gary Blake / 2020-06-02) - Initial script creation
    - 1.0.001 (Gary Blake / 2020-06-15) - Minor fixes

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of creating the JSON Spec needed for creating a Managementy Domain with VMware
    Cloud Builder. It uses the Planning and Preparation Workbook to obtain the required details needed in the JSON file
    that can then be consumed via the VMware Cloud Foundation Public API or PowerVCF.

    .EXAMPLE

    .\createManagementDomainSpec.ps1 -workbook E:\pnpWorkbook.xlsx -json E:\MyLab\sfo\sfo-managementDomain.json -DefaultPassword VMw@re1! -nsxtPassword VMw@re1!
#>
 
 Param(
    [Parameter(Mandatory=$true)]
        [String]$Workbook,
    [Parameter(Mandatory=$true)]
        [String]$Json,
    [Parameter(Mandatory=$true)]
        [String]$nsxtPassword,
    [Parameter(Mandatory=$true)]
        [String]$defaultPassword
)

$module = "Management Domain JSON Spec"

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
if ($pnpWorkbook.Workbook.Names["vcf_version"].Value -ne "v4.0.1") {
    LogMessage " Planning and Prepatation Workbook Provided Not Supported" Red 
    Break
}

LogMessage " Extracting Worksheet Data from the Excel Workbook"
LogMessage " Generating the $module"

$cidr = $pnpWorkbook.Workbook.Names["mgmt_mgmt_cidr"].Value.split("/")
$managmentMask = cidrToMask $cidr[1]

$ntpServers = New-Object System.Collections.ArrayList
    if ($pnpWorkbook.Workbook.Names["region_ntp2_ip"].Value -eq "n/a") {
        [Array]$ntpServers = $pnpWorkbook.Workbook.Names["region_ntp1_ip"].Value
    }
    else {
        [Array]$ntpServers = $pnpWorkbook.Workbook.Names["region_ntp1_ip"].Value,$pnpWorkbook.Workbook.Names["region_ntp2_ip"].Value
    }

    $dnsObject = @()
        $dnsObject += [pscustomobject]@{
            'domain' = $pnpWorkbook.Workbook.Names["region_ad_child"].Value
            'subdomain' = $pnpWorkbook.Workbook.Names["region_ad_child"].Value
            'nameserver' = $pnpWorkbook.Workbook.Names["region_dns1_ip"].Value
            'secondaryNameserver' = $pnpWorkbook.Workbook.Names["region_dns1_ip"].Value
        }

    $rootUserObject = @()
        $rootUserObject += [pscustomobject]@{
            'username' = "root"
            'password' = $defaultPassword
        }

    $secondUserObject = @()
        $secondUserObject += [pscustomobject]@{
            'username' = "vcf"
            'password' = $defaultPassword
        }

    $restApiUserObject = @()
        $restApiUserObject += [pscustomobject]@{
            'username' = "admin"
            'password' = $defaultPassword
        }

    $sddcManagerObject = @()
        $sddcManagerObject += [pscustomobject]@{
            'hostname' = $pnpWorkbook.Workbook.Names["sddc_mgr_hostname"].Value
            'ipAddress' = $pnpWorkbook.Workbook.Names["sddc_mgr_ip"].Value
            'netmask' = $managmentMask
            rootUserCredentials = ($rootUserObject | Select-Object -Skip 0)
            restApiCredentials = ($restApiUserObject | Select-Object -Skip 0)
            secondUserCredentials = ($secondUserObject | Select-Object -Skip 0)
        }
    
    $vmnics = New-Object System.Collections.ArrayList
    [Array]$vmnics = $($pnpWorkbook.Workbook.Names["primary_vds_vmnics"].Value.Split(',')[0]),$($pnpWorkbook.Workbook.Names["primary_vds_vmnics"].Value.Split(',')[1])

    $networks = New-Object System.Collections.ArrayList
    [Array]$networks = "MANAGEMENT","VMOTION","VSAN","UPLINK01","UPLINK02","NSXT_EDGE_TEP"

    $vmotionIpObject = @()
        $vmotionIpObject += [pscustomobject]@{
            'startIpAddress' = $pnpWorkbook.Workbook.Names["mgmt_vmotion_pool_start"].Value
            'endIpAddress' = $pnpWorkbook.Workbook.Names["mgmt_vmotion_pool_end"].Value
        }

    $vsanIpObject = @()
        $vsanIpObject += [pscustomobject]@{
            'startIpAddress' = $pnpWorkbook.Workbook.Names["mgmt_vsan_pool_start"].Value
            'endIpAddress' = $pnpWorkbook.Workbook.Names["mgmt_vsan_pool_end"].Value
        }

    $networkObject = @()
        $networkObject += [pscustomobject]@{
            'networkType' = "MANAGEMENT"
            'subnet' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_cidr"].Value
            'vlanId' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_vlan"].Value -as [string]
            'mtu' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_mtu"].Value -as [string]
            'gateway' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_gateway"].Value
            'portGroupKey' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_pg"].Value
            'association' = $pnpWorkbook.Workbook.Names["mgmt_datacenter"].Value
        }
        $networkObject += [pscustomobject]@{
            'networkType' = "VMOTION"
            'subnet' = $pnpWorkbook.Workbook.Names["mgmt_vmotion_cidr"].Value
            includeIpAddressRanges = $vmotionIpObject
            'vlanId' = $pnpWorkbook.Workbook.Names["mgmt_vmotion_vlan"].Value -as [string]
            'mtu' = $pnpWorkbook.Workbook.Names["mgmt_vmotion_mtu"].Value -as [string]
            'gateway' = $pnpWorkbook.Workbook.Names["mgmt_vmotion_gateway"].Value
            'portGroupKey' = $pnpWorkbook.Workbook.Names["mgmt_vmotion_pg"].Value
            'association' = $pnpWorkbook.Workbook.Names["mgmt_datacenter"].Value
        }
        $networkObject += [pscustomobject]@{
            'networkType' = "VSAN"
            'subnet' = $pnpWorkbook.Workbook.Names["mgmt_vsan_cidr"].Value
            includeIpAddressRanges = $vsanIpObject
            'vlanId' = $pnpWorkbook.Workbook.Names["mgmt_vsan_vlan"].Value
            'mtu' = $pnpWorkbook.Workbook.Names["mgmt_vsan_mtu"].Value -as [string]
            'gateway' = $pnpWorkbook.Workbook.Names["mgmt_vsan_gateway"].Value
            'portGroupKey' = $pnpWorkbook.Workbook.Names["mgmt_vsan_pg"].Value
            'association' = $pnpWorkbook.Workbook.Names["mgmt_datacenter"].Value
        }
        $networkObject += [pscustomobject]@{
            'networkType' = "UPLINK01"
            'subnet' = $pnpWorkbook.Workbook.Names["mgmt_uplink01_cidr"].Value
            'vlanId' = $pnpWorkbook.Workbook.Names["mgmt_uplink01_vlan"].Value -as [string]
            'mtu' = $pnpWorkbook.Workbook.Names["mgmt_uplink01_mtu"].Value -as [string]
            'gateway' = $pnpWorkbook.Workbook.Names["mgmt_uplink01_gateway"].Value
            'portGroupKey' = $pnpWorkbook.Workbook.Names["mgmt_uplink01_pg"].Value
            'association' = $pnpWorkbook.Workbook.Names["mgmt_datacenter"].Value
        }
        $networkObject += [pscustomobject]@{
            'networkType' = "UPLINK02"
            'subnet' = $pnpWorkbook.Workbook.Names["mgmt_uplink02_cidr"].Value
            'vlanId' = $pnpWorkbook.Workbook.Names["mgmt_uplink02_vlan"].Value -as [string]
            'mtu' = $pnpWorkbook.Workbook.Names["mgmt_uplink02_mtu"].Value -as [string]
            'gateway' = $pnpWorkbook.Workbook.Names["mgmt_uplink02_gateway"].Value
            'portGroupKey' = $pnpWorkbook.Workbook.Names["mgmt_uplink02_pg"].Value
            'association' = $pnpWorkbook.Workbook.Names["mgmt_datacenter"].Value
        }
        $networkObject += [pscustomobject]@{
            'networkType' = "NSXT_EDGE_TEP"
            'subnet' = $pnpWorkbook.Workbook.Names["mgmt_edge_overlay_cidr"].Value
            'vlanId' = $pnpWorkbook.Workbook.Names["mgmt_edge_overlay_vlan"].Value -as [string]
            'mtu' = $pnpWorkbook.Workbook.Names["mgmt_edge_overlay_mtu"].Value -as [string]
            'gateway' = $pnpWorkbook.Workbook.Names["mgmt_edge_overlay_gateway"].Value
            'association' = $pnpWorkbook.Workbook.Names["mgmt_datacenter"].Value
        }
        $networkObject += [pscustomobject]@{
            'networkType' = "REGION_SPECIFIC"
            'subnet' = $pnpWorkbook.Workbook.Names["reg_seg01_cidr"].Value
            'vlanId' = "0"
            'mtu' = $pnpWorkbook.Workbook.Names["primary_vds_mtu"].Value -as [string]
            'gateway' = $pnpWorkbook.Workbook.Names["reg_seg01_gateway"].Value
            'association' = $pnpWorkbook.Workbook.Names["mgmt_datacenter"].Value
        }
        $networkObject += [pscustomobject]@{
            'networkType' = "X_REGION"
            'subnet' = $pnpWorkbook.Workbook.Names["xreg_seg01_cidr"].Value
            'vlanId' = "0"
            'mtu' = $pnpWorkbook.Workbook.Names["primary_vds_mtu"].Value -as [string]
            'gateway' = $pnpWorkbook.Workbook.Names["xreg_seg01_gateway"].Value
            'association' = $pnpWorkbook.Workbook.Names["mgmt_datacenter"].Value
        }


    $nsxtManagerObject = @()
        $nsxtManagerObject += [pscustomobject]@{
            'hostname' = $pnpWorkbook.Workbook.Names["mgmt_nsxt_mgra_hostname"].Value
            'ip' = $pnpWorkbook.Workbook.Names["mgmt_nsxt_mgra_ip"].Value
        }
    $nsxtManagerObject += [pscustomobject]@{
            'hostname' = $pnpWorkbook.Workbook.Names["mgmt_nsxt_mgrb_hostname"].Value
            'ip' = $pnpWorkbook.Workbook.Names["mgmt_nsxt_mgrb_ip"].Value
        }
    $nsxtManagerObject += [pscustomobject]@{
            'hostname' = $pnpWorkbook.Workbook.Names["mgmt_nsxt_mgrc_hostname"].Value
            'ip' = $pnpWorkbook.Workbook.Names["mgmt_nsxt_mgrc_ip"].Value
        }

    $vlanTransportZoneObject = @()
        $vlanTransportZoneObject += [pscustomobject]@{
            'zoneName' = $pnpWorkbook.Workbook.Names["mgmt_sddc_domain"].Value+"-tz-vlan01"
            'networkName' = "netName-vlan"
        }

    $overlayTransportZoneObject = @()
        $overlayTransportZoneObject += [pscustomobject]@{
            'zoneName' = $pnpWorkbook.Workbook.Names["mgmt_sddc_domain"].Value+"-tz-overlay01"
            'networkName' = "netName-overlay"
        }

    $edgeNode01interfaces = @()
        $edgeNode01interfaces += [pscustomobject]@{
            'name' = $pnpWorkbook.Workbook.Names["mgmt_sddc_domain"].Value+"-uplink01-tor1"
            'interfaceCidr' = $pnpWorkbook.Workbook.Names["mgmt_en1_uplink1_interface_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["mgmt_uplink01_cidr"].Value.split("/")[-1]
        }
        $edgeNode01interfaces += [pscustomobject]@{
            'name' = $pnpWorkbook.Workbook.Names["mgmt_sddc_domain"].Value+"-uplink01-tor2"
            'interfaceCidr' = $pnpWorkbook.Workbook.Names["mgmt_en1_uplink2_interface_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["mgmt_uplink02_cidr"].Value.split("/")[-1]
        }

    $edgeNode02interfaces = @()
        $edgeNode02interfaces += [pscustomobject]@{
            'name' = $pnpWorkbook.Workbook.Names["mgmt_sddc_domain"].Value+"-uplink01-tor1"
            'interfaceCidr' = $pnpWorkbook.Workbook.Names["mgmt_en2_uplink1_interface_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["mgmt_uplink01_cidr"].Value.split("/")[-1]
        }
        $edgeNode02interfaces += [pscustomobject]@{
            'name' = $pnpWorkbook.Workbook.Names["mgmt_sddc_domain"].Value+"-uplink01-tor2"
            'interfaceCidr' = $pnpWorkbook.Workbook.Names["mgmt_en2_uplink2_interface_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["mgmt_uplink02_cidr"].Value.split("/")[-1]
        
        }

    $edgeNodeObject = @()
        $edgeNodeObject += [pscustomobject]@{
            'edgeNodeName' = $pnpWorkbook.Workbook.Names["mgmt_en1_hostname"].Value
            'edgeNodeHostname' = $pnpWorkbook.Workbook.Names["mgmt_en1_fqdn"].Value
            'managementCidr' = $pnpWorkbook.Workbook.Names["mgmt_en1_mgmt_interface_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["mgmt_mgmt_cidr"].Value.split("/")[-1]
            'edgeVtep1Cidr' = $pnpWorkbook.Workbook.Names["mgmt_en1_edge_overlay_interface_ip_1"].Value+"/"+$pnpWorkbook.Workbook.Names["mgmt_edge_overlay_cidr"].Value.split("/")[-1]
            'edgeVtep2Cidr' = $pnpWorkbook.Workbook.Names["mgmt_en1_edge_overlay_interface_ip_2"].Value+"/"+$pnpWorkbook.Workbook.Names["mgmt_edge_overlay_cidr"].Value.split("/")[-1]
            interfaces = $edgeNode01interfaces
        }
        $edgeNodeObject += [pscustomobject]@{
            'edgeNodeName' = $pnpWorkbook.Workbook.Names["mgmt_en2_hostname"].Value
            'edgeNodeHostname' = $pnpWorkbook.Workbook.Names["mgmt_en2_fqdn"].Value
            'managementCidr' = $pnpWorkbook.Workbook.Names["mgmt_en2_mgmt_interface_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["mgmt_mgmt_cidr"].Value.split("/")[-1]
            'edgeVtep1Cidr' = $pnpWorkbook.Workbook.Names["mgmt_en2_edge_overlay_interface_ip_1"].Value+"/"+$pnpWorkbook.Workbook.Names["mgmt_edge_overlay_cidr"].Value.split("/")[-1]
            'edgeVtep2Cidr' = $pnpWorkbook.Workbook.Names["mgmt_en2_edge_overlay_interface_ip_2"].Value+"/"+$pnpWorkbook.Workbook.Names["mgmt_edge_overlay_cidr"].Value.split("/")[-1]
            interfaces = $edgeNode02interfaces
        }

    $edgeServicesObject = @()
        $edgeServicesObject += [pscustomobject]@{
            'tier0GatewayName' = $pnpWorkbook.Workbook.Names["mgmt_sddc_domain"].Value+"-ec01-t0-gw01"
            'tier1GatewayName' = $pnpWorkbook.Workbook.Names["mgmt_sddc_domain"].Value+"-ec01-t1-gw01"
        }

    $bgpNeighboursObject = @()
        $bgpNeighboursObject += [pscustomobject]@{
            'neighbourIp' = $pnpWorkbook.Workbook.Names["mgmt_tor1_peer_ip"].Value
            'autonomousSystem' = $pnpWorkbook.Workbook.Names["mgmt_tor1_peer_asn"].Value
            'password' = $pnpWorkbook.Workbook.Names["mgmt_tor1_peer_bgp_password"].Value
        }
        $bgpNeighboursObject += [pscustomobject]@{
            'neighbourIp' = $pnpWorkbook.Workbook.Names["mgmt_tor2_peer_ip"].Value
            'autonomousSystem' = $pnpWorkbook.Workbook.Names["mgmt_tor2_peer_asn"].Value
            'password' = $pnpWorkbook.Workbook.Names["mgmt_tor2_peer_bgp_password"].Value
        }

    $nsxtEdgeObject = @()
        $nsxtEdgeObject += [pscustomobject]@{
            'edgeClusterName' = $pnpWorkbook.Workbook.Names["mgmt_ec_name"].Value
            'edgeRootPassword' = $nsxtPassword
            'edgeAdminPassword' = $nsxtPassword
            'edgeAuditPassword' = $nsxtPassword
            'edgeFormFactor' = $pnpWorkbook.Workbook.Names["mgmt_nsxt_mgr_formfactor"].Value.ToUpper()
            'tier0ServicesHighAvailability' = "ACTIVE_ACTIVE"
            'asn' = $pnpWorkbook.Workbook.Names["mgmt_en_asn"].Value
            edgeServicesSpecs = ($edgeServicesObject | Select-Object -Skip 0)
            edgeNodeSpecs = $edgeNodeObject
            bgpNeighbours = $bgpNeighboursObject
        }

    $logicalSegmentsObject = @()
        $logicalSegmentsObject += [pscustomobject]@{
            'name' = $pnpWorkbook.Workbook.Names["reg_seg01_name"].Value
            'networkType' = "REGION_SPECIFIC"
        }
        $logicalSegmentsObject += [pscustomobject]@{
            'name' = $pnpWorkbook.Workbook.Names["xreg_seg01_name"].Value
            'networkType' = "X_REGION"
        }

    $nsxtObject = @()
        $nsxtObject += [pscustomobject]@{
            'nsxtManagerSize' = $pnpWorkbook.Workbook.Names["mgmt_nsxt_mgr_formfactor"].Value
            nsxtManagers = $nsxtManagerObject
            'rootNsxtManagerPassword' = $nsxtPassword
            'nsxtAdminPassword' = $nsxtPassword
            'nsxtAuditPassword' = $nsxtPassword
            'rootLoginEnabledForNsxtManager' = "true"
            'sshEnabledForNsxtManager' = "true"
            overLayTransportZone = ($overlayTransportZoneObject | Select-Object -Skip 0)
            vlanTransportZone = ($vlanTransportZoneObject | Select-Object -Skip 0)
            'vip' = $pnpWorkbook.Workbook.Names["mgmt_nsxt_vip_ip"].Value
            'vipFqdn' = $pnpWorkbook.Workbook.Names["mgmt_nsxt_vip_fqdn"].Value
            'nsxtLicense' = $pnpWorkbook.Workbook.Names["nsxt_license"].Value
            'transportVlanId' = $pnpWorkbook.Workbook.Names["mgmt_host_overlay_vlan"].Value
            nsxtEdgeSpec = ($nsxtEdgeObject | Select-Object -Skip 0)
            logicalSegments = $logicalSegmentsObject
        }

    $excelvsanDedup = $pnpWorkbook.Workbook.Names["mgmt_vsan_dedup"].Value
    if ($excelvsanDedup -eq "No") {
        $vsanDedup = $false
    }
    elseif ($excelvsanDedup -eq "Yes") {
        $vsanDedup = $true
    }

    $vsanObject = @()
        $vsanObject += [pscustomobject]@{
            'vsanName' = "vsan-1"
            'licenseFile' = $pnpWorkbook.Workbook.Names["vsan_license"].Value
            'vsanDedup' = $vsanDedup
            'datastoreName' = $pnpWorkbook.Workbook.Names["mgmt_vsan_datastore"].Value
        }

    $niocObject = @()
        $niocObject += [pscustomobject]@{
            'trafficType' = "VSAN"
            'value' = "HIGH"
        }
        $niocObject += [pscustomobject]@{
            'trafficType' = "VMOTION"
            'value' = "LOW"
        }
        $niocObject += [pscustomobject]@{
            'trafficType' = "VDP"
            'value' = "LOW"
        }
        $niocObject += [pscustomobject]@{
            'trafficType'= "VIRTUALMACHINE"
            'value'= "HIGH"
        }
        $niocObject += [pscustomobject]@{
            'trafficType'= "MANAGEMENT"
            'value' = "NORMAL"
        }
        $niocObject += [pscustomobject]@{
            'trafficType' = "NFS"
            'value' = "LOW"
        }
        $niocObject += [pscustomobject]@{
            'trafficType' = "HBR"
            'value' = "LOW"
        }
        $niocObject += [pscustomobject]@{
            'trafficType' = "FAULTTOLERANCE"
            'value' = "LOW"
        }
        $niocObject += [pscustomobject]@{
            'trafficType' = "ISCSI"
            'value' = "LOW"
        }

    $dvsObject = @()
        $dvsObject += [pscustomobject]@{
            'mtu' = $pnpWorkbook.Workbook.Names["primary_vds_mtu"].Value
            niocSpecs = $niocObject
            'dvsName' = $pnpWorkbook.Workbook.Names["primary_vds_name"].Value
            'vmnics' = $vmnics
            'networks' = $networks
        }

    $vmFolderObject = @()
        $vmFOlderObject += [pscustomobject]@{
            'MANAGEMENT' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_vm_folder"].Value
            'NETWORKING' = $pnpWorkbook.Workbook.Names["mgmt_nsx_vm_folder"].Value
            'EDGENODES' = $pnpWorkbook.Workbook.Names["mgmt_edge_vm_folder"].Value
        }

    if ($pnpWorkbook.Workbook.Names["mgmt_evc_mode"].Value -eq "n/a") {
        $evcMode = ""
    }
    else {
        $evcMode = $pnpWorkbook.Workbook.Names["mgmt_evc_mode"].Value
    }

    $resourcePoolObject = @()
        $resourcePoolObject += [pscustomobject]@{
            'type' = "management"
            'name' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_rp"].Value
            'cpuSharesLevel' = "high"
            'cpuSharesValue' = "0" -as [int]
            'cpuLimit' = "-1" -as [int]
            'cpuReservationExpandable' = $true
            'cpuReservationPercentage' = "0" -as [int]
            'memorySharesLevel' = "normal"
            'memorySharesValue' = "0" -as [int]
            'memoryLimit' = "-1" -as [int]
            'memoryReservationExpandable' = $true
            'memoryReservationPercentage' = "0" -as [int]   
        }
        $resourcePoolObject += [pscustomobject]@{
            'type' = "network"
            'name' = $pnpWorkbook.Workbook.Names["mgmt_nsx_rp"].Value
            'cpuSharesLevel' = "high"
            'cpuSharesValue' = "0" -as [int]
            'cpuLimit' = "-1" -as [int]
            'cpuReservationExpandable' = $true
            'cpuReservationPercentage' = "0" -as [int]
            'memorySharesLevel' = "normal"
            'memorySharesValue' = "0" -as [int]
            'memoryLimit' = "-1" -as [int]
            'memoryReservationExpandable' = $true
            'memoryReservationPercentage' = "0" -as [int]  
        }
        $resourcePoolObject += [pscustomobject]@{
            'type' = "compute"
            'name' = $pnpWorkbook.Workbook.Names["mgmt_user_edge_rp"].Value
            'cpuSharesLevel' = "normal"
            'cpuSharesValue' = "0" -as [int]
            'cpuLimit' = "-1" -as [int]
            'cpuReservationExpandable' = $true
            'cpuReservationPercentage' = "0" -as [int]
            'memorySharesLevel' = "normal"
            'memorySharesValue' = "0" -as [int]
            'memoryLimit' = "-1" -as [int]
            'memoryReservationExpandable' = $true
            'memoryReservationPercentage' = "0" -as [int]  
        }
        $resourcePoolObject += [pscustomobject]@{
            'type' = "compute"
            'name' = $pnpWorkbook.Workbook.Names["mgmt_user_vm_rp"].Value
            'cpuSharesLevel' = "normal"
            'cpuSharesValue' = "0" -as [int]
            'cpuLimit' = "-1" -as [int]
            'cpuReservationExpandable' = $true
            'cpuReservationPercentage' = "0" -as [int]
            'memorySharesLevel' = "normal"
            'memorySharesValue' = "0" -as [int]
            'memoryLimit' = "-1" -as [int]
            'memoryReservationExpandable' = $true
            'memoryReservationPercentage' = "0" -as [int]
        }

    if ($pnpWorkbook.Workbook.Names["Consolidated_Result"].Value -eq "Excluded") {
        $clusterObject = @()
            $clusterObject += [pscustomobject]@{
                vmFolders = ($vmFolderObject | Select-Object -Skip 0)
                'clusterName' = $pnpWorkbook.Workbook.Names["mgmt_cluster"].Value
                'clusterEvcMode' = $evcMode
            }
    }
    else {
        $clusterObject = @()
        $clusterObject += [pscustomobject]@{
            vmFolders = ($vmFolderObject | Select-Object -Skip 0)
            'clusterName' = $pnpWorkbook.Workbook.Names["mgmt_cluster"].Value
            'clusterEvcMode' = $evcMode
            resourcePoolSpecs = $resourcePoolObject
        }
    }

    $ssoObject = @()
        $ssoObject += [pscustomobject]@{
            'ssoSiteName' = $pnpWorkbook.Workbook.Names["mgmt_sddc_domain"].Value
            'ssoDomainPassword' = $defaultPassword
            'ssoDomain' = "vsphere.local"
            'isJoinSsoDomain' = $false
        }

    $pscObject = @()
        $pscObject += [pscustomobject]@{
            'pscId' = "psc-1"
            'vcenterId' = "vcenter-1"
            pscSsoSpec =  ($ssoObject | Select-Object -Skip 0)
            'adminUserSsoPassword' = $defaultPassword
        }

    $vcenterObject = @()
        $vcenterObject += [pscustomobject]@{
            'vcenterIp' = $pnpWorkbook.Workbook.Names["mgmt_vc_ip"].Value
            'vcenterHostname' = $pnpWorkbook.Workbook.Names["mgmt_vc_hostname"].Value
            'vcenterId' = "vcenter-1"
            'licenseFile' = $pnpWorkbook.Workbook.Names["vc_license"].Value
            'rootVcenterPassword' = $defaultPassword
            'vmSize' = $pnpWorkbook.Workbook.Names["mgmt_vc_size"].Value
        }

    $hostCredentialsObject = @()
        $hostCredentialsObject += [pscustomobject]@{
            'username' = "root"
            'password' = $defaultPassword
        }

    $ipAddressPrivate01Object = @()
        $ipAddressPrivate01Object += [pscustomobject]@{
            'subnet' = $managmentMask
            'cidr' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_cidr"].Value
            'ipAddress' = $pnpWorkbook.Workbook.Names["mgmt_host1_ip"].Value
            'gateway' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_gateway"].Value
        }

    $ipAddressPrivate02Object = @()
        $ipAddressPrivate02Object += [pscustomobject]@{
            'subnet' = $managmentMask
            'cidr' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_cidr"].Value
            'ipAddress' = $pnpWorkbook.Workbook.Names["mgmt_host2_ip"].Value
            'gateway' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_gateway"].Value
        }

    $ipAddressPrivate03Object = @()
        $ipAddressPrivate03Object += [pscustomobject]@{
            'subnet' = $managmentMask
            'cidr' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_cidr"].Value
            'ipAddress' = $pnpWorkbook.Workbook.Names["mgmt_host3_ip"].Value
            'gateway' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_gateway"].Value
        }

    $ipAddressPrivate04Object = @()
        $ipAddressPrivate04Object += [pscustomobject]@{
            'subnet' = $managmentMask
            'cidr' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_cidr"].Value
            'ipAddress' = $pnpWorkbook.Workbook.Names["mgmt_host4_ip"].Value
            'gateway' = $pnpWorkbook.Workbook.Names["mgmt_mgmt_gateway"].Value
        }

    $HostObject = @()
        $HostObject += [pscustomobject]@{
            'hostname' = $pnpWorkbook.Workbook.Names["mgmt_host1_hostname"].Value
            'vSwitch' = $pnpWorkbook.Workbook.Names["mgmt_vss_switch"].Value
            'serverId' = "host-0"
            'association' = $pnpWorkbook.Workbook.Names["mgmt_datacenter"].Value
            credentials = ($hostCredentialsObject | Select-Object -Skip 0)
            ipAddressPrivate = ($ipAddressPrivate01Object | Select-Object -Skip 0)
        }
        $HostObject += [pscustomobject]@{
            'hostname' = $pnpWorkbook.Workbook.Names["mgmt_host2_hostname"].Value
            'vSwitch' = $pnpWorkbook.Workbook.Names["mgmt_vss_switch"].Value
            'serverId' = "host-1"
            'association' = $pnpWorkbook.Workbook.Names["mgmt_datacenter"].Value
            credentials = ($hostCredentialsObject | Select-Object -Skip 0)
            ipAddressPrivate = ($ipAddressPrivate02Object | Select-Object -Skip 0)
        }
        $HostObject += [pscustomobject]@{
            'hostname' = $pnpWorkbook.Workbook.Names["mgmt_host3_hostname"].Value
            'vSwitch' = $pnpWorkbook.Workbook.Names["mgmt_vss_switch"].Value
            'serverId' = "host-2"
            'association' = $pnpWorkbook.Workbook.Names["mgmt_datacenter"].Value
            credentials = ($hostCredentialsObject | Select-Object -Skip 0)
            ipAddressPrivate = ($ipAddressPrivate03Object | Select-Object -Skip 0)
        }
        $HostObject += [pscustomobject]@{
            'hostname' = $pnpWorkbook.Workbook.Names["mgmt_host4_hostname"].Value
            'vSwitch' = $pnpWorkbook.Workbook.Names["mgmt_vss_switch"].Value
            'serverId' = "host-3"
            'association' = $pnpWorkbook.Workbook.Names["mgmt_datacenter"].Value
            credentials = ($hostCredentialsObject | Select-Object -Skip 0)
            ipAddressPrivate = ($ipAddressPrivate04Object | Select-Object -Skip 0)
        }

    $excluded = New-Object System.Collections.ArrayList
    [Array]$excluded = "NSX-V"

    $ceipState = $pnpWorkbook.Workbook.Names["mgmt_ceip_status"].Value
    if ($ceipState -eq "Enabled") {
        $ceipEnabled = "$true"
    }
    else {
        $ceipEnabled = "$false"
    }

    $managementDomainObject = @()
        $managementDomainObject += [pscustomobject]@{
            'taskName' = "workflowconfig/workflowspec-ems.json"
            'sddcId' = $pnpWorkbook.Workbook.Names["mgmt_sddc_domain"].Value
            'ceipEnabled' = $ceipEnabled
            'managementPoolName' = $pnpWorkbook.Workbook.Names["mgmt_pool_name"].Value
            'dvSwitchVersion' = "7.0.0"
            'skipEsxThumbprintValidation' = $true
            'esxLicense' = $pnpWorkbook.Workbook.Names["esx_license_std"].Value
            'excludedComponents' = $excluded
            ntpServers = $ntpServers
            dnsSpec = ($dnsObject | Select-Object -Skip 0)
            sddcManagerSpec = ($sddcManagerObject | Select-Object -Skip 0)
            networkSpecs = $networkObject
            nsxtSpec = ($nsxtObject | Select-Object -Skip 0)
            vsanSpec = ($vsanObject | Select-Object -Skip 0)
            dvsSpecs = $dvsObject
            clusterSpec = ($clusterObject | Select-Object -Skip 0)
            pscSpecs = $pscObject
            vcenterSpec = ($vcenterObject | Select-Object -Skip 0)
            hostSpecs = $hostObject
        }

LogMessage " Exporting the $module to $Json"

$managementDomainObject | ConvertTo-Json -Depth 12 | Out-File -FilePath $Json
LogMessage " Closing the Excel Workbook: $workbook"
Close-ExcelPackage $pnpWorkbook -ErrorAction SilentlyContinue
LogMessage " Completed the Process of Generating the $module" Yellow