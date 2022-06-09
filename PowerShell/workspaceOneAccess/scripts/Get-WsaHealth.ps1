Function Get-WsaHealth {
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			09/03/2021
        Organization:	VMware
        Blog:           my-cloudy-world.com
        Twitter:        @GaryJBlake
        ===========================================================================

		.SYNOPSIS
    	Get health details

    	.DESCRIPTION
    	The Get-WsaHealth cmdlet retrieves health details from the Workspace ONE Access instance

    	.EXAMPLE
    	Get-WsaHealth
        This example shows how to reetrieve the health details of a Workspace ONE Access instance
  	#>

    Try {
        $headers = @{"Authorization" = "$wsaToken"}
        $uri = "https://$wsaFqdn/SAAS/API/1.0/REST/system/health"
        Invoke-RestMethod $uri -Method 'GET' -Headers $headers
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}