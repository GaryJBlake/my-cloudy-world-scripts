# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

<#
    .NOTES
    ===================================================================================================================
    Created by:  Gary Blake - Senior Staff Solutions Architect
    Date:   2022-10-10
    Copyright 2021-2022 VMware, Inc.
    ===================================================================================================================
    
    .SYNOPSIS
    Remove Solution Interoperability for Identity and Access Management

    .DESCRIPTION
    The iamSolutionInteroperability.ps1 provides a single script to remove the configuration of Solution 
    Interoperability as defined by the Identity and Access Management for VMware Cloud Foundation validated solution.

    .EXAMPLE
    iamSolutionInteroperability.ps1 -sddcManagerFqdn sfo-vcf01.sfo.rainpole.io -sddcManagerUser administrator@vsphere.local -sddcManagerPass VMw@re1! -workbook F:\vvs\PnP.xlsx
    This example performs the removal of the configuration of Solution Interoperability using the parameters provided within the Planning and Preparation Workbook
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerFqdn,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerUser,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerPass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$workbook
)

Clear-Host; Write-Host ""

Start-SetupLogFile -Path $filePath -ScriptName $MyInvocation.MyCommand.Name
Write-LogMessage -Type INFO -Message "Starting the Process of Removing Solution Interoperability for Identity and Access Management for VMware Cloud Foundation" -Colour Yellow
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

            $wsaFqdn                            = $pnpWorkbook.Workbook.Names["region_wsa_fqdn"].Value
            $wsaAdapterName                     = $wsaFqdn
            $wsaVmName                          = $pnpWorkbook.Workbook.Names["region_wsa_hostname"].Value
            $wsaRootPassword                    = $pnpWorkbook.Workbook.Names["standalone_wsa_appliance_root_password"].Value
            $wsaAgentGroupName                  = "Workspace ONE Access (IAM) - Appliance Agent Group"
            $photonAgentGroupName               = "Photon OS (IAM) - Appliance Agent Group"

            if ((Get-VCFvROPS).status -eq "ACTIVE") {
                Write-LogMessage -Type INFO -Message "Remove Integration with vRealize Operations Manager"

                # Remove the VMware Identity Manager Adapter for the Standalone Workspace ONE Access Instance
                Write-LogMessage -Type INFO -Message "Attempting to Remove the VMware Identity Manager Adapter for the Standalone Workspace ONE Access Instance"
                $StatusMsg = Undo-vROPSAdapter -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -adapterName $wsaAdapterName -adapterType IdentityManagerAdapter -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
                if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
                
                # Remove the Ping Adapter for the Standalone Workspace ONE Access Instance
                Write-LogMessage -Type INFO -Message "Attempting to Remove the Ping Adapter for the Standalone Workspace ONE Access Instance"
                $StatusMsg = Undo-vROPSAdapter -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -adapterName $wsaVmName -adapterType PingAdapter -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
                if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
            } else {
                Write-LogMessage -Type INFO -Message "Remove Integration with vRealize Operations Manager, Not Installed: SKIPPED" -Colour Cyan
            }

            if ((Get-VCFvRLI).status -eq "ACTIVE") {
                # Write-LogMessage -Type INFO -Message "Remove Integration with vRealize Log Insight"

                # Disable the vRealize Log Insight Agent on the Standalone Workspace ONE Access Appliance
                Write-LogMessage -Type INFO -Message "Attempting to Disable the vRealize Log Insight Agent on the Standalone Workspace ONE Access Appliance"
                $StatusMsg = Undo-vRLIPhotonAgent -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -vmName $wsaVmName -vmRootPass $wsaRootPassword -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
                if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

                # Remove the Identity Manager Agent Group for the Standalone Workspace ONE Access from vRealize Log Insight
                Write-LogMessage -Type INFO -Message "Attempting to Remove the Identity Manager Agent Group for the Standalone Workspace ONE Access from vRealize Log Insight"
                $StatusMsg = Undo-vRLIAgentGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -agentGroupName $wsaAgentGroupName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
                if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }

                # Remove the Photon vRealize Log Insight Agent for the Standalone Workspace ONE Access Appliance
                Write-LogMessage -Type INFO -Message "Attempting to Remove the Phont vRealize Log Insight Agent for the Standalone Workspace ONE Access Appliance"
                $StatusMsg = Undo-vRLIAgentGroup -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -agentGroupName $photonAgentGroupName -WarningAction SilentlyContinue -ErrorAction SilentlyContinue -WarningVariable WarnMsg -ErrorVariable ErrorMsg
                if ( $StatusMsg ) { Write-LogMessage -Type INFO -Message "$StatusMsg" } if ( $WarnMsg ) { Write-LogMessage -Type WARNING -Message $WarnMsg -Colour Magenta } if ( $ErrorMsg ) { Write-LogMessage -Type ERROR -Message $ErrorMsg -Colour Red }
            } else {
                Write-LogMessage -Type INFO -Message "Remove Integration with vRealize Log Insight, Not Installed: SKIPPED" -Colour Cyan
            }
        }
    }
}
Catch {
    Debug-CatchWriter -object $_
}