$username = "admin"
$password = "VMw@re1!"
$fqdn = "lax-wsa01.lax.rainpole.io"

###### Obtain Access Token
$headers = @{"Content-Type" = "application/json"}
$headers.Add("Accept", "application/json; charset=utf-8")
$body = '{"username": "' + $username + '", "password": "' + $password + '", "issueToken": "true"}'
$uri = "https://$nsxtManager/SAAS/API/1.0/REST/auth/system/login"
$response = Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body
$response
$accessToken = "HZN " + $response.sessionToken

###### Create Directory
$headers = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.directory.ad.over.ldap+json"}
$headers.Add("Accept", "application/vnd.vmware.horizon.manager.connector.management.directory.ad.over.ldap+json")
$headers.Add("Authorization", "$sessionToken")
$body = '{"useSRV":true,"directoryType":"ACTIVE_DIRECTORY_LDAP","directorySearchAttribute":"sAMAccountName","directoryConfigId":null,"useGlobalCatalog":false,"syncConfigurationEnabled":false,"useStartTls":false,"userAttributeMappings":[],"name":"lax.rainpole.io","baseDN":"ou=VVD,dc=lax,dc=rainpole,dc=io","bindDN":"cn=svc-wsa-ad,ou=VVD,dc=lax,dc=rainpole,dc=io"}'
$uri = "https://$nsxtManager/SAAS/jersey/manager/api/connectormanagement/directoryconfigs"
$response = Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body
$response
$directoryId = $response.directoryConfigId
$directoryId

###### Get Connectors
$headers = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.connector+json"}
$headers.Add("Authorization", "$sessionToken")
$uri = "https://$nsxtManager/SAAS/jersey/manager/api/connectormanagement/connectorinstances"
$response = Invoke-RestMethod $uri -Method 'GET' -Headers $headers
$response.items
$connectorId = $response.items.instanceId
$connectorId

###### Configure Password for Bind Account
$headers = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.directory.details+json"}
$headers.Add("Accept", "application/vnd.vmware.horizon.manager.connector.management.connector+json")
$headers.Add("Authorization", "$sessionToken")
$body = '{"directoryId":"' + $directoryId + '","directoryBindPassword":"VMw@re1\u0021","usedForAuthentication":true}'
$uri = "https://$nsxtManager/SAAS/jersey/manager/api/connectormanagement/connectorinstances/$connectorId/associatedirectory"
$response = Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body
$response

###### Get Domains
$headers = @{"Accept" = "application/vnd.vmware.horizon.manager.connector.management.directory.domain.list+json"}
$headers.Add("Authorization", "$sessionToken")
$uri = "https://$nsxtManager/SAAS/jersey/manager/api/connectormanagement/directoryconfigs/$directoryId/domains"
$response = Invoke-RestMethod $uri -Method 'GET' -Headers $headers
$response.items
$domainId = ($response.items._links.self.href -Split("/domains/"))[1]
$domainId



$groupBaseDn = "ou=VVD,dc=lax,dc=rainpole,dc=io"
$groups = @("gg-nsx-enterprise-admins","gg-wsa-admins","gg-wsa-directory-admins","gg-wsa-read-only")
$group = "gg-nsx-enterprise-admins"
$bindUser = "svc-vsphere-ad"

$securePassword = ConvertTo-SecureString -String "VMw@re1!" -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential ($bindUser, $securePassword)
$adGroupObject = (Get-ADGroup -Server lax.rainpole.io -Credential $creds -Filter { SamAccountName -eq $group })

$adGroupObject.DistinguishedName

###### Add OU for Groups and Define Groups to Sync
$headers = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.directory.sync.profile.groups+json"}
$headers.Add("Accept", "application/vnd.vmware.horizon.manager.connector.management.directory.sync.profile.groups+json")
$headers.Add("Authorization", "$sessionToken")

$mappedGroupObject = @()
Foreach ($group in $groups) {
    $adGroupObject = (Get-ADGroup -Server lax.rainpole.io -Credential $creds -Filter { SamAccountName -eq $group })
    $mappedGroupObject += [pscustomobject]@{
        'horizonName' = $group
        'dn' = $adGroupObject.DistinguishedName
        'objectGuid' = $adGroupObject.ObjectGUID.GUID
        'groupBaseDN' = $groupBaseDn
        'source' = "DIRECTORY"
        },
        'selected' = "true"
        )
    
    }

    $mappedGroupDataObject = @()
        $mappedGroupDataObject += [pscustomobject]@{
            'mappedGroupData' = $mappedGroupObject
            'selected' = "true"
        }


    $Global:mappedGroupDataObject = '[
        {
            "mappedGroup": {
                "horizonName": "'+ $group +'",
                "dn": "'+ $adGroupObject.DistinguishedName +'",
                "objectGuid": "'+ $adGroupObject.ObjectGUID.GUID +'",
                "groupBaseDN": "'+ $groupBaseDn +'",
                "source": "DIRECTORY"
            },
            "selected": true
        }]'

