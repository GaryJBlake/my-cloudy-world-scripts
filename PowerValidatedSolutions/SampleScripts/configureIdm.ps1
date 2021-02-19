Clear-Host

$domain = "ldn.cloudy.io"
$domainBindUser = "svc-vsphere-ad"
$domainBindPass = "VMw@re1!"
$dcMachineName = "ldn-dc1"
$baseGroupDn = "OU=VVD,dc=ldn,dc=cloudy,dc=io"
$baseUserDn = "OU=VVD,dc=ldn,dc=cloudy,dc=io"
$domainJoinUser = "svc-domain-join"
$domainJoinPass = "VMw@re1!"

$vCenterVmName = "ldn-m01-vc01"
$vcRootPassword = "VMw@re1!"

$vcServer = $vCenterVmName + "." + $domain
$vcUsername = "administrator@vsphere.local"
$vcPassword = "VMw@re1!"

$principal = "gg-vc-admins"
$role = "Admin"

$esxiUser = "root"
$esxiPassword = "VMw@re1!"
$esxiGroup = "gg-esxi-admins"

$vcfFqdn = "ldn-vcf01.ldn.cloudy.io"
$vcfUser = "administrator@vsphere.local"
$vcfPass = "VMw@re1!"

$vcfAdminGroup = "gg-vcf-admins"
$vcfOperatorGroup = "gg-vcf-operators"
$vcfViewerGroup = "gg-vcf-viewers"

$wsaHostname = "ldn-wsa01"
$wsaIpAddress = "192.168.31.60"
$wsaGateway = "192.168.31.1"
$wsaSubnetMask = "255.255.255.0"
$wsaOvaPath = "identity-manager-3.3.4.0-17451211_OVF10.ova"
$wsaFolder = "ldn-m01-fd-wsa"
$wsaFqdn = $wsaHostname + "." + $domain
$wsaAdminPassword = "VMw@re1!"
$wsaRootPassword = "VMw@re1!"
$wsaSshUserPassword = "VMw@re1!"
$rootCa = "Root64.cer"
$wsaCertKey = "ldn-wsa01.key"
$wsaCert = "ldn-wsa01.1.cer"

# Assign Active Directory Group for ESXi Host Administration
Add-ESXiDomainUser -vcServer $vcServer -vcUser $vcUsername -vcPass $vcPassword -esxiUser $esxiUser -esxiPass $esxiPassword -domain $domain -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $esxiGroup -role $role -propagate $true

# Add Active Directory Identity Provider to vCenter Server
Connect-VIServer -Server $vcServer -User $vcUsername -pass $vcPassword
#Add-IdentitySource -vCenterVmName $vCenterVmName -rootPass $vcRootPassword -domain $domain -domainBindUser $domainBindUser -domainBindPass $domainBindPass -dcMachineName $dcMachineName -baseGroupDn $baseGroupDn -baseUserDn $baseUserDn

# Assign Active Directory Group the Administrator Role in vCenter Server
Add-GlobalPermission -server $vcServer -user $vcUsername -pass $vcPassword -domain $domain -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $principal -role $role -propagate true -type group

# Assign Active Directory Groups to Roles in SDDC Manager
Add-SddcManagerRole -server $vcfFqdn -user $vcfUser -pass $vcfPass -domain $domain -domainBindUser $domainBindUser -domainBindPass $domainBindPass -group $vcfAdminGroup -role ADMIN
Add-SddcManagerRole -server $vcfFqdn -user $vcfUser -pass $vcfPass -domain $domain -domainBindUser $domainBindUser -domainBindPass $domainBindPass -group $vcfOperatorGroup -role OPERATOR
Add-SddcManagerRole -server $vcfFqdn -user $vcfUser -pass $vcfPass -domain $domain -domainBindUser $domainBindUser -domainBindPass $domainBindPass -group $vcfViewerGroup -role VIEWER

# Join the ESXi Hosts to Active Directory
Join-ESXiJoinDomain -domain $domain -domainJoinUser $domainJoinUser -domainJoinPass $domainJoinPass

# Create the VM and Template Folder for Region-Specific Workspace ONE Access
Add-VMFolder -server $vcfFqdn -user $vcfUser -pass $vcfPass -folderName $wsaFolder

# Deploy Workspace ONE Access Virtual Appliance
Install-WorkspaceOne -vcServer $vcServer -vcUser $vcUsername -vcPass $vcPassword -server $vcfFqdn -user $vcfUser -pass $vcfPass -wsaHostname $wsaHostname -wsaIpAddress $wsaIpAddress -wsaGateway $wsaGateway -wsaSubnetMask $wsaSubnetMask -wsaOvaPath $wsaOvaPath -wsaFolder $wsaFolder

# Perform Initial Configuration of Workspace ONE Access Virtual Appliance
Initialize-WorkspaceOne -wsaFqdn $wsaFqdn -adminPass $wsaAdminPassword -rootPass $wsaRootPassword -sshUserPass $wsaSshUserPassword

# Install a Signed Certificate on Workspace ONE Access Appliance
Install-WorkspaceOneCertificate -wsaFqdn $wsaFqdn -vmName $wsaHostname -rootPass $wsaRootPassword -sshUserPass $wsaSshUserPassword -rootCa $rootCa -wsaCertKey $wsaCertKey -wsaCert $wsaCert

# Configure NTP Server on Workspace ONE Access Appliance
Set-WorkspaceOneNtpConfig -vcServer $vcServer -vcUser $vcUsername -vcPass $vcPassword -vcfFqdn $vcfFqdn -vcfUser $vcfUser -vcfPass $vcfPass -vmName $wsaHostname -rootPass $wsaRootPassword

Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue
