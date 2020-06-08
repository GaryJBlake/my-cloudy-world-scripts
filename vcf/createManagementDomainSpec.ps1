 <#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         HCI BU
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 001)
    .Date:          2020-06-02
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function
    - Ken Gould - cidrToMask Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.000 (Gary Blake / 2020-06-02) - Initial script creation

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
$optionsWorksheet = $pnpWorkbook.Workbook.Worksheets[‘Deployment Options’]
if ($optionsWorksheet.Cells['J8'].Value -ne "v4.0.0") {
    LogMessage " Planning and Prepatation Workbook Provided Not Supported" Red 
    Break
}

LogMessage " Extracting Worksheet Data from the Excel Workbook"
$mgmtWorksheet = $pnpWorkbook.Workbook.Worksheets[‘Management Domain’]

LogMessage " Generating the $module"

$cidr = $mgmtWorksheet.Cells['H10'].Value.split("/")
$managmentMask = cidrToMask $cidr[1]

$ntpServers = New-Object System.Collections.ArrayList
if ($mgmtWorksheet.Cells['D57'].Value -eq "n/a") {
    [Array]$ntpServers = $mgmtWorksheet.Cells['D56'].Value
}
else {
    [Array]$ntpServers = $mgmtWorksheet.Cells['D56'].Value,$mgmtWorksheet.Cells['D57'].Value
}

$dnsObject = @()
    $dnsObject += [pscustomobject]@{
        'domain' = $mgmtWorksheet.Cells['D190'].Value
        'subdomain' = $mgmtWorksheet.Cells['D190'].Value
        'nameserver' = $mgmtWorksheet.Cells['D62'].Value
        'secondaryNameserver' = $mgmtWorksheet.Cells['D63'].Value
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
        'hostname' = $mgmtWorksheet.Cells['D75'].Value
        'ipAddress' = $mgmtWorksheet.Cells['H75'].Value
        'netmask' = $managmentMask
        rootUserCredentials = ($rootUserObject | Select-Object -Skip 0)
        restApiCredentials = ($restApiUserObject | Select-Object -Skip 0)
        secondUserCredentials = ($secondUserObject | Select-Object -Skip 0)
    }

$vmnics = New-Object System.Collections.ArrayList
[Array]$vmnics = $mgmtWorksheet.Cells['G139'].Value,$mgmtWorksheet.Cells['G140'].Value

$networks = New-Object System.Collections.ArrayList
[Array]$networks = "MANAGEMENT","VMOTION","VSAN","UPLINK01","UPLINK02","NSXT_EDGE_TEP"

$vmotionIpObject = @()
    $vmotionIpObject += [pscustomobject]@{
        'startIpAddress' = $mgmtWorksheet.Cells['H98'].Value
        'endIpAddress' = $mgmtWorksheet.Cells['H99'].Value
    }

$vsanIpObject = @()
    $vsanIpObject += [pscustomobject]@{
        'startIpAddress' = $mgmtWorksheet.Cells['H100'].Value
        'endIpAddress' = $mgmtWorksheet.Cells['H101'].Value
    }

