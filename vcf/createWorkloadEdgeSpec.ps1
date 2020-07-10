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

    - 1.0.000 (Gary Blake / 2020-06-01) - Initial script creation
    - 1.0.001 (Gary Blake / 2020-06-15) - Minor fixes
    - 2.0.001 (Gary Blake / 2020-07-10) - Updated for VCF 4.0.1 where Named Cells in the Planning and Preparation
                                          Workbook are now available

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of creating the JSON Spec needed for creating a NSX-T Edge Cluster in SDDC 
    Manager. It uses the Planning and Preparation Workbook to obtain the required details needed in the JSON file
    that can then be consumed via the VMware Cloud Foundation Public API or PowerVCF.

    .EXAMPLE

    .\createWorkloadEdgeSpec.ps1 -Workbook E:\pnpWorkbook.xlsx -Json E:\MyLab\sfo\sfo-workloadEdge.json -nsxtPassword VMw@re1!VMw@re1!
#>
 
 Param(
    [Parameter(Mandatory=$true)]
        [String]$Workbook,
    [Parameter(Mandatory=$true)]
        [String]$Json,
    [Parameter(Mandatory=$true)]
        [String]$nsxtPassword
)

$module = "NSX-T Edge Cluster JSON Spec"

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
LogMessage " Generating the $module"

