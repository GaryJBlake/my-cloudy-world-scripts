<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         HCI BU
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 001)
    .Date:          2020-02-13
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.001 (Gary Blake / 2020-02-11) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION
        This script automates the process of creating the JSON Specs needed for comissioning additional ESXi hosts
        in SDDC Manager. It makes the assumption that the hosts will be commissioned using the default network
        pool created during the Management Domain bringup process.

    .EXAMPLE
    .\generateCommissionHostsJson.ps1 -sddcMgrFqdn sfo01mgr01.sddc.local -sddcMgrUsername admin -sddcMgrPassword VMw@re1!
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
$Global:esxiUsername = "root"
$Global:esxiPassword = "VMw@re1!"
$Global:domainName = "sddc.local"
$Global:esxiHostname = ("sfo01w01esx01","sfo01w01esx02","sfo01w01esx03")

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
  $Global:sddcMgrVersion = $Global:sddcMgr.version.split(".")[0]
  LogMessage "Gathering Inventory of Network Pools in SDDC Manager"
  $Global:sddMgrNetworkPools = Get-VCFNetworkPool
}

Function generatingCommissionHostSpec {

LogMessage "Generating comissionHostsSpec.json"

$hostsObject = @()
  foreach ($esxiHost in $Global:esxiHostname) {
    $hostsObject += [pscustomobject]@{
      'fqdn' = $esxiHost+'.'+$Global:domainName
      'username' = $Global:esxiUsername
      'storageType' = "VSAN"
      'password' = $Global:esxiPassword
      'networkPoolName' = $Global:sddMgrNetworkPools.name
      'networkPoolId' = $Global:sddMgrNetworkPools.id
    }
  }

  $hostsObject | ConvertTo-Json | Out-File -FilePath $Global:path"comissionHostsSpec.json"
}

#Clear-Host
LogMessage "Connecting to SDDC Manager $sddcMgrFqdn"
Connect-VCFManager -fqdn $sddcMgrFqdn -username $sddcMgrUsername -password $sddcMgrPassword | Out-Null # Connect to SDDC Manager
LogMessage "Running Procedure against SDDC Manager that is running v$Global:sddcMgrVersion.x" Yellow

gatherSddcInventory
generatingCommissionHostSpec
