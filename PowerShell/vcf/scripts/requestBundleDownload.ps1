<#	SCRIPT DETAILS

    .NOTES
    ===============================================================================================================
    .Created By:    Gary Blake
    .Organization:  my-cloudy-world.com
    .Version:       1.0.0
    .Date:          2022-06-09
    ===============================================================================================================

    .CHANGE_LOG

    - 1.0.0   (Gary Blake / 2022-06-09) - Initial script creation

    ===============================================================================================================
    .DESCRIPTION

    This script automates the process of requesting the download of bundles to SDDC Manager based on the JSON file
    provided.

    .EXAMPLE
    .\requestBundleDownload.ps1 -json .\requestBundleDownloadList.json
#>

Param (
    [Parameter (Mandatory = $true)] [ValidateNotNullOrEmpty()] [String]$json
)

Try {
    if (!(Test-Path $json)) { # Reads the requestBundleDownloadList json file contents into the $bundleList variable
        Throw " Unable to locate JSON file"
        Exit
    } else {
        $bundleList = Get-Content $json | ConvertFrom-Json 
    }
} Catch {
    Write-Error $_.Exception.Message
}

Clear-Host
Write-Output "", " Starting the Process of Downloading all Bundles Based on the JSON Provided"
Foreach ($bundle in $bundleList.bundles) { # Download the Bundle and monitor the task until its completed
    Write-Output " Checking the Download Status of Bundle: $($bundle.product)"
    if ((Get-VCFBundle -id $bundle.bundleId).downloadStatus -ne 'SUCCESSFUL') {
        Write-Output " Attempting to Download Bundle: $($bundle.product)"
        $requestBundle = Request-VCFBundle -id $bundle.bundleId
        Start-Sleep 5
        do { $taskStatus = Get-VCFTask -id $($requestBundle.id) | Select-Object status; Start-Sleep 5 } until ($taskStatus -match "Successful")
    } else {
        Write-Warning " Bundle Already Downloaded: $($bundle.product)"
    }
}