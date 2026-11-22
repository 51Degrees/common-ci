<#
  ==================== Staging Slots =====================
  .Description
  This module contains a function to refresh or add the staging slot on an 
  Azure App Service.
#>


function Add-WebAppStagingSlot {

    param(
        [Parameter(Mandatory=$true)]
        [Object]$Webapp,

        [Hashtable]$AppSettings
    )

    Write-Host "Adding Staging slot..."

    # Remove the staging slot ready to rebuild it.
    $null = Remove-AzWebAppSlot `
      -ResourceGroupName $webapp.ResourceGroup `
      -Name $webapp.Name `
      -Slot "Staging" `
      -Force

    # Adds a new staging slot with fresh configuration.
    $null = New-AzWebAppSlot `
      -ResourceGroupName $webapp.ResourceGroup `
      -Name $webapp.Name `
      -Slot "Staging"

    if ($null -eq $AppSettings){
      $AppSettings = $webapp.SiteConfig.AppSettings
    }

    # Config the fresh staging slot. Belt and braces incase the CD script doesn't
    # set the correct parameters.
    $null = Set-AzWebAppSlot `
      -ResourceGroupName $webapp.ResourceGroup `
      -Name $webapp.Name `
      -Slot "Staging" `
      -AppSettings $AppSettings `
      -WebSocketsEnabled $false `
      -Use32BitWorkerProcess $false `
      -AlwaysOn $true `
      -FtpsState "Disabled"
}

Export-ModuleMember -Function Add-WebAppStagingSlot