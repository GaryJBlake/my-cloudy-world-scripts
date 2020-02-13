
<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         HCI BU
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 002)
    .Date:          2020-02-13
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.001 (Gary Blake / 2020-02-11) - Initial script creation
    - 1.0.002 (Gary Blake / 2020-02-13) - Added support for Platform Services Controllers in VCF 3.x

    ===============================================================================================================
    .DESCRIPTION
        This script automates the process of creating the JSON Specs needed for generating CSRs, signed
        certificates and the installation of the signed certificates using SDDC Manager for the management domain

    .EXAMPLE
    .\generateCertificateJsons.ps1 -sddcMgrFqdn sfo01mgr01.sddc.local -sddcMgrUsername admin -sddcMgrPassword VMw@re1!
    -vcfVersion 4
#>

    param(
    [Parameter(Mandatory=$true)]
    [String]$sddcMgrFqdn,
    [Parameter(Mandatory=$true)]
    [String]$sddcMgrUsername,
    [Parameter(Mandatory=$true)]
    [String]$sddcMgrPassword
    )

# Set your Variables here

$Global:path = "E:\MyLab\"

Function LogMessage {
    param(
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

Function gatherSddcInventory {
  LogMessage "Gathering Inventory for SDDC Manager"
  $Global:sddcMgr = Get-VCFManager
  LogMessage "Gathering Inventory for vCenter Server"
  $Global:vCenterServer = Get-VCFvCenter
  if ($Global:sddcMgrVersion -eq "3") {
    LogMessage "Gathering Inventory for NSX-V Manager"
    $Global:nsxvManager = Get-VCFnsxvManager
    LogMessage "Gathering Inventory for Platform Services Controllers"
    $Global:pscs = Get-VCFPSC
  }
  if ($Global:sddcMgrVersion -eq "4") {
    LogMessage "Gathering Inventory for NSX-T Management Cluster"
    $Global:nsxtManager = Get-VCFnsxtCluster
  }
  $Global:sddcMgrVersion = $Global:sddcMgr.version.split(".")[0]
}

Function generateCsrSpec {

  LogMessage "Populating requestCsrSpec.json with SDDC Manager, vCenter Server, Platform Services Controllers and NSX-V Manager"

  $resourcesObject = @()
    $resourcesObject += [pscustomobject]@{
      'fqdn' = $Global:sddcMgr.fqdn
      'name' = $Global:sddcMgr.fqdn.split(".")[0]
      'resourceId' = $Global:sddcMgr.id
      'type' = "SDDC_MANAGER"
    }
    $resourcesObject += [pscustomobject]@{
      'fqdn' = $Global:vCenterServer.fqdn
      'name' = $Global:vCenterServer.fqdn.split(".")[0]
      'resourceId' = $Global:vCenterServer.id
      'type' = "VCENTER"
    }
    if ($Global:sddcMgrVersion -eq "3") {
      $resourcesObject += [pscustomobject]@{
        'fqdn' = $Global:nsxvManager.fqdn
        'name' = $Global:nsxvManager.fqdn.split(".")[0]
        'resourceId' = $Global:nsxvManager.id
        'type' = "NSX_MANAGER"
      }
      foreach ($psc in $Global:pscs) {
        $resourcesObject += [pscustomobject]@{
          'fqdn' = $psc.fqdn
          'name' = $psc.fqdn.split(".")[0]
          'resourceId' = $psc.id
          'type' = "PSC"
        }
      }
    }
    if ($Global:sddcMgrVersion -eq "4") {
      $resourcesObject += [pscustomobject]@{
        'fqdn' = $Global:nsxtManager.fqdn
        'name' = $Global:nsxtManager.fqdn.split(".")[0]
        'resourceId' = $Global:nsxtManager.id
        'type' = "NSXT_MANAGER"
      }
    }

    $csrGenerationSpecJson =
    '{
      "csrGenerationSpec": {
        "country": "US",
        "email": "",
    		"keyAlgorithm": "RSA",
    		"keySize": "2048",
    		"locality": "San Francisco",
    		"organization": "VMware",
    		"organizationUnit": "Rainpole",
    		"state": "CA"
    	},
    '

  $resourcesBodyObject += [pscustomobject]@{
      resources = $resourcesObject
  }

  $resourcesBodyObject | ConvertTo-Json | Out-File -FilePath $Global:path"temp.json"
  Get-Content $Global:path"temp.json" | Select-Object -Skip 1 | Set-Content $Global:path"temp1.json"
  $resouresJson = Get-Content $Global:path"temp1.json" -Raw
  Remove-Item -Path $Global:path"temp.json"
  Remove-Item -Path $Global:path"temp1.json"
  $requestCsrSpecJson = $csrGenerationSpecJson + $resouresJson
  $requestCsrSpecJson | Out-File $Global:path"requestCsrSpec.json"
}

Function generateCertificateSpec {

  if ($Global:sddcMgrVersion -eq "3") {
    LogMessage "Populating requestCertificateSpec.json with SDDC Manager, vCenter Server, Platform Services Controllers and NSX-V Manager"
  	$generateCertificateSpecbody =
  	'{
  		"caType": "Microsoft",
  		"resources": [
  			{
  				"fqdn": "'+$Global:sddcMgr.fqdn+'",
  				"name": "'+$Global:sddcMgr.fqdn.split(".")[0]+'",
  				"resourceId": "'+$Global:sddcMgr.id+'",
  				"type": "SDDC_MANAGER"
  			},{
  				"fqdn": "'+$Global:nsxvManager.fqdn+'",
  				"name": "'+$Global:nsxvManager.fqdn.split(".")[0]+'",
  				"resourceId": "'+$Global:nsxvManager.id+'",
  				"type": "NSXV_MANAGER"
  			},{
  				"fqdn": "'+$Global:vCenterServer.fqdn+'",
  				"name": "'+$Global:vCenterServer.fqdn.split(".")[0]+'",
  				"resourceId": "'+$Global:vCenterServer.id+'",
  				"type": "VCENTER"
  			}
  		]
  	}' | Out-File -FilePath $Global:path"requestCertificateSpec.json"
  }

  if ($Global:sddcMgrVersion -eq "4") {
    LogMessage "Populating requestCertificateSpec.json with SDDC Manager, vCenter Server and NSX-T Management Cluster"
  	$generateCertificateSpecbody =
  	'{
  		"caType": "Microsoft",
  		"resources": [
  			{
  				"fqdn": "'+$Global:sddcMgr.fqdn+'",
  				"name": "'+$Global:sddcMgr.fqdn.split(".")[0]+'",
  				"resourceId": "'+$Global:sddcMgr.id+'",
  				"type": "SDDC_MANAGER"
  			},{
  				"fqdn": "'+$Global:nsxtManager.fqdn+'",
  				"name": "'+$Global:nsxtManager.fqdn.split(".")[0]+'",
  				"resourceId": "'+$Global:nsxtManager.id+'",
  				"type": "NSXT_MANAGER"
  			},{
  				"fqdn": "'+$Global:vCenterServer.fqdn+'",
  				"name": "'+$Global:vCenterServer.fqdn.split(".")[0]+'",
  				"resourceId": "'+$Global:vCenterServer.id+'",
  				"type": "VCENTER"
  			}
  		]
  	}' | Out-File -FilePath $Global:path"requestCertificateSpec.json"
  }
}

