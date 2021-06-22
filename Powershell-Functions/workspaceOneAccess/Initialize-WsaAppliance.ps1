Function Initialize-WsaAppliance {
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
    	Perfoems initial configuration

    	.DESCRIPTION
    	The Initialize-WsaAppliance cmdlet performs the initial configuration of Workspace ONE Access virtual appliance

    	.EXAMPLE
    	Initialize-WsaAppliance -fqdn sfo-wsa01.sfo.rainpole.io -adminPass VMw@re1! -rootPass VMware1! -sshUserPass VMw@re1!
        This example shows how to connect to a Workspace ONE Access instance and assign credentials to complete the initial configuration
  	#>

    Param (
        [Parameter(Mandatory = $true)] [String]$fqdn,
        [Parameter(Mandatory = $true)] [String]$adminPass,
        [Parameter(Mandatory = $true)] [String]$rootPass,
        [Parameter(Mandatory = $true)] [String]$sshUserPass    
    )
    
    Try {
        $baseUri = "https://" + $fqdn + ":8443"
        $uri = $baseUri + "/login"
        $response = Invoke-RestMethod $uri -Method 'GET' -SessionVariable webSession
        $response | Out-File wsaResponse.txt
        $tokenSource = (Select-String -Path wsaResponse.txt -Pattern 'window.ec_wiz.vk =')
        $token = ($tokenSource -Split ("'"))[1]
        Remove-Item wsaResponse.txt
        if ($token) {
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
            $headers.Add("X-Vk", "$token")
            $headers.Add("Accept", "application/json")
            # Set the Admin Password
            $body = "password=" + $adminPass + "&confpassword=" + $adminPass
            $uri = $baseUri + "/cfg/changePassword"
            Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body -WebSession $webSession | Out-Null
            # Set the Root & SSHUser Passwords
            $body = "rootPassword=" + $rootPass + "&sshuserPassword=" + $sshUserPass
            $uri = $baseUri + "/cfg/system"
            Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body -WebSession $webSession  | Out-Null
            # Initalize the Internal Database
            $uri = $baseUri + "/cfg/setup/initialize"
            Invoke-RestMethod $uri -Method 'POST' -Headers $headers -WebSession $webSession  | Out-Null
            # Activate the default connector
            $uri = $baseUri + "/cfg/setup/activateConnector"
            Invoke-RestMethod $uri -Method 'POST' -Headers $headers -WebSession $webSession  | Out-Null
            Write-Output "Initial configuration of Workspace ONE Access Virtual Appliance $fqdn completed Succesfully"
        }
        else {
            Write-Warning "Initial configuration of Workspace ONE Access Virtual Appliance $fqdn has already been performed"
        }
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}