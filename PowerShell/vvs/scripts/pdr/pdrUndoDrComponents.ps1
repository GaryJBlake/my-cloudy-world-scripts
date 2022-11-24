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
    Remove the Disaster Recovery Management Components for the Management Domain

    .DESCRIPTION
    The pdrUndoDrComponents.ps1.ps1 provides a single script to remove Site Recovery Manager and vSphere
    Replication as defined by the Site Protection and Disaster Recovery Validated Solution

    .EXAMPLE
    pdrUndoDrComponents.ps1.ps1 -sddcManagerFqdn sfo-vcf01.sfo.rainpole.io -sddcManagerUser administrator@vsphere.local -sddcManagerPass VMw@re1! -workbook F:\vvs\PnP.xlsx -filePath F:\vvs -domainType mgmt
    This example performs the removal of Site Recovery Manager and vSphere Replication for the Management Domain using the parameters provided within the Planning and Preparation Workbook

    .EXAMPLE
    pdrUndoDrComponents.ps1.ps1 -sddcManagerFqdn sfo-vcf01.sfo.rainpole.io -sddcManagerUser administrator@vsphere.local -sddcManagerPass VMw@re1! -workbook F:\vvs\PnP.xlsx -filePath F:\vvs -domainType wld
    This example performs the removal of Site Recovery Manager and vSphere Replication for the the VI Workload Domain using the parameters provided within the Planning and Preparation Workbook
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
Write-LogMessage -Type INFO -Message "Starting the Process of Removing Site Recovery Manager and vSphere Replication for Site Protection and Disaster Recovery for VMware Cloud Foundation" -Colour Yellow
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
            $srmLicenseKey                      = $pnpWorkbook.Workbook.Names["srm_license"].Value
            $srmFqdn                            = $pnpWorkbook.Workbook.Names["$($domainType)_srm_fqdn"].Value
            $srmHostname                        = $pnpWorkbook.Workbook.Names["$($domainType)_srm_hostname"].Value
            $srmFolderName                      = $pnpWorkbook.Workbook.Names["$($domainType)_srm_vm_folder"].Value
            $srmVaAdminPassword                 = $pnpWorkbook.Workbook.Names["$($domainType)_srm_admin_password"].Value
            $vrmsFqdn                           = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_fqdn"].Value
            $vrmsHostname                       = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_hostname"].Value
            $vrmsVaAdminPassword                = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_admin_password"].Value
            $vrmsFolderName                     = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_vm_folder"].Value
            $replicationPortgroup               = $pnpWorkbook.Workbook.Names["$($domainType)_vrms_pg"].Value
            [IPAddress]$replicationNetwork      = ($pnpWorkbook.Workbook.Names["$($domainType)_vrms_cidr"].Value).Split("/")[0]

            # Remove License for Site Recovery Manager
            $message = "Removing License key ($srmLicenseKey) for Site Recovery Manager from vCenter Server: SUCCESSFUL"
            Write-LogMessage -Type INFO -Message "Attempting to Remove License for Site Recovery Manager"
            $StatusMsg = Undo-SrmLicenseKey -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -srmLicenseKey $srmLicenseKey -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg -match "SUCCESSFUL" ) { Write-LogMessage -Type INFO -Message "$($message): SUCCESSFUL" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta; $ErrorMsg = $null } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Unregister Site Recovery Manager with with vCenter Server
            Write-LogMessage -Type INFO -Message "Attempting to Unregister Site Recovery Manager with with vCenter Server"
            $StatusMsg = Undo-DRSolutionTovCenter -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -applianceFqdn $srmFqdn -vamiAdminPassword $srmVaAdminPassword -solution SRM -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta; $ErrorMsg = $null } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Shutdown and Delete the Site Recovery Manager Virtual Appliance
            Write-LogMessage -Type INFO -Message "Attempting to Shutdown and Delete the Site Recovery Manager Virtual Appliance"
            $StatusMsg = Undo-SiteRecoveryManager -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -srmHostname $srmHostname -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Remove the Virtual Machine Folder for Site Recovery Manager
            Write-LogMessage -Type INFO -Message "Attempting to Remove the Virtual Machine Folder for vSphere Replication"
            $StatusMsg = Undo-VMFolder -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -foldername $srmFolderName -folderType VM -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Unregister vSphere Replication appliance with vCenter Server
            Write-LogMessage -Type INFO -Message "Attempting to Unregister vSphere Replication appliance with vCenter Server"
            $StatusMsg = Undo-DRSolutionTovCenter -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -applianceFqdn $vrmsFqdn -vamiAdminPassword $vrmsVaAdminPassword -solution VRMS -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta; $ErrorMsg = $null } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
            
            # Shutdown and Delete the vSphere Replication Virtual Appliance
            Write-LogMessage -Type INFO -Message "Attempting to Shutdown and Delete the vSphere Replication Virtual Appliance"
            $StatusMsg = Undo-vSphereReplicationManager -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -vrmsHostname $vrmsHostname -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Remove a VMkernel Adapter from the ESXi Hosts for vSphere Replication Traffic
            Write-LogMessage -Type INFO -Message "Attempting to Remove a VMkernel Adapter from the ESXi Hosts for vSphere Replication Traffic"
            $StatusMsg = Undo-EsxiVrmsVMkernelPort -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -portgroup $replicationPortgroup -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Remove ESXi Host Static Routes for vSphere Replication
            $message = "Removed all ESXi Host with Static Routes for vSphere Replication"
            Write-LogMessage -Type INFO -Message "Attempting to Remove ESXi Host Static Routes for vSphere Replication"
            $StatusMsg = Undo-EsxiVrmsStaticRoute -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -network $replicationNetwork.IPAddressToString -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg -match "SUCCESSFUL" ) { Write-LogMessage -Type INFO -Message "$($message): SUCCESSFUL" } if ( $WarnMsg -match "SKIPPED" ) { Write-LogMessage -Type INFO -Message "$($message): SKIPPED" } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Remove a VMkernel Adapter on the ESXi Hosts for vSphere Replication Traffic
            Write-LogMessage -Type INFO -Message "Attempting to Remove a VMkernel Adapter on the ESXi Hosts for vSphere Replication Traffic"
            $StatusMsg = Undo-EsxiVrmsVMkernelPort -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -portgroup $replicationPortgroup -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

            # Remove the Port Group for vSphere Replication Traffic
            Write-LogMessage -Type INFO -Message "Attempting to Remove the Port Group for vSphere Replication Traffic"
            $StatusMsg = Undo-VdsPortGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -portgroup $replicationPortgroup -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
        
            # Remove the Virtual Machine Folder for vSphere Replication
            Write-LogMessage -Type INFO -Message "Attempting to Remove the Virtual Machine Folder for vSphere Replication"
            $StatusMsg = Undo-VMFolder -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -domain $sddcDomain -foldername $vrmsFolderName -folderType VM -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
            if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}