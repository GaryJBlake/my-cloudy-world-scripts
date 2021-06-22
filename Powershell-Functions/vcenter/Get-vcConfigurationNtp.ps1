Function Get-vcConfigurationNtp {
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
    	Get NTP configuration

    	.DESCRIPTION
    	The Get-vcConfigurationNtp cmdlet gets the NTP configuration of the connected vCenter Server

    	.EXAMPLE
    	Get-vcConfigurationNtp
    	This example gets the NTP configuration of the connected vCenter Server
  	#>

    Try {
        $vcenterHeader = @{"vmware-api-session-id" = "$vcToken"}
        $uri = "https://$vcenterFqdn/api/appliance/ntp"

        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $vcenterHeader
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}