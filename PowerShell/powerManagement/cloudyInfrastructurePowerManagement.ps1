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
    Powers Up My Cloudy World Lab Infrastructure

    .DESCRIPTION
    This scripts powers up the My Cloudy World Lab Infrastructure.

    .EXAMPLE
    .\cloudyInfrastructurePowerManagement.ps1 -esxiFqdn lab01esx01.sddc.local -esxiUser root -esxiPass VMw@re1! -state startup -logPath /Users/gblake/Downloads/cloudyLab

    .EXAMPLE
    .\cloudyInfrastructurePowerManagement.ps1 -esxiFqdn lab01esx01.sddc.local -esxiUser root -esxiPass VMw@re1! -state shutdown -logPath /Users/gblake/Downloads/cloudyLab
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$esxiFqdn,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$esxiUser,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$esxiPass,
    [Parameter (Mandatory = $true)] [ValidateSet('startup','shutdown')] [String]$state,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$logPath
)

# Virtual Machine Names
$activeDirectoryDc      = "lab01ad01"
$infraVcenter           = "lab01-vc01"
$pattern                = "cloudy*"
$timeout                = "90"

Function startupNode ($node, $nodeDescription) {
    Write-LogMessage -Type INFO -Message "Attempting to Start Up $nodeDescription '$node'"
    $vmObject = Get-VMGuest -VM $node -Server $esxiFqdn | Where-Object VmUid -match $esxiFqdn
    if ($vmObject.State -eq 'Running') {
        Write-LogMessage -Type INFO -Message "Powering On Node '$($node.name)' Already Running: SKIPPED" -Colour Cyan
    } else {
        Start-VM -VM $node | Out-Null
        $vmObject = Get-VMGuest -VM $node -Server $esxiFqdn | Where-Object VmUid -match $esxiFqdn
        Write-LogMessage -Type INFO -Message "Powering On Node '$($node)'..."
        While (($vmObject.State -ne 'Running') -AND ($count -ne $timeout)) {
            Start-Sleep -Seconds 1
            $count = $count + 1
            $vmObject = Get-VMGuest -VM $node -Server $esxiFqdn | Where-Object VmUid -match $esxiFqdn
        }
        if ($count -eq $timeout) {
            Write-LogMessage -Type ERROR -Message "Powering On Node '$($node)' did not Complete Within Expected Timeframe: FAILURE" -Colour Red
        } else {
            Write-LogMessage -Type INFO -Message "Powering On Node '$($node)': SUCCESSFUL" -Colour Green
        }
    }
}

Function shutdownNode ($node, $nodeDescription) {
    Write-LogMessage -Type INFO -Message "Attempting to Shutdown $nodeDescription '$node'"
    if (Get-VM -Server $esxiFqdn | Where-Object { $_.Name -eq $node }) {
        $vmObject = Get-VMGuest -VM $node -Server $esxiFqdn | Where-Object VmUid -match $esxiFqdn
        if ($vmObject.State -eq 'NotRunning') {
            Write-LogMessage -Type INFO -Message "Powering Down Node '$node' Already Shutdown: SKIPPED" -Colour Cyan
        } else {
            Write-LogMessage -Type INFO -Message "Powering Down Node '$($node)'..."
            Stop-VMGuest -VM $node -Server $esxiFqdn -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            Write-LogMessage -Type INFO -Message "Waiting for Node '$node' to Shut Down..."
            While (($vmObject.State -ne 'NotRunning') -and ($count -ne $timeout)) {
                Start-Sleep -Seconds 5
                $count = $count + 1
                $vmObject = Get-VMGuest -VM $node -Server $esxiFqdn -ErrorAction SilentlyContinue
            }
            if ($count -eq $timeout) {
                Write-LogMessage -Type ERROR -Message "Powering Down Node '$($node)' did not Complete Within Expected Timeframe: FAILURE"	-Colour Red			
            } else {
                Write-LogMessage -Type INFO -Message "Powering Down Node '$($node)': SUCCESSFUL" -Colour Green
            }
        }
    } else {
        Write-LogMessage -Type ERROR -Message "Unable to Find '$node' in the Inventory" -Colour Red
    }
}
Function startupPattern ($pattern) {
    Write-LogMessage -Type INFO -Message "Attempting to Start Up Nodes with Pattern '$pattern'..."
    $patternNodes = Get-VM -Server $esxiFqdn | Where-Object Name -match $pattern | Select-Object Name, PowerState, VMHost | Where-Object VMHost -match $esxiFqdn
    if ($patternNodes.Name.Count -ne 0) {
        foreach ($node in $patternNodes) {
            $count = 0
            $vmObject = Get-VMGuest -server $esxiFqdn -VM $node.Name | Where-Object VmUid -match $esxiFqdn
            if ($vmObject.State -eq 'Running') {
                Write-LogMessage -Type INFO -Message "Powering On Node '$($node.name)' Already Running: SKIPPED" -Colour Cyan
            } else {
                Start-VM -VM $node.Name | Out-Null
                $vmObject = Get-VMGuest -Server $esxiFqdn -VM $node.Name | Where-Object VmUid -match $esxiFqdn
                Write-LogMessage -Type INFO -Message "Attempting to start up node '$($node.name)'..."
                While (($vmObject.State -ne 'Running') -AND ($count -ne $timeout)) {
                    Start-Sleep -Seconds 1
                    $count = $count + 1
                    $vmObject = Get-VMGuest -Server $esxiFqdn -VM $node.Name | Where-Object VmUid -match $esxiFqdn
                }
                if ($count -eq $timeout) {
                    Write-LogMessage -Type ERROR -Message "Powering On Node '$($node.name)' did not Complete Within Expected Timeframe: FAILURE" -Colour Red
                }
                else {
                    Write-LogMessage -Type INFO -Message "Powering On Node '$($node.name)': SUCCESSFUL" -Colour Green 
                }
            }
        }
    } elseif ($pattern) {
        Write-LogMessage -Type WARNING -Message "Unable to Find Pattern '$pattern' in the Inventory"
    }
}

