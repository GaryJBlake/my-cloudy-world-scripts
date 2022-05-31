# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

<#
    .NOTES
    ===================================================================================================================
    Created by:  Gary Blake - Senior Staff Solutions Architect
    Date:   2022-03-17
    Copyright 2021-2022 VMware, Inc.
    ===================================================================================================================
    .CHANGE_LOG

    - 1.0.000   (Gary Blake / 2022-03-17) - Initial script creation

    ===================================================================================================================
    
    .SYNOPSIS
    Perform health checks across and SDDC Manager instance

    .DESCRIPTION
    The preChecks.ps1 provides a single script to perform health checks across an SDDC Manager instance

    .EXAMPLE
    preChecks.ps1 -sddcManagerFqdn sfo-vcf01.sfo.rainpole.io -sddcManagerUser administrator@vsphere.local -sddcManagerPass VMw@re1!
    This example performs the health checks
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerFqdn,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerUser,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerPass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerRootPass
)

Clear-Host; Write-Host ""

Start-SetupLogFile -Path $filePath -ScriptName $MyInvocation.MyCommand.Name
Write-LogMessage -Type INFO -Message "Starting the Process of Running Health Checks for VMware Cloud Foundation Instance ($sddcManagerFqdn)" -Colour Yellow
Write-LogMessage -Type INFO -Message "Setting up the log file to path $logfile"
$reportName = ".\reports\" + $sddcManagerFqdn.Split(".")[0] + "-healthCheck.htm"

$reportFormat = @"
<style>
    h1 {
        font-family: Arial, Helvetica, sans-serif;
        color: #e68a00;
        font-size: 28px;
    }
    h2 {
        font-family: Arial, Helvetica, sans-serif;
        color: #000099;
        font-size: 20px;
    }
    h3 {
        font-family: Arial, Helvetica, sans-serif;
        color: #000099;
        font-size: 16px;
    }
    table {
		font-size: 12px;
		border: 0px; 
		font-family: monospace;
	} 
    td {
		padding: 4px;
		margin: 0px;
		border: 0;
	}
    th {
        background: #395870;
        background: linear-gradient(#49708f, #293f50);
        color: #fff;
        font-size: 11px;
        text-transform: uppercase;
        padding: 10px 15px;
        vertical-align: middle;
	}
    tbody tr:nth-child(even) {
        background: #f0f0f2;
    }
        #CreationDate {
        font-family: Arial, Helvetica, sans-serif;
        color: #ff3300;
        font-size: 12px;
    }
</style>
"@

# Define the Report Tile
$reportTitle = "<h1>Health Check Report for SDDC Manager: $sddcManagerFqdn</h1>"

# # Execute SoS Health Check for the SDDC Manager Instance
# Write-LogMessage -Type INFO -Message "Executing an SoS Health Check on the SDDC Manager Appliance for all Workload Domains"
# $command = "/opt/vmware/sddc-support/sos --health-check --domain-name ALL"
# $sosHealthCheckHtml = Invoke-SddcCommand -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -rootPass $sddcManagerRootPass -command $command -html

# Execute SoS Health Check for the SDDC Manager Instance
Write-LogMessage -Type INFO -Message "Executing an SoS Health Check on the SDDC Manager Appliance for all Workload Domains"
$command = "cat /var/log/vmware/vcf/sddc-support/``ls -t /var/log/vmware/vcf/sddc-support/ | grep healthcheck | head -1``/health-report.log | grep -v -E `"(SoS|Health|\+|\|)`" | sed 's,RED,<font color>=`"`#ff0000`">&</font>, ; s,YELLOW,<font color>=`"`#ff9f00`">&</font>, ; s,GREEN,<font color>=`"`#00ff00`">&</font>, ; s,  *, ,g'"

#$command = "cat /var/log/vmware/vcf/sddc-support/``ls -t /var/log/vmware/vcf/sddc-support/ | grep healthcheck | head -1``/health-report.log | grep -v -E `"(SoS|Health|\+|\|)`" | sed 's,RED,\x1B[31m&\x1B[0m, ; s,YELLOW,\x1B[33m&\x1B[0m, ; s,GREEN,\x1B[32m&\x1B[0m, ; s,  *, ,g'"
$sddcHealthHtml = Invoke-SddcCommand -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -rootPass $sddcManagerRootPass -command $command -html

# # Execute SoS Connectivity Helath Check for the SDDC Manager Instance
# $command = "/opt/vmware/sddc-support/sos --connectivity-health"
# Write-LogMessage -Type INFO -Message "Executing SoS Connectivity Health Check Command ($command) on SDDC Manager Appliance ($($sddcManagerFqdn.Split(".")[0])) "
# $Global:connectivityHealthHtml = Invoke-SddcCommand -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -rootPass $sddcManagerRootPass -command $command -html

# Check the Status of the Backup Account on the SDDC Manager Instance
$command = "chage -l backup"
Write-LogMessage -Type INFO -Message "Check the Status of the Backup Account Using Command ($command) on SDDC Manager Appliance ($($sddcManagerFqdn.Split(".")[0])) "
$backupUserHtml = Invoke-SddcCommand -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -rootPass $sddcManagerRootPass -command $command -html

# Generating the System Password Report from SDDC Manager 
Write-LogMessage -Type INFO -Message "Generating the System Password Report from SDDC Manager ($sddcManagerFqdn)"
$systemPasswordHtml = Export-SystemPassword -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -html

$datastoreTitle = "<h2>Datastore Capacity for all Workload Domains</h2>"
# Generating Datastore Capacity Report for all Workload Domains
Write-LogMessage -Type INFO -Message "Generating Datastore Capacity Report for all Workload Domains"
$allWorkloadDomain = Get-VCFWorkloadDomain | Select-Object name
foreach ($workloadDomain in $allWorkloadDomain) {   
    $storageCapacityHtml = Export-StorageCapacity -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -sddcDomain $workloadDomain.name -html
    $allStorageCapacityHtml += $storageCapacityHtml
}

$coreDumpTitle = "<h2>ESXi Host Core Dump Configuration for all Workload Domains</h2>"
# Generating ESXi Host Core Dump Configuaration for all Workload Domains
Write-LogMessage -Type INFO -Message "Generating ESXi Host Core Dump Configuaration for all Workload Domains"
$allWorkloadDomain = Get-VCFWorkloadDomain | Select-Object name
foreach ($workloadDomain in $allWorkloadDomain) {
    Write-LogMessage -Type INFO -Message "Gathering ESXi Host Core Dump Configuaration for Workload Domain ($($workloadDomain.name))"
    $esxiCoreDumpHtml = Export-EsxiCoreDumpConfig -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -sddcDomain $workloadDomain.name -html
    $allEsxiCoreDumpHtml += $esxiCoreDumpHtml
}

# Combine all information gathered into a single HTML report
$report = ConvertTo-HTML -Body "$reportTitle $sddcHealthHtml $connectivityHealthHtml $sosHealthCheckHtml $backupUserHtml $systemPasswordHtml $datastoreTitle $allStorageCapacityHtml $coreDumpTitle $allEsxiCoreDumpHtml " -Title "SDDC Manager Health Check Report" -Head $reportFormat -PostContent "<p>Creation Date: $(Get-Date)<p>"

# Generate the report to an HTML file and then open it in the default browser
Write-LogMessage -Type INFO -Message "Generating the Final Report and Saving to ($reportName)"
$report | Out-File $reportName
Invoke-Item $reportName

