<#
  ==================== ConnectAzure =====================
  .Description
  This module contains functions to connect to an Azure Account and select an
  Azure subscription.
#>

function Connect-AzSubscription {

    $subscriptionId=''
    $ctx = $null

    # Connect to the Azure remote management API. Authentication may be required.
    Read-Host -Prompt ("You will be prompted to log in to your Microsoft work account. " +
        "Please choose an account which has access to create new Azure resources. " +
        "Press enter to continue...")
    Connect-AzAccount

    $subs = Get-AzSubscription 

    if ($subs.Length -eq 0) {
        Write-Host ("No Azure subscriptions for this account could be found." + 
            "Please confirm this account has access to azure and try again.")
        exit 1
    }

    $subs | Format-Table
    
    while ($null -eq $ctx) {
        while ('' -eq $subscriptionId) {
            $subscriptionId = Read-Host -Prompt ("Choose the azure subscription id from "+ 
            "above and paste on this line, then press enter to continue")
        }

        # Set the context to the subscription Id where the cluster will be created
        try {
            $ctx = Select-AzSubscription -SubscriptionId $subscriptionId -ErrorAction Stop
        } 
        catch {
            Write-Host "Invalid subscription selected."
        }
    }
}

Export-ModuleMember -Function Connect-AzSubscription 