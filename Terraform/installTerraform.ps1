Function installTerraform
{
    Write-Host "Checking Chocolatey Installation"
    Try {
        if (Test-Path -path "C:\ProgramData\Chocolatey") {
            $env:PATH = $env:Path + ";C:\ProgramData\Chocolatey"
        } 
        $isChocoPresent = Invoke-Expression "choco list --localonly" -erroraction silentlyContinue
    } Catch {
        Write-Host "Installing Chocolatey"
		Set-ExecutionPolicy Bypass -Scope Process -Force | Out-Null
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1')) *>$null
		Invoke-Expression "choco feature enable -n allowGlobalConfirmation" | Out-Null
    }
	# Check for	terraform
	Write-Host "Checking Terraform Installation"
    $isTerraformPresent = Invoke-Expression "choco list --localonly terraform"
	if ($isTerraformPresent[-1] -notlike "1 packages installed.") {
        Write-Host "Installing Terraform"
		Invoke-Expression "choco install terraform" | Out-Null
	}
}