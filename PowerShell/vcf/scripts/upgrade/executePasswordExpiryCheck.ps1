# Script to get password expiry details for VMware Cloud Foundation Credentials
# Written by Gary Blake, Senior Staff Solution Architect @ VMware
# Refactored using original script by Brian O'Oconnel, Staff 2 Solution Architect @ VMware

Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$fqdn,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$username,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$password,
        [Parameter (Mandatory = $false)] [ValidateSet("VCENTER", "PSC", "ESXI", "BACKUP", "NSXT_MANAGER", "NSXT_EDGE", "VRSLCM", "WSA", "VROPS", "VRLI", "VRA", "VXRAIL_MANAGER")] [ValidateNotNullOrEmpty()] [String]$resourceType
    )
    
    Clear-Host; Write-Host ""
    # Obtain Authentication Token from SDDC Manager
    Request-VCFToken -fqdn $fqdn -username $username -password $password

    $vcfVersion = ((Get-VCFManager).version -Split ('\.\d{1}\-\d{8}')) -split '\s+' -match '\S'
    if ($vcfVersion -gt "4.4.0") {
        # Get all credential objects that are not type SERVICE
        if (!$PsBoundParameters.ContainsKey("resourceType")) {
            $credentials = Get-VCFCredential | where-object {$_.accountType -ne "SERVICE"}
        }
        else {
            $credentials = Get-VCFCredential -resourceType $resourceType | where-object {$_.accountType -ne "SERVICE"}
        }

        $validationArray = @()
        Foreach ($credential in $credentials) {
            $resourceType = $credential.resource.resourceType
            $resourceID = $credential.resource.resourceId
            $username = $credential.username
            $credentialType = $credential.credentialType
            $body = '[
            {
                "resourceType": "'+$resourceType+'",
                "resourceId": "'+$resourceID+'",
                "credentials": [
                    {
                        "username": "'+$username+'",
                        "credentialType": "'+$credentialType+'"
                    }
                ]
            }
            ]'
            $uri = "https://$sddcManager/v1/credentials/validations"
            # Submit a credential validation request
            $response = Invoke-RestMethod -Method POST -URI $uri -headers $headers -body $body
            $validationTaskId = $response.id

            Do {
                # Keep checking until executionStatus is not IN_PROGRESS
                $validationTaskuri = "https://$sddcManager/v1/credentials/validations/$validationTaskId"
                $validationTaskResponse = Invoke-RestMethod -Method GET -URI $validationTaskuri -headers $headers
            }
            While ($validationTaskResponse.executionStatus -eq "IN_PROGRESS")
                # Build the output
                $validationObject = New-Object -TypeName psobject
                $validationObject | Add-Member -notepropertyname 'Resource Name' -notepropertyvalue $validationTaskResponse.validationChecks.resourceName
                $validationObject | Add-Member -notepropertyname 'Username' -notepropertyvalue $validationTaskResponse.validationChecks.username
                $validationObject | Add-Member -notepropertyname 'Number Of Days To Expiry' -notepropertyvalue $validationTaskResponse.validationChecks.passwordDetails.numberOfDaysToExpiry
                    
                Write-Output "Checking Password Expiry for username $($validationTaskResponse.validationChecks.username) from resource $($validationTaskResponse.validationChecks.resourceName)"
                # Add each credential result to the array
                $validationArray += $validationObject
                #break
            }
        # Print the array
        $validationArray
    }
    else {
        Write-Warning "Public APIs are not available in this release of VMware Cloud Foundation"
    }