$networkObject = @()
    $networkObject += [pscustomobject]@{
        'networkType' = "MANAGEMENT"
        'subnet' = $mgmtWorksheet.Cells['H10'].Value
        'vlanId' = $mgmtWorksheet.Cells['D10'].Value -as [string]
        'mtu' = $mgmtWorksheet.Cells['L10'].Value -as [string]
        'gateway' = $mgmtWorksheet.Cells['J10'].Value
        'portGroupKey' = $mgmtWorksheet.Cells['F10'].Value
        'association' = $mgmtWorksheet.Cells['G148'].Value
    }
    $networkObject += [pscustomobject]@{
        'networkType' = "VMOTION"
        'subnet' = $mgmtWorksheet.Cells['H11'].Value
        includeIpAddressRanges = $vmotionIpObject
        'vlanId' = $mgmtWorksheet.Cells['D11'].Value -as [string]
        'mtu' = $mgmtWorksheet.Cells['L11'].Value -as [string]
        'gateway' = $mgmtWorksheet.Cells['J11'].Value
        'portGroupKey' = $mgmtWorksheet.Cells['F11'].Value
        'association' = $mgmtWorksheet.Cells['G148'].Value
    }
    $networkObject += [pscustomobject]@{
        'networkType' = "VSAN"
        'subnet' = $mgmtWorksheet.Cells['H12'].Value
        includeIpAddressRanges = $vsanIpObject
        'vlanId' = $mgmtWorksheet.Cells['D12'].Value -as [string]
        'mtu' = $mgmtWorksheet.Cells['L12'].Value -as [string]
        'gateway' = $mgmtWorksheet.Cells['J12'].Value
        'portGroupKey' = $mgmtWorksheet.Cells['F12'].Value
        'association' = $mgmtWorksheet.Cells['G148'].Value
    }
    $networkObject += [pscustomobject]@{
        'networkType' = "UPLINK01"
        'subnet' = $mgmtWorksheet.Cells['H14'].Value
        'vlanId' = $mgmtWorksheet.Cells['D14'].Value -as [string]
        'mtu' = $mgmtWorksheet.Cells['L14'].Value -as [string]
        'gateway' = $mgmtWorksheet.Cells['J14'].Value
        'portGroupKey' = $mgmtWorksheet.Cells['F14'].Value
        'association' = $mgmtWorksheet.Cells['G148'].Value
    }
    $networkObject += [pscustomobject]@{
        'networkType' = "UPLINK02"
        'subnet' = $mgmtWorksheet.Cells['H15'].Value
        'vlanId' = $mgmtWorksheet.Cells['D15'].Value -as [string]
        'mtu' = $mgmtWorksheet.Cells['L15'].Value -as [string]
        'gateway' = $mgmtWorksheet.Cells['J15'].Value
        'portGroupKey' = $mgmtWorksheet.Cells['F15'].Value
        'association' = $mgmtWorksheet.Cells['G148'].Value
    }
    $networkObject += [pscustomobject]@{
        'networkType' = "NSXT_EDGE_TEP"
        'subnet' = $mgmtWorksheet.Cells['H16'].Value
        'vlanId' = $mgmtWorksheet.Cells['D16'].Value -as [string]
        'mtu' = $mgmtWorksheet.Cells['L16'].Value -as [string]
        'gateway' = $mgmtWorksheet.Cells['J16'].Value
        'association' = $mgmtWorksheet.Cells['G148'].Value
    }
    $networkObject += [pscustomobject]@{
        'networkType' = "REGION_SPECIFIC"
        'subnet' = $mgmtWorksheet.Cells['H19'].Value
        'vlanId' = "0"
        'mtu' = $mgmtWorksheet.Cells['G142'].Value -as [string]
        'gateway' = $mgmtWorksheet.Cells['J19'].Value
        'association' = $mgmtWorksheet.Cells['G148'].Value
    }
    $networkObject += [pscustomobject]@{
        'networkType' = "X_REGION"
        'subnet' = $mgmtWorksheet.Cells['H20'].Value
        'vlanId' = "0"
        'mtu' = $mgmtWorksheet.Cells['G142'].Value -as [string]
        'gateway' = $mgmtWorksheet.Cells['J20'].Value
        'association' = $mgmtWorksheet.Cells['G148'].Value
    }


$nsxtManagerObject = @()
    $nsxtManagerObject += [pscustomobject]@{
        'hostname' = $mgmtWorksheet.Cells['D82'].Value
        'ip' = $mgmtWorksheet.Cells['H82'].Value
    }
$nsxtManagerObject += [pscustomobject]@{
        'hostname' = $mgmtWorksheet.Cells['D83'].Value
        'ip' = $mgmtWorksheet.Cells['H83'].Value
    }
$nsxtManagerObject += [pscustomobject]@{
        'hostname' = $mgmtWorksheet.Cells['D84'].Value
        'ip' = $mgmtWorksheet.Cells['H84'].Value
    }

$vlanTransportZoneObject = @()
    $vlanTransportZoneObject += [pscustomobject]@{
        'zoneName' = $mgmtWorksheet.Cells['G135'].Value+"-tz-vlan01"
        'networkName' = "netName-vlan"
    }

$overlayTransportZoneObject = @()
    $overlayTransportZoneObject += [pscustomobject]@{
        'zoneName' = $mgmtWorksheet.Cells['G135'].Value+"-tz-overlay01"
        'networkName' = "netName-overlay"
    }

