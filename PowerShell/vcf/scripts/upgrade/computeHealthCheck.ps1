# Script to execute as system precheck for a Workloda Domain
# Written by Gary Blake, Senior Staff Solution Architect @ VMware


$Global:computeHealth = Get-Content -Raw .\reports\compute-health.json | ConvertFrom-Json

Foreach ($licenseCheck in $computeHealth.Compute.'ESXi License Status') {
        $Global:licenseCheck 
}