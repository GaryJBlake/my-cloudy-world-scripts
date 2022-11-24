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
    Configure the Disaster Recovery Management Components for the Management Domain

    .DESCRIPTION
    The pdrDeployDrComponents.ps1 provides a single script to deploy Site Recovery Manager and vSphere
    Replication as defined by the Site Protection and Disaster Recovery Validated Solution

    .EXAMPLE
    pdrDeployDrComponents.ps1 -sddcManagerFqdn sfo-vcf01.sfo.rainpole.io -sddcManagerUser administrator@vsphere.local -sddcManagerPass VMw@re1! -workbook F:\vvs\PnP.xlsx -filePath F:\vvs -domainType mgmt
    This example performs the deployment of Site Recovery Manager and vSphere Replication for the Management Domain using the parameters provided within the Planning and Preparation Workbook

    .EXAMPLE
    pdrDeployDrComponents.ps1 -sddcManagerFqdn sfo-vcf01.sfo.rainpole.io -sddcManagerUser administrator@vsphere.local -sddcManagerPass VMw@re1! -workbook F:\vvs\PnP.xlsx -filePath F:\vvs -domainType wld
    This example performs the deployment of Site Recovery Manager and vSphere Replication for the VI Workload Domain using the parameters provided within the Planning and Preparation Workbook
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerFqdn,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerUser,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerPass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$workbook,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$filePath,
    [Parameter (Mandatory = $true)] [ValidateSet('mgmt','wld')] [String]$domainType
)

Clear-Host; Write-Host ""