$edgeNode01interfaces = @()
    $edgeNode01interfaces += [pscustomobject]@{
        'name' = $mgmtWorksheet.Cells['G135'].Value+"-uplink01-tor1"
        'interfaceCidr' = $mgmtWorksheet.Cells['H86'].Value+"/"+$mgmtWorksheet.Cells['H14'].Value.split("/")[-1]
    }
    $edgeNode01interfaces += [pscustomobject]@{
        'name' = $mgmtWorksheet.Cells['G135'].Value+"-uplink01-tor2"
        'interfaceCidr' = $mgmtWorksheet.Cells['H87'].Value+"/"+$mgmtWorksheet.Cells['H15'].Value.split("/")[-1]
    }

$edgeNode02interfaces = @()
     $edgeNode02interfaces += [pscustomobject]@{
        'name' = $mgmtWorksheet.Cells['G135'].Value+"-uplink01-tor1"
        'interfaceCidr' = $mgmtWorksheet.Cells['H91'].Value+"/"+$mgmtWorksheet.Cells['H14'].Value.split("/")[-1]
    }
    $edgeNode02interfaces += [pscustomobject]@{
        'name' = $mgmtWorksheet.Cells['G135'].Value+"-uplink01-tor2"
        'interfaceCidr' = $mgmtWorksheet.Cells['H92'].Value+"/"+$mgmtWorksheet.Cells['H15'].Value.split("/")[-1]
    
    }

$edgeNodeObject = @()
    $edgeNodeObject += [pscustomobject]@{
        'edgeNodeName' = $mgmtWorksheet.Cells['D85'].Value
        'edgeNodeHostname' = $mgmtWorksheet.Cells['F85'].Value
        'managementCidr' = $mgmtWorksheet.Cells['H85'].Value+"/"+$mgmtWorksheet.Cells['H10'].Value.split("/")[-1]
        'edgeVtep1Cidr' = $mgmtWorksheet.Cells['H88'].Value+"/"+$mgmtWorksheet.Cells['H16'].Value.split("/")[-1]
        'edgeVtep2Cidr' = $mgmtWorksheet.Cells['H89'].Value+"/"+$mgmtWorksheet.Cells['H16'].Value.split("/")[-1]
        interfaces = $edgeNode01interfaces
    }
    $edgeNodeObject += [pscustomobject]@{
        'edgeNodeName' = $mgmtWorksheet.Cells['D90'].Value
        'edgeNodeHostname' = $mgmtWorksheet.Cells['F90'].Value
        'managementCidr' = $mgmtWorksheet.Cells['H90'].Value+"/"+$mgmtWorksheet.Cells['H10'].Value.split("/")[-1]
        'edgeVtep1Cidr' = $mgmtWorksheet.Cells['H93'].Value+"/"+$mgmtWorksheet.Cells['H16'].Value.split("/")[-1]
        'edgeVtep2Cidr' = $mgmtWorksheet.Cells['H94'].Value+"/"+$mgmtWorksheet.Cells['H16'].Value.split("/")[-1]
        interfaces = $edgeNode02interfaces
    }

$edgeServicesObject = @()
    $edgeServicesObject += [pscustomobject]@{
        'tier0GatewayName' = $mgmtWorksheet.Cells['G135'].Value+"-ec01-t0-gw01"
        'tier1GatewayName' = $mgmtWorksheet.Cells['G135'].Value+"-ec01-t1-gw01"
    }

$bgpNeighboursObject = @()
    $bgpNeighboursObject += [pscustomobject]@{
        'neighbourIp' = $mgmtWorksheet.Cells['D25'].Value
        'autonomousSystem' = $mgmtWorksheet.Cells['D26'].Value
        'password' = $mgmtWorksheet.Cells['D27'].Value
    }
    $bgpNeighboursObject += [pscustomobject]@{
        'neighbourIp' = $mgmtWorksheet.Cells['D28'].Value
        'autonomousSystem' = $mgmtWorksheet.Cells['D29'].Value
        'password' = $mgmtWorksheet.Cells['D30'].Value
    }

$nsxtEdgeObject = @()
    $nsxtEdgeObject += [pscustomobject]@{
        'edgeClusterName' = $mgmtWorksheet.Cells['G144'].Value
        'edgeRootPassword' = $nsxtPassword
        'edgeAdminPassword' = $nsxtPassword
        'edgeAuditPassword' = $nsxtPassword
        'edgeFormFactor' = $mgmtWorksheet.Cells['G145'].Value
        'tier0ServicesHighAvailability' = "ACTIVE-ACTIVE"
        'asn' = $mgmtWorksheet.Cells['D24'].Value
        edgeServicesSpecs = ($edgeServicesObject | Select-Object -Skip 0)
        edgeNodeSpecs = $edgeNodeObject
        bgpNeighbours = $bgpNeighboursObject
    }