$uplink01NetworkObject = @()
$uplink01NetworkObject += [pscustomobject]@{
    'uplinkVlan' = $pnpWorkbook.Workbook.Names["wld_uplink1_vlan"].Value -as [int]
    'uplinkInterfaceIP' = $pnpWorkbook.Workbook.Names["wld_en1_uplink1_interface_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["wld_uplink1_cidr"].Value.split("/")[-1]
    'peerIP' = $pnpWorkbook.Workbook.Names["wld_tor1_peer_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["wld_uplink1_cidr"].Value.split("/")[-1]
    'asnPeer' = $pnpWorkbook.Workbook.Names["wld_tor1_peer_asn"].Value -as [int]
    'bgpPeerPassword' = $pnpWorkbook.Workbook.Names["wld_tor1_peer_bgp_password"].Value
}
$uplink01NetworkObject += [pscustomobject]@{
    'uplinkVlan' = $pnpWorkbook.Workbook.Names["wld_uplink2_vlan"].Value -as [int]
    'uplinkInterfaceIP' = $pnpWorkbook.Workbook.Names["wld_en1_uplink2_interface_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["wld_uplink2_cidr"].Value.split("/")[-1]
    'peerIP' = $pnpWorkbook.Workbook.Names["wld_tor2_peer_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["wld_uplink2_cidr"].Value.split("/")[-1]
    'asnPeer' = $pnpWorkbook.Workbook.Names["wld_tor2_peer_asn"].Value -as [int]
    'bgpPeerPassword' = $pnpWorkbook.Workbook.Names["wld_tor2_peer_bgp_password"].Value
}

$uplink02NetworkObject = @()
$uplink02NetworkObject += [pscustomobject]@{
    'uplinkVlan' = $pnpWorkbook.Workbook.Names["wld_uplink1_vlan"].Value -as [int]
    'uplinkInterfaceIP' = $pnpWorkbook.Workbook.Names["wld_en2_uplink1_interface_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["wld_uplink1_cidr"].Value.split("/")[-1]
    'peerIP' = $pnpWorkbook.Workbook.Names["wld_tor1_peer_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["wld_uplink1_cidr"].Value.split("/")[-1]
    'asnPeer' = $pnpWorkbook.Workbook.Names["wld_tor1_peer_asn"].Value -as [int]
    'bgpPeerPassword' = $pnpWorkbook.Workbook.Names["wld_tor1_peer_bgp_password"].Value
}
$uplink02NetworkObject += [pscustomobject]@{
    'uplinkVlan' = $pnpWorkbook.Workbook.Names["wld_uplink2_vlan"].Value -as [int]
    'uplinkInterfaceIP' = $pnpWorkbook.Workbook.Names["wld_en2_uplink2_interface_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["wld_uplink2_cidr"].Value.split("/")[-1]
    'peerIP' = $pnpWorkbook.Workbook.Names["wld_tor2_peer_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["wld_uplink2_cidr"].Value.split("/")[-1]
    'asnPeer' = $pnpWorkbook.Workbook.Names["wld_tor2_peer_asn"].Value -as [int]
    'bgpPeerPassword' = $pnpWorkbook.Workbook.Names["wld_tor2_peer_bgp_password"].Value
}

$edgeNodeObject = @()
$edgeNodeObject += [pscustomobject]@{
    'edgeNodeName' = $pnpWorkbook.Workbook.Names["wld_en1_fqdn"].Value
    'managementIP' = $pnpWorkbook.Workbook.Names["wld_en1_mgmt_interface_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["wld_mgmt_cidr"].Value.split("/")[-1]
    'managementGateway' = $pnpWorkbook.Workbook.Names["wld_mgmt_gateway"].Value
    'edgeTepGateway' = $pnpWorkbook.Workbook.Names["wld_edge_overlay_gateway"].Value
    'edgeTep1IP' = $pnpWorkbook.Workbook.Names["wld_en1_edge_overlay_interface_ip_1"].Value+"/"+$pnpWorkbook.Workbook.Names["wld_edge_overlay_cidr"].Value.split("/")[-1]
    'edgeTep2IP' = $pnpWorkbook.Workbook.Names["wld_en1_edge_overlay_interface_ip_2"].Value+"/"+$pnpWorkbook.Workbook.Names["wld_edge_overlay_cidr"].Value.split("/")[-1]
    'edgeTepVlan' = $pnpWorkbook.Workbook.Names["wld_edge_overlay_vlan"].Value
    'clusterId' = "CLUSTER-ID"
    'interRackCluster' = "false"
    uplinkNetwork = $uplink01NetworkObject

}
$edgeNodeObject += [pscustomobject]@{
    'edgeNodeName' = $pnpWorkbook.Workbook.Names["wld_en2_fqdn"].Value
    'managementIP' = $pnpWorkbook.Workbook.Names["wld_en2_mgmt_interface_ip"].Value+"/"+$pnpWorkbook.Workbook.Names["wld_mgmt_cidr"].Value.split("/")[-1]
    'managementGateway' = $pnpWorkbook.Workbook.Names["wld_mgmt_gateway"].Value
    'edgeTepGateway' = $pnpWorkbook.Workbook.Names["wld_edge_overlay_gateway"].Value
    'edgeTep1IP' = $pnpWorkbook.Workbook.Names["wld_en2_edge_overlay_interface_ip_1"].Value+"/"+$pnpWorkbook.Workbook.Names["wld_edge_overlay_cidr"].Value.split("/")[-1]
    'edgeTep2IP' = $pnpWorkbook.Workbook.Names["wld_en2_edge_overlay_interface_ip_2"].Value+"/"+$pnpWorkbook.Workbook.Names["wld_edge_overlay_cidr"].Value.split("/")[-1]
    'edgeTepVlan' = $pnpWorkbook.Workbook.Names["wld_edge_overlay_vlan"].Value
    'clusterId' = "CLUSTER-ID"
    'interRackCluster' = "false"
    uplinkNetwork = $uplink02NetworkObject
}

$edgeClusterProfileObject = @()
$edgeClusterProfileObject += [pscustomobject]@{
    'bfdAllowedHop' = "255" -as [int]
    'bfdDeclareDeadMultiple' = "3" -as [int]
    'bfdProbeInterval' = "1000" -as [int]
    'edgeClusterProfileName' = $pnpWorkbook.Workbook.Names["wld_ec_profile_name"].Value
    'standbyRelocationThreshold' = "30" -as [int]
}

$workloadEdgeObject = @()
$workloadEdgeObject += [pscustomobject]@{
    'edgeClusterName' = $pnpWorkbook.Workbook.Names["wld_ec_name"].Value
    'edgeClusterProfileType' = "CUSTOM"
    edgeClusterProfileSpec = ($edgeClusterProfileObject | Select-Object -Skip 0)
    'edgeClusterType' = "NSX-T"
    'edgeRootPassword' = $nsxtPassword
    'edgeAdminPassword' = $nsxtPassword
    'edgeAuditPassword' = $nsxtPassword
    'edgeFormFactor' = $pnpWorkbook.Workbook.Names["wld_ec_formfactor"].Value.ToUpper()
    'tier0ServicesHighAvailability' = "ACTIVE_ACTIVE"
    'mtu' = $pnpWorkbook.Workbook.Names["wld_edge_overlay_mtu"].Value -as [int]
    'asn' = $pnpWorkbook.Workbook.Names["wld_en_asn"].Value
    'tier0RoutingType' = "EBGP"
    'tier0Name' = $pnpWorkbook.Workbook.Names["wld_t0_name"].Value
    'tier1Name' = $pnpWorkbook.Workbook.Names["wld_t1_name"].Value
    edgeNodeSpecs = $edgeNodeObject
}

LogMessage " Exporting the $module to $Json"

    $workloadEdgeObject | ConvertTo-Json -Depth 11 | Out-File -FilePath $Json
LogMessage " Closing the Excel Workbook: $workbook"
Close-ExcelPackage $pnpWorkbook -ErrorAction SilentlyContinue
LogMessage " Completed the Process of Generating the $module" Yellow