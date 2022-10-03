<#
    .NOTES
    ===================================================================================================================
    Created by:		Gary Blake
    Date:			30/09/2022
    Organization:	VMware
    Blog:           my-cloudy-world.com
    Twitter:        @GaryJBlake
    ===================================================================================================================

    .SYNOPSIS
    Deploys and configures Workspace ONE Access with a Standard (single node) deployment using vRealize Suite Lifecycle
    Manager

    .DESCRIPTION
    This scripts reads inputs from the VMware Cloud Foundation Planning and Preperation workbook and then requests the
    deployment of Workspace ONE Access using a Standard (single node) deployment.

    .EXAMPLE
    .\deployWorkspaceOneStandard.ps1 -sddcManagerFqdn ldn-vcf01.ldn.cloudy.io -sddcManagerUser administrator@vsphere.local -sddcManagerPass VMw@re1! -workbook F:\MyLab\vcf-4500\02-regiona-pnpWorkbook.xlsx -filePath F:\MyLab\ldn
    This example shows how to deploy Workspace ONE Access using a Standard (single node) deployment using the supplied VMware Cloud Foundation Planning and Preperation workbook inputs
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerFqdn,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerUser,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerPass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$workbook,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$filePath
)

Clear-Host; Write-Host ""

Start-SetupLogFile -Path $filePath -ScriptName $MyInvocation.MyCommand.Name
Write-LogMessage -Type INFO -Message "Starting the Process of Deploying and Configuring Workspace ONE Access using a Standard (single node) Deployment" -Colour Yellow
Write-LogMessage -Type INFO -Message "Setting up the log file to path $logfile"