$logicalSegmentsObject = @()
    $logicalSegmentsObject += [pscustomobject]@{
        'name' = $mgmtWorksheet.Cells['F19'].Value
		'networkType' = "REGION_SPECIFIC"
    }
    $logicalSegmentsObject += [pscustomobject]@{
        'name' = $mgmtWorksheet.Cells['F20'].Value
		'networkType' = "X_REGION"
    }

$nsxtObject = @()
    $nsxtObject += [pscustomobject]@{
        'nsxtManagerSize' = $mgmtWorksheet.Cells['G145'].Value
        nsxtManagers = $nsxtManagerObject
        'rootNsxtManagerPassword' = $nsxtPassword
        'nsxtAdminPassword' = $nsxtPassword
        'nsxtAuditPassword' = $nsxtPassword
        'rootLoginEnabledForNsxtManager' = "true"
        'sshEnabledForNsxtManager' = "true"
        overLayTransportZone = ($overlayTransportZoneObject | Select-Object -Skip 0)
        vlanTransportZone = ($vlanTransportZoneObject | Select-Object -Skip 0)
        'vip' = $mgmtWorksheet.Cells['H81'].Value
		'vipFqdn' = $mgmtWorksheet.Cells['F81'].Value
		'nsxtLicense' = $mgmtWorksheet.Cells['C130'].Value
		'transportVlanId' = $mgmtWorksheet.Cells['D13'].Value
        nsxtEdgeSpec = ($nsxtEdgeObject | Select-Object -Skip 0)
        logicalSegments = $logicalSegmentsObject
    }

$excelvsanDedup = $mgmtWorksheet.Cells['C147'].Value
if ($excelvsanDedup -eq "No") {
    $vsanDedup = $false
}
elseif ($excelvsanDedup -eq "Yes") {
    $vsanDedup = $true
}

$vsanObject = @()
    $vsanObject += [pscustomobject]@{
        'vsanName' = "vsan-1"
        'licenseFile' = $mgmtWorksheet.Cells['C129'].Value
        'vsanDedup' = $vsanDedup
		'datastoreName' = $mgmtWorksheet.Cells['G146'].Value
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
        'mtu' = $mgmtWorksheet.Cells['G142'].Value
        niocSpecs = $niocObject
        'dvsName' = $mgmtWorksheet.Cells['G141'].Value
        'vmnics' = $vmnics
        'networks' = $networks
    }

$vmFolderObject = @()
    $vmFOlderObject += [pscustomobject]@{
        'MANAGEMENT' = $mgmtWorksheet.Cells['G164'].Value
        'NETWORKING' = $mgmtWorksheet.Cells['G165'].Value
        'EDGENODES' = $mgmtWorksheet.Cells['G165'].Value
    }

$excelEvcMode = $mgmtWorksheet.Cells['G150'].Value
if ($excelEvcMode -eq "n/a") {
    $evcMode = ""
}
else {
    $evcMode = $mgmtWorksheet.Cells['G150'].Value
}

