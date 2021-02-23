Function basicFunction {
    # Basic function to illustrate structure
    Try {
        $vcenterFqdn = "sfo-m01-vc01.sfo.rainpole.io"
        $vcenterUsername = "administrator@vsphere.local"
        $vcenterPassword = "VMw@re1!"

        Connect-VIServer -Server $vcenterFqdn -User $vcenterUsername -Pass $vcenterPassword

        Write-Output "Connected to vCenter $vcenterFqdn"
    }
    Catch {
        Write-Error "And Error Occured"
    }
}

# Execution Section

# Call Function
basicFunction