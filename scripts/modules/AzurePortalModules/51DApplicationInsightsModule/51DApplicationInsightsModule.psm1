<#
  ==================== ApplicationInsights =====================
  .Description
  This module contains a function to add application insights extension to an 
  Azure App Service
#>

function Add-ApplicationInsightsExt {

    param(
        # The web app instance retreived using Get-AzWebApp
        [Parameter(Mandatory=$true)]
        [Object]$Webapp,

        # The name of the application insights resouce
        [Parameter(Mandatory=$true)]
        [string]$AppInsightsName,

        # The name of the application insights resource group
        [Parameter(Mandatory=$true)]
        [string]$AppInsightsResourceGroup
    )

    # Create the site extension needed for Application Insights.
    $resourceNameString = $Webapp.Name + "/Microsoft.ApplicationInsights.AzureWebSites"
    New-AzResource `
        -ResourceType "Microsoft.Web/sites/siteextensions" `
        -ResourceGroupName $Webapp.ResourceGroup `
        -Name $resourceNameString `
        -ApiVersion "2018-02-01" `
        -Force `
        -ErrorAction Stop

    # Get instrumentation key from ENV application insights resource.
    $appInsightsInstrumentationKey = (Get-AzApplicationInsights `
        -Name $AppInsightsName `
        -ResourceGroupName $AppInsightsResourceGroup).InstrumentationKey

    # Set the appseting to send telemetry to common applicaiton insights.
    $webAppSettings = $Webapp.SiteConfig.AppSettings
    $hash = @{ }
    Write-Host "Clearing hash table"
    foreach ($setting in $webAppSettings) {
        $hash[$setting.Name] = $setting.Value
    }

    # Its important to include the syntax around the variable eg. "$($var)"" if not 
    # supplied like this it will change the hash table's object type.
    $hash['APPINSIGHTS_INSTRUMENTATIONKEY'] = "$($appInsightsInstrumentationKey)" 

    # Write back app settings into web app.
    Write-Host "Writing back updated appsettings to app service" $Webapp.Name
    Set-AzWebApp `
        -ResourceGroupName $Webapp.ResourceGroup `
        -Name $Webapp.Name `
        -AppSettings $hash `
        -verbose

    # Restart the web app to link to application insights.
    Restart-AzWebApp `
        -ResourceGroupName $Webapp.ResourceGroup `
        -Name $Webapp.Name
}

# Create a new Application Insights API Key.
function New-ApplicationInsightsAPIKey {

    param (
        [Parameter(Mandatory=$true)]
        [string]$ResourceGroup,

        [Parameter(Mandatory=$true)]
        [string]$AppInsightsName,

        [Parameter(Mandatory=$true)]
        [string]$Description

    )
    
    # Get the Application Insights resource.
    $appInsights = Get-AzApplicationInsights `
        -ResourceGroupName $ResourceGroup `
        -Name $AppInsightsName `
        -ErrorAction SilentlyContinue

    $apiKey = ""

    if(-not $appInsights) {
        Write-Host "No App Insights found, cannot create an API Key."
    } else {
        # Create a app insights API key.
        $permissions = @("AuthenticateSDKControlChannel")
        $apiKey = New-AzApplicationInsightsApiKey `
            -ApplicationInsightsComponent $appInsights `
            -Description "$($Description) - $(Get-Date)" `
            -Permissions $permissions
    }

    return $apiKey
}

Export-ModuleMember -Function Add-ApplicationInsightsExt
Export-ModuleMember -Function New-ApplicationInsightsAPIKey
Export-ModuleMember -Function New-ApplicationInsightsResource