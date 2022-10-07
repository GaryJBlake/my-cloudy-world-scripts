if ($_.Exception.Message -match "400") {
    Write-Error "400 (Bad Request: ($_.Exception.ErrorLabel)"
} elseif ($_.Exception.Message -match "401") {
    Write-Error "401 (Unauthorized: Not Connected to vRealize Suite Lifecycle Manager Appliance: $vrslcmAppliance)"
} elseif ($_.Exception.Message -match "403") {
    Write-Error "403 (Forbidden on vRealize Suite Lifecycle Manager Appliance: $vrslcmAppliance)"
} elseif ($_.Exception.Message -match "404") {
    Write-Error "404 (Resouce Not Found on vRealize Suite Lifecycle Manager Appliance: $vrslcmAppliance)"
} elseif ($_.Exception.Message -match "409") {
    Write-Error "409 (Conflict: $_.Exception.ErrorLabel"
} elseif ($_.Exception.Message -match "500") {
    Write-Error "500 (Internal Server Error: $_.Exception.ErrorLabel"
} else {
    Write-Error $_.Exception.Message
}