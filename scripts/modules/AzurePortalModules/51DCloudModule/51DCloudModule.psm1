<#
  ==================== Cloud =====================
  .Description
  This module contains functions specific to the cloud environment configuration
#>

# Create a new blocklist json file and add it to the provided storage account
function Add-BlocklistFile {

    param (
        [Parameter(Mandatory=$true)]
        [Object]$storageAccount, # storage account object

        [string]$shareName = "cloudconfig", # file share name
        [string]$fileName = "blocklist.json" # blocklist filename
    )

    # Storage context
    $ctx = $storageAccount.Context

    $storageFiles = Get-AzStorageFile `
        -ShareName $shareName `
        -Context $ctx

    $storageFile = $storageFiles | Where-Object {$_.Name -eq $fileName }

    # If the blocklist file does not exist then create a new one.
    if(-not $storageFile) {
        Write-Host "Adding blocklist file..."

        # Create the blocklist json object
        $blocklist = @{
            DataPublishedDateTime = (Get-Date).ToString("yyyy-MM-dd")
            UpdateAvailableTime = (Get-Date).ToString("yyyy-MM-dd")
            BlacklistedKeys = @()
            BlacklistedReferers = @()
            BlacklistedIPs = @()
            BlacklistedLicenseIds = @()
            BlacklistedResourceKeys = @()
        }

        # Convert the object to JSON.
        $content = $blocklist | ConvertTo-Json -depth 32

        # Create a file with the JSON content on disk.
        $Null = New-Item . -Name $fileName -ItemType "file" -Value $content -Force

        # Try to get the file share
        $share = $null
        try {
            $share = Get-AzStorageShare `
                -Name $shareName `
                -Context $ctx `
                -ErrorAction SilentlyContinue
        } catch {}

        # Create the file share if it does not exist.
        if(-not($share)) {
            $share = New-AzStorageShare `
                -Name $shareName `
                -Context $ctx
        }
    
        # Add the file to the file share.
        $Null = Set-AzStorageFileContent `
            -ShareName $shareName `
            -Source $fileName `
            -Context $ctx

        # Cleanup the file on disk.
        $Null = Remove-Item $fileName
    }

    # Create the shared access signature URI for accessing the file.
    $StartTime = Get-Date
    $EndTime = $StartTime.AddYears(50)

    $token = New-AzStorageFileSASToken `
        -ShareName $shareName `
        -Path $fileName `
        -Permission "r" `
        -StartTime $StartTime `
        -ExpiryTime $EndTime `
        -Context $ctx

    $sas = "$($ctx.FileEndPoint)$($shareName)/$($fileName)$($token)"

    return $sas
}

# Add a Resource key to the entitlement table of a storage account.
function Add-ResourceKey {
    param (
        [Parameter(Mandatory=$true)]
        [Object]$storageAccount
    )

    Write-Host "Setting up test resource key..."

    # Make sure the AzTable module is installed
    if (-not (Get-Module -ListAvailable -Name AzTable)) {
        Write-Host "Az Table module does not exist, installing..."
        Install-Module AzTable
    }
    
    # Construct the resource key table row
    $resource = @{
        partitionKey = "AQS5HKcyxmoxU0-q10g"
        rowKey = "2020-02-05T15:23:17.1100358Z"
        properties = @{
            "AgreedToTerms"=$TRUE
            "Domains"=""
            "Email"="engineering@51degrees.com"
            "ProductKeys"="FBVAAAELPALWBBNCEJAGALSAB2ASUP34ZHMR3475Y9SL92L2P7A5X6HUB8JYQFBC7GDNY9AYFYFS5VTYXTB8BNRCA5KXE"
            "Properties"=""
            "ReceiveMarketingEmails"=$FALSE
        }
    }

    # Storage Account context
    $ctx = $storageAccount.Context

    # The name of the storage table
    $name = "entitlement"

    # Try to get the storage table.
    $t = $null
    try {
        $t = Get-AzStorageTable `
            -Name $name `
            -Context $ctx `
            -ErrorAction SilentlyContinue
    } catch { }

    # If the storage table sodes not exist then create it.
    if (-not ($t)) {
        $t = New-AzStorageTable -Name $name -Context $ctx
    }
        
    # Try to get the exisiting Resource Key.
    $table = $t.CloudTable
    $row = Get-AzTableRow -table $table -partitionKey $resource.partitionKey | Format-Table

    # If it does not exist then create the Resource Key Row in the table.
    if(-not ($row)) {
        Add-AzTableRow `
            -table $table `
            -partitionKey $resource.partitionKey `
            -rowKey $resource.rowKey `
            -property $resource.properties
    }

    # Log the key to console.
    Write-Host "Resource key for testing: $($resource.partitionKey)"
}