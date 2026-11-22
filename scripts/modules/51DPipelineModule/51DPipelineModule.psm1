<#
  ===================== Pipeline =====================
  .Description
  This module contains functions that perform actions
  on Azure Devops pipelines.
  For more information, please read description of
  each function.
#>

Using module 51DAuthorizationModule
Using module 51DEnvironmentModule

<#
  .Description
  Get all pipelines from a Team project.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  pipelines object as returned from AzureDevops web request or $null.
#>
function Get-Pipelines {
	param(
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	# Obtain the list of pipelines to access pipeline id later.
	$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/pipelines?api-version=6.0-preview.1"
	
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	if (!$(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to get the list of pipelines.")){
		return $null
	}
	
	# This variables is read-only
	$pipelines = $response.content | Out-String | ConvertFrom-Json
	return $pipelines
}

<#
  .Description
  Get the Id number of a pipeline.
  
  .Inputs Name
  Name of the pipeline.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  Id number of the pipeline or $null if nothing found.
#>
function Get-PipelineId {
	param (
		[Parameter(Mandatory)]
		[string]$Name,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	$pipelines = Get-Pipelines -TeamProjectName $TeamProjectName
	if ($pipelines -eq $null) {
		Write-Host "# ERROR: Failed to get pipelines of current project '$TeamProjectName'"
		return $null
	}

	for ($i = 0; $i -lt $pipelines.count; $i++) {
		if ($pipelines.value[$i].name -eq $Name) {
			Write-Host "# ID $($pipelines.value[$i].id) found for pipeline $Name."
			return $pipelines.value[$i].id
		}
	}
	Write-Host "# No ID found for pipeline $Name."
	return $null
}

Export-ModuleMember -Function Get-PipelineId