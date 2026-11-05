<#
.SYNOPSIS
    Extracts the existing vApp option value for 'api_key' from a VMware vSphere Virtual Machine.

.DESCRIPTION
    This script/function inspects the vApp property configuration (VirtualMachine.Config.VAppConfig.Property)
    of a VMware vSphere Virtual Machine object or VM name. It searches for the 'api_key' vApp option
    that has already been set on the VM and outputs its value.

.PARAMETER VM
    The Virtual Machine to query. Accepts a PowerCLI VirtualMachine object (e.g. from Get-VM),
    a vSphere API VirtualMachine object, or a string representing the VM name. Supports Pipeline input.

.EXAMPLE
    Get-VmApiKey -VM "vcf-appliance-01"

.EXAMPLE
    Get-VM -Name "VCFA-01" | Get-VmApiKey

.EXAMPLE
    $apiKey = Get-VmApiKey -VM $vmObject
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
    [psobject]$VM
)

function Get-VmApiKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
        [psobject]$VM
    )

    process {
        # 1. Resolve VM object if a string VM name was provided
        $vmObject = $null
        if ($VM -is [string]) {
            if (-not (Get-Command -Name Get-VM -ErrorAction SilentlyContinue)) {
                throw "VMware PowerCLI module (VMware.VimAutomation.Core) is required when passing VM by name string."
            }
            Write-Verbose "Fetching VM object for name '$VM'..."
            $vmObject = Get-VM -Name $VM -ErrorAction Stop
        } else {
            $vmObject = $VM
        }

        if (-not $vmObject) {
            throw "Invalid or null VM input provided."
        }

        # Determine VM name for log/warning outputs
        $vmName = if ($vmObject.Name) { $vmObject.Name } else { $vmObject.ToString() }

        # 2. Access VAppConfig from PowerCLI VirtualMachine object or vSphere API MoRef object
        $vAppConfig = $null
        if ($vmObject.PSObject.Properties['ExtensionData'] -and $vmObject.ExtensionData.Config) {
            $vAppConfig = $vmObject.ExtensionData.Config.VAppConfig
        } elseif ($vmObject.PSObject.Properties['Config']) {
            $vAppConfig = $vmObject.Config.VAppConfig
        }

        if (-not $vAppConfig -or -not $vAppConfig.Property) {
            Write-Warning "No vApp options/properties are configured on VM '$vmName'."
            return $null
        }

        # 3. Locate the 'api_key' vApp property
        $targetKey = "api_key"
        $property = $vAppConfig.Property | Where-Object {
            $_.Id -ieq $targetKey -or 
            $_.Id -ieq "guestinfo.$targetKey" -or
            $_.Label -ieq $targetKey
        } | Select-Object -First 1

        # Fallback substring search if key formatted with prefix/suffix (e.g. guestinfo.api_key)
        if (-not $property) {
            $property = $vAppConfig.Property | Where-Object {
                $_.Id -ilike "*$targetKey*"
            } | Select-Object -First 1
        }

        if (-not $property) {
            Write-Warning "vApp option 'api_key' was not found on VM '$vmName'."
            return $null
        }

        # 4. Extract and return the configured value (or DefaultValue if value field is empty)
        $value = $property.Value
        if ([string]::IsNullOrEmpty($value)) {
            $value = $property.DefaultValue
        }

        return $value
    }
}

# If executed directly as a script (not dot-sourced), invoke the function
if ($MyInvocation.InvocationName -ne '.') {
    Get-VmApiKey -VM $VM
}
