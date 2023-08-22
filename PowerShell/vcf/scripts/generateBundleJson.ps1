<#	SCRIPT DETAILS

    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Organization:  my-cloudy-world.com
    .Version:       1.0.0
    .Date:          2023-22-08
    ===============================================================================================================

    .CHANGE_LOG

    - 1.0.0   (Gary Blake / 2023-22-08) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of geerating the JSON for downloading the bundles to SDDC Manager based on a
    version.

    .EXAMPLE
    generateBundleJson.ps1 -server lax-vcf01.lax.rainpole.io -user administrator@vsphere.local -pass VMw@re1! -release 4.5.1.0 -outJson vcf4510Bundles.json
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$server,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$user,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$pass,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$release,
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$outJson
)

Try {
    Clear-Host
    Request-VCFToken -fqdn $server -username $user -password $pass | Out-Null
    Write-Output "", " Starting the Process of Generating the Bundle Download JSON for VMware Cloud Foundation v$release"
    $releases = Get-VCFRelease | Where-Object {$_.version -eq $release}
    $bundles = @()
    foreach ($bom in $releases.bom) {
        $bundles += Get-VCFBundle | Where-Object {$_.components.description -match "Update" -and $_.components.toVersion -eq $bom.version}
    }

    $bundleList = @()
    foreach ($bundle in $bundles) {
        $bundleId = New-Object -TypeName psobject
        $bundleId | Add-Member -notepropertyname 'bundleId' -notepropertyvalue $bundle.id
        $bundleId | Add-Member -notepropertyname 'product' -notepropertyvalue $bundle.components.type
        $bundleList += $bundleId
    }
    $json = New-Object -TypeName psobject
    $json | Add-Member -notepropertyname 'bundles' -notepropertyvalue $bundleList
    $json | ConvertTo-Json | Out-File $outJson
    Write-Output " Generated JSON ($outJson) for VMware Cloud Foundation v$release", ""
} Catch {
    Write-Error $_.Exception.Message
}