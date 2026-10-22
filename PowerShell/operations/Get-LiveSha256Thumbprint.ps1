function Get-LiveSha256Thumbprint {
    param([string]$NodeAddress)

    try {
        $tcp = New-Object System.Net.Sockets.TcpClient($NodeAddress, 443)
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, { $true })
        $ssl.AuthenticateAsClient($NodeAddress)
        
        # Get raw cert and compute SHA-256 hash
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
        $sha256 = [System.Security.Cryptography.HashAlgorithm]::Create("SHA256")
        $hashBytes = $sha256.ComputeHash($cert.RawData)
        
        # Format as uppercase colon-separated string (e.g., AA:BB:CC:...)
        $thumbprint = ($hashBytes | ForEach-Object { $_.ToString("X2") }) -join ":"
        
        $ssl.Close()
        $tcp.Close()
        
        return $thumbprint
    }
    catch {
        throw "Failed to fetch SSL certificate from ${NodeAddress}: $_"
    }
}