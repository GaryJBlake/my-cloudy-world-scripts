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

$vcfFqdn = "ldn-vcf01.ldn.cloudy.io"
$vcfUser = "administrator@vsphere.local"
$vcfPass = "VMw@re1!"

$vcfAdminGroup = "gg-vcf-admins"
$vcfOperatorGroup = "gg-vcf-operators"
$vcfViewerGroup = "gg-vcf-viewers"

$wsaFolder = "ldn-m01-fd-wsa"

# Add Active Directory Identity Provider to vCenter Server
Connect-VIServer -Server $vcServer -User $vcUsername -pass $vcPassword
#Add-IdentitySource -vCenterVmName $vCenterVmName -rootPass $vcRootPassword -domain $domain -domainBindUser $domainBindUser -domainBindPass $domainBindPass -dcMachineName $dcMachineName -baseGroupDn $baseGroupDn -baseUserDn $baseUserDn
Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue

# Assign Active Directory Group the Administrator Role in vCenter Server
Connect-VIServer -Server $vcServer -User $vcUsername -pass $vcPassword
Add-GlobalPermission -server $vcServer -user $vcUsername -pass $vcPassword -domain $domain -domainBindUser $domainBindUser -domainBindPass $domainBindPass -principal $principal -role $role -propagate true -type group
Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue

# Assign Active Directory Groups to Roles in SDDC Manager
Add-SddcManagerRole -server $vcfFqdn -user $vcfUser -pass $vcfPass -domain $domain -domainBindUser $domainBindUser -domainBindPass $domainBindPass -group $vcfAdminGroup -role ADMIN
Add-SddcManagerRole -server $vcfFqdn -user $vcfUser -pass $vcfPass -domain $domain -domainBindUser $domainBindUser -domainBindPass $domainBindPass -group $vcfOperatorGroup -role OPERATOR
Add-SddcManagerRole -server $vcfFqdn -user $vcfUser -pass $vcfPass -domain $domain -domainBindUser $domainBindUser -domainBindPass $domainBindPass -group $vcfViewerGroup -role VIEWER

# Join the ESXi Hosts to Active Directory
Connect-VIServer -Server $vcServer -User $vcUsername -pass $vcPassword
Join-ESXiJoinDomain -domain $domain -domainJoinUser $domainJoinUser -domainJoinPass $domainJoinPass
Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue

# Assign Active Directory Group for ESXi Host Administration
Add-ESXiDomainUser -vcServer $vcServer -vcUser $vcUsername

# Create the VM and Template Folder for Region-Specific Workspace ONE Access
Connect-VIServer -Server $vcServer -User $vcUsername -pass $vcPassword
Add-VMFolder -server $vcfFqdn -user $vcfUser -pass $vcfPass -folderName $wsaFolder
Disconnect-VIServer * -Force -Confirm:$false -WarningAction SilentlyContinue