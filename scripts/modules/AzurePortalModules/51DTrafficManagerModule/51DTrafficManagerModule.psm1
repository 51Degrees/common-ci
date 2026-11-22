<#
  ==================== TrafficManager =====================
  .Description
  This module contains functions for managing the Azure Traffic Manager profiles
#>

# function to add or udpate a traffic manager endpoint with a type of 
# AzureEndpoint
function Update-TrafficManagerAzureEndpoint {
    
    param(
        [Parameter(Mandatory=$true)]
        [Object]$webapp,

        [Parameter(Mandatory=$true)]
        [string]$trafficManagerProfile,

        [Parameter(Mandatory=$true)]
        [string]$trafficManagerResourceGroup
    )

    $EndpointType = "AzureEndpoints"

    # Get exisiting traffic manager endpoint.
    $trafficManagerEndpoint = $null
    try {
        $trafficManagerEndpoint = Get-AzTrafficManagerEndpoint `
            -Name $webapp.Name `
            -ProfileName $trafficManagerProfile `
            -ResourceGroupName $trafficManagerResourceGroup `
            -Type $EndpointType `
            -ErrorAction SilentlyContinue
    } catch {}

    # Check if traffic manager endpoint already exists.
    if ($trafficManagerEndpoint) {
        # If traffic manager endpoint exists then update the existing endpoint
        # target, leave other settings the same.
        Write-Host "Updating endpoint in traffic manager"
        $trafficManagerEndpoint.TargetResourceId = $webapp.Id

        Set-AzTrafficManagerEndpoint -TrafficManagerEndpoint $trafficManagerEndpoint
    } else {
        # If traffic manager endpoint does not exist then add App Service to 
        # traffic manager (as a disabled endpoint).
        Write-Host ("Adding endpoint to traffic manager, endpoint will be added as " + 
            "disabled. The endpoint should only be enabled when the cloud "+
            "application has been tested on the new App Service")

        New-AzTrafficManagerEndpoint `
            -Name $webapp.Name `
            -ProfileName $trafficManagerProfile `
            -ResourceGroupName $trafficManagerResourceGroup `
            -Type $EndpointType `
            -TargetResourceId $webapp.Id `
            -EndpointStatus Disabled
    }
}