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

#########  Start Authentication Functions  ##########

Function Get-ESXiAdminGroup {
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			01/04/2020
        Organization:	VMware
        ===========================================================================
        .SYNOPSIS
        Retrieves Config.HostAgent.plugins.hostsvc.esxAdminsGroup on ESXi host
        .DESCRIPTION
        Connects to specified ESXi Host and retrives the setting for Config.HostAgent.plugins.hostsvc.esxAdminsGroup
        .EXAMPLE
        Get-ESXiAdminGroup -esxiHostfqdn sfo01-m01-esx01.sfo.rainpole.io
    #>
        Param (
            [Parameter (Mandatory=$true)]
            [ValidateNotNullOrEmpty()]
            [string]$esxiHostfqdn
        )
        
        If (-Not $Global:DefaultVIServer.IsConnected) {
            Write-Error "No valid VC Connection found, please use the Connect-VIServer to connect"; break
        }
        else {
            $esxAdminsGroupSettings = (Get-AdvancedSetting -Entity $esxiHostfqdn -Name Config.HostAgent.plugins.hostsvc.esxAdminsGroup).Value.toString()
            $tmp = [pscustomobject] @{
                VCENTER = $esxiHostfqdn;
                esxAdminsGroup = $esxAdminsGroupSettings;
                }
            $tmp
        }
    }
    Export-ModuleMember -Function Get-ESXiAdminGroup
    
    Function Set-ESXiAdminGroup {
    <#
        .NOTES
        ===========================================================================
        Created by:		Gary Blake
        Date:			01/04/2020
        Organization:	VMware
        ===========================================================================
        .SYNOPSIS
        Configure Config.HostAgent.plugins.hostsvc.esxAdminsGroup on ESXi host
        .DESCRIPTION
        Connects to specified ESXi Host and sets a new value for Config.HostAgent.plugins.hostsvc.esxAdminsGroup
        .EXAMPLE
        Set-ESXiAdminGroup -esxiHostfqdn sfo01-m01-esx01.sfo.rainpole.io -groupName ug-esxi-admins
    #>
        Param (
            [Parameter (Mandatory=$true)]
                [ValidateNotNullOrEmpty()]
                [string]$esxiHostfqdn,
            [Parameter (Mandatory=$true)]
                [ValidateNotNullOrEmpty()]
                [string]$groupName
        )
        
        If (-Not $Global:DefaultVIServer.IsConnected) {
            Write-Error "No valid VC Connection found, please use the Connect-VIServer to connect"; break
        }
        Else {
            Get-AdvancedSetting -Entity $esxiHostfqdn -Name Config.HostAgent.plugins.hostsvc.esxAdminsGroup | Set-AdvancedSetting -Value $groupName -Confirm:$false
        }
    }
    Export-ModuleMember -Function Set-ESXiAdminGroup
    