Function Get-WsaLoggedInUser {
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			11/03/2021
        Organization:	VMware
        Blog:           my-cloudy-world.com
        Twitter:        @GaryJBlake
        ===========================================================================

		.SYNOPSIS
    	Provides information about the logged-in user

    	.DESCRIPTION
    	The Get-WsaLoggedInUser cmdlet retrieves details about the logged in user

    	.EXAMPLE
    	Get-WsaLoggedInUser
        This example shows how to reetrieve details for the logged in user
  	#>

    Try {
        $headers = @{"Authorization" = "$wsaToken"}
        $uri = "https://$wsaFqdn/SAAS/jersey/manager/api/scim/Me"
        Invoke-RestMethod $uri -Method 'GET' -Headers $headers
    }
    Catch {
        Write-Error $_.Exception.Message 
    }
}