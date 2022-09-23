Function basicFunctionWithParameters {
    # Basic function to illustrate using parameters as inputs rather than hardcoded values
    Param (
        [Parameter(Mandatory = $true)][String]$vcenterFqdn,
        [Parameter(Mandatory = $true)][String]$vcenterUsername,
        [Parameter(Mandatory = $true)][String]$vcenterPassword
    )
    Try {
        # Simple connection to vCenter Server
        Connect-VIServer -Server $vcenterFqdn -User $vcenterUsername -Pass $vcenterPassword

        # Control some screen output, should not use Write-Host but Write-Output if really required this can then be passed on
        Write-Output "Connected to vCenter $vcenterFqdn"
    }
    Catch {
        # Write-Error will display a RED error message to the console when an error occurs
        Write-Error "And Error Occured"
    }
}

# Execution Section

# Call Function and pass in values
basicFunctionWithParameters -vcenterFqdn sfo-m01-vc01.sfo.rainpole.io -vcenterUsername administrator@vsphere.local -vcenterPassword VMw@re1!