
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
        This script automates the process of configuring the a Microsoft Certificate Authority Server with
        SDDC Manager

    .EXAMPLE
    .\configureMicrosoftCa.ps1 -sddcMgrFqdn sfo01mgr01.sddc.local -sddcMgrUsername admin -sddcMgrPassword VMw@re1!
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

$Global:activeDirectory = "lab01ad01"
$Global:rootDomain = "sddc.local"
$Global:serviceAccountPassword = "VMw@re1!"
$Global:serviceAccount = "svc-mgr-ca"
$Global:caTemplateName = "VMware"

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

Function configureMicrosoftCa {

  Try {
    LogMessage "Checking Certificate Authority Configuration"
    $vcfCertCa = Get-VCFCertificateAuthConfiguration
  	if ($vcfCertCa.id -ne "Microsoft"){
      $serverUrl = "https://$Global:activeDirectory.$Global:rootDomain/certsrv"
  		LogMessage "Configuring Microsoft Certificate Authority Connection in SDDC Manager with $serverUrl"
      LogMessage "Using the Service Account named $Global:serviceAccount"
  		Set-VCFMicrosoftCA -serverUrl $serverUrl -username $Global:serviceAccount -password $Global:serviceAccountPassword -templateName $Global:caTemplateName | Out-Null
  		LogMessage "Configuration of Microsoft Certificate Authority in SDDC Manager Complete"
  	}
  	else {
  		LogMessage "Configuration Certificate Authority Already Done" Magenta
  	}
  }
  Catch {
    $ErrorMessage = $_.Exception.Message
    LogMessage "Error was: $ErrorMessage" Red
  }
}

Clear-Host
LogMessage "Connecting to SDDC Manager $sddcMgrFqdn"
Connect-VCFManager -fqdn $sddcMgrFqdn -username $sddcMgrUsername -password $sddcMgrPassword | Out-Null # Connect to SDDC Manager
configureMicrosoftCa
