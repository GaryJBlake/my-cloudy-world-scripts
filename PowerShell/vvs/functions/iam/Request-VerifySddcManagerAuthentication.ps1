<#
    .SYNOPSIS
    Operational verification of authentication to SDDC Manager

    .DESCRIPTION
    The Request-VerifySddcManagerAuthentication cmdlet verifies authentication with SDDC Manager. The cmdlet connects
    to SDDC Manager using the -server, -user, and -password values:
    - Validates that network connectivity is available to the SDDC Manager instance
    - Validates authentication to the SDDC Manager instance

    .EXAMPLE
    Request-VerifySddcManagerAuthentication -server ldn-vcf01.ldn.cloudy.io -user admin@local -pass VMw@re1!VMw@re1! -domainUser cloud-admin@ldn -domainPass VMw@re1!
    This example performs operational verification of authentication to SDDC Manager
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainUser,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$domainPass
)

Try {
    $allClustersObject = New-Object System.Collections.ArrayList
    if (Test-VCFConnection -server $server) {
        # Verify Authentication in SDDC Manager by Using a Local System Account
        $authStatus = Test-VCFAuthentication -server $server -user $user -pass $pass -ErrorAction Ignore -ErrorVariable ErrMsg
        if ($authStatus -eq $True) { $alert = "GREEN"} else { $alert = "RED"}
        $message = "Verify authentication to $server using a local system account $user"
        $customObject = New-Object -TypeName psobject
        $customObject | Add-Member -NotePropertyName 'Component' -NotePropertyValue "SDDC Manager"
        $customObject | Add-Member -NotePropertyName 'System FQDN' -NotePropertyValue $server
        $customObject | Add-Member -NotePropertyName 'Alert' -NotePropertyValue $alert
        $customObject | Add-Member -NotePropertyName 'Message' -NotePropertyValue $message        
        $allClustersObject += $customObject

        # Verify Authentication to SDDC Manager by Using an Active Directory User Account
        $authStatus = Test-VCFAuthentication -server $server -user $domainUser -pass $domainPass -ErrorAction Ignore -ErrorVariable ErrMsg
        if ($authStatus -eq $True) { $alert = "GREEN"} else { $alert = "RED"}
        $message = "Verify authentication to $server using a Active Directory account $domainUser"
        $customObject = New-Object -TypeName psobject
        $customObject | Add-Member -NotePropertyName 'Component' -NotePropertyValue "SDDC Manager"
        $customObject | Add-Member -NotePropertyName 'System FQDN' -NotePropertyValue $server
        $customObject | Add-Member -NotePropertyName 'Alert' -NotePropertyValue $alert
        $customObject | Add-Member -NotePropertyName 'Message' -NotePropertyValue $message
        $allClustersObject += $customObject
    } else {
        $alert = "RED"
        $message = "Unable to communicate with $server"
        $customObject = New-Object -TypeName psobject
        $customObject | Add-Member -NotePropertyName 'Component' -NotePropertyValue "SDDC Manager"
        $customObject | Add-Member -NotePropertyName 'System FQDN' -NotePropertyValue $server
        $customObject | Add-Member -NotePropertyName 'Alert' -NotePropertyValue $alert
        $customObject | Add-Member -NotePropertyName 'Message' -NotePropertyValue $message
        $allClustersObject += $customObject
    }
    $allClustersObject
} Catch {
    Debug-CatchWriter -object $_
}