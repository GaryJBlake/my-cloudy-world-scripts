<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Blog:          http:/my-cloudy-world.com
    .Twitter:       @GaryJBlake
    .Version:       1.0 (Build 001)
    .Date:          2021-02-12
    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.001 (Gary Blake / 2020-02-12) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION
    This scripts performs the configuration of Identity and Access Management for VMware Cloud Foundation.
    It uses the the JSON as the input and then performs the following steps:
    - Dynamically obtain details from SDDC Manager and vCenter Server
    - Add Active Directory over LDAP Identity Source to vCenter Server and Set as Default
    - Assign an Active Directory Group the Administrator Role as a Global Permission in vCenter Server
    - Assign Active Directory Groups to Admin, Operator and Viewer Roles in SDDC Manager
    - Join each ESXi Host to the Active Directory Domain
    - Assign an Active Directory Group to each ESXi Host for Administration
    - Create VM and Template Folder and Deploy the Workspace One Access Virtual Appliance
    - Perform Initial Configuration of Workspace ONE Access Virtual Appliance
    - Configure NTP Server on Workspace ONE Access Appliance
    - Install a Signed Certificate on Workspace ONE Access Appliance

    .EXAMPLE
    .\configureIam.ps1 -json iamConfig.json
#>

Param (
    [Parameter(mandatory=$true)]
        [String]$json
)

$powerVcfVersion = "2.1.1"

Function configureEnvironment 
{    
    $ErrorActionPreference = "Stop"
    #change size, buffer and Background
    if ($Env:OS = "Windows_NT") {  
        if ($headlessPassed) {
            $width = (Get-Host).UI.RawUI.MaxWindowSize.Width
        }
        else {
            $width = 200
        }
        $height = $((Get-Host).UI.RawUI.MaxWindowSize.Height-2)
        $Console = $host.ui.rawui
        $Buffer  = $Console.BufferSize
        $ConSize = $Console.WindowSize

        # If the Buffer is wider than the new console setting, first reduce the buffer, then do the resize
        if ($Buffer.Width -gt $Width ) {
           $ConSize.Width = $Width
           $Console.WindowSize = $ConSize
        }
        $Buffer.Width = $Width
        $ConSize.Width = $Width
        $Buffer.Height = 3000
        $Console.BufferSize = $Buffer
        $ConSize = $Console.WindowSize
        $ConSize.Width = $Width
        $ConSize.Height = $Height
        $Console.WindowSize = $ConSize
        $ConColour = $Console.BackgroundColor
        $Console.BackgroundColor = "Black"
        Clear-Host
    }
    Set-Item wsman:\localhost\client\trustedhosts * -Force
    Clear-Host; Write-Host ""; Write-Host -Object " Configuring PowerShell Environment" -ForegroundColor Yellow
    $OriginalPref = $ProgressPreference # Default is 'Continue'
    $ProgressPreference = "SilentlyContinue"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Host ""; Write-Host -Object " Checking that PowerVCF is Installed" -ForegroundColor White
    $powerVcf = Get-InstalledModule -Name PowerVCF -ErrorAction SilentlyContinue
    if ($powerVcf.Version -eq $powerVcfVersion) {
        Write-Host -Object ""
        Start-SetupLogFile -Path $PSScriptRoot -ScriptName "configureIam" # Create new log
        Write-LogMessage -Message "PowerVCF $($powerVcf.Version) Found" -Colour Green
    }
    else {
        Write-Host ""; Write-Host -Object " PowerVCF Module $powerVcfVersion not found. Attempting to install" -ForegroundColor White; Write-Host -Object ""
        Install-PackageProvider NuGet -Force | Out-Null
        Set-PSRepository PSGallery -InstallationPolicy Trusted | Out-Null
        Install-Module PowerVCF -RequiredVersion $powerVcfVersion -Force -confirm:$false | Out-Null
        $powerVcf = Get-InstalledModule -Name PowerVCF -ErrorAction SilentlyContinue
        if ($powerVcf.Version -eq $powerVcfVersion) {
            Write-LogMessage -Message "PowerVCF $powerVcfVersion Installed Successfully" -Colour Green
        }
        else {
            Write-Host "";Write-Host -Object " Issue installing PowerVCF Module $powerVcfVersion" -ForegroundColor Red; Exit
        }
    }

    Write-LogMessage -Message "Checking if VMware PowerCLI is installed"
    $powerCli = Get-InstalledModule -Name VMware.PowerCLI -ErrorAction SilentlyContinue
    if (!$powerCli) {
        Write-LogMessage -Message "VMware PowerCLI not found, please install and retry" -Colour Green; Exit
    }
    else {
        Write-LogMessage -Message "VMware PowerCLI Found" -Colour Green
        #Get-Module -Name VMware* -ListAvailable | Import-Module | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Configuring PowerShell CEIP Setting"
        $setCLIConfigurationCEIP = Set-PowerCLIConfiguration -Scope AllUsers -ParticipateInCEIP $false -Confirm:$false -warningaction SilentlyContinue -InformationAction SilentlyContinue 2>&1 | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Configuring PowerShell Certifcate Setting"
        $setCLIConfigurationCerts = Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$False -Scope AllUsers -warningaction SilentlyContinue -InformationAction SilentlyContinue 2>&1 | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Permitting Multiple Default VI Servers"
        $setCLIConfigurationVIServers = Set-PowerCLIConfiguration -DefaultVIServerMode multiple -Confirm:$false -Scope AllUsers -warningaction SilentlyContinue -InformationAction SilentlyContinue 2>&1 | Out-File $logFile -Encoding ASCII -Append
    }

    Write-LogMessage -Message "Checking that the VMware OVF Tool is installed"
    $ovfToolPath = 'C:\Program Files\VMware\VMware OVF Tool\ovftool.exe'
    $ovfToolsPresent = Test-Path -Path $ovfToolPath
    if (!$ovfToolsPresent) {
        Write-LogMessage -Message "VMware OVF Tool not found at path $ovfToolPath" -Colour Red; Exit
    }
    else {
        Write-LogMessage -Message "VMware OVF Tool Found" -Colour Green
    }
}

