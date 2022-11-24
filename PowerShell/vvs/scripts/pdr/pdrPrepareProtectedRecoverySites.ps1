# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

<#
    .NOTES
    ===================================================================================================================
    Created by:  Gary Blake - Senior Staff Solutions Architect
    Date:   2022-11-01
    Copyright 2021-2022 VMware, Inc.
    ===================================================================================================================
    
    .SYNOPSIS
    Configure Protected and Recovery Sites for Site Protection and Disaster Recovery

    .DESCRIPTION
    The pdrPrepareProtectedRecoverySites.ps1 provides a single script to configure Protected and Recovery Sites as
    defined by the Site Protection and Disaster Recovery Validated Solution

    .EXAMPLE
    pdrPrepareProtectedRecoverySites.ps1 -sddcManagerFqdn sfo-vcf01.sfo.rainpole.io -sddcManagerUser administrator@vsphere.local -sddcManagerPass VMw@re1! -workbook F:\vvs\PnP.xlsx -filePath F:\vvs
    This example performs the configuration of the Protected and Recovery Sites using the parameters provided within the Planning and Preparation Workbook
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
Write-LogMessage -Type INFO -Message "Starting the Process of Configuring the Protected and Recovery Sites for Site Protection and Disaster Recovery for VMware Cloud Foundation" -Colour Yellow
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

            $sddcDomain                         = $pnpWorkbook.Workbook.Names["mgmt_sddc_domain"].Value
            $vrslcmFolderName                   = $pnpWorkbook.Workbook.Names["vrslcm_xreg_vm_folder"].Value
            $vrslcmVmList                       = $pnpWorkbook.Workbook.Names["xreg_vrslcm_hostname"].Value
            $wsaFolderName                      = $pnpWorkbook.Workbook.Names["xreg_wsa_vm_folder"].Value
            $vropsFolderName                    = $pnpWorkbook.Workbook.Names["xreg_vrops_vm_folder"].Value
            $vraFolderName                      = $pnpWorkbook.Workbook.Names["xreg_vra_vm_folder"].Value
            $wsaCertName                        = $pnpWorkbook.Workbook.Names["xreg_wsa_virtual_hostname"].Value
            $wsaRootPass                        = $pnpWorkbook.Workbook.Names["global_env_admin_password"].Value
            $serviceInterfaceIp                 = $pnpWorkbook.Workbook.Names["mgmt_srm_recovery_t1_si_ip"].Value 
            
            $ntpServer                          = $pnpWorkbook.Workbook.Names["xregion_ntp2_server"].Value
            $ntpServers                         = $pnpWorkbook.Workbook.Names["xregion_ntp1_server"].Value + " " + $pnpWorkbook.Workbook.Names["xregion_ntp2_server"].Value
            $ntpServerDesc                      = "VCF NTP Server 2"
            $dnsServers                         = $pnpWorkbook.Workbook.Names["xregion_dns1_ip"].Value + " " + $pnpWorkbook.Workbook.Names["xregion_dns2_ip"].Value
            $dnsSearchDomains                   = $pnpWorkbook.Workbook.Names["parent_dns_zone"].Value
            $environmentName                    = $pnpWorkbook.Workbook.Names["vrslcm_xreg_env"].Value

            $vraUser                            = $pnpWorkbook.Workbook.Names["local_configadmin_username"].Value
            $vraPass                            = $pnpWorkbook.Workbook.Names["local_configadmin_password"].Value
            
            $recoverySddcManagerFqdn            = $pnpWorkbook.Workbook.Names["mgmt_srm_recovery_sddc_manager_fqdn"].Value
            $recoverySddcManagerUser            = $pnpWorkbook.Workbook.Names["mgmt_srm_recovery_sddc_manager_user"].Value
            $recoverySddcManagerPass            = $pnpWorkbook.Workbook.Names["mgmt_srm_recovery_sddc_manager_password"].Value
            $recoverySddcDomain                 = $pnpWorkbook.Workbook.Names["mgmt_srm_recovery_sddc_manager_domain"].Value

            # Create a Virtual Machine Folder and Move the vRealize Suite Lifecycle Manager Virtual Machine in the Protected VMware Cloud Foundation Instance
            Write-LogMessage -Type INFO -Message "Attempting to Create a Virtual Machine Folder and Move the vRealize Suite Lifecycle Manager Virtual Machine in the Protected VMware Cloud Foundation Instance"
            $StatusMsg = Add-VMFolder -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -folderName $vrslcmFolderName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
            $StatusMsg = Move-VMtoFolder -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -vmList $vrslcmVmList -folder $vrslcmFolderName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Create Virtual Machine Folders for SDDC Management Components in the Recovery VMware Cloud Foundation Instance
            Write-LogMessage -Type INFO -Message "Attempting to Create Virtual Machine Folders for SDDC Management Components in the Recovery VMware Cloud Foundation Instance"
            
            Write-LogMessage -Type INFO -Message "Attempting to Create vRealize Suite Lifecycle Manager Virtual Machine Folder in the Recovery VMware Cloud Foundation Instance"
            $StatusMsg = Add-VMFolder -server $recoverySddcManagerFqdn -user $recoverySddcManagerUser -pass $recoverySddcManagerPass -domain $recoverySddcDomain -folderName $vrslcmFolderName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            Write-LogMessage -Type INFO -Message "Attempting to Create Workspace ONE Access Virtual Machine Folder in the Recovery VMware Cloud Foundation Instance"
            $StatusMsg = Add-VMFolder -server $recoverySddcManagerFqdn -user $recoverySddcManagerUser -pass $recoverySddcManagerPass -domain $recoverySddcDomain -folderName $wsaFolderName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            Write-LogMessage -Type INFO -Message "Attempting to Create vRealize Operations Virtual Machine Folder in the Recovery VMware Cloud Foundation Instance"
            $StatusMsg = Add-VMFolder -server $recoverySddcManagerFqdn -user $recoverySddcManagerUser -pass $recoverySddcManagerPass -domain $recoverySddcDomain -folderName $vropsFolderName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            Write-LogMessage -Type INFO -Message "Attempting to Create vRealize Automation Virtual Machine Folder in the Recovery VMware Cloud Foundation Instance"
            $StatusMsg = Add-VMFolder -server $recoverySddcManagerFqdn -user $recoverySddcManagerUser -pass $recoverySddcManagerPass -domain $recoverySddcDomain -folderName $vraFolderName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
        
            # Prepare Load Balancing Services for the vRealize Suite Components and the Clustered Workspace ONE Access Instance in the Recovery VMware Cloud Foundation Instance
            Write-LogMessage -Type INFO -Message "Attempting to Prepare Load Balancing Services for the vRealize Suite Components and the Clustered Workspace ONE Access Instance in the Recovery VMware Cloud Foundation Instance"
            $StatusMsg = Copy-vRealizeLoadBalancer -sddcManagerAFQDN $sddcManagerFqdn -sddcManagerAUser $sddcManagerUser -sddcManagerAPassword $sddcManagerPass -sddcManagerBFQDN $recoverySddcManagerFqdn -sddcManagerBUser $recoverySddcManagerUser -sddcManagerBPassword $recoverySddcManagerPass -serviceInterfaceIP $serviceInterfaceIP -wsaCertName $wsaCertName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Reconfigure DNS and Domain Search on the vRealize Suite Lifecycle Manager Appliance
            $message = "Reconfigure DNS and Domain Search on the vRealize Suite Lifecycle Manager Appliance"
            Write-LogMessage -Type INFO -Message "Attempting to Reconfigure DNS and Domain Search on the vRealize Suite Lifecycle Manager Appliance"
            $StatusMsg = Set-vRSLCMDnsConfig -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -dnsServers $dnsServers -dnsSearchDomains $dnsSearchDomains -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg -match "SUCCESSFUL" ) { Write-LogMessage -Type INFO -Message "$message : SUCCESSFUL" } if ( $WarnMsg -match "SKIPPED") { Write-LogMessage -Type WARNING -Message "$message : SKIPPED" -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Reconfigure NTP on the vRealize Suite Lifecycle Manager Appliance
            Write-LogMessage -Type INFO -Message "Attempting to Reconfigure NTP on the vRealize Suite Lifecycle Manager Appliance"
            $StatusMsg = Add-vRSLCMNtpServer -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -ntpServer $ntpServer -ntpServerDesc $ntpServerDesc -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Reconfigure DNS and Domain Search on the Clustered Workspace ONE Access Nodes
            $message = "Reconfigure DNS and Domain Search on the Clustered Workspace ONE Access Nodes"
            Write-LogMessage -Type INFO -Message "Attempting to Reconfigure DNS and Domain Search on the Clustered Workspace ONE Access Nodes"
            $StatusMsg = Set-WorkspaceOneDnsConfig -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -dnsServers $dnsServers -dnsSearchDomains $dnsSearchDomains -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg -match "SUCCESSFUL" ) { Write-LogMessage -Type INFO -Message "$message : SUCCESSFUL" } if ( $WarnMsg -match "SKIPPED") { Write-LogMessage -Type WARNING -Message "$message : SKIPPED" -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Reconfigure NTP on the Clustered Workspace ONE Access Nodes
            $message = "Reconfigure NTP on the Clustered Workspace ONE Access Nodes"
            Write-LogMessage -Type INFO -Message "Attempting to Reconfigure NTP on the Clustered Workspace ONE Access Nodes"
            $StatusMsg = Set-WorkspaceOneNtpConfig -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -rootPass $wsaRootPass $dnsServers -ntpServer $ntpServer -vrslcmIntegrated -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg -match "SUCCESSFUL" ) { Write-LogMessage -Type INFO -Message "$message : SUCCESSFUL" } if ( $WarnMsg -match "SKIPPED") { Write-LogMessage -Type WARNING -Message "$message : SKIPPED" -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Reconfigure DNS and Domain Search on the vRealize Operations Manager Analytics Cluster Nodes
            $message = "Reconfigure DNS and Domain Search on the vRealize Operations Manager Analytics Cluster Nodes"
            Write-LogMessage -Type INFO -Message "Attempting to Reconfigure DNS and Domain Search on the vRealize Operations Manager Analytics Cluster Nodes"
            $StatusMsg = Set-vROPSDnsConfig -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -environmentName $environmentName -dnsServers $dnsServers -dnsSearchDomains $dnsSearchDomains -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg -match "SUCCESSFUL" ) { Write-LogMessage -Type INFO -Message "$message : SUCCESSFUL" } if ( $WarnMsg -match "SKIPPED") { Write-LogMessage -Type WARNING -Message "$message : SKIPPED" -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Reconfigure NTP on the vRealize Operations Manager Analytics Cluster Nodes
            Write-LogMessage -Type INFO -Message "Attempting to Reconfigure NTP on the vRealize Operations Manager Analytics Cluster Nodes"
            $StatusMsg = Add-vROPSNtpServer -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -environmentName $environmentName -ntpServer $ntpServer -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Reconfigure DNS and Domain Search on the vRealize Automation Nodes
            $message = "Reconfigure DNS and Domain Search on the vRealize Automation Nodes"
            Write-LogMessage -Type INFO -Message "Attempting to Reconfigure DNS and Domain Search on the vRealize Automation Nodes"
            $StatusMsg = Set-vRADnsConfig -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -environmentName $environmentName -dnsServers $dnsServers -dnsSearchDomains $dnsSearchDomains -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg -match "SUCCESSFUL" ) { Write-LogMessage -Type INFO -Message "$message : SUCCESSFUL" } if ( $WarnMsg -match "SKIPPED") { Write-LogMessage -Type WARNING -Message "$message : SKIPPED" -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Reconfigure NTP on vRealize Automation
            $message = "Reconfigure NTP on vRealize Automation"
            Write-LogMessage -Type INFO -Message "Attempting to Reconfigure NTP on vRealize Automation"
            $StatusMsg = Set-vRANtpConfig -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vraUser $vraUser -vraPass $vraPass -environmentName $environmentName -ntpServers $ntpServers -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg -match "SUCCESSFUL" ) { Write-LogMessage -Type INFO -Message "$message : SUCCESSFUL" } if ( $WarnMsg -match "SKIPPED") { Write-LogMessage -Type WARNING -Message "$message : SKIPPED" -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}
