<#	SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Blog:          http:/my-cloudy-world.com
    .Twitter:       @GaryJBlake
    .Version:       1.0 (Build 001)
    .Date:          2021-02-03
    ===============================================================================================================
    .CHANGE_LOG

    - 1.0.001 (Gary Blake / 2020-02-03) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION
    This scripts performs the configuration of Identity and Access Management for VMware Cloud Foundation.
    It uses the the JSON as the input and then performs the following steps:
    - Add Active Directory over LDAP Identity Source to vCenter Server and Set as Default
    - Assign an Active Directory Group the Administrator Role as a Global Permission in vCenter Server
    - Assign Active Directory Groups to Roles in SDDC Manager
    - Join each ESXi Host to the Active Directory Domain

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

Function importPowerCLI
{
    LogMessage -message "Importing PowerCLI Modules"
    Try
    {
        Import-Module -Name VMware.VimAutomation.Common | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null
    }
    Catch
    {
        Install-Module -Name VMware.VimAutomation.Common -confirm:$false | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null
    }
    Try
    {
        Import-Module -Name VMware.VimAutomation.Core | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null    
    }
    Catch
    {
        Install-Module -Name VMware.VimAutomation.Core -confirm:$false | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null       
    }
    Try
    {
        Import-Module -Name VMware.VimAutomation.License | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null    
    }
    Catch
    {
        Install-Module -Name VMware.VimAutomation.License -confirm:$false | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null
    }
    Try
    {
        Import-Module -Name VMware.VimAutomation.Nsxt | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null    
    }
    Catch
    {
        Install-Module -Name VMware.VimAutomation.Nsxt -confirm:$false | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null
    }
    Try
    {
        Import-Module -Name VMware.VimAutomation.Storage | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null    
    }
    Catch
    {
        Install-Module -Name VMware.VimAutomation.Storage -confirm:$false | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null
    }
    Try
    {
        Import-Module -Name VMware.VimAutomation.Vds | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null    
    }
    Catch
    {
        Install-Module -Name VMware.VimAutomation.Vds -confirm:$false | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null
    }
    LogMessage -message "Configuring PowerShell CEIP Setting"
    $setCLIConfigurationCEIP = Set-PowerCLIConfiguration -Scope AllUsers -ParticipateInCEIP $false -Confirm:$false -warningaction SilentlyContinue -InformationAction SilentlyContinue 2>&1 | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null
    LogMessage -message "Configuring PowerShell Certifcate Setting"
    $setCLIConfigurationCerts = Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$False -Scope AllUsers -warningaction SilentlyContinue -InformationAction SilentlyContinue 2>&1 | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null
    LogMessage -message "Permitting Multiple Default VI Servers"
    $setCLIConfigurationVIServers = Set-PowerCLIConfiguration -DefaultVIServerMode multiple -Confirm:$false -Scope AllUsers -warningaction SilentlyContinue -InformationAction SilentlyContinue 2>&1 | Out-File $logFile -encoding ASCII -append #2>&1 | Out-Null
    $ProgressPreference = $OriginalPref
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

        #$vCenterFqdn = $configJson.vcenterSpec.vCenterFqdn
        $vCenterAdminUser = $configJson.vcenterSpec.vCenterAdminUser
        $vCenterAdminPassword = $configJson.vcenterSpec.vCenterAdminPassword
        #$vCenterVmName = $configJson.vcenterSpec.vCenterVmName
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
        $wsaOva = $configJson.wsaSpec.wsaOva
        $wsaFolderName = $configJson.wsaSpec.wsaFolderName
        $wsaDomainBindUser = $configJson.wsaSpec.domainBindUser
        $wsaDomainBindPassword = $configJson.wsaSpec.domainBindPassword

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

        # Assign Active Directory Groups to Roles in SDDC Manager
        Try {
            Write-LogMessage -Message "Assign Active Directory Groups to Roles in SDDC Manager" -Colour Yellow
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

        # Assign Active Directory Group to each ESXi Host for Administration
        Try {
            Write-LogMessage -Message "Assign Active Directory Group to each ESXi Host for Administration" -Colour Yellow

            $groupName = $esxiAdmin.Split("\")[1]
            Write-LogMessage -Message "Checking if Active Directory Group '$groupName' is present in Active Directory Domain"
            if (Get-ADGroup -Server $domain -Credential $creds -Filter {SamAccountName -eq $groupName}) {
                $count=0
                Foreach ($esxiHost in $esxiHosts) {
                    connectVsphere -hostname $esxiHost -user $esxiRootUser -password $esxiRootPassword # Connect to vCenter Server
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


                    disconnectVsphere -hostname $esxiHost # Disconnect from vCenter Server
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

        Try {
            # Create VM and Template Folder and Deploy the Workspace One Access Virtual Appliance
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
                    Write-LogMessage -Message  "Created VM and Template Folder '$wsaFolderName' in vCenter Server $vCenterFqdn Successfully"
                }
                else {
                    Write-LogMessage -Message "reating VM and Template Folder '$wsaFolderName' in vCenter Server $vCenterFqdn Failed" -Colour Red
                }
            }

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