Function shutdownPattern ($pattern) {
    $patternNodes = Get-VM -Server $esxiFqdn | Where-Object Name -match $pattern | Select-Object Name, PowerState, VMHost | Where-Object VMHost -match $esxiFqdn
    if ($patternNodes.Name.Count -ne 0) {
        foreach ($node in $patternNodes) {
            $count = 0
            $vmObject = Get-VMGuest -VM $node.Name -Server $esxiFqdn | Where-Object VmUid -match $esxiFqdn
            if ($vmObject.State -eq 'NotRunning') {
                Write-LogMessage -Type INFO -Message "Powering Down Node '$($node.name)' Already Shutdown: SKIPPED" -Colour Cyan
            } else {
                Get-VMGuest -VM $node.Name -Server $esxiFqdn | Where-Object VmUid -match $esxiFqdn | Stop-VMGuest -Confirm:$false | Out-Null
                $vmObject = Get-VMGuest -VM $node.Name -Server $esxiFqdn | Where-Object VmUid -match $esxiFqdn
                While (($vmObject.State -ne 'NotRunning') -and ($count -ne $timeout)) {
                    Start-Sleep -Seconds 1
                    $count = $count + 1
                    $vmObject = Get-VMGuest -VM $node.Name -Server $esxiFqdn | Where-Object VmUid -match $esxiFqdn
                }
                if ($count -eq $timeout) {
                    Write-LogMessage -Type ERROR -Message "Powering Down Node '$($node.name)' did not Complete Within Expected Timeframe: FAILURE" -Colour Red
                } else {
                    Write-LogMessage -Type INFO -Message "Powering Down Node '$($node.name)': SUCCESSFUL" -Colour Green
                }
            }
        }
    } elseif ($pattern) {
        Write-LogMessage -Type WARNING -Message "Unable to Find Pattern '$pattern' in the Inventory"
    }
}

Clear-Host; Write-Host ""
Set-PowerCLIConfiguration -InvalidCertificateAction:Ignore -Confirm:$false | Out-Null

Start-SetupLogFile -Path $logPath -ScriptName $MyInvocation.MyCommand.Name
Write-LogMessage -Type INFO -Message "Starting the Process of Powering On My Cloudy World Lab Infrastructure" -Colour Yellow
Write-LogMessage -Type INFO -Message "Setting up the log file to path $logfile"

if ($state -eq "startup") {
    Try {
        # Authenticate to Virtual Infrastructure
        Write-LogMessage -Type INFO -Message "Testing Connectivity With the Virtual Infrastructure '$esxiFqdn'"
        if (Test-Connection -ComputerName $esxiFqdn -Quiet -Count 1) {
            Connect-VIServer -Server $esxiFqdn -User $esxiUser -Password $esxiPass -Protocol https | Out-Null
            if ($DefaultVIServer.Name -eq $esxiFqdn) {
                
                startUpNode -node $activeDirectoryDc -nodeDescription "Active Directory Domain Controller"
                startUpNode -node $infraVcenter -nodeDescription "Infrastructure vCenter Server"
                startUpPattern -pattern $pattern

                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot authenticate to host '$esxiFqdn'. Check your environment and try again." -Colour Red
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Cannot connect to host '$esxiFqdn'. Check your environment and try again." -Colour Red
        }
    } Catch {
        Debug-CatchWriter -object $_
        Exit
    }
} elseif ($state -eq "shutdown") {
    Try {
        # Authenticate to Virtual Infrastructure
        Write-LogMessage -Type INFO -Message "Testing Connectivity With the Virtual Infrastructure '$esxiFqdn'"
        if (Test-Connection -ComputerName $esxiFqdn -Quiet -Count 1) {
            Connect-VIServer -Server $esxiFqdn -User $esxiUser -Password $esxiPass -Protocol https | Out-Null
            if ($DefaultVIServer.Name -eq $esxiFqdn) {

                shutdownPattern -pattern $pattern
                shutdownNode -node $infraVcenter -nodeDescription "Infrastructure vCenter Server"
                shutdownNode -node $activeDirectoryDc -nodeDescription "Active Directory Domain Controller"

                Disconnect-VIServer -Server * -Force -Confirm:$false -WarningAction SilentlyContinue  -ErrorAction  SilentlyContinue | Out-Null
            } else {
                Write-LogMessage -Type ERROR -Message "Cannot authenticate to host '$esxiFqdn'. Check your environment and try again." -Colour Red
            }
        } else {
            Write-LogMessage -Type ERROR -Message "Cannot connect to host '$esxiFqdn'. Check your environment and try again." -Colour Red
        }
    } Catch {
        Debug-CatchWriter -object $_
        Exit
    }
}
