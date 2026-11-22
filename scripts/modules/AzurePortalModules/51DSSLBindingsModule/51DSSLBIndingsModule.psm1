<#
  ==================== SSLBindings =====================
  .Description
  This module contains a function to refresh the custom domains assigned to an
  Azure app service and update the SSL bindings.

  References:
    https://github.com/uglide/azure-content/blob/master/articles/app-service-web/app-service-web-app-powershell-ssl-binding.md
    https://docs.microsoft.com/en-us/powershell/module/Az.websites/remove-Azwebappsslbinding?view=Azps-6.13.0
#>

# Update hosts and SSL bindings for a web app.
function Set-SSLBindings {

    param(
        [Parameter(Mandatory=$true)]
        [Hashtable[]]$Certs,

        [Parameter(Mandatory=$true)]
        [Hashtable[]]$Hosts,

        [Parameter(Mandatory=$true)]
        [Object]$Webapp
    )

    # Remove all the exising SSL bindings.
    foreach ($hostName in $Hosts.Name) {
        Remove-AzWebAppSSLBinding `
            -ResourceGroupName $Webapp.ResourceGroup `
            -WebAppName $Webapp.Name `
            -Name $hostName `
            -Force `
            -DeleteCertificate $false 
    }

    # Replace all the existing host names with the ones in this script.
    Set-AzWebApp `
        -ResourceGroupName $Webapp.ResourceGroup `
        -Name $Webapp.Name `
        -HostNames @($Hosts.Name, $Webapp.DefaultHostName) `
        -Use32BitWorkerProcess $false 

    # # Upload the new SSL certificates if they do not exist and bind them to the 
    # # host name. If the SSL certificate does exist then use the existing one.
    foreach($current in $Hosts) {

        # Use the -like directive to find wildcard certificates that have the
        # *.domain.com format.
        Write-Host "Finding certificates for $($current.Name)"
        $existing = New-Object -TypeName 'System.Collections.ArrayList'
        foreach($cert in (Get-AzWebAppCertificate `
            -ResourceGroupName $Webapp.ResourceGroup) | `
            Where-Object { `
                ($_.Location -eq $Webapp.Location) -and `
                ($_.ExpirationDate -gt (Get-Date))}) {
            foreach($hostName in $cert.HostNames) {
                if ($current.Name -like $hostName) {
                    $existing.Add($cert) | Out-Null
                    Write-Host "Found" $cert.Thumbprint
                    Break
                }
            }
        }
        
        if (($null -eq $existing) -OR ($existing.Count -eq 0)) {

            # There are no available certificates. Find the one that is contained
            # in the same folder as this script and add it to the web app.
            $cert = $Certs |
                Where-Object CertificateFile -eq $current.CertificateFile |
                Select-Object -First 1
            if ($null -ne $cert) {
                Write-Host "Adding certificate for $($current.Name)"
                New-AzWebAppSSLBinding `
                    -ResourceGroupName $Webapp.ResourceGroup `
                    -WebAppName $Webapp.Name `
                    -Name $current.Name `
                    -CertificateFilePath (Join-Path $pwd $cert.CertificateFile) `
                    -CertificatePassword $cert.Password 
            } else {
                Write-Host "No cerificate available for $($current.Name)"
            }
        } else {

            # Order the list so that the certificate that expires the furthest in the
            # future is used form the domain.
            $existing = $existing | Sort-Object ExpirationDate -Descending

            # Use the thumbprint from the certicate to set bind to the domain.
            Write-Host "Using existing certificate $($existing[0].Thumbprint) for $($current.Name)"
            New-AzWebAppSSLBinding `
                -ResourceGroupName $Webapp.ResourceGroup `
                -WebAppName $Webapp.Name `
                -Name $current.Name `
                -Thumbprint $existing[0].Thumbprint
        }
    }
}

Export-ModuleMember -Function Set-SSLBindings