$body = '{
    "identityGroupInfo": {
        "ou=VVD,dc=lax,dc=rainpole,dc=io": {
            "mappedGroupData": [
                {
                    "mappedGroup": {
                        "horizonName": "'+ $group +'",
                        "dn": "'+ $adGroupObject.DistinguishedName +'",
                        "objectGuid": "'+ $adGroupObject.ObjectGUID.GUID +'",
                        "groupBaseDN": "'+ $groupBaseDn +'",
                        "source": "DIRECTORY"
                    },
                    "selected": true
                },
                {
                    "mappedGroup": {
                        "horizonName": "gg-wsa-admins",
                        "dn": "CN=gg-wsa-admins,OU=VVD,DC=lax,DC=rainpole,DC=io",
                        "objectGuid": "c5bb7d42-7eb6-4160-84d1-a723fbaedf06",
                        "groupBaseDN": "ou=VVD,dc=lax,dc=rainpole,dc=io",
                        "source": "DIRECTORY"
                    },
                    "selected": true
                },
                {
                    "mappedGroup": {
                        "horizonName": "gg-wsa-directory-admins",
                        "dn": "CN=gg-wsa-directory-admins,OU=VVD,DC=lax,DC=rainpole,DC=io",
                        "objectGuid": "b463af4d-1c37-4ea1-945e-40db1a1b4227",
                        "groupBaseDN": "ou=VVD,dc=lax,dc=rainpole,dc=io",
                        "source": "DIRECTORY"
                    },
                    "selected": true
                },
                {
                    "mappedGroup": {
                        "horizonName": "gg-wsa-read-only",
                        "dn": "CN=gg-wsa-read-only,OU=VVD,DC=lax,DC=rainpole,DC=io",
                        "objectGuid": "f96545f6-472f-47a5-89e4-9273f97e4617",
                        "groupBaseDN": "ou=VVD,dc=lax,dc=rainpole,dc=io",
                        "source": "DIRECTORY"
                    },
                    "selected": true
                }
            ],
            "selected": false
        }
    },
    "excludeNestedGroupMembers": false
}'
$uri = "https://$nsxtManager/SAAS/jersey/manager/api/connectormanagement/directoryconfigs/$directoryId/syncprofile"
$response = Invoke-RestMethod $uri -Method 'PUT' -Headers $headers -Body $body
$response

###### Add Users OU for Sync
$headers = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.directory.sync.profile.users+json"}
$headers.Add("Accept", "application/vnd.vmware.horizon.manager.connector.management.directory.sync.profile.users+json")
$headers.Add("Authorization", "$sessionToken")
$body = '{ "identityUserInfo": { "cn=svc-wsa-ad,ou=VVD,dc=lax,dc=rainpole,dc=io": { "selected": true }, "ou=VVD,dc=lax,dc=rainpole,dc=io": { "selected": true }}}'
$uri = "https://$nsxtManager/SAAS/jersey/manager/api/connectormanagement/directoryconfigs/$directoryId/syncprofile"
Invoke-RestMethod $uri -Method 'PUT' -Headers $headers -Body $body

###### Configure Sync Schedule
$headers = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.directory.sync.profile.syncschedule+json"}
$headers.Add("Accept", "application/vnd.vmware.horizon.manager.connector.management.directory.sync.profile.syncschedule+json")
$headers.Add("Authorization", "$sessionToken")
$body = '{"frequency":"fifteenMinutes"}'
$uri = "https://$nsxtManager/SAAS/jersey/manager/api/connectormanagement/directoryconfigs/$directoryId/syncprofile"
Invoke-RestMethod $uri -Method 'PUT' -Headers $headers -Body $body

###### Start Sync of Users and Groups
$headers = @{"Content-Type" = "application/vnd.vmware.horizon.manager.connector.management.directory.sync.profile.sync+json"}
$headers.Add("Accept", "application/vnd.vmware.horizon.v1.0+json")
$headers.Add("Authorization", "$sessionToken")
$body = '{"ignoreSafeguards":true}'
$uri = "https://$nsxtManager/SAAS/jersey/manager/api/connectormanagement/directoryconfigs/$directoryId/syncprofile/sync"
Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body