Try {
    Write-LogMessage -Type INFO -Message "Checking Existance of Planning and Preparation Workbook: $workbook"
    if (!(Test-Path $workbook )) {
        Write-LogMessage -Type ERROR -Message "Unable to Find Planning and Preparation Workbook: $workbook, check details and try again" -Colour Red
        Break
    }
    else {
        Write-LogMessage -Type INFO -Message "Found Planning and Preparation Workbook: $workbook"
    }
    Write-LogMessage -Type INFO -Message "Checking a Connection to SDDC Manager: $sddcManagerFqdn"
    if (Test-VCFConnection -server $sddcManagerFqdn ) {
        Write-LogMessage -Type INFO -Message "Attempting to connect to VMware Cloud Foundation to Gather System Details"
        if (Test-VCFAuthentication -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass) {
            Write-LogMessage -Type INFO -Message "Gathering Details from SDDC Manager Inventory and Extracting Worksheet Data from the Excel Workbook"
            Write-LogMessage -type INFO -message "Opening the Excel Workbook: $Workbook"
            $pnpWorkbook = Open-ExcelPackage -Path $Workbook
            Write-LogMessage -type INFO -message "Checking Valid Planning and Prepatation Workbook Provided"
            if (($pnpWorkbook.Workbook.Names["vcf_version"].Value -ne "v4.3.x") -and ($pnpWorkbook.Workbook.Names["vcf_version"].Value -ne "v4.4.x") -and ($pnpWorkbook.Workbook.Names["vcf_version"].Value -ne "v4.5.x")) {
                Write-LogMessage -type INFO -message "Planning and Prepatation Workbook Provided Not Supported" -colour Red 
                Break
            }
            
            $sddcDomainName                           = $pnpWorkbook.Workbook.Names["mgmt_sddc_domain"].Value

            $vrslcmFqdn                               = $pnpWorkbook.Workbook.Names["xreg_vrslcm_fqdn"].Value
            $vrslcmUsername                           = "vcfadmin@local"
            $vrlscmPassword                           = $pnpWorkbook.Workbook.Names["vcfadmin_local_password"].Value
            
            Request-vRSLCMToken -fqdn $vrslcmFqdn -username $vrslcmUsername -password $vrlscmPassword | Out-Null

            $vrslcmDcName                             = $pnpWorkbook.Workbook.Names["vrslcm_xreg_dc"].Value
            $vrslcmDcLocation                         = $pnpWorkbook.Workbook.Names["vrslcm_xreg_location"].Value
            $vrslcmDcUsername                         = "svc-" + $pnpWorkbook.Workbook.Names["xreg_vrslcm_hostname"].Value + "-" + $pnpWorkbook.Workbook.Names["mgmt_vc_hostname"].Value + "@vsphere.local"
            $vrslcmDcUserAlias                        = (Get-vRSLCMLockerPassword | Where-Object {$_.username -eq "svc-xint-vrslcm01-ldn-m01-vc01@vsphere.local"}).alias
            
            $vcenterFqdn                              = $pnpWorkbook.Workbook.Names["mgmt_vc_fqdn"].Value

            $wsaCertificateAlias                      = $pnpWorkbook.Workbook.Names["xreg_wsa_cert_name"].Value  
            $wsaCertChainPath                         = $filePath + "\" + $pnpWorkbook.Workbook.Names["xreg_wsa_cert_name"].Value + ".2.chain.pem"
            
            $globalPasswordAlias                      = $pnpWorkbook.Workbook.Names["global_env_admin_password_alias"].Value
            $globalPassword                           = $pnpWorkbook.Workbook.Names["global_env_admin_password"].Value
            $globalUserName                           = $pnpWorkbook.Workbook.Names["global_env_admin_username"].Value

            $wsaAdminPasswordAlias                    = $pnpWorkbook.Workbook.Names["local_admin_password_alias"].Value
            $wsaAdminPassword                         = $pnpWorkbook.Workbook.Names["local_admin_password"].Value
            $wsaAdminUserName                         = $pnpWorkbook.Workbook.Names["local_admin_username"].Value

            $wsaConfigAdminPasswordAlias              = $pnpWorkbook.Workbook.Names["local_configadmin_password_alias"].Value
            $wsaConfigAdminPassword                   = $pnpWorkbook.Workbook.Names["local_configadmin_password"].Value
            $wsaConfigAdminUserName                   = $pnpWorkbook.Workbook.Names["local_configadmin_username"].Value

            $antiAffinityRuleName                     = "anti-affinity-rule-wsa"
            $antiAffinityVMs                          = $pnpWorkbook.Workbook.Names["xreg_wsa_nodea_hostname"].Value
            $drsGroupName                             = $pnpWorkbook.Workbook.Names["xreg_wsa_vm_group_name"].Value
            
            $wsaFqdn                                  = $pnpWorkbook.Workbook.Names["xreg_wsa_nodea_fqdn"].Value
            $wsaAdminPassword                         = $pnpWorkbook.Workbook.Names["local_admin_password"].Value
            $wsaRootPassword                          = $pnpWorkbook.Workbook.Names["global_env_admin_password"].Value

            $domainFqdn                               = $pnpWorkbook.Workbook.Names["region_ad_child_fqdn"].Value
            $baseDnUsers                              = $pnpWorkbook.Workbook.Names["child_ad_users_ou"].Value
            $baseDnGroups                             = $pnpWorkbook.Workbook.Names["child_ad_groups_ou"].Value
            $wsaBindUserDn                            = $pnpWorkbook.Workbook.Names["child_ad_bind_dn"].Value
            $wsaBindUserPassword                      = $pnpWorkbook.Workbook.Names["child_svc_wsa_ad_password"].Value
            $wsaSuperAdminGroup                       = $pnpWorkbook.Workbook.Names["group_child_gg_wsa_admins"].Value
            $wsaDirAdminGroup                         = $pnpWorkbook.Workbook.Names["group_child_gg_wsa_directory_admins"].Value
            $wsaReadOnlyGroup                         = $pnpWorkbook.Workbook.Names["group_child_gg_wsa_read_only"].Value
            $adGroups                                 = $pnpWorkbook.Workbook.Names["group_gg_vrslcm_content_admins"].Value + "," + $pnpWorkbook.Workbook.Names["group_gg_vrslcm_content_developers"].Value + "," + $pnpWorkbook.Workbook.Names["group_gg_vrslcm_admins"].Value + "," + $wsaSuperAdminGroup + "," + $wsaDirAdminGroup + "," + $wsaReadOnlyGroup
            $rootCaPath                               = $filePath + "\" + "Root64.cer"

            # $minLen = "6"
            # $minLower = "1"
            # $minUpper = "1"
            # $minDigit = "1"
            # $minSpecial = "1"
            # $history = "5"
            # $maxConsecutiveIdenticalCharacters = "1"
            # $maxPreviousPasswordCharactersReused = "0"
            # $tempPasswordTtlInHrs = "24"
            # $passwordTtlInDays = "90" 
            # $notificationThresholdInDays = "15" 
            # $notificationIntervalInDays = "1"

            # $numAttempts = "5"
            # $attemptInterval = "15"
            # $unlockInterval = "15"

            # Attempting to Create the Cross Instance Data Center in vRealize Suite Lifecycle Manager
            Write-LogMessage -Type INFO -Message "Attempting to Create the Cross Instance Data Center in vRealize Suite Lifecycle Manager"
            $StatusMsg = New-vRSLCMDatacenter -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -datacenterName $vrslcmDcName -location $vrslcmDcLocation -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Attempting to Add a vCenter Server to the Cross Instance Data Center in vRealize Suite Lifecycle Manager
            Write-LogMessage -Type INFO -Message "Attempting to Add a vCenter Server to the Cross Instance Data Center in vRealize Suite Lifecycle Manager"
            $StatusMsg = New-vRSLCMDatacenterVcenter -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -datacenterName $vrslcmDcName -vcenterFqdn $vcenterFqdn -userLockerAlias $vrslcmDcUserAlias -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Attempting to Import Workspace ONE Access Certificate into vRealize Suite Lifecycle Manager
            Write-LogMessage -Type INFO -Message "Attempting to Import Workspace ONE Access Certificate into vRealize Suite Lifecycle Manager"
            $StatusMsg = Import-vRSLCMLockerCertificate -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -certificateAlias $wsaCertificateAlias -certChainPath $wsaCertChainPath -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Attempting to Add Workspace ONE Access Passwords into vRealize Suite Lifecycle Manager
            Write-LogMessage -Type INFO -Message "Attempting to Add Workspace ONE Access Passwords into vRealize Suite Lifecycle Manager"
            $StatusMsg = New-vRSLCMLockerPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $globalPasswordAlias -password $globalPassword -userName $globalUserName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
            $StatusMsg = New-vRSLCMLockerPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $wsaAdminPasswordAlias -password $wsaAdminPassword -userName $wsaAdminUserName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
            $StatusMsg = New-vRSLCMLockerPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -alias $wsaConfigAdminPasswordAlias -password $wsaConfigAdminPassword -userName $wsaConfigAdminUserName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Attempting to Deploy Standard Workspace ONE Access Instance Using vRealize Suite Lifecycle Manager
            Write-LogMessage -Type INFO -Message "Attempting to Deploy Standard Workspace ONE Access Instance Using vRealize Suite Lifecycle Manager"
            $StatusMsg = New-WSADeployment -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -workbook $workbook -standard -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Attempting to Configure an Anti-Affinity Rule and a Virtual Machine Group for the Standard Workspace ONE Access Instance
            Write-LogMessage -Type INFO -Message "Attempting to Configure an Anti-Affinity Rule and a Virtual Machine Group for the Standard Workspace ONE Access Instance"
            $StatusMsg = Add-AntiAffinityRule -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -ruleName $antiAffinityRuleName -antiAffinityVMs $antiAffinityVMs -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
            
            # Attempting to Configure a Virtual Machine Group for the Standard Workspace ONE Access Instance
            Write-LogMessage -Type INFO -Message "Attempting to Attempting to Configure a Virtual Machine Group for the Standard Workspace ONE Access Instance"
            $StatusMsg = Add-ClusterGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomainName -drsGroupName $drsGroupName -drsGroupVMs $antiAffinityVMs -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Configure NTP on the Standard Workspace ONE Access Instance
            Write-LogMessage -Type INFO -Message "Attempting to Configure NTP on the Standard Workspace ONE Access Instance"
            $StatusMsg = Set-WorkspaceOneNtpConfig -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -wsaFqdn $wsaFqdn -rootPass $wsaRootPassword -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Configure Identity Source for the Standalone Workspace ONE Access Instance
            Write-LogMessage -Type INFO -Message "Attempting to Configure Identity Source for the Standalone Workspace ONE Access Instance"
            $StatusMsg = Add-WorkspaceOneDirectory -server $wsaFqdn -user admin -pass $wsaAdminPassword -domain $domainFqdn -baseDnUser $baseDnUsers -baseDnGroup $baseDnGroups -bindUserDn $wsaBindUserDn -bindUserPass $wsaBindUserPassword -adGroups $adGroups -certificate $rootCaPath -protocol ldaps -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Assign Roles to Active Directory Groups for the Clustered Workspace ONE Access Instance
            Write-LogMessage -Type INFO -Message "Attempting to Assign Roles to Active Directory Groups for the Standalone Workspace ONE Access Instance"
            $StatusMsg =  Add-WorkspaceOneRole -server $wsaFqdn -user admin -pass $wsaAdminPassword -group $wsaSuperAdminGroup -role "Super Admin" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
            $StatusMsg =  Add-WorkspaceOneRole -server $wsaFqdn -user admin -pass $wsaAdminPassword -group $wsaDirAdminGroup -role "Directory Admin" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
            $StatusMsg =  Add-WorkspaceOneRole -server $wsaFqdn -user admin -pass $wsaAdminPassword -group $wsaReadOnlyGroup -role "ReadOnly Admin" -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # # Set WSA Password Policy
            # Request-WSAToken -fqdn $wsaFqdn -user admin -pass $wsaAdminPassword
            # Set-WSAPasswordPolicy -minLen $minLen -minLower $minLower -minUpper $minUpper -minDigit $minDigit -minSpecial $minSpecial -history $history -maxConsecutiveIdenticalCharacters $maxConsecutiveIdenticalCharacters -maxPreviousPasswordCharactersReused $maxPreviousPasswordCharactersReused -tempPasswordTtlInHrs $tempPasswordTtlInHrs -passwordTtlInDays $passwordTtlInDays -notificationThresholdInDays $notificationThresholdInDays -notificationIntervalInDays $notificationIntervalInDays | Get-WSAPasswordPolicy
            # Set-WSAPasswordLockout -numAttempts $numAttempts -attemptInterval $attemptInterval -unlockInterval $unlockInterval
        }
    }
} Catch {
    Debug-CatchWriter -object $_
}


