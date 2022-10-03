<#
    .NOTES
    ===================================================================================================================
    Created by:		Gary Blake
    Date:			03/10/2022
    Organization:	VMware
    Blog:           my-cloudy-world.com
    Twitter:        @GaryJBlake
    ===================================================================================================================

    .SYNOPSIS
    Enables SSH on ESXi

    .DESCRIPTION
    This scripts enables or disables SSH for ESXi

    .EXAMPLE
    .\esxiSshStatus.ps1 -esxiUser root -esxiPass VMw@re1! -esxiListFile ./esxiList.txt -logPath /Users/gblake/Downloads/cloudyLab -status start
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$esxiUser,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$esxiPass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$esxiListFile,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$logPath,
    [Parameter (Mandatory = $true)] [ValidateSet("start","stop")] [String]$status
)

Clear-Host; Write-Host ""
Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null

Start-SetupLogFile -Path $logPath -ScriptName $MyInvocation.MyCommand.Name
Write-LogMessage -Type INFO -Message "Starting the Process of Setting the Status of SSH on ESXi Hosts" -Colour Yellow
Write-LogMessage -Type INFO -Message "Setting up the log file to path $logfile"

if (!(Test-Path -Path $esxiListFile)) {
    Write-LogMessage -Type ERROR -Message "ESXi List '$esxiListFile' File Not Found"
} else {
    $esxilist = Get-Content $esxiListFile
}

if ($status -eq "start") {
    Try {
        foreach ($esxi in $esxilist) {
            Write-LogMessage -Type INFO -Message "Attempting to Connect to ESXi Host '$esxi'"
            if (Test-Connection -ComputerName $esxi -Quiet -Count 1) {
                Connect-VIServer -Server $esxi -User $esxiUser -Password $esxiPass -Protocol https | Out-Null
                Write-LogMessage -Type INFO -Message "Starting SSH on ESXi Host '$esxi'"
                $sshStatus = Get-VMHostService  -VMHost $esxi | Where-Object {$psitem.key -eq "TSM-SSH"}
                if ($sshStatus.Running -eq $False) {
                    Get-VMHostService | Where-Object {$psitem.key -eq "TSM-SSH"} | Start-VMHostService -Confirm:$false | Out-Null
                    Get-VMHostservice | Where-object {$_.key -eq "TSM-SSH" } | Set-VMHostService -policy "On" -Confirm:$false | Out-Null
                    $sshStatus = Get-VMHostService -VMHost $esxi | Where-Object {$psitem.key -eq "TSM-SSH"}
                    if ($sshStatus.Running -eq $True) {
                        Write-LogMessage -Type INFO -Message "Starting SSH on ESXi Host '$esxi': SUCCESSFUL" -Colour Green
                    } else {
                        Write-LogMessage -Type INFO -Message "Starting SSH on ESXi Host '$esxi': POST_VALIDATION_FAILED" -Colour Red
                    }
                } else {
                    Write-LogMessage -Type INFO -Message "SSH Already Running on ESXi Host '$esxi'" -Colour Cyan
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to host '$esxi'. Check your environment and try again." -Colour Red
            }

        }
    } Catch {
        Debug-CatchWriter -object $_
        Exit
    }
}

if ($status -eq "stop") {
    Try {
        foreach ($esxi in $esxilist) {
            Write-LogMessage -Type INFO -Message "Attempting to Connect to ESXi Host '$esxi'"
            if (Test-Connection -ComputerName $esxi -Quiet -Count 1) {
                Connect-VIServer -Server $esxi -User $esxiUser -Password $esxiPass -Protocol https | Out-Null
                Write-LogMessage -Type INFO -Message "Stopping SSH on ESXi Host '$esxi'"
                $sshStatus = Get-VMHostService -VMHost $esxi | Where-Object {$psitem.key -eq "TSM-SSH"}
                if ($sshStatus.Running -eq $True) {
                    Get-VMHostService | Where-Object {$psitem.key -eq "TSM-SSH"} | Stop-VMHostService -Confirm:$false | Out-Null
                    Get-VMHostservice | Where-object {$_.key -eq "TSM-SSH" } | Set-VMHostService -policy "Off" -Confirm:$false | Out-Null
                    $sshStatus = Get-VMHostService -VMHost $esxi | Where-Object {$psitem.key -eq "TSM-SSH"}
                    if ($sshStatus.Running -eq $False) {
                        Write-LogMessage -Type INFO -Message "Stopping SSH on ESXi Host '$esxi': SUCCESSFUL" -Colour Green
                    } else {
                        Write-LogMessage -Type INFO -Message "Stopping SSH on ESXi Host '$esxi': POST_VALIDATION_FAILED" -Colour Red
                    }
                } else {
                    Write-LogMessage -Type INFO -Message "SSH Already Stopped on ESXi Host '$esxi'" -Colour Cyan
                }
                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot connect to host '$esxi'. Check your environment and try again." -Colour Red
            }

        }
    } Catch {
        Debug-CatchWriter -object $_
        Exit
    }
}