$resourcePoolObject = @()
    $resourcePoolObject += [pscustomobject]@{
        'type' = "management"
        'name' = $mgmtWorksheet.Cells['G151'].Value
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
        'name' = $mgmtWorksheet.Cells['G152'].Value
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
        'name' = $mgmtWorksheet.Cells['G153'].Value
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
        'name' = $mgmtWorksheet.Cells['G154'].Value
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

$clusterObject = @()
    $clusterObject += [pscustomobject]@{
        vmFolders = ($vmFolderObject | Select-Object -Skip 0)
        'clusterName' = $mgmtWorksheet.Cells['G149'].Value
        'clusterEvcMode' = $evcMode
        resourcePoolSpecs = $resourcePoolObject
    }

$ssoObject = @()
    $ssoObject += [pscustomobject]@{
        'ssoSiteName' = $mgmtWorksheet.Cells['G135'].Value
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
        'vcenterIp' = $mgmtWorksheet.Cells['H76'].Value
		'vcenterHostname' = $mgmtWorksheet.Cells['D76'].Value
		'vcenterId' = "vcenter-1"
		'licenseFile' = $mgmtWorksheet.Cells['C127'].Value
		'rootVcenterPassword' = $defaultPassword
		'vmSize' = $mgmtWorksheet.Cells['G136'].Value
    }

$hostCredentialsObject = @()
    $hostCredentialsObject += [pscustomobject]@{
        'username' = "root"
		'password' = $defaultPassword
    }

$ipAddressPrivate01Object = @()
    $ipAddressPrivate01Object += [pscustomobject]@{
        'subnet' = $managmentMask
	    'cidr' = $mgmtWorksheet.Cells['H10'].Value
		'ipAddress' = $mgmtWorksheet.Cells['H77'].Value
		'gateway' = $mgmtWorksheet.Cells['J10'].Value
    }

$ipAddressPrivate02Object = @()
    $ipAddressPrivate02Object += [pscustomobject]@{
        'subnet' = $managmentMask
	    'cidr' = $mgmtWorksheet.Cells['H10'].Value
		'ipAddress' = $mgmtWorksheet.Cells['H78'].Value
		'gateway' = $mgmtWorksheet.Cells['J10'].Value
    }

$ipAddressPrivate03Object = @()
    $ipAddressPrivate03Object += [pscustomobject]@{
        'subnet' = $managmentMask
	    'cidr' = $mgmtWorksheet.Cells['H10'].Value
		'ipAddress' = $mgmtWorksheet.Cells['H79'].Value
		'gateway' = $mgmtWorksheet.Cells['J10'].Value
    }

$ipAddressPrivate04Object = @()
    $ipAddressPrivate04Object += [pscustomobject]@{
        'subnet' = $managmentMask
	    'cidr' = $mgmtWorksheet.Cells['H10'].Value
		'ipAddress' = $mgmtWorksheet.Cells['H80'].Value
		'gateway' = $mgmtWorksheet.Cells['J10'].Value
    }

$HostObject = @()
    $HostObject += [pscustomobject]@{
        'hostname' = $mgmtWorksheet.Cells['D77'].Value
		'vSwitch' = $mgmtWorksheet.Cells['G138'].Value
		'serverId' = "host-0"
		'association' = $mgmtWorksheet.Cells['G148'].Value
        credentials = ($hostCredentialsObject | Select-Object -Skip 0)
        ipAddressPrivate = ($ipAddressPrivate01Object | Select-Object -Skip 0)
    }
    $HostObject += [pscustomobject]@{
        'hostname' = $mgmtWorksheet.Cells['D78'].Value
		'vSwitch' = $mgmtWorksheet.Cells['G138'].Value
		'serverId' = "host-1"
		'association' = $mgmtWorksheet.Cells['G148'].Value
        credentials = ($hostCredentialsObject | Select-Object -Skip 0)
        ipAddressPrivate = ($ipAddressPrivate02Object | Select-Object -Skip 0)
    }
    $HostObject += [pscustomobject]@{
        'hostname' = $mgmtWorksheet.Cells['D79'].Value
		'vSwitch' = $mgmtWorksheet.Cells['G138'].Value
		'serverId' = "host-2"
		'association' = $mgmtWorksheet.Cells['G148'].Value
        credentials = ($hostCredentialsObject | Select-Object -Skip 0)
        ipAddressPrivate = ($ipAddressPrivate03Object | Select-Object -Skip 0)
    }
    $HostObject += [pscustomobject]@{
        'hostname' = $mgmtWorksheet.Cells['D80'].Value
		'vSwitch' = $mgmtWorksheet.Cells['G138'].Value
		'serverId' = "host-3"
		'association' = $mgmtWorksheet.Cells['G148'].Value
        credentials = ($hostCredentialsObject | Select-Object -Skip 0)
        ipAddressPrivate = ($ipAddressPrivate04Object | Select-Object -Skip 0)
    }

$excluded = New-Object System.Collections.ArrayList
[Array]$excluded = "NSX-V"

$managementDomainObject = @()
    $managementDomainObject += [pscustomobject]@{
        'taskName' = "workflowconfig/workflowspec-ems.json"
        'sddcId' = $mgmtWorksheet.Cells['G135'].Value
        'ceipEnabled' = $true
        'managementPoolName' = $mgmtWorksheet.Cells['G134'].Value
	    'dvSwitchVersion' = "7.0.0"
	    'skipEsxThumbprintValidation' = $true
	    'esxLicense' = $mgmtWorksheet.Cells['C128'].Value
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
Close-ExcelPackage $pnpWorkbook
LogMessage " Completed the Process of Generating the $module" Yellow