Function generateUpdateCertificateSpec {

if ($Global:sddcMgrVersion -eq "3") {
    LogMessage "Populating updateCertificateSpec.json with SDDC Manager, vCenter Server, Platform Services Controllers and NSX-V Manager"
  	$generateUpdateCertificateSpecbody =
  	'{
  		"operationType": "INSTALL",
  		"resources": [
  			{
  				"fqdn": "'+$Global:sddcMgr.fqdn+'",
  				"name": "'+$Global:sddcMgr.fqdn.split(".")[0]+'",
  				"resourceId": "'+$Global:sddcMgr.id+'",
  				"type": "SDDC_MANAGER"
  			},{
  				"fqdn": "'+$Global:nsxvManager.fqdn+'",
  				"name": "'+$Global:nsxvManager.fqdn.split(".")[0]+'",
  				"resourceId": "'+$Global:nsxvManager.id+'",
  				"type": "NSXV_MANAGER"
  			},{
  				"fqdn": "'+$Global:vCenterServer.fqdn+'",
  				"name": "'+$Global:vCenterServer.fqdn.split(".")[0]+'",
  				"resourceId": "'+$Global:vCenterServer.id+'",
  				"type": "VCENTER"
  			}
  		]
  	}' | Out-File -FilePath $Global:path"updateCertificateSpec.json"
  }

if ($Global:sddcMgrVersion -eq "4") {
    LogMessage "Populating updateCertificateSpec.json with SDDC Manager, vCenter Server and NSX-T Management Cluster"
    $generateUpdateCertificateSpecbody =
    '{
      "operationType": "INSTALL",
      "resources": [
        {
          "fqdn": "'+$Global:sddcMgr.fqdn+'",
          "name": "'+$Global:sddcMgr.fqdn.split(".")[0]+'",
          "resourceId": "'+$Global:sddcMgr.id+'",
          "type": "SDDC_MANAGER"
        },{
          "fqdn": "'+$Global:nsxtManager.fqdn+'",
          "name": "'+$Global:nsxtManager.fqdn.split(".")[0]+'",
          "resourceId": "'+$Global:nsxtManager.id+'",
          "type": "NSXT_MANAGER"
        },{
          "fqdn": "'+$Global:vCenterServer.fqdn+'",
          "name": "'+$Global:vCenterServer.fqdn.split(".")[0]+'",
          "resourceId": "'+$Global:vCenterServer.id+'",
          "type": "VCENTER"
        }
      ]
    }' | Out-File -FilePath $Global:path"updateCertificateSpec.json"
  }
}

Clear-Host
LogMessage "Connecting to SDDC Manager $sddcMgrFqdn"
Connect-VCFManager -fqdn $sddcMgrFqdn -username $sddcMgrUsername -password $sddcMgrPassword | Out-Null # Connect to SDDC Manager
LogMessage "Running Procedure against SDDC Manager that is running v$Global:sddcMgrVersion.x" Yellow
gatherSddcInventory
generateCsrSpec
generateCertificateSpec
generateUpdateCertificateSpec
