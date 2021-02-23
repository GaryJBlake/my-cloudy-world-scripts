Function basicFunction {
    # Basic function to illustrate structure
    Try {

        # Hardcoded values
        $vcenterFqdn = "sfo-m01-vc01.sfo.rainpole.io"
        $vcenterUsername = "administrator@vsphere.local"
        $vcenterPassword = "VMw@re1!"

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

# Call Function
basicFunction