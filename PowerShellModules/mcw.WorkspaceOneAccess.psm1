# PowerShell module for VMware Workspace ONE Access
# Contributions, Improvements &/or Complete Re-writes Welcome!
# https://github.com/?

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
# WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
# COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
# OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

### Note
# This powershell module should be considered entirely experimental. It is still in development & not tested beyond lab
# scenarios. It is recommended you dont use it for any production environment without testing extensively!

# Enable communication with self signed certs when using Powershell Core. If you require all communications to be secure
# and do not wish to allow communication with self signed certs remove lines 17-38 before importing the module.

if ($PSEdition -eq 'Core') {
    $PSDefaultParameterValues.Add("Invoke-RestMethod:SkipCertificateCheck", $true)
}

if ($PSEdition -eq 'Desktop') {
    # Enable communication with self signed certs when using Windows Powershell
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;

    add-type @"
	using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertificatePolicy : ICertificatePolicy {
        public TrustAllCertificatePolicy() {}
		public bool CheckValidationResult(
            ServicePoint sPoint, X509Certificate certificate,
            WebRequest wRequest, int certificateProblem) {
            return true;
        }
	}
"@
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertificatePolicy
}

#########  Do not modify anything below this line. All user variables are in the accompanying JSON files #########

#########  Start Initial Workspace One Appliance Configuration  ##########

Function Initialize-WorkspaceOne {
    # Perform Initial Configuration of Workspace ONE Access Virtual Appliance
    Param (
        [Parameter(Mandatory = $true)][String]$wsaFqdn,
        [Parameter(Mandatory = $true)][String]$adminPass,
        [Parameter(Mandatory = $true)][String]$rootPass,
        [Parameter(Mandatory = $true)][String]$sshUserPass    
    )
    
    Try {
        $baseUri = "https://" + $wsaFqdn + ":8443"
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
            Write-Output "Initial configuration of Workspace ONE Access Virtual Appliance $wsaFqdn completed Succesfully"
        }
        else {
            Write-Warning "Initial configuration of Workspace ONE Access Virtual Appliance $wsaFqdn has already been performed"
        }
    }
    Catch {
        Debug-CatchWriter -object $_ 
    }
}
Export-ModuleMember -Function Initialize-WorkspaceOne

#########  End Initial Workspace One Appliance Configuration  ##########


#########  Start Authentication Functions  ##########

Function Request-WSAToken {
    <#
		.SYNOPSIS
    	Connects to the specified Workspace ONE Access instance to obtain a session token

    	.DESCRIPTION
    	The Request-WSAToken cmdlet connects to the specified Workspace ONE Access instance and requests a session token

    	.EXAMPLE
    	PS C:\> Request-WSAToken -fqdn sfo-wsa01.sfo.rainpole.io -username admin -password VMware1!
        This example shows how to connect to a Workspace ONE Access instance and request a session token
  	#>

    Param (
        [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [string]$fqdn,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [string]$username,
        [Parameter (Mandatory = $false)] [ValidateNotNullOrEmpty()] [string]$password
    )

    If ( -not $PsBoundParameters.ContainsKey("username") -or ( -not $PsBoundParameters.ContainsKey("password"))) {
        # Request Credentials
        $creds = Get-Credential
        $username = $creds.UserName.ToString()
        $password = $creds.GetNetworkCredential().password
    }
    
    # Validate credentials by executing an API call
    $headers = @{"Content-Type" = "application/json"}
    $headers.Add("Accept", "application/json; charset=utf-8")
    $uri = "https://$fqdn/SAAS/API/1.0/REST/auth/system/login"
    $body = '{"username": "' + $username + '", "password": "' + $password + '", "issueToken": "true"}'
    
    Try {
        # Checking against the API
        # PS Core has -SkipCertificateCheck implemented, PowerShell 5.x does not
        if ($PSEdition -eq 'Core') {
            $response = Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body -SkipCertificateCheck
            $Global:accessToken = "HZN " + $response.sessionToken
        }
        else {
            $response = Invoke-RestMethod $uri -Method 'POST' -Headers $headers -Body $body
            $Global:accessToken = "HZN " + $response.sessionToken
        }
        if ($response.sessionToken) {
            Write-Output "Successfully Requested New Session Token From Workspace ONE Access instance: $fqdn"
        }
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Request-WSAToken

#########  End Authentication Functions  ##########

Function Get-WSAHealth {
    <#
		.SYNOPSIS
    	Get health details

    	.DESCRIPTION
    	The Get-WSAHealth cmdlet retrieves health details from the Workspace ONE Access instance

    	.EXAMPLE
    	PS C:\> Get-WSAHealth
        This example shows how to reetrieve the health details of a Workspace ONE Access instance
  	#>

    Try {
        $headers = @{"Authorization" = "$accessToken"}
        $uri = "https://$fqdn/SAAS/API/1.0/REST/system/health"
        Invoke-RestMethod $uri -Method 'GET' -Headers $headers
    }
    Catch {
        Write-Error $_.Exception.Message
    }
}
Export-ModuleMember -Function Get-WSAHealth

Function Get-WSALoggedInUser {
    <#
		.SYNOPSIS
    	Provides information about the logged-in user

    	.DESCRIPTION
    	The Get-WSALoggedInUser cmdlet retrieves details about the logged in user

    	.EXAMPLE
    	PS C:\> WSALoggedInUser
        This example shows how to reetrieve details for the logged in user
  	#>
    Try {
        $headers = @{"Authorization" = "$accessToken"}
        $uri = "https://$fqdn/SAAS/jersey/manager/api/scim/Me"
        Invoke-RestMethod $uri -Method 'GET' -Headers $headers
    }
    Catch {
        Write-Error $_.Exception.Message 
    }
}
Export-ModuleMember -Function Get-WSALoggedInUser