Start-SetupLogFile -Path $filePath -ScriptName $MyInvocation.MyCommand.Name
Write-LogMessage -Type INFO -Message "Starting the Process of Deploying Site Recovery Manager and vSphere Replication for Site Protection and Disaster Recovery for VMware Cloud Foundation" -Colour Yellow
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

            $sddcDomain                         = $pnpWorkbook.Workbook.Names["$($domainType)_sddc_domain"].Value
            $vrmsFolderName                     = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_vm_folder"].Value
            $vrmsFqdn                           = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_fqdn"].Value
            $vrmsIpAddress                      = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_mgmt_ip"].Value
            $vrmsGateway                        = $pnpWorkbook.Workbook.Names["$($domainType)_az1_mgmt_gateway_ip"].Value
            $vrmsNetPrefix                      = ($pnpWorkbook.Workbook.Names["$($domainType)_az1_mgmt_cidr"].Value -Split "/")[-1]
            $vrmsNetworkSearchPath              = $pnpWorkbook.Workbook.Names["child_dns_zone"].Value
            $vrmsVaRootPassword                 = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_root_password"].Value
            $vrmsVaAdminPassword                = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_admin_password"].Value
            
            $vrmsCertPassword                   = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_p12_password"].Value
            $vrmsSiteName                       = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_site_name"].Value
            $vrmsAdminEmail                     = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_admin_email"].Value
            $replicationPortgroup               = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_pg"].Value
            $replicationVlan                    = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_vlan"].Value
            $replicationIpAddress               = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_vrms_ip"].Value
            $replicationSubnet                  = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_cidr"].Value
            $replicationGateway                 = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_gateway_ip"].Value
            $replicationNetmask                 = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_mask"].Value
            $remoteReplicationNetwork           = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_recovery_replication_cidr"].Value
            $replicationEsxiIps                 = @(($pnpWorkbook.Workbook.Names["$($domainType)_az1_host1_vrms_ip"].Value),($pnpWorkbook.Workbook.Names["$($domainType)_az1_host2_vrms_ip"].Value),($pnpWorkbook.Workbook.Names["$($domainType)_az1_host3_vrms_ip"].Value),($pnpWorkbook.Workbook.Names["$($domainType)_az1_host4_vrms_ip"].Value))
            
            $srmFolderName                      = $pnpWorkbook.Workbook.Names["$($domainType)_srm_vm_folder"].Value
            $srmFqdn                            = $pnpWorkbook.Workbook.Names["$($domainType)_srm_fqdn"].Value
            $srmIpAddress                       = $pnpWorkbook.Workbook.Names["$($domainType)_srm_ip"].Value
            $srmGateway                         = $pnpWorkbook.Workbook.Names["$($domainType)_az1_mgmt_gateway_ip"].Value
            $srmNetPrefix                       = ($pnpWorkbook.Workbook.Names["$($domainType)_az1_mgmt_cidr"].Value -Split "/")[-1]
            $srmNetworkSearchPath               = $pnpWorkbook.Workbook.Names["child_dns_zone"].Value
            $srmVaRootPassword                  = $pnpWorkbook.Workbook.Names["$($domainType)_srm_root_password"].Value
            $srmVaAdminPassword                 = $pnpWorkbook.Workbook.Names["$($domainType)_srm_admin_password"].Value
            $srmDbPassword                      = $pnpWorkbook.Workbook.Names["$($domainType)_srm_database_password"].Value
            $srmCertPassword                    = $pnpWorkbook.Workbook.Names["$($domainType)_srm_p12_password"].Value
            $srmSiteName                        = $pnpWorkbook.Workbook.Names["$($domainType)_srm_site_name"].Value
            $srmAdminEmail                      = $pnpWorkbook.Workbook.Names["$($domainType)_srm_admin_email"].Value
            $srmLicenseKey                      = $pnpWorkbook.Workbook.Names["srm_license"].Value

            $vrmsOvf                            = "\vrms\vSphere_Replication_OVF10.ovf"
            if (!(Test-Path ($filePath + "\" + $vrmsOvf) )) { Write-LogMessage -Type ERROR -Message "Unable to Find OVF File: $vrmsOvf, check details and try again" -Colour Red; Break } else { Write-LogMessage -Type INFO -Message "Found OVF File: $vrmsOvf" }
            
            $vrmsPem                            = $pnpWorkbook.Workbook.Names["mgmt_vrms_hostname"].Value + ".4.p12"
            if (!(Test-Path ($filePath + "\" + $vrmsPem) )) { Write-LogMessage -Type ERROR -Message "Unable to Find Certificate File: $vrmsPem, check details and try again" -Colour Red; Break } else { Write-LogMessage -Type INFO -Message "Found Certificate File: $vrmsPem" }

            $srmOvf                             = "\srm\srm-va_OVF10.ovf"
            if (!(Test-Path ($filePath + "\" + $srmOvf) )) { Write-LogMessage -Type ERROR -Message "Unable to Find OVF File: $srmOvf, check details and try again" -Colour Red; Break } else { Write-LogMessage -Type INFO -Message "Found OVF File: $srmOvf" }
            
            $srmPem                             = $pnpWorkbook.Workbook.Names["mgmt_srm_hostname"].Value + ".4.p12" 
            if (!(Test-Path ($filePath + "\" + $srmPem) )) { Write-LogMessage -Type ERROR -Message "Unable to Find Certificate File: $srmPem, check details and try again" -Colour Red; Break } else { Write-LogMessage -Type INFO -Message "Found Certificate File: $srmPem" }

            # Create a Virtual Machine Folder for vSphere Replication
            Write-LogMessage -Type INFO -Message "Attempting to Create a Virtual Machine Folder for vSphere Replication"            
            $StatusMsg = Add-VMFolder -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -folderName $vrmsFolderName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
        
            # Deploy vSphere Replication
            $message = "Deploying vSphere Replication Virtual Appliance named ($vrmsFqdn)"
            Write-LogMessage -Type INFO -Message "Attempting to Deploy vSphere Replication"
            $StatusMsg = Install-vSphereReplicationManager -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -vrmsFqdn $vrmsFqdn -vrmsIpAddress $vrmsIpAddress -vrmsGateway $vrmsGateway -vrmsNetPrefix $vrmsNetPrefix -vrmsNetworkSearchPath $vrmsNetworkSearchPath -vrmsFolder $vrmsFolderName -vrmsVaRootPassword $vrmsVaRootPassword -vrmsVaAdminPassword $vrmsVaAdminPassword -vrmsOvfPath ($filePath + "\" + $vrmsOvf) -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg -match "SUCCESSFUL" ) { Write-LogMessage -Type INFO -Message "$($message): SUCCESSFUL" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
        
            # Replace the Certificate of vSphere Replication
            Write-LogMessage -Type INFO -Message "Attempting to Replace the Certificate of vSphere Replication"
            $StatusMsg = Install-VamiCertificate -server $vrmsFqdn -user admin -pass $vrmsVaAdminPassword -certFile ($filePath + "\" + $vrmsPem) -certPassword $vrmsCertPassword -solution VRMS -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
            
            # Waiting for the vSphere Replication Appliance to Reboot
            Do {
                Start-Sleep 2
                $vamiStatus = Test-VrmsVamiAuthentication -server $vrmsFqdn -user admin -pass $vrmsVaAdminPassword -ErrorAction SilentlyContinue
            } Until (($vamiStatus -eq $true))

            # Register vSphere Replication with vCenter Single Sign-On
            Write-LogMessage -Type INFO -Message "Attempting to Register vSphere Replication with vCenter Single Sign-On"
            $StatusMsg = Connect-DRSolutionTovCenter -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -applianceFqdn $vrmsFqdn -vamiAdminPassword $vrmsVaAdminPassword -siteName $vrmsSiteName -adminEmail $vrmsAdminEmail -solution VRMS -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg"; $ErrorMsg = '' } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta; $ErrorMsg = '' } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Create a Port Group for vSphere Replication Traffic
            Write-LogMessage -Type INFO -Message "Attempting to Create a Port Group for vSphere Replication Traffic"
            $StatusMsg = Add-VdsPortGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -portgroup $replicationPortgroup -vlan $replicationVlan -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Add a Network Adapter and Configure Static Routes for vSphere Replication
            Write-LogMessage -Type INFO -Message "Attempting to Add a Network Adapter and Configure Static Routes for vSphere Replication"
            $StatusMsg = Add-VrmsNetworkAdapter -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -vrmsFqdn $vrmsFqdn -vrmsRootPass $vrmsVaRootPassword -vrmsAdminPass $vrmsVaAdminPassword -vrmsIpAddress $vrmsIpAddress -replicationSubnet $replicationSubnet -replicationIpAddress $replicationIpAddress -replicationGateway $replicationGateway -replicationPortgroup $replicationPortgroup -replicationRemoteNetwork $remoteReplicationNetwork -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
            
            # Create a VMkernel Adapter on the ESXi Hosts for vSphere Replication Traffic
            Write-LogMessage -Type INFO -Message "Attempting to Create a VMkernel Adapter on the ESXi Hosts for vSphere Replication Traffic"
            $StatusMsg = Add-EsxiVrmsVMkernelPort -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -portgroup $replicationPortgroup -netmask $replicationNetmask -ipAddresses $replicationEsxiIps -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Configure ESXi Host Static Routes for vSphere Replication
            $message = "Configuring all ESXi Host with Static Routes for vSphere Replication"
            Write-LogMessage -Type INFO -Message "Attempting to Configure ESXi Host Static Routes for vSphere Replication"
            $StatusMsg = Add-EsxiVrmsStaticRoute -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -gateway $replicationGateway -subnet $replicationSubnet -portgroup $replicationPortgroup -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg -match "SUCCESSFUL" ) { Write-LogMessage -Type INFO -Message "$($message): SUCCESSFUL" } if ( $WarnMsg -match "SKIPPED" ) { Write-LogMessage -Type INFO -Message "$($message): SKIPPED" } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Create a Virtual Machine Folder for Site Recovery Manager
            Write-LogMessage -Type INFO -Message "Attempting to Create a Virtual Machine Folder for Site Recovery Manager"
            $StatusMsg = Add-VMFolder -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -folderName $srmFolderName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
        
            # Deploy Site Recovery Manager
            $message = "Deploying Site Recovery Manager Virtual Appliance named ($srmFqdn)"
            Write-LogMessage -Type INFO -Message "Attempting to Deploy Site Recovery Manager"
            $StatusMsg = Install-SiteRecoveryManager -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -srmFqdn $srmFqdn -srmIpAddress $srmIpAddress -srmGateway $srmGateway -srmNetPrefix $srmNetPrefix -srmNetworkSearchPath $srmNetworkSearchPath -srmFolder $srmFolderName -srmVaRootPassword $srmVaRootPassword -srmVaAdminPassword $srmVaAdminPassword -srmDbPassword $srmDbPassword -deploymentOption "standard" -srmOvfPath ($filePath + "\" + $srmOvf) -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg -match "SUCCESSFUL" ) { Write-LogMessage -Type INFO -Message "$($message): SUCCESSFUL" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
        
            # Replace the Certificate of Site Recovery Manager
            Write-LogMessage -Type INFO -Message "Attempting to Replace the Certificate of Site Recovery Manager"
            $StatusMsg = Install-VamiCertificate -server $srmFqdn -user admin -pass $srmVaAdminPassword -certFile ($filePath + "\" + $srmPem) -certPassword $srmCertPassword -solution SRM -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
            
            # Waiting for the Site Recoovery Manager Appliance to Reboot
            Do {
                Start-Sleep 2
                $vamiStatus = Test-SrmVamiAuthentication -server $srmFqdn -user admin -pass $srmVaAdminPassword -ErrorAction SilentlyContinue
            } Until (($vamiStatus -eq $true))

            # Register Site Recovery Manager with vCenter Single Sign-On
            Write-LogMessage -Type INFO -Message "Attempting to Register Site Recovery Manager with vCenter Single Sign-On"
            $StatusMsg = Connect-DRSolutionTovCenter -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -applianceFqdn $srmFqdn -vamiAdminPassword $srmVaAdminPassword -siteName $srmSiteName -adminEmail $srmAdminEmail -solution SRM -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg"; $ErrorMsg = '' } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta; $ErrorMsg = '' } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Assign Licenses to Site Recovery Manager
            $message = "Adding and Assigning License key ($srmLicenseKey) for Site Recovery Manager to vCenter Server: SUCCESSFUL"
            Write-LogMessage -Type INFO -Message "Attempting to Assign Licenses to Site Recovery Manager"
            $StatusMsg = Add-SrmLicenseKey -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -srmLicenseKey $srmLicenseKey -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg -match "SUCCESSFUL" ) { Write-LogMessage -Type INFO -Message "$($message): SUCCESSFUL" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}
