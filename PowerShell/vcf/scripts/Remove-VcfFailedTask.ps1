    <#
		.SYNOPSIS
        Delete failed tasks from SDDC Manager

        .DESCRIPTION
        The Remove-VcfFailedTask cmdlet deletes all failed tasks from SDDC Manger.
        The cmdlet connects to SDDC Manager using the -server, -user, and -password values:
        - Validates that network connectivity and authentication is possible to SDDC Manager
        - Validates that network connectivity and authentication is possible to Management Domain vCenter Server
        - Gathers a list of failed tasks and deletes them

        .EXAMPLE
        Remove-VcfFailedTask -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1!
        This example deletes all failed tasks
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass
    )

    Try {
        if (Test-VCFConnection -server $server) {
            if (Test-VCFAuthentication -server $server -user $user -pass $pass) {  
                $failedTaskIds = @()
                $ids = (Get-VCFTask -status FAILED).id
                Foreach ($id in $ids) {
                    $failedTaskIds += ,$id
                }
                if ($failedTaskIds) {
                    Foreach ($taskId in $failedTaskIds) {
                        Write-Output "Deleting Failed Task with ID ($taskId)"
                        $uri = "https://$sddcManager/v1/tasks/$taskId"
                        Invoke-RestMethod -Method DELETE -URI $uri -headers $headers | Out-Null
                        if (Get-VCFTask -id $taskId) {
                            Write-Error "Deletion of Failed Task with ID ($taskId): POST_VALIDATION"
                        } else {
                            Write-Output "Deletion of Failed Task with ID ($taskId): SUCCESSFUL"
                        }
                    }
                } else {
                    Write-Output "No Failed Tasks Found in SDDC Manager ($server)"
                }
            }
        }
    } Catch {
        Write-Error $_.Exception.Message
    }