Function connectVsphere ($hostname, $user, $password) {
    Try {
        Write-LogMessage -Message "Connecting to vCenter/ESXi Server $hostname"
        Connect-VIServer -Server $hostname -User $user -Password $password | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Connected to vCenter/ESXi Server $hostname Successfully" -Colour Green
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function disconnectVsphere ($hostname) {
    Try {
        Write-LogMessage -Message "Disconnecting from vCenter/ESXi Server $hostname"
        Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
        Write-LogMessage -Message "Disconnected from vCenter/ESXi Server $hostname Successfully" -Colour Green
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function connectVcf ($fqdn, $username, $password) {
    Write-LogMessage -Message "Connecting to SDDC Manager $sddcMgrFqdn"
    Try {
        if (Test-Connection -ComputerName $fqdn -ErrorAction SilentlyContinue) {
            Write-LogMessage -Message "Checking that connection to SDDC Manager $fqdn is possible"
            $connection =  Request-VCFToken -fqdn $fqdn -username $username -password $password
            if ($connection.success) {Write-LogMessage -Message "$($connection.success)" -Colour Green}
        }
        else {
            if ($connection.error) {Write-LogMessage -Message "$($connection.error)" -Colour Red}
        }
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}

Function New-GlobalPermission {
<#
    .DESCRIPTION Script to add/remove vSphere Global Permission
    .NOTES  Author:  William Lam. Modified by Ken Gould to permit principal type (user or group)
    .NOTES  Site:    www.virtuallyghetto.com
    .NOTES  Reference: http://www.virtuallyghetto.com/2017/02/automating-vsphere-global-permissions-with-powercli.html
    .PARAMETER vc_server
        vCenter Server Hostname or IP Address
    .PARAMETER vc_username
        VC Username
    .PARAMETER vc_password
        VC Password
    .PARAMETER vc_user
        Name of the user to remove global permission on
    .PARAMETER vc_role_id
        The ID of the vSphere Role (retrieved from Get-VIRole)
    .PARAMETER propagate
        Whether or not to propgate the permission assignment (true/false)
#>
    Param (
        [Parameter(Mandatory=$true)][string]$vc_server,
        [Parameter(Mandatory=$true)][String]$vc_username,
        [Parameter(Mandatory=$true)][String]$vc_password,
        [Parameter(Mandatory=$true)][String]$vc_user,
        [Parameter(Mandatory=$true)][String]$vc_role_id,
        [Parameter(Mandatory=$true)][String]$propagate,
        [Parameter(Mandatory=$true)][String]$type
    )
    
    $secpasswd = ConvertTo-SecureString $vc_password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential($vc_username, $secpasswd)
    
    # vSphere MOB URL to private enableMethods
    $mob_url = "https://$vc_server/invsvc/mob3/?moid=authorizationService&method=AuthorizationService.AddGlobalAccessControlList"
    
# Ingore SSL Warnings
add-type -TypeDefinition  @"
        using System.Net;
        using System.Security.Cryptography.X509Certificates;
        public class TrustAllCertsPolicy : ICertificatePolicy {
            public bool CheckValidationResult(
                ServicePoint srvPoint, X509Certificate certificate,
                WebRequest request, int certificateProblem) {
                return true;
            }
        }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    
        # Initial login to vSphere MOB using GET and store session using $vmware variable
        $results = Invoke-WebRequest -Uri $mob_url -SessionVariable vmware -Credential $credential -Method GET
    
        # Extract hidden vmware-session-nonce which must be included in future requests to prevent CSRF error
        # Credit to https://blog.netnerds.net/2013/07/use-powershell-to-keep-a-cookiejar-and-post-to-a-web-form/ for parsing vmware-session-nonce via Powershell
        if($results.StatusCode -eq 200) {
            $null = $results -match 'name="vmware-session-nonce" type="hidden" value="?([^\s^"]+)"'
            $sessionnonce = $matches[1]
        } else {
            LogMessage "Failed to login to vSphere MOB" Red
            exit 1
        }
    
        # Escape username
        $vc_user_escaped = [uri]::EscapeUriString($vc_user)
    
        # The POST data payload must include the vmware-session-nonce variable + URL-encoded
    If ($type -eq "group")
    {
        $body = @"
vmware-session-nonce=$sessionnonce&permissions=%3Cpermissions%3E%0D%0A+++%3Cprincipal%3E%0D%0A++++++%3Cname%3E$vc_user_escaped%3C%2Fname%3E%0D%0A++++++%3Cgroup%3Etrue%3C%2Fgroup%3E%0D%0A+++%3C%2Fprincipal%3E%0D%0A+++%3Croles%3E$vc_role_id%3C%2Froles%3E%0D%0A+++%3Cpropagate%3E$propagate%3C%2Fpropagate%3E%0D%0A%3C%2Fpermissions%3E
"@        
    }
    else {
            $body = @"
vmware-session-nonce=$sessionnonce&permissions=%3Cpermissions%3E%0D%0A+++%3Cprincipal%3E%0D%0A++++++%3Cname%3E$vc_user_escaped%3C%2Fname%3E%0D%0A++++++%3Cgroup%3Efalse%3C%2Fgroup%3E%0D%0A+++%3C%2Fprincipal%3E%0D%0A+++%3Croles%3E$vc_role_id%3C%2Froles%3E%0D%0A+++%3Cpropagate%3E$propagate%3C%2Fpropagate%3E%0D%0A%3C%2Fpermissions%3E
"@
    }

    # Second request using a POST and specifying our session from initial login + body request
    #Write-Host "Adding Global Permission for $vc_user ..."
    $results = Invoke-WebRequest -Uri $mob_url -WebSession $vmware -Method POST -Body $body

    # Logout out of vSphere MOB
    $mob_logout_url = "https://$vc_server/invsvc/mob3/logout"
    $results = Invoke-WebRequest -Uri $mob_logout_url -WebSession $vmware -Method GET
}

Function createSddcManagerRole ($adGroup, $adDomain, $secureCreds, $vcfRole) {
    $groupName = $adGroup.Split("\")[1]
    Write-LogMessage -Message "Checking if Active Directory Group '$groupName' is present in Active Directory Domain"
    if (Get-ADGroup -Server $adDomain -Credential $secureCreds -Filter {SamAccountName -eq $groupName}) {
        Write-LogMessage -Message "Checking if Active Directory Group '$adGroup' has already been assigned the $vcfRole role in SDDC Manager"
        $groupCheck = Get-VCFUser | Where-Object {$_.name -eq $adGroup}; $groupCheck | Out-File $logFile -Encoding ASCII -Append
        if ($groupCheck.name -eq $adGroup) {
           Write-LogMessage -Message "Active Directory Group '$adGroup' already assigned the $vcfRole role in SDDC Manager" -Colour Magenta
        }
        else {
            Write-LogMessage -Message "Adding Active Directory Group '$adGroup' the $vcfRole role in SDDC Manager"
            New-VCFGroup -group $adGroup.Split("\")[1] -domain $adDomain -role $vcfRole | Out-File $logFile -Encoding ASCII -Append
            Write-LogMessage -Message "Checking if Active Directory Group '$adGroup' was added correctly"
            $groupCheck = Get-VCFUser | Where-Object {$_.name -eq $adGroup}; $groupCheck | Out-File $logFile -Encoding ASCII -Append
            if ($groupCheck.name -eq $adGroup) {
                Write-LogMessage -Message "Active Directory Group '$adGroup' assigned the $vcfRole role in SDDC Manager Successfully" -Colour Green
            }
            else {
                Write-LogMessage -Message "Assigning Active Directory Group '$adGroup' $vcfRole role in SDDC Manager Failed" -Colour Red
            }
        }
    }
    else {
        Write-LogMessage -Message "Active Directory Group '$groupName' not found in the Active Directory Domain, please create and retry" -Colour Red
    }
}

# EXECUTION SECTION

Try {
    configureEnvironment

    Write-LogMessage  -Message "Reading the JSON File Provided" -Colour Yellow
    if (Test-Path -Path $json) {
        $Global:configJson = (Get-Content -Raw $json) | ConvertFrom-Json

        $sddcMgrFqdn = $configJson.sddcManagerSpec.sddcMgrFqdn
        $sddcMgrUser = $configJson.sddcManagerSpec.sddcMgrUser
        $sddcMgrPassword = $configJson.sddcManagerSpec.sddcMgrPassword

        $timeZone = $configJson.infraSpec.timezone

        $domain = $configJson.activeDirectory.domain
        $domainAlias = ($domain.Split("."))[0].ToUpper()
        $baseUserDn = $configJson.activeDirectory.baseUserDn
        $baseGroupDn = $configJson.activeDirectory.baseGroupDn
        $primaryUrl = 'ldap://' + $configJson.activeDirectory.dcMachineName + '.' + $domain + ':389'

        $vcAdmin = $configJson.adGroupSpec.vcAdmin
        $vcfAdmin = $domain.ToUpper() + "\" + $configJson.adGroupSpec.vcfAdmin
        $vcfOperator = $domain.ToUpper() + "\" + $configJson.adGroupSpec.vcfOperator
        $vcfViewer = $domain.ToUpper() + "\" + $configJson.adGroupSpec.vcfViewer
        $esxiAdmin = $domainAlias.ToUpper() + "\" + $configJson.adGroupSpec.esxiAdmin

        $vCenterAdminUser = $configJson.vcenterSpec.vCenterAdminUser
        $vCenterAdminPassword = $configJson.vcenterSpec.vCenterAdminPassword
        $vCenterRootUser = $configJson.vcenterSpec.vCenterRootUser
        $vCenterRootPassword = $configJson.vcenterSpec.vCenterRootPassword
        $vcenterDomainBindUser = $configJson.vcenterSpec.domainBindUser + '@' + ($domain.Split("."))[0].ToLower()
        $vcenterDomainBindPassword = $configJson.vcenterSpec.domainBindPassword
        $securePassword = ConvertTo-SecureString -String $vcenterDomainBindPassword -AsPlainText -Force
        $creds = New-Object System.Management.Automation.PSCredential ($vcenterDomainBindUser, $securePassword)

        $esxiRootUser = $configJson.esxiSpec.esxiRootUser
        $esxiRootPassword = $configJson.esxiSpec.esxiRootPassword
        $esxiDomainJoinUser = $configJson.esxiSpec.domainJoinUser
        $esxiDomainJoinPassword = $configJson.esxiSpec.domainJoinPassword
        
        $wsaFqdn = $configJson.wsaSpec.wsaFqdn
        $wsaHostname = $wsaFqdn.Split(".")[0]
        $wsaRootPassword = $configJson.wsaSpec.wsaRootPassword
        $wsaSshUserPassword = $configJson.wsaSpec.wsaSshUserPassword
        $wsaAdminPassword = $configJson.wsaSpec.wsaAdminPassword
        $wsaIpAddress = $configJson.wsaSpec.wsaIpAddress
        $wsaGateway = $configJson.wsaSpec.wsaGateway
        $wsaSubnetMask = $configJson.wsaSpec.wsaSubnetMask
        $wsaOva = $configJson.wsaSpec.wsaOva
        $wsaOvaPath = $PSScriptRoot + "\" + $wsaOva
        $wsaFolderName = $configJson.wsaSpec.wsaFolderName
        $wsaDomainBindUser = $configJson.wsaSpec.domainBindUser
        $wsaDomainBindPassword = $configJson.wsaSpec.domainBindPassword
        $rootCa = $configJson.wsaSpec.rootCa
        $wsaCertKey = $configJson.wsaSpec.wsaCertKey
        $wsaCert = $configJson.wsaSpec.wsaCert
        $rootCaPath = $PSScriptRoot + "\" + $rootCa
        $wsaCertKeyPath = $PSScriptRoot + "\" + $wsaCertKey
        $wsaCertPath = $PSScriptRoot + "\" + $wsaCert

        Write-LogMessage  -Message "Checking for Workspace ONE Access OVA File" -Colour Yellow
        if (!(Test-Path -Path $wsaOvaPath)) {
            Write-LogMessage  -Message "Workspace ONE Access OVA File Not Found" -Colour Red; Exit
        }

        Write-LogMessage  -Message "Checking for Workspace ONE Access Certificate Files" -Colour Yellow
        if (!(Test-Path -Path $rootCaPath)) {
            Write-LogMessage  -Message "Root Certificate cannot be found, ensure its present in the script folder" -Colour Red; Exit
        }
        if (!(Test-Path -Path $wsaCertKeyPath)) {
            Write-LogMessage  -Message "Workspace ONE Access Private Key cannot be found, ensure its present in the script folder" -Colour Red; Exit
        }
        if (!(Test-Path -Path $wsaCertPath)) {
            Write-LogMessage  -Message "Workspace ONE Access Certificate cannot be found, ensure its present in the script folder" -Colour Red; Exit
        }

        # Dynamically obtain details from SDDC Manager and vCenter Server
        connectVcf -fqdn $sddcMgrFqdn -username $sddcMgrUser -password $sddcMgrPassword

        $vCenterFqdn = (Get-VCFWorkloadDomain | Where-Object {$_.type -eq "MANAGEMENT"}).vcenters.fqdn
        $vCenterVmName = $vCenterFqdn.Split(".")[0]
         
        connectVsphere -hostname $vCenterFqdn -user $vCenterAdminUser -password $vCenterAdminPassword # Connect to vCenter Server

        $ntpServer = (Get-VCFConfigurationNTP).ipAddress
        $dnsServer1 = (Get-VCFConfigurationDNS | Where-Object {$_.isPrimary -Match "True"}).ipAddress
        $dnsServer2 = (Get-VCFConfigurationDNS | Where-Object {$_.isPrimary -Match "False"}).ipAddress

        $cluster = (Get-VCFCluster | Where-Object {$_.id -eq ((Get-VCFWorkloadDomain | Where-Object {$_.type -eq "MANAGEMENT"}).clusters.id)}).Name
        $datastore = (Get-VCFCluster | Where-Object {$_.id -eq ((Get-VCFWorkloadDomain | Where-Object {$_.type -eq "MANAGEMENT"}).clusters.id)}).primaryDatastoreName
        $datacenter = (Get-Datacenter -Cluster $cluster).Name
        $regionaPortgroup = (Get-VCFApplicationVirtualNetwork | Where-Object {$_.regionType -eq "REGION_A"}).name
    }
    else {
        Write-LogMessage  -Message "JSON File Not Found" -Colour Red; Exit
    }  

    if ($DefaultVIServer.Name -eq $vCenterFqdn) {

        # Add Active Directory over LDAP as Identity Provider to vCenter Server and Set as Default
        Try {
            Write-LogMessage -Message "Add Active Directory over LDAP as Identity Provider to vCenter Server and Set as Default" -Colour Yellow
            Write-LogMessage -Message "Checking if the Identity Source $domain has already been set on vCenter Server $vCenterFqdn"
            $scriptCommand = '/opt/vmware/bin/sso-config.sh -get_identity_sources'
            $output = Invoke-VMScript -VM $vCenterVmName -ScriptText $scriptCommand -GuestUser $vCenterRootUser -GuestPassword $vCenterRootPassword -ErrorAction SilentlyContinue; $output | Out-File $logFile -Encoding ASCII -Append
            if (($output.ScriptOutput).Contains($domain)) {
                Write-LogMessage -Message "Identity Source $domain already added to vCenter Server $vCenterFqdn" -Colour Magenta
            }
            else {
                Write-LogMessage -Message "Adding $domain as an Identity Source on vCenter Server $vCenterFqdn with user $vcenterDomainBindUser"
                $scriptCommand = '/opt/vmware/bin/sso-config.sh -add_identity_source -type adldap -baseUserDN '+$baseUserDn+' -baseGroupDN '+$baseGroupDn+' -domain '+$domain+' -alias '+$domainAlias+' -username '+$vcenterDomainBindUser+' -password '+$vcenterDomainBindPassword+' -primaryURL '+$primaryUrl+''
                $output = Invoke-VMScript -VM $vCenterVmName -ScriptText $scriptCommand -GuestUser $vCenterRootUser -GuestPassword $vCenterRootPassword; $output | Out-File $logFile -Encoding ASCII -Append
                Write-LogMessage -Message "Checking if Identity Source $domain was added correctly"
                $scriptCommand = '/opt/vmware/bin/sso-config.sh -get_identity_sources'
                $output = Invoke-VMScript -VM $vCenterVmName -ScriptText $scriptCommand -GuestUser $vCenterRootUser -GuestPassword $vCenterRootPassword -ErrorAction SilentlyContinue; $output | Out-File $logFile -Encoding ASCII -Append
                if (($output.ScriptOutput).Contains($domain)) {
                    Write-LogMessage -Message "Confirmed adding Identity Source $domain to vCenter Server $vCenterFqdn Successfully" -Colour Green
                }
                else {
                    Write-LogMessage -Message "Adding Identity Source $domain to vCenter Server $vCenterFqdn Failed" -Colour Red
                    disconnectVsphere -hostname $vCenterFqdn # Disconnect from First ESXi Host
                    Exit
                }
                Write-LogMessage -Message "Setting Identity Source $domain as Default in vCenter Server $vCenterFqdn"
                $scriptCommand = '/opt/vmware/bin/sso-config.sh -set_default_identity_sources -i '+$domain+''
                $output = Invoke-VMScript -VM $vCenterVmName -ScriptText $scriptCommand -GuestUser $vCenterRootUser -GuestPassword $vCenterRootPassword; $output | Out-File $logFile -Encoding ASCII -Append
                Write-LogMessage -Message "Confirmed setting $domain as Default Identity Source on vCenter Server $vCenterFqdn Successfully" -Colour Green
            }
        }
        Catch {
            Debug-CatchWriter -object $_
        }

        # Assign an Active Directory Group the Administrator Role as a Global Permission in vCenter Server
        Try {
            Write-LogMessage -Message "Assign an Active Directory Group the Administrator Role as a Global Permission in vCenter Server" -Colour Yellow
            Write-LogMessage -Message "Checking if Active Directory Group '$vcAdmin' is present in Active Directory Domain"
            if (Get-ADGroup -Server $domain -Credential $creds -Filter {SamAccountName -eq $vcAdmin}) {
                Write-LogMessage -Message "Getting Role ID for 'Administrator' from vCenter Server $vCenterFqdn"
                $roleId = (Get-VIRole -Name "Admin" | Select-Object -ExpandProperty Id)
                Write-LogMessage -Message "Assigning Global Permission Role 'Administrator' to $vcAdmin in vCenter Server $vCenterFqdn"
                New-GlobalPermission -vc_server $vCenterFqdn -vc_username $vCenterAdminUser -vc_password $vCenterAdminPassword -vc_role_id $roleId -vc_user $vcAdmin -propagate $true -type group
                Write-LogMessage -Message "Assigned Global Permission Role 'Administrator' to $vcAdmin in vCenter Server $vCenterFqdn Successfully" -Colour Green
            }
            else {
                Write-LogMessage -Message "Active Directory Group '$vcAdmin' not found in the Active Directory Domain, please create and retry" -Colour Red
            }
        }
        Catch {
            Debug-CatchWriter -object $_
        }

        # Assign Active Directory Groups to the Admin, Operator and Viewer Roles in SDDC Manager
        Try {
            Write-LogMessage -Message "Assign Active Directory Groups to the Admin, Operator and Viewer Roles in SDDC Manager" -Colour Yellow
            createSddcManagerRole -adGroup $vcfAdmin -adDomain $domain -secureCreds $creds -vcfRole ADMIN
            createSddcManagerRole -adGroup $vcfOperator -adDomain $domain -secureCreds $creds -vcfRole OPERATOR
            createSddcManagerRole -adGroup $vcfViewer -adDomain $domain -secureCreds $creds -vcfRole VIEWER
        }
        Catch {
            Debug-CatchWriter -object $_
        }

        # Join each ESXi Host to the Active Directory Domain
        Try {
            Write-LogMessage -Message "Join each ESXi Host to the Active Directory Domain" -Colour Yellow
            $esxiHosts = Get-VMHost
            $count=0
            Foreach ($esxiHost in $esxiHosts) {
                Write-LogMessage -Message "Checking if ESXi Host $esxiHost is already joined to Active Directory Domain $domain"
                $currentDomainState = Get-VMHostAuthentication -VMHost $esxiHost
                $currentDomain = [String]$currentDomainState.Domain
                if ($currentDomain -ne $domain) {
                    Write-LogMessage -Message "Joining ESXi Host $esxiHost to Active Directory Domain $domain"
                    Get-VMHostAuthentication -VMHost $esxiHost | Set-VMHostAuthentication -Domain $domain -JoinDomain -Username $esxiDomainJoinUser -Password $esxiDomainJoinPassword -Confirm:$false | Out-File $logFile -Encoding ASCII -Append
                    Write-LogMessage -Message "Verifiying that ESXi Host $esxiHost joined Active Directory Domain $domain correctly"
                    $currentDomainState = Get-VMHostAuthentication -VMHost $esxiHost
                    $currentDomain = [String]$currentDomainState.Domain
                    if ($currentDomain -eq $domain.ToUpper()) {
                        Write-LogMessage -Message "Confirmed ESXi Host $esxiHost joined Active Directory Domain $domain Successfully" -Colour Green
                    }
                    else {
                        Write-LogMessage -Message "Adding ESXi Host $esxiHost to Active Directory Domain $domain Failed" -Colour Red
                        disconnectVsphere -hostname $vCenterFqdn # Disconnect from vCenter Server
                    Exit
                    }
                }
                else {
                    Write-LogMessage -Message "ESXi Host $esxiHost is already joined to Active Directory Domain $domain" -Colour Magenta
                }
                $count=$count+1
            }
        }
        Catch {
            Debug-CatchWriter -object $_
        }

        disconnectVsphere -hostname $vCenterFqdn # Disconnect from vCenter Server

        # Assign an Active Directory Group to each ESXi Host for Administration
        Try {
            Write-LogMessage -Message "Assign an Active Directory Group to each ESXi Host for Administration" -Colour Yellow

            $groupName = $esxiAdmin.Split("\")[1]
            Write-LogMessage -Message "Checking if Active Directory Group '$groupName' is present in Active Directory Domain"
            if (Get-ADGroup -Server $domain -Credential $creds -Filter {SamAccountName -eq $groupName}) {
                $count=0
                Foreach ($esxiHost in $esxiHosts) {
                    connectVsphere -hostname $esxiHost -user $esxiRootUser -password $esxiRootPassword # Connect to ESXi Server
                    Write-LogMessage -Message "Checking to see if Active Directory Group $esxiAdmin has already been assigned permissions to $esxiHost"
                    $checkPermission = Get-VIPermission | Where-Object {$_.Principal -eq $esxiAdmin}
                    if ($checkPermission.Principal -eq $esxiAdmin) {
                        Write-LogMessage -Message "Active Directory Group '$esxiAdmin' already assigned permissions to $esxiHost" -Colour Magenta
                    }
                    else {
                        Write-LogMessage -Message "Adding Active Directory Group '$esxiAdmin' the Administrator role to $esxiHost"
                        New-VIPermission -Entity (Get-VMHost) -Principal $esxiAdmin -Propagate $true -Role Admin | Out-File $logFile -Encoding ASCII -Append
                        Write-LogMessage -Message "Checking if Active Directory Group '$esxiAdmin' was added correctly"
                        $checkPermission = Get-VIPermission | Where-Object {$_.Principal -eq $esxiAdmin}
                        if ($checkPermission.Principal -eq $esxiAdmin) {
                            Write-LogMessage -Message "Active Directory Group '$esxiAdmin' assigned the Administrator role to $esxiHost Successfully" -Colour Green
                        }
                        else {
                            Write-LogMessage -Message "Assigning Active Directory Group '$esxiAdmin' the Administrator role to $esxiHost Failed" -Colour Red
                        }
                    }
                    disconnectVsphere -hostname $esxiHost # Disconnect from ESXi Server
                    $count=$count+1
                }
            }
            else {
                Write-LogMessage -Message "Active Directory Group '$groupName' not found in the Active Directory Domain, please create and retry" -Colour Red
            }
        }
        Catch {
            Debug-CatchWriter -object $_
        }

        # Deploy and Configure Workspace ONE Access Virtual Appliance
        Try {
            # Create VM and Template Folder
            Write-LogMessage -Message "Create VM and Template Folder and Deploy the Workspace One Access Virtual Appliance" -Colour Yellow
            connectVsphere -hostname $vCenterFqdn -user $vCenterAdminUser -password $vCenterAdminPassword # Connect to vCenter Server
            
            Write-LogMessage -Message "Checking if VM and Template Folder '$wsaFolderName' already exists in vCenter Server $vCenterFqdn"
            $folderExists = (Get-Folder -Name $wsaFolderName -ErrorAction SilentlyContinue)
            if ($folderExists) {
                Write-LogMessage -Message "The VM and Template Folder '$wsaFolderName' already exists in $vCenterFqdn" -colour Magenta
            }
            else {
                Write-LogMessage -Message "Creating VM and Template Folder '$wsaFolderName' in vCenter Server $vCenterFqdn"
                $folder = (Get-View (Get-View -viewtype datacenter -filter @{"name"=[string]$datacenter}).vmfolder).CreateFolder($wsaFolderName)
                Write-LogMessage -Message "Checking if VM and Template Folder '$wsaFolderName' was created correctly"
                $folderExists = (Get-Folder -Name $wsaFolderName -ErrorAction SilentlyContinue)
                if ($folderExists) {
                    Write-LogMessage -Message  "Created VM and Template Folder '$wsaFolderName' in vCenter Server $vCenterFqdn Successfully" -Colour Green
                }
                else {
                    Write-LogMessage -Message "Creating VM and Template Folder '$wsaFolderName' in vCenter Server $vCenterFqdn Failed" -Colour Red
                }
            }

            # Deploy Workspace ONE Access Virtual Appliance
            Write-LogMessage -Message "Checking for pre-existing Workspace ONE Access virtual machine called $wsaHostname in vCenter Server $vCenterFqdn"
            $wsaExists = Get-VM -Name $wsaHostname -ErrorAction SilentlyContinue
            if ($wsaExists) {
                Write-LogMessage -Message "A virtual machine called $wsaHostname already exists in vCenter Server $vCenterFqdn" -Colour Magenta
            }
            else {
                Write-LogMessage -Message "No virtual machine called $wsaHostname found in vCenter Server $vCenterFqdn. Proceeding with Deployment"  					
                $command = '"C:\Program Files\VMware\VMware OVF Tool\ovftool.exe" --noSSLVerify --acceptAllEulas  --allowAllExtraConfig --diskMode=thin --powerOn --name='+$wsaHostname+' --ipProtocol="IPv4" --ipAllocationPolicy="fixedAllocatedPolicy" --vmFolder='+$wsaFolderName+' --net:"Network 1"='+$regionaPortgroup+'  --datastore='+$datastore+' --X:injectOvfEnv --prop:vamitimezone='+$timezone+'  --prop:vami.ip0.IdentityManager='+$wsaIpAddress+' --prop:vami.netmask0.IdentityManager='+$wsaSubnetMask+' --prop:vami.hostname='+$wsaFqdn+' --prop:vami.gateway.IdentityManager='+$wsaGateway+' --prop:vami.domain.IdentityManager='+$domain+' --prop:vami.searchpath.IdentityManager='+$domain+' --prop:vami.DNS.IdentityManager='+$dnsServer1+','+$dnsServer2+' '+$wsaOvaPath+'  "vi://'+$vCenterAdminUser+':'+$vCenterAdminPassword+'@'+$vcenterFqdn+'/'+$datacenter+'/host/'+$cluster+'/"'
                $command | Out-File $logFile -Encoding ASCII -Append
                Write-LogMessage -Message "This will take at least 10-15 minutes and maybe significantly longer depending on the environment. Please be patient" 
                Invoke-Expression "& $command" | Out-File $logFile -Encoding ASCII -Append
                $wsaExists = Get-VM -Name $wsaHostname -ErrorAction SilentlyContinue
                if ($wsaExists) {
                    $Timeout = 900  ## seconds
                    $CheckEvery = 15  ## seconds
                    Try {
                        $timer = [Diagnostics.Stopwatch]::StartNew()  ## Start the timer
                        Write-LogMessage -Message "Checking the deployment status of Workspace ONE Access Virtual Machine $wsaHostname in vCenter Server $vCenterFqdn"
                        Write-LogMessage -Message "Waiting for $wsaIpAddress to become pingable." -Colour Yellow
                        While (-not (Test-Connection -ComputerName $wsaIpAddress -Quiet -Count 1)) {
                            ## If the timer has waited greater than or equal to the timeout, throw an exception exiting the loop
                            if ($timer.Elapsed.TotalSeconds -ge $Timeout) {
                                Throw "Timeout Exceeded. Giving up on ping availability to $wsaIpAddress"
                            }
                            Start-Sleep -Seconds $CheckEvery  ## Stop the loop every $CheckEvery seconds
                        }
                    }
                    Catch {
                        Write-LogMessage -Message "ERROR: Failed to get a Response from $wsaHostname" -Colour Red
                    }
                    Finally {
                        $timer.Stop()  ## Stop the timer
                    }
                    Try {
                        #Polling for Completed Deployment
                        $scriptSuccess = 'more /var/log/boot.msg | grep "' + "'hzn-dots start'" + ' exits with status 0"'
                        $scriptError = 'more /var/log/boot.msg | grep "' + "'hzn-dots start'" + ' exits with status 1"'
                        Write-LogMessage -Message "Initial connection made, waiting for $wsaHostname to fully boot and services to start. Be warned, this takes a long time." -Colour Yellow
                        Do {
                            Start-Sleep 30
                            $ScriptSuccessOutput = Invoke-VMScript -VM $wsaHostname -ScriptText $scriptSuccess -GuestUser root -GuestPassword vmware -ErrorAction SilentlyContinue
                            $ScriptErrorOutput = Invoke-VMScript -VM $wsaHostname -ScriptText $scriptError -GuestUser root -GuestPassword vmware -ErrorAction SilentlyContinue
                            If (($ScriptSuccessOutput.ScriptOutput) -OR ($scriptError.ScriptOutput)) {
                                $finished=$true
                            }
                        } Until($finished)
                        if ($ScriptSuccessOutput) {
                            Write-LogMessage -Message "Deployment of $wsaHostname using $wsaOvaPath completed Successfully" -Colour Green
                           }
                        elseif ($ScriptErrorOutput) {
                            Write-LogMessage -Message "$wsaHostname failed to initialize properly. Please delete the VM from $vcenterFqdn and retry."
                            Exit
                        }
                    }
                    Catch {
                        Debug-CatchWriter -object $_
                    }
                }
                else {
                    Write-LogMessage -Message "Workspace ONE Access Failed to deploy. Please check for errors in $logFile" -Colour Red    
                }
            }

            # Perform Initial Configuration of Workspace ONE Access Virtual Appliance
            Write-LogMessage -Message "Perform Initial Configuration of Workspace ONE Access Virtual Appliance" -Colour Yellow
            $baseUri = "https://"+$wsaFqdn+":8443"
            Write-LogMessage -Message "Connecting to Workspace ONE Access Virtual Appliance to obtain a token"
            $uri = $baseUri + "/login"
            $response = Invoke-RestMethod $uri -Method 'GET' -SessionVariable webSession
            $response | Out-File wsaResponse.txt
            $tokenSource = (Select-String -Path wsaResponse.txt -Pattern 'window.ec_wiz.vk =')
            $token = ($tokenSource -Split ("'"))[1]
            Remove-Item wsaResponse.txt
            if ($token) {
                $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                $headers.Add("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
                $headers.Add("X-Vk", "$token")
                $headers.Add("Accept", "application/json")

                Write-LogMessage -Message "Setting the Admin Password for Workspace ONE Access Virtual Appliance $wsaFqdn"
                $body = "password="+$wsaAdminPassword+"&confpassword="+$wsaAdminPassword
                $uri = $baseUri + "/cfg/changePassword"
                Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body -WebSession $webSession | Out-File $logFile -Encoding ASCII -Append

                Write-LogMessage -Message "Setting the Root & SSHUser Passwords for Workspace ONE Access Virtual Appliance $wsaFqdn"
                $body = "rootPassword="+$wsaRootPassword+"&sshuserPassword="+$wsaSshUserPassword
                $uri = $baseUri + "/cfg/system"
                Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body -WebSession $webSession | Out-File $logFile -Encoding ASCII -Append

                Write-LogMessage -Message "Starting the Internal Database for Workspace ONE Access Virtual Appliance $wsaFqdn"
                $uri = $baseUri + "/cfg/setup/initialize"
                Invoke-RestMethod $uri -Method 'POST' -Headers $headers -WebSession $webSession | Out-File $logFile -Encoding ASCII -Append

                Write-LogMessage -Message "Activating the default connector Workspace ONE Access Virtual Appliance $wsaFqdn" 
                $uri = $baseUri + "/cfg/setup/activateConnector"
                Invoke-RestMethod $uri -Method 'POST' -Headers $headers -WebSession $webSession | Out-File $logFile -Encoding ASCII -Append
                Write-LogMessage -Message "Initial configuration of Workspace ONE Access Virtual Appliance $wsaFqdn completed Succesfully" -Colour Green
            }
            else {
                Write-LogMessage -Message "Initial configuration of Workspace ONE Access Virtual Appliance $wsaFqdn has already been performed" -Colour Magenta
            }
<#
            # Setting the the Admin Password on Workspace One Access Virtual Appliance
            Write-LogMessage -Message "Setting the the Admin Password on Workspace One Access Virtual Appliance" -Colour Yellow
            $scriptCommand = 'echo '+$wsaAdminPassword+' | /usr/sbin/hznAdminTool setSystemAdminPassword --pass '+$wsaAdminPassword
            $output = Invoke-VMScript -VM $wsaHostname -ScriptText $scriptCommand -GuestUser root -GuestPassword $wsaRootPassword; $output | Out-File $logFile -Encoding ASCII -Append
            if (($output.ScriptOutput).Contains("Successfully set admin password")) {
                Write-LogMessage -Message "Set the the Admin Password on $wsaFqdn Successfully" -Colour Green
            }
            else {
                Write-LogMessage -Message "Setting the the Admin Password on $wsaFqdn Failed" -Colour Red
            }
#>
        
            # Configure NTP Server on Workspace ONE Access Appliance
            Write-LogMessage -Message "Configure NTP Server on Workspace One Access Virtual Appliance" -Colour Yellow
            Write-LogMessage -Message "Checking if NTP Server '$ntpServer' has been configured on Workspace One Access Virtual Appliance $wsaFqdn"
            $scriptCommand = '/usr/local/horizon/scripts/ntpServer.hzn --get'
            $output = Invoke-VMScript -VM $wsaHostname -ScriptText $scriptCommand -GuestUser root -GuestPassword $wsaRootPassword; $output | Out-File $logFile -Encoding ASCII -Append
            if (($output.ScriptOutput).Contains($ntpServer)) {
                Write-LogMessage -Message "NTP Server '$ntpServer' already configured on Workspace One Access Virtual Appliance $wsaFqdn" -Colour Magenta
            }
            else {
                Write-LogMessage -Message "Attempting to configure NTP Server '$ntpServer' on Workspace One Access Virtual Appliance $wsaFqdn"
                $scriptCommand = '/usr/local/horizon/scripts/ntpServer.hzn --set '+$ntpServer
                $output = Invoke-VMScript -VM $wsaHostname -ScriptText $scriptCommand -GuestUser root -GuestPassword $wsaRootPassword; $output | Out-File $logFile -Encoding ASCII -Append
                Write-LogMessage -Message "Checking to see if configuring NTP Server '$ntpServer' on Workspace One Access Virtual Appliance $wsaFqdn completed correctly"
                $scriptCommand = '/usr/local/horizon/scripts/ntpServer.hzn --get'
                $output = Invoke-VMScript -VM $wsaHostname -ScriptText $scriptCommand -GuestUser root -GuestPassword $wsaRootPassword; $output | Out-File $logFile -Encoding ASCII -Append
                if (($output.ScriptOutput).Contains($ntpServer)) {
                    Write-LogMessage -Message "Configured NTP Server '$ntpServer' on Workspace One Access Virtual Appliance $wsaFqdn Successfully" -Colour Green
                }
                else {
                    Write-LogMessage -Message "Configuring NTP Server '$ntpServer' on Workspace One Access Virtual Appliance $wsaFqdn Failed" -Colour Red
                }
            }

            # Install a Signed Certificate on Workspace ONE Access Appliance
            Write-LogMessage -Message "Install a Signed Certificate on Workspace One Access Virtual Appliance" -Colour Yellow
            Write-LogMessage -Message "Copying Certificate Files to Workspace One Access Virtual Appliance $wsaFqdn"
            $SecurePassword = ConvertTo-SecureString -String $wsaSshUserPassword -AsPlainText -Force
            $secureCreds = New-Object System.Management.Automation.PSCredential ("sshuser", $SecurePassword)
            Set-SCPFile -ComputerName $wsaFqdn -Credential $secureCreds -RemotePath '/tmp' -LocalFile $rootCaPath -NoProgress -AcceptKey $true -Force -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
            Set-SCPFile -ComputerName $wsaFqdn -Credential $secureCreds -RemotePath '/tmp' -LocalFile $wsaCertKeyPath -NoProgress -AcceptKey $true -Force -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
            Set-SCPFile -ComputerName $wsaFqdn -Credential $secureCreds -RemotePath '/tmp' -LocalFile $wsaCertPath -NoProgress -AcceptKey $true -Force -WarningAction SilentlyContinue | Out-File $logFile -Encoding ASCII -Append
            Write-LogMessage -Message "Installing Signed Certifcate $wsaCert on Workspace One Access Virtual Appliance $wsaFqdn"
            $scriptCommand = 'echo "yes" | /usr/local/horizon/scripts/installExternalCertificate.hzn --ca /tmp/'+$rootCa+' --cert /tmp/'+$wsaCert+' --key /tmp/'+$wsaCertKey
            $output = Invoke-VMScript -VM $wsaHostname -ScriptText $scriptCommand -GuestUser root -GuestPassword $wsaRootPassword; $output | Out-File $logFile -Encoding ASCII -Append
            Write-LogMessage -Message "Installed Signed Certifcate $wsaCert on Workspace One Access Virtual Appliance $wsaFqdn Successfully" -Colour Green

            disconnectVsphere -hostname $vCenterFqdn # Disconnect from vCenter Server
        }
        Catch {
            Debug-CatchWriter -object $_
        }
    }
    else {
        Write-LogMessage  -Message "Connection Attempt to $vCenterFqdn Failed" -Colour Red
        Exit
    }
}
Catch {
    Debug-CatchWriter -object $_
}