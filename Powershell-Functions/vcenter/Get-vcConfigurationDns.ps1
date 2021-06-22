Function Get-vcConfigurationDns {
     <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			03/06/2021
        Organization:	VMware
        Blog:           my-cloudy-world.com
        Twitter:        @GaryJBlake
        ===========================================================================

        .SYNOPSIS
        Get DNS configuration

        .DESCRIPTION
        The Get-vcConfigurationDns cmdlet gets the DNS configuration of the connected vCenter Server

        .EXAMPLE
        Get-vcConfigurationDns
        This example gets the DNS configuration of the connected vCenter Server
    #>

    Try {
        $vcenterHeader = @{"vmware-api-session-id" = "$vcToken"}
        $uri = "https://$vcenterFqdn/api/appliance/networking/dns/servers"

        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $vcenterHeader
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}