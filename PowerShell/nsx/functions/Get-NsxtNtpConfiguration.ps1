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
    Get NTP configuration

    .DESCRIPTION
    The Get-NsxtNtpConfiguration cmdlet retrieves the current NTP configuration from NSX Manager

    .EXAMPLE
    Get-NsxtNtpConfiguration
    This example retrieves the current NTP configuration from NSX Manager
#>

Try {
    $uri = "https://$nsxtManager/api/v1/node/services/ntp"
    Invoke-RestMethod $uri -Method 'GET' -Headers $nsxtHeaders
}
Catch {
    Write-Error $_.Exception.Message
}