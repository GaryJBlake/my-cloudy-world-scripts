Function Get-vcVersion {
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
        Get the version

        .DESCRIPTION
        The Get-vcVersion cmdlet gets the version of the vCenter Server

        .EXAMPLE
        Get-vcVersion
        This example gets the version of the vCenter Server
    #>

    Try {
        $vcenterHeader = @{"vmware-api-session-id" = "$vcToken"}
        $uri = "https://$vcenterFqdn/api/appliance/system/version"

        $response = Invoke-RestMethod -Method GET -Uri $uri -Headers $vcenterHeader
        $response
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}