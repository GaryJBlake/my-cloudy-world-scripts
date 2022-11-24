Function Set-EsxiAdminGroup {
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
        Configures the Config.HostAgent.plugins.hostsvc.esxAdminsGroup setting

        .DESCRIPTION
        The Set-EsxiAdminGroup cmdlet connects to specified ESXi Host and sets a new value for Config.HostAgent.plugins.hostsvc.esxAdminsGroup

        .EXAMPLE
        Set-EsxiAdminGroup -server sfo01-m01-esx01.sfo.rainpole.io -groupName ug-esxi-admins
    #>
        
    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$groupName
    )
    
    Try {
        if (-Not $Global:DefaultVIServer.IsConnected) {
            Write-Error "Not Connected to a valid vCenter/ESXi Server, Please use the Connect-VIServer to connect"; Break
        }
        else {
            Get-AdvancedSetting -Entity $server -Name Config.HostAgent.plugins.hostsvc.esxAdminsGroup | Set-AdvancedSetting -Value $groupName -Confirm:$false
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }  
}