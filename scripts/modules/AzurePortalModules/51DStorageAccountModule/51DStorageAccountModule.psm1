<#
  ==================== Stroage Accounts =====================
  .Description
  This module contains a function to create storage accounts.
  References:
    https://docs.microsoft.com/en-us/azure/cosmos-db/scripts/powershell/table/create
    https://docs.microsoft.com/en-us/powershell/module/az.cosmosdb/new-azcosmosdbaccount
#>

# Create a new Storage Account
function New-StorageAcc {
  param (
    [Parameter(Mandatory = $true)]
    [string]$storageAccName,

    [Parameter(Mandatory = $true)]
    [string]$resourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$region,

    [Hashtable]$tags = @{}
  )
  Write-Host ""

  while ($storageAccName.length -lt 3) {
    $choice = Read-Host -Prompt ("Storage account name '$($storageAccName)' " + 
      "is too short, enter a new name here")
    if (-not [string]::IsNullOrWhiteSpace($choice)) {
      $storageAccName = $choice.Replace("-", "").ToLower()
    }
  }

  while ($storageAccName.length -gt 24) {
    $truncated = $storageAccName.Substring(0, 24)
    $choice = Read-Host -Prompt ("Storage account name '$($storageAccName)' " + 
      "is too long, use trunctated name or enter a new name here [$($truncated)]")
    if ([string]::IsNullOrWhiteSpace($choice)) {
      $storageAccName = truncated
    }
    else {
      $storageAccName = $choice.Replace("-", "").ToLower()
    }
  }

  $sb = $null
  
  while (-not $sb) {
    # Check if storage account exists
    $sb = Get-AzStorageAccount `
      -ResourceGroupName $resourceGroupName `
      -Name $storageAccName `
      -ErrorAction SilentlyContinue

    if(-not $sb) {
      # create sotrage account
      Write-Host "Creating storage account:" $storageAccName

      $sb = New-AzStorageAccount `
        -ResourceGroupName $resourceGroupName `
        -Name $storageAccName `
        -Location $region `
        -Tag $tags `
        -SkuName Standard_RAGRS `
        -Kind StorageV2

      if(-not $sb) {
        # If there is still no storage account then the 
        # 'New-AzStorageAccount' command has failed. Retreive the last
        # Azure Error.
        $lastError = Resolve-AzError -Last -WarningAction silentlyContinue

        # Check that the last error is from the expected source, if not
        # we can't handle it. Prompt the user to check the Errors 
        # manually.
        if ($lastError.Exception.Source -ne "Microsoft.Azure.PowerShell.Cmdlets.Storage.Management") {
          Write-Host ("Could not resolve error creating storage " +
            "account. Use the PowerShell Cmdlet 'Resolve-AzError -Last' to " + 
            "inspect the last Azure error in this session.")
          exit 1
        }

        # If the stroage account name has already been taken then
        # prompt the user for a new account name.
        if ($lastError.Message.Contains("The storage account named " +
          "$($storageAccName) is already taken. (Parameter 'Name')")) {
          $storageAccName = Read-Host -Prompt ("Storage account name " +
            "'$($storageAccName)' already taken in a different Azure " + 
            "subscription, enter a new name here")
        } elseif ($lastError.Message.Contains("$($storageAccName) is not a " +
          "valid storage account name.")) {
          $storageAccName = Read-Host -Prompt ("'$($storageAccName)' is not a " +
            "valid storage account name, enter a new name here")
          # If the Azure error is not the expected error then abort
          # the process and ask the user to review the Azure errors 
          # manually.
        } else {
          Write-Host "Error message: $($lastError.Message)"
          Write-Host ("Could not resolve error creating storage " +
            "account. Use the PowerShell Cmdlet 'Resolve-AzError -Last' to " + 
            "inspect the last Azure error in this session.")
          exit 1
        }
      }
    } else {
      Write-Host -ForegroundColor Magenta ("Storage account '$($storageAccName)' " +
        "already exists, using exsiting account")  
    }
  }

  return $sb
}

# Function to create a new Cosmos DB account. First check if one with the same
# account name exists already, if not the create a new one, otherwise prompt the
# user for a new name.
function New-CosmosAccount {
    
  param ( 
    # The name of the Cosmos DB Account
    [Parameter(Mandatory = $true)]
    [string]$accountName,

    # The name of the resource group where the Cosmos DB account is created
    # or located
    [Parameter(Mandatory = $true)]
    [string]$resourceGroupName,

    # Tags to create the Cosmos DB account with.
    [hashtable]$tags = @{},

    # The kind of CosmosDB API to use.
    [string]$apiKind = "Table",
    [string]$consistencyLevel = "BoundedStaleness",
    [int]$maxStalenessIntervalInSeconds = 86400,
    [int]$maxStalenessPrefix = 1000000,
    [Array]$locations = @(
      (New-AzCosmosDBLocationObject -LocationName "West Europe" -FailoverPriority 0 -IsZoneRedundant 0),
      (New-AzCosmosDBLocationObject -LocationName "Central US" -FailoverPriority 1 -IsZoneRedundant 0)
      # TODO consider adding central india as a cosmos db region.
      #(New-AzCosmosDBLocationObject -LocationName "Central India" -FailoverPriority 1 -IsZoneRedundant 0)
    )
  )

  $cosmosDBAccount = $null 

  while (-not $cosmosDBAccount) {
    # Get an existing Cosmos DB account.
    $cosmosDBAccount = Get-AzCosmosDBAccount `
      -ResourceGroupName $resourceGroupName `
      -Name $accountName `
      -ErrorAction SilentlyContinue

    if (-not $cosmosDBAccount) {
      # If there is no Cosmos DB account then try to create one.
      Write-Host "Creating Cosmos DB account '$($accountName)'"
      $cosmosDBAccount = New-AzCosmosDBAccount `
        -ResourceGroupName $resourceGroupName `
        -Name $accountName `
        -LocationObject $locations `
        -ApiKind $apiKind `
        -DefaultConsistencyLevel $consistencyLevel `
        -MaxStalenessIntervalInSeconds $maxStalenessIntervalInSeconds `
        -MaxStalenessPrefix $maxStalenessPrefix `
        -Tag $tags

      if (-not $cosmosDBAccount) {
        # If there is still no Cosmos DB account then the 
        # 'New-AzCosmosDBAccount' command has failed. Retreive the last
        # Az Error.
        $lastError = Resolve-AzError -Last -WarningAction silentlyContinue

        # Check that the last error is from the expected source, if not
        # we can't handle it. Prompt the user to check the Errors 
        # manually.
        if ($lastError.Exception.Source -ne "Microsoft.Azure.Management.CosmosDB") {
          Write-Host ("Could not resolve error creating cosmos DB " +
            "account. Use the PowerShell Cmdlet 'Resolve-AzError -Last' to " + 
            "inspect the last Azure error in this session.")
          exit 1
        }

        # The Cosmos DB DNS record is determined by the account name. 
        # If the error is caused by the DNS record being taken then
        # prompt the user for a new account name.
        if ($lastError.Message.Contains("Dns record for " +
            "$($accountName) under zone Document is already " +
            "taken. Please use a different name for the account")) {
          $suggestion = $accountName + "-1"
          $choice = Read-Host -Prompt ("Cosmos DB account name " +
            "'$($accountName)' already taken in a different Azure " +
            "Subscription, use suggestion or enter a new name here [$($suggestion)]")

          if ([string]::IsNullOrWhiteSpace($choice)) {
            $accountName = $suggestion
          }
          else {
            $accountName = $choice
          }
          # If the Cosmos DB error is not the expected error then abort
          # the process and ask the user to review the Azure errors 
          # manually.
        }
        else {
          Write-Host "Error message: $($lastError.Message)"
          Write-Host ("Could not resolve error creating cosmos DB " +
            "account. Use the PowerShell Cmdlet 'Resolve-AzError -Last' to " + 
            "inspect the last Azure error in this session.")
          exit 1
        }
      }   
    } else {
      Write-Host -ForegroundColor Magenta ("Cosmos DB account '$($accountName)' " +
        "exists, using existing account.")
    }
  }

  return $cosmosDBAccount
}

function New-CosmosDbTable {

  param (
    [Parameter(Mandatory=$true)]
    [object]$cosmosAccount,

    [Parameter(Mandatory=$true)]
    [string]$tableName,

    [Parameter(Mandatory=$true)]
    [int]$tableRUs
  )

  $table = Get-AzCosmosDBTable `
    -Name $tableName `
    -ParentObject $cosmosAccount `
    -ErrorAction SilentlyContinue

  if(-not $table) {
    Write-Host "Creating Cosmos DB table: $($tableName)"
    New-AzCosmosDBTable `
      -ParentObject $cosmosAccount `
      -Name $tableName `
      -Throughput $tableRUs
  } else {
    Write-Host "Cosmos DB table '$($tableName)' already exists."
  }
}