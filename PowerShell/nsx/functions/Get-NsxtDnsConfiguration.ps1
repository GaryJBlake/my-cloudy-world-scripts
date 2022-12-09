<#
    .NOTES
    ===================================================================================================================
    Created by:		Gary Blake
    Date:			2022/11/25
    Organization:	VMware
    Blog:           my-cloudy-world.com
    Twitter:        @GaryJBlake
    ===================================================================================================================
    
    .SYNOPSIS
    Get DNS configuration

    .DESCRIPTION
    The Get-NsxtDnsConfiguration cmdlet retrieves the current DNS configuration from NSX Manager

    .EXAMPLE
    Get-NsxtDnsConfiguration
    This example retrieves the current DNS configuration from NSX Manager
#>

Try {
    $uri = "https://$nsxtManager/api/v1/node/network/name-servers"
    Invoke-RestMethod $uri -Method 'GET' -Headers $nsxtHeaders
}
Catch {
    Write-Error $_.Exception.Message
}