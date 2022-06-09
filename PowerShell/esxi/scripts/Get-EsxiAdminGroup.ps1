Function Get-EsxiAdminGroup {
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			01/04/2020
        Organization:	VMware
        Blog:           my-cloudy-world.com
        Twitter:        @GaryJBlake
        ===========================================================================
        
        .SYNOPSIS
        Retrieves Config.HostAgent.plugins.hostsvc.esxAdminsGroup setting
        
        .DESCRIPTION
        The Get-EsxiAdminGroup cmdlet connects to specified ESXi Host and retrives the setting for Config.HostAgent.plugins.hostsvc.esxAdminsGroup
        
        .EXAMPLE
        Get-EsxiAdminGroup -server sfo01-m01-esx01.sfo.rainpole.io
    #>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server
    )
    
    Try {
        if (-Not $Global:DefaultVIServer.IsConnected) {
            Write-Error "Not Connected to a valid vCenter/ESXi Server, Please use the Connect-VIServer to connect"; Break
        }
        else {
            $esxAdminsGroupSettings = (Get-AdvancedSetting -Entity $server -Name Config.HostAgent.plugins.hostsvc.esxAdminsGroup).Value.toString()
            $response = [pscustomobject] @{
                server = $server;
                esxAdminsGroup = $esxAdminsGroupSettings;
                }
            $response
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}