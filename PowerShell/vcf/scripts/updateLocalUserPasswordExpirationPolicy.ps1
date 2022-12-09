<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Group:         Solution Engineering, Cloud Infrastructure Business Unit (CIBG)
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 001)
    .Date:          2022-11-24
    ===============================================================================================================

    .CHANGE_LOG

    - 1.0.000 (Gary Blake / 2022-11-49) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of setting the Password Expiration Policy for a local user within a virtual
    appliance

    .EXAMPLE
    .\updateLocalUserPasswordExpirationPolicy.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -vmName sfo-m01-vc01 -vmRootpass VMw@re1! -localUser root -passwordChangeFrequency 999 -passwordWarningDays 14 -resourceType VCENTER -vcfIntegrated
    This example updates the password expiration policy for the root user of the sfo-m01-vc01 virtual machine and then triggers an update in SDDC Manager based on it being a managed component

    .EXAMPLE
    .\updateLocalUserPasswordExpirationPolicy.ps1 -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -vmName sfo-wsa01 -vmRootpass VMw@re1! -localUser root -passwordChangeFrequency 999 -passwordWarningDays 14
    This example updates the password expiration policy for the root user of the sfo-wsa01 virtual machine
#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vmName,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$vmRootPass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$localUser,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [Int]$passwordChangeFrequency,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [Int]$passwordWarningDays,
        [Parameter (Mandatory = $false, ParameterSetName = 'vcfIntegrated')] [ValidateNotNullOrEmpty()] [Switch]$vcfIntegrated,
        [Parameter (Mandatory = $false, ParameterSetName = 'vcfIntegrated')] [ValidateSet("VCENTER","ESXI","PSC","NSXT_MANAGER","NSXT_EDGE","VRLI","VROPS","VRA","WSA","VRSLCM","VXRAIL_MANAGER","BACKUP")] [String]$resourceType
    )

