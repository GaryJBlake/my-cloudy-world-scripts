 <#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         HCI BU
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 001)
    .Date:          2020-06-01
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function
    - Ken Gould - cidrToMask Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.000 (Gary Blake / 2020-06-01) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of creating the JSON Spec needed for creating a NSX-T Edge Cluster in SDDC 
    Manager. It uses the Planning and Preparation Workbook to obtain the required details needed in the JSON file
    that can then be consumed via the VMware Cloud Foundation Public API or PowerVCF.

    .EXAMPLE

    .\createWorkloadEdgeSpec.ps1 -Workbook E:\pnpWorkbook.xlsx -Json E:\MyLab\sfo\sfo-workloadEdge.json -nsxtPassword 
    VMw@re1!VMw@re1! -bgpPassword VMw@re1!
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

$uplink01NetworkObject = @()
    $uplink01NetworkObject += [pscustomobject]@{
        'uplinkVlan' = $wldWorksheet.Cells['D14'].Value -as [int]
        'uplinkInterfaceIP' = $wldWorksheet.Cells['H87'].Value+"/"+$wldWorksheet.Cells['H14'].Value.split("/")[-1]
        'peerIP' = $wldWorksheet.Cells['D24'].Value+"/"+$wldWorksheet.Cells['H14'].Value.split("/")[-1]
        'asnPeer' = $wldWorksheet.Cells['D25'].Value -as [int]
        'bgpPeerPassword' = $wldWorksheet.Cells['D26'].Value
    }
$uplink01NetworkObject += [pscustomobject]@{
        'uplinkVlan' = $wldWorksheet.Cells['D15'].Value -as [int]
        'uplinkInterfaceIP' = $wldWorksheet.Cells['H88'].Value+"/"+$wldWorksheet.Cells['H15'].Value.split("/")[-1]
        'peerIP' = $wldWorksheet.Cells['D27'].Value+"/"+$wldWorksheet.Cells['H15'].Value.split("/")[-1]
        'asnPeer' = $wldWorksheet.Cells['D28'].Value -as [int]
        'bgpPeerPassword' = $wldWorksheet.Cells['D29'].Value
    }

$uplink02NetworkObject = @()
    $uplink02NetworkObject += [pscustomobject]@{
        'uplinkVlan' = $wldWorksheet.Cells['D14'].Value -as [int]
        'uplinkInterfaceIP' = $wldWorksheet.Cells['H92'].Value+"/"+$wldWorksheet.Cells['H14'].Value.split("/")[-1]
        'peerIP' = $wldWorksheet.Cells['D24'].Value+"/"+$wldWorksheet.Cells['H14'].Value.split("/")[-1]
        'asnPeer' = $wldWorksheet.Cells['D25'].Value -as [int]
        'bgpPeerPassword' = $wldWorksheet.Cells['D26'].Value
    }
$uplink02NetworkObject += [pscustomobject]@{
        'uplinkVlan' = $wldWorksheet.Cells['D15'].Value -as [int]
        'uplinkInterfaceIP' = $wldWorksheet.Cells['H93'].Value+"/"+$wldWorksheet.Cells['H15'].Value.split("/")[-1]
        'peerIP' = $wldWorksheet.Cells['D27'].Value+"/"+$wldWorksheet.Cells['H15'].Value.split("/")[-1]
        'asnPeer' = $wldWorksheet.Cells['D28'].Value -as [int]
        'bgpPeerPassword' = $wldWorksheet.Cells['D29'].Value
    }

$edgeNodeObject = @()
    $edgeNodeObject += [pscustomobject]@{
        'edgeNodeName' = $wldWorksheet.Cells['F86'].Value
        'managementIP' = $wldWorksheet.Cells['H86'].Value+"/"+$wldWorksheet.Cells['H9'].Value.split("/")[-1]
        'managementGateway' = $wldWorksheet.Cells['J9'].Value
        'edgeTepGateway' = $wldWorksheet.Cells['J16'].Value
        'edgeTep1IP' = $wldWorksheet.Cells['H89'].Value+"/"+$wldWorksheet.Cells['H16'].Value.split("/")[-1]
        'edgeTep2IP' = $wldWorksheet.Cells['H90'].Value+"/"+$wldWorksheet.Cells['H16'].Value.split("/")[-1]
        'edgeTepVlan' = $wldWorksheet.Cells['D16'].Value
        'clusterId' = "CLUSTER-ID"
        'interRackCluster' = "false"
        uplinkNetwork = $uplink01NetworkObject

    }
    $edgeNodeObject += [pscustomobject]@{
        'edgeNodeName' = $wldWorksheet.Cells['F91'].Value
        'managementIP' = $wldWorksheet.Cells['H91'].Value+"/"+$wldWorksheet.Cells['H9'].Value.split("/")[-1]
        'managementGateway' = $wldWorksheet.Cells['J9'].Value
        'edgeTepGateway' = $wldWorksheet.Cells['J16'].Value
        'edgeTep1IP' = $wldWorksheet.Cells['H94'].Value+"/"+$wldWorksheet.Cells['H16'].Value.split("/")[-1]
        'edgeTep2IP' = $wldWorksheet.Cells['H95'].Value+"/"+$wldWorksheet.Cells['H16'].Value.split("/")[-1]
        'edgeTepVlan' = $wldWorksheet.Cells['D16'].Value
        'clusterId' = "CLUSTER-ID"
        'interRackCluster' = "false"
        uplinkNetwork = $uplink02NetworkObject
    }

$edgeClusterProfileObject = @()
    $edgeClusterProfileObject += [pscustomobject]@{
        'bfdAllowedHop' = "255" -as [int]
	    'bfdDeclareDeadMultiple' = "3" -as [int]
		'bfdProbeInterval' = "1000" -as [int]
		'edgeClusterProfileName' = $wldWorksheet.Cells['G139'].Value
		'standbyRelocationThreshold' = "30" -as [int]
    }

$workloadEdgeObject = @()
    $workloadEdgeObject += [pscustomobject]@{
        'edgeClusterName' = $wldWorksheet.Cells['G140'].Value
        'edgeClusterProfileType' = "CUSTOM"
        edgeClusterProfileSpec = ($edgeClusterProfileObject | Select-Object -Skip 0)
        'edgeClusterType' = "NSX-T"
	    'edgeRootPassword' = $nsxtPassword
	    'edgeAdminPassword' = $nsxtPassword
	    'edgeAuditPassword' = $nsxtPassword
	    'edgeFormFactor' = "MEDIUM"
	    'tier0ServicesHighAvailability' = "ACTIVE_ACTIVE"
	    'mtu' = $wldWorksheet.Cells['L16'].Value -as [int]
	    'asn' = $wldWorksheet.Cells['D23'].Value -as [int]
	    'tier0RoutingType' = "EBGP"
	    'tier0Name' = $wldWorksheet.Cells['G142'].Value
	    'tier1Name' = $wldWorksheet.Cells['G143'].Value
        edgeNodeSpecs = $edgeNodeObject
    }

LogMessage " Exporting the $module to $Json"

    $workloadEdgeObject | ConvertTo-Json -Depth 11 | Out-File -FilePath $Json
LogMessage " Closing the Excel Workbook: $workbook"
Close-ExcelPackage $pnpWorkbook
LogMessage " Completed the Process of Generating the $module" Yellow