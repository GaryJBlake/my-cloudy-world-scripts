
<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         HCI BU
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 001)
    .Date:          2020-02-11
    ===============================================================================================================
    .CREDITS

    - William Lam & Ken Gould - LogMessage Function

    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.001 (Gary Blake / 2020-02-11) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION
        This script automates the process of configuring the repository settings in SDDC Manager

    .EXAMPLE
    .\configureRepositoryCredentials.ps1 -sddcMgrFqdn sfo01mgr01.sddc.local -sddcMgrUsername admin -sddcMgrPassword VMw@re1!
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

$Global:depotUsername = "vcf_user3@mailinator.com"
$Global:depotPassword = "VMware123!"

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

Function configureRepositoryCreds {

  Try {
    LogMessage "Checking VCF Depot Credentials Configuration"
  	$vcfDepotCreds = Get-VCFDepotCredentials
  	if (!$vcfDepotCreds.vmwareAccount.username){
  		LogMessage "Configuring VCF Depot Credentials"
  		Set-VCFDepotCredentials -username $depotUsername -password $depotPassword | Out-Null
  		LogMessage "Configuration of VCF Depot Credentials Complete"
  	}
  	else {
  		LogMessage "Configuration of VCF Depot Credentials Already Done" Magenta
  	}
  }
  catch {
    $ErrorMessage = $_.Exception.Message
    LogMessage "Error was: $ErrorMessage" Red
  }
}

Clear-Host
LogMessage "Connecting to SDDC Manager $sddcMgrFqdn"
Connect-VCFManager -fqdn $sddcMgrFqdn -username $sddcMgrUsername -password $sddcMgrPassword | Out-Null # Connect to SDDC Manager
configureRepositoryCreds