Try {
    Clear-Host; Write-Host ''
    Write-Host "Update Password Expiration Policy for ($localUser) on Virtual Appliance ($vmName) " -ForegroundColor Cyan

    if (Test-VCFConnection -server $server) {
        if (Test-VCFAuthentication -server $server -user $user -pass $pass) {
            if (($vcfVcenterDetails = Get-vCenterServerDetail -server $server -user $user -pass $pass -domain $domain)) {
                if (Test-VsphereConnection -server $($vcfVcenterDetails.fqdn)) {
                    if (Test-VsphereAuthentication -server $vcfVcenterDetails.fqdn -user $vcfVcenterDetails.ssoAdmin -pass $vcfVcenterDetails.ssoAdminPass) {
                        if (Get-VM -Name $vmName -Server $($vcfVcenterDetails.fqdn)) {
                            $counter = 0
                            # Retrieve the current password expiry settings
                            $command = 'chage --list ' + $localUser
                            $output = Invoke-VMScript -VM $vmName -ScriptText $command -GuestUser root -GuestPassword $vmRootPass
                            $formatOutput = ($output.ScriptOutput -split '\r?\n').Trim()
                            $formatOutput = $formatOutput -replace '(^\s+|\s+$)', '' -replace '\s+', ' '
                            $currentPasswordChangeFrequency = ($formatOutput[-3] -Split (':').Trim())[-1]
                            $currentPasswordChangeFrequency = $currentPasswordChangeFrequency -replace '(^\s+|\s+$)', '' -replace '\s+', ' '
                            $currentPasswordWarningDays = ($formatOutput[-2] -Split (':').Trim())[-1]
                            $currentPasswordWarningDays = $currentPasswordWarningDays -replace '(^\s+|\s+$)', '' -replace '\s+', ' '
                            if ($currentPasswordChangeFrequency -ne $passwordChangeFrequency) {
                                $command = 'chage --maxdays ' + $passwordChangeFrequency + ' ' + $localUser
                                Invoke-VMScript -VM $vmName -ScriptText $command -GuestUser root -GuestPassword $vmRootPass | Out-Null
                                $command = 'chage --list ' + $localUser
                                $output = Invoke-VMScript -VM $vmName -ScriptText $command -GuestUser root -GuestPassword $vmRootPass
                                $formatOutput = ($output.ScriptOutput -split '\r?\n').Trim()
                                $formatOutput = $formatOutput -replace '(^\s+|\s+$)', '' -replace '\s+', ' '
                                $newPasswordChangeFrequency = ($formatOutput[-3] -Split (':').Trim())[-1]
                                $newPasswordChangeFrequency = $newPasswordChangeFrequency -replace '(^\s+|\s+$)', '' -replace '\s+', ' '
                                if ($newPasswordChangeFrequency -eq $passwordChangeFrequency) {
                                    Write-Output "Update Password Expiration Policy for ($localUser) to ($passwordChangeFrequency) Maximim Days on Virtual Appliance ($vmName): SUCCESSFUL"
                                    $counter ++
                                } else {
                                    Write-Error "Update Password Expiration Policy for ($localUser) to ($passwordChangeFrequency) Maximim Days on Virtual Appliance ($vmName): POST_VALIDATION_FAILED"
                                }
                            } else {
                                Write-Warning "Update Password Expiration Policy for ($localUser) to ($passwordChangeFrequency) Maximim Days on Virtual Appliance ($vmName), already set: SKIPPED"
                            }
                            if ($PsBoundParameters.ContainsKey("passwordWarningDays")) {
                                if ($currentPasswordWarningDays -ne $passwordWarningDays) {
                                    $command = 'chage --warndays ' + $passwordWarningDays + ' ' + $localUser
                                    Invoke-VMScript -VM $vmName -ScriptText $command -GuestUser root -GuestPassword $vmRootPass | Out-Null
                                    $command = 'chage --list ' + $localUser
                                    $output = Invoke-VMScript -VM $vmName -ScriptText $command -GuestUser root -GuestPassword $vmRootPass
                                    $formatOutput = ($output.ScriptOutput -split '\r?\n').Trim()
                                    $formatOutput = $formatOutput -replace '(^\s+|\s+$)', '' -replace '\s+', ' '
                                    $newPasswordWarningDays = ($formatOutput[-2] -Split (':').Trim())[-1]
                                    $newPasswordWarningDays = $newPasswordWarningDays -replace '(^\s+|\s+$)', '' -replace '\s+', ' '
                                    if ($newPasswordWarningDays -eq $passwordWarningDays) {
                                        Write-Output "Update Password Expiration Policy for ($localUser) to ($passwordWarningDays) Warning Days on Virtual Appliance ($vmName): SUCCESSFUL"
                                    } else {
                                        Write-Error "Update Password Expiration Policy for ($localUser) to ($passwordWarningDays) Warning Days on Virtual Appliance ($vmName): POST_VALIDATION_FAILED"
                                    }
                                } else {
                                    Write-Warning "Update Password Expiration Policy for ($localUser) to ($passwordWarningDays) Warning Days on Virtual Appliance ($vmName), already set: SKIPPED"
                                }
                            }

                            if ($counter -ne 0 -and $PsBoundParameters.ContainsKey("vcfIntegrated")) {
                                if ($credentilIds = @((Get-VcfCredential | Where-Object {$_.username -eq $localUser -and $_.resource.resourceType -eq $resourceType -and $_.resource.resourceName -match $vmName} | Select-Object username, id).id)) {
                                    $credentialsExpirationSpec = New-Object -TypeName psobject
                                    $credentialsExpirationSpec  | Add-Member -NotePropertyName 'credentialIds' -NotePropertyValue $credentilIds
                                    $credentialsExpirationSpec  | Add-Member -NotePropertyName 'domainName' -NotePropertyValue (Get-VcfCredential | Where-Object {$_.username -eq $localUser -and $_.resource.resourceType -eq $resourceType -and $_.resource.resourceName -match $vmName}).resource.domainName
                                    $credentialsExpirationSpec  | Add-Member -NotePropertyName 'resourceType' -NotePropertyValue $resourceType

                                    $body = $credentialsExpirationSpec | ConvertTo-Json
                                    $uri = "https://$sddcManager/v1/credentials/expirations"
                                    Write-Warning "Update Password Expiration Statue of Credential ($localUser) for Component ($vmName): IN PROGRESS"
                                    $vcfTask = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body -ContentType application/json
                                    $uri = "https://$sddcManager/v1/credentials/expirations/$($vcfTask.id)"
                                    Do {
                                        $vcfTaskStatus =  Invoke-RestMethod -Uri $uri -Method GET -Headers $headers 
                                    } Until ( $vcfTaskStatus.status -ne "IN_PROGRESS")
                                    if ($vcfTaskStatus.status -eq "COMPLETED") {
                                        Write-Output "Update Password Expiration Status of Credential ($localUser) for Component ($vmName): SUCCESSFUL"
                                    } else {
                                        Write-Error "Update Password Expiration Status of Credential ($localUser) for Component ($vmName): POST_VALIDATION_FAILED"
                                    }
                                }
                            }
                            
                        } else {
                            Write-Error "Unable to locate virtual machine ($vmName) in the vCenter Server ($($vcfVcenterDetails.fqdn)) inventory: PRE_VALIDATION_FAILED"
                        }
                    }
                }
            }
        }
    }
} Catch {
    Debug-ExceptionWriter -object $_
}
