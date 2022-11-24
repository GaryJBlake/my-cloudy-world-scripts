
<#
    .SYNOPSIS
    Publish operational verification report for Identity and Access Management

    .DESCRIPTION
    The Publish-IamOperationalVerification cmdlet returns operational verification report for Identity and Access
    Management.
    - Validates authentication to SDDC Manager
    - Validates authentication to vCenter Server
    - Validates authentication to Workspace ONE Access

    .EXAMPLE
    Publish-IamOperationalVerification -server ldn-vcf01.ldn.cloudy.io -user admin@local -pass VMw@re1!VMw@re1! -wsaServer ldn-wsa01.ldn.cloudy.io -wsaUser admin -wsaPass VMw@re1! -domain ldn.cloudy.io -domainUser cloud-admin -domainPass VMw@re1!
    This example will return operational verification data for Identity and Access Management.
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaServer,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaUser,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$wsaPass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domain,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainUser,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainPass
)

Try {
    $allAuthObject = New-Object System.Collections.ArrayList
    $iamSddcManagerAuth = F:\my-cloudy-world\PowerShell\vvs\functions\iam\Request-VerifySddcManagerAuthentication.ps1 -server $server -user $user -pass $pass -domainUser ($domainUser + "@" + $domain.Split('.')[0]) -domainPass $domainPass
    $allAuthObject += $iamSddcManagerAuth
    $iamVcenterAuth = F:\my-cloudy-world\PowerShell\vvs\functions\iam\Request-VerifyVcenterAuthentication.ps1 -server $server -user $user -pass $pass -domainUser ($domainUser + "@" + $domain.Split('.')[0]) -domainPass $domainPass
    $allAuthObject += $iamVcenterAuth
    $iamWsaAuth = F:\my-cloudy-world\PowerShell\vvs\functions\iam\Request-VerifyWsaAuthentication.ps1 -server $wsaServer -user $wsaUser -pass $wsaPass
    $allAuthObject += $iamWsaAuth
    $iamNsxtAuth = F:\my-cloudy-world\PowerShell\vvs\functions\iam\Request-VerifyNsxAuthentication.ps1 -server $server -user $user -pass $pass -domainUser ($domainUser + "@" + $domain) -domainPass $domainPass
    $allAuthObject += $iamNsxtAuth
    
    $allAuthObject = $allAuthObject | ConvertTo-Html -Fragment -PreContent '<h4>Authentication Validation</h4>'
    $allAuthObject = Convert-CssClass -htmldata $allAuthObject
    $allAuthObject
}
Catch {
    Debug-CatchWriter -object $_
}
