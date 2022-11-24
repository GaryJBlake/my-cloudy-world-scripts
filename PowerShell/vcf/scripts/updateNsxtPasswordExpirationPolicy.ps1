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

    This script automates the process of setting the Password Expiration Policy for NSX Manager and NSX Edge Nodes
    accounts for a VMware Cloud Foundation instance

    .EXAMPLE
    .\updateNsxtPasswordExpirationPolicy.ps1 -server sfo-vcf01.sfo.rainpole.io -username administrator@vsphere.local -password VMw@re1! -passwordChangeFrequency 999 -nsxtAccounts "root","admin","audit"
#>

Param(
    [Parameter(Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$server,
    [Parameter(Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$username,
    [Parameter(Mandatory=$true)] [ValidateNotNullOrEmpty()] [String]$password,
    [Parameter(Mandatory=$true)] [ValidateNotNullOrEmpty()] [Array]$nsxtAccounts,
    [Parameter(Mandatory=$true)] [ValidateNotNullOrEmpty()] [Int]$passwordChangeFrequency

)

Function Update-NsxtManagerPasswordExpiration {
    <#
        .SYNOPSIS
        Update Password Expiration policy

        .DESCRIPTION
        The Update-NsxtManagerPasswordExpiration cmdlet updates the Password Expiration policy for all NSX Managers
        associated with a Workload Domain in VMware Cloud Foundation.

        .EXAMPLE
        Update-NsxtManagerPasswordExpirationp -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -nsxtAccounts "root","admin","audit" -passwordChangeFrequency 999
        This example updates the Password Expiration policy to 999 for accounts root,admin,audit for the NSX Manager associated with the Workload Domain sfo-m01
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [Array]$nsxtAccounts,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [Int]$passwordChangeFrequency
    )

    Try {
        if (Test-VCFConnection -server $server) {
            if (Test-VCFAuthentication -server $server -user $user -pass $pass) {
                if (($vcfNsxtDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain)) {
                    if (Test-NSXTConnection -server $vcfNsxtDetails.fqdn) {
                        if (Test-NSXTAuthentication -server $vcfNsxtDetails.fqdn -user $vcfNsxtDetails.adminUser -pass $vcfNsxtDetails.adminPass) {
                            $allNsxtUsers = Get-NsxtApplianceUser | Select-Object username, userid, password_change_frequency
                            $counter = 0
                            foreach ($nsxtUser in $allnsxtUsers ) {
                                if ($nsxtAccounts -contains  $nsxtUser.username) {
                                    if ($nsxtUser.password_change_frequency -ne $passwordChangeFrequency) {
                                        Set-NsxtApplianceUserExpirationPolicy -userId $nsxtUser.userid -days $passwordChangeFrequency
                                        Write-Output "Update Password Expiration Policy for ($($nsxtUser.username)) to ($passwordChangeFrequency) Days on NSX Manager ($($vcfNsxtDetails.fqdn)): SUCCESSFUL"
                                        $counter ++
                                    } else {
                                        Write-Warning "Update Password Expiration Policy for ($($nsxtUser.username)) to ($passwordChangeFrequency) Days on NSX Manager ($($vcfNsxtDetails.fqdn)), already set: SKIPPED"
                                    }
                                }
                            }
                            if ($counter -ne 0) {
                                $vcfCredentials = Get-VcfCredential | Where-Object {$_.resource.resourceType -eq "NSXT_MANAGER" -and $_.resource.domainName -eq $domain} | Select-Object username, id
                                $vcfNsxtCredentialIds = @()
                                foreach ($vcfCredential in $vcfCredentialS) {
                                    $vcfNsxtCredentialIds +=  $vcfCredential.id
                                } 

                                $credentialsExpirationSpec = New-Object -TypeName psobject
                                $credentialsExpirationSpec  | Add-Member -NotePropertyName 'credentialIds' -NotePropertyValue $vcfNsxtCredentialIds
                                $credentialsExpirationSpec  | Add-Member -NotePropertyName 'domainName' -NotePropertyValue $domain
                                $credentialsExpirationSpec  | Add-Member -NotePropertyName 'resourceType' -NotePropertyValue "NSXT_MANAGER"

                                $body = $credentialsExpirationSpec | ConvertTo-Json
                                $uri = "https://$sddcManager/v1/credentials/expirations"
                                Write-Warning "Update Password Expiration for NSX Manager Credentials in SDDC Manager ($server): IN PROGRESS"
                                $vcfTask = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body -ContentType application/json
                                $uri = "https://$sddcManager/v1/credentials/expirations/$($vcfTask.id)"
                                Do {
                                    $vcfTaskStatus =  Invoke-RestMethod -Uri $uri -Method GET -Headers $headers 
                                } Until ( $vcfTaskStatus.status -ne "IN_PROGRESS")
                                if ($vcfTaskStatus.status -eq "COMPLETED") {
                                    Write-Output "Update Password Expiration for NSX Manager Credentials in SDDC Manager ($server): SUCCESSFUL"
                                } else {
                                    Write-Error "Update Password Expiration for NSX Manager Credentials in SDDC Manager ($server): POST_VALIDATION_FAILED"
                                }
                            }
                        }
                    }
                }
            }
        }
    } Catch {
        Debug-ExceptionWriter -object $_
    }
}

Function Update-NsxtEdgePasswordExpiration {
    <#
        .SYNOPSIS
        Update Password Expiration policy

        .DESCRIPTION
        The Update-NsxtEdgePasswordExpiration cmdlet updates the Password Expiration policy for all NSX Edge Nodes
        associated with a Workload Domain in VMware Cloud Foundation.

        .EXAMPLE
        Update-NsxtEdgePasswordExpiration -server sfo-vcf01.sfo.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -domain sfo-m01 -nsxtAccounts "root","admin","audit" -passwordChangeFrequency 999
        This example updates the Password Expiration policy to 999 for accounts root,admin,audit for the NSX Edge Nodes associated with the Workload Domain sfo-m01
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [Array]$nsxtAccounts,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [Int]$passwordChangeFrequency
    )

    Try {
        if (Test-VCFConnection -server $server) {
            if (Test-VCFAuthentication -server $server -user $user -pass $pass) {
                if (($vcfNsxtDetails = Get-NsxtServerDetail -fqdn $server -username $user -password $pass -domain $domain)) {
                    if (Test-NSXTConnection -server $vcfNsxtDetails.fqdn) {
                        if (Test-NSXTAuthentication -server $vcfNsxtDetails.fqdn -user $vcfNsxtDetails.adminUser -pass $vcfNsxtDetails.adminPass) {
                            $counter = 0
                            $nsxtEdgeNodes = (Get-NsxtEdgeCluster | Where-Object {$_.member_node_type -eq "EDGE_NODE"})
                            foreach ($nsxtEdgeNode in $nsxtEdgeNodes.members) {
                                    $allNsxtUsers = Get-NsxtApplianceUser -transportNodeId $nsxtEdgeNode.transport_node_id | Select-Object username, userid, password_change_frequency
                                    foreach ($nsxtUser in $allnsxtUsers ) {
                                        if ($nsxtAccounts -contains  $nsxtUser.username) {
                                            if ($nsxtUser.password_change_frequency -ne $passwordChangeFrequency) {
                                                Set-NsxtApplianceUserExpirationPolicy -userId $nsxtUser.userid -days $passwordChangeFrequency -transportNodeId $nsxtEdgeNode.transport_node_id
                                                Write-Output "Update Password Expiration Policy for ($($nsxtUser.username)) to ($passwordChangeFrequency) Days for ($($nsxtEdgeNode.display_name)): SUCCESSFUL"
                                                $counter ++
                                            } else {
                                                Write-Warning "Update Password Expiration Policy for ($($nsxtUser.username)) to ($passwordChangeFrequency) Days for $($nsxtEdgeNode.display_name), already set: SKIPPED"
                                            }
                                        }
                                    } 
                            }

                            if ($counter -ne 0) {
                                $vcfCredentials = Get-VcfCredential | Where-Object {$_.resource.resourceType -eq "NSXT_EDGE" -and $_.resource.domainName -eq $domain} | Select-Object username, id
                                $vcfNsxtCredentialIds = @()
                                foreach ($vcfCredential in $vcfCredentialS) {
                                    $vcfNsxtCredentialIds +=  $vcfCredential.id
                                }

                                $credentialsExpirationSpec = New-Object -TypeName psobject
                                $credentialsExpirationSpec  | Add-Member -NotePropertyName 'credentialIds' -NotePropertyValue $vcfNsxtCredentialIds
                                $credentialsExpirationSpec  | Add-Member -NotePropertyName 'domainName' -NotePropertyValue $domain
                                $credentialsExpirationSpec  | Add-Member -NotePropertyName 'resourceType' -NotePropertyValue "NSXT_EDGE"

                                $body = $credentialsExpirationSpec | ConvertTo-Json
                                $uri = "https://$sddcManager/v1/credentials/expirations"
                                Write-Warning "Update Password Expiration for NSX Edge Credentials in SDDC Manager ($server): IN PROGRESS"
                                $vcfTask = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body -ContentType application/json
                                $uri = "https://$sddcManager/v1/credentials/expirations/$($vcfTask.id)"
                                Do {
                                    $vcfTaskStatus =  Invoke-RestMethod -Uri $uri -Method GET -Headers $headers
                                } Until ( $vcfTaskStatus.status -ne "IN_PROGRESS")
                                if ($vcfTaskStatus.status -eq "COMPLETED") {
                                    Write-Output "Update Password Expiration for NSX Edge Credentials in SDDC Manager ($server): SUCCESSFUL"
                                } else {
                                    Write-Error "Update Password Expiration for NSX Edge Credentials in SDDC Manager ($server): POST_VALIDATION_FAILED"
                                }
                            }
                        }
                    }
                }
            }
        }
    } Catch {
        Debug-ExceptionWriter -object $_
    }
}


Try {

    Clear-Host; Write-Host ''
    
    if (Test-VCFConnection -server $server) {
        if (Test-VCFAuthentication -server $server -user $username -pass $password) {
            $allWorkloadDomains = (Get-VCFWorkloadDomain | Select-Object name)
            foreach ($workloadDoman in $allWorkloadDomains.name) { 
                Write-Host "Update Password Expiration Policy for NSX Manager and Edge Nodes of Workload Domain ($workloadDoman)" -ForegroundColor Cyan
                Update-NsxtManagerPasswordExpiration -server $server -user $username -pass $password -domain $workloadDoman -nsxtAccounts $nsxAccounts -passwordChangeFrequency $passwordChangeFrequency
                Update-NsxtEdgePasswordExpiration -server $server -user $username -pass $password -domain $workloadDoman -nsxtAccounts $nsxAccounts -passwordChangeFrequency $passwordChangeFrequency
            }
        }
    }
} Catch {
    Write-Error $_.Exception.Message
}
