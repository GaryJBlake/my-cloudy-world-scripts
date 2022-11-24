<#
    .SYNOPSIS
    Generates the operational verification report for Identity and Access Management

    .DESCRIPTION
    The Invoke-IamOperationalVerificationReport provides a single cmdlet to generate an operational verification report for Identity and Access Management.

    .EXAMPLE
    Invoke-IamOperationalVerificationReport.ps1 -sddcManagerFqdn ldn-vcf01.ldn.cloudy.io -sddcManagerUser admin@local -sddcManagerPass VMw@re1!VMw@re1! -wsaServer ldn-wsa01.ldn.cloudy.io -wsaUser admin -wsaPass VMw@re1! -domain ldn.cloudy.io -domainUser cloud-admin -domainPass VMw@re1! -reportPath F:\Reporting
    This example generates the operational verification report for Identity and Access Management.
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerFqdn,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerUser,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$sddcManagerPass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaServer,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaUser,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaPass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainUser,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainPass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$reportPath,
    [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Switch]$darkMode
)

Try {
    Clear-Host; Write-Host ""

    $defaultReport = Start-CreateReportDirectory -path $reportPath -sddcManagerFqdn $sddcManagerFqdn -reportType overview # Setup Report Location and Report File
    if (!(Test-Path -Path $reportPath)) {Write-Warning "Unable to locate report path $reportPath, enter a valid path and try again"; Write-Host ""; Break }
    if ($message = Test-VcfReportingPrereq) {Write-Warning $message; Write-Host ""; Break }
    $reportname = $defaultReport.Split('.')[0] + "-" + $sddcManagerFqdn.Split(".")[0] + ".htm"
    $workflowMessage = "Operational Verification Report for Identity and Access Management for VMware Cloud Foundation"
    Start-SetupLogFile -Path $reportPath -ScriptName $MyInvocation.MyCommand.Name # Setup Log Location and Log File
    Write-LogMessage -Type INFO -Message "Starting the Process of Creating a System Overview Report for $workflowMessage." -Colour Yellow
    Write-LogMessage -Type INFO -Message "Setting up the log file to path $logfile."
    Write-LogMessage -Type INFO -Message "Setting up report folder and report $reportName."

    Write-LogMessage -Type INFO -Message "Generating $workflowMessage."
    $iamReportHtml = F:\my-cloudy-world\PowerShell\vvs\functions\iam\Publish-IamOperationalVerification -server $sddcManagerFqdn -user $sddcManagerUser -pass $sddcManagerPass -wsaServer $wsaServer -wsaUser $wsaUser -wsaPass $wsaPass -domain $domain -domainUser $domainUser -domainPass $domainPass 
    
    $reportData += $iamReportHtml

    if ($PsBoundParameters.ContainsKey("darkMode")) {
        $reportHeader = Get-ClarityReportHeader -dark
    } else {
        $reportHeader = Get-ClarityReportHeader
    }
    $reportNavigation = Get-ClarityReportNavigation -reportType overview
    $reportFooter = Get-ClarityReportFooter
    $report = $reportHeader
    $report += $reportNavigation
    $report += $reportData
    $report += $reportFooter

    # Generate the report to an HTML file and then open it in the default browser
    Write-LogMessage -Type INFO -Message "Generating the Final Report and Saving to ($reportName)."
    $report | Out-File $reportName
    if ($PSEdition -eq "Core" -and ($PSVersionTable.OS).Split(' ')[0] -ne "Linux") {
        Invoke-Item $reportName
    } elseif ($PSEdition -eq "Desktop") {
        Invoke-Item $reportName
    }
}
Catch {
    Debug-CatchWriter -object $_
}