<#
  .Description
  This contains shared variables and constants
#>

Using module 51DAuthorizationModule

class TestEnvPredefinedVariables {
	# Projects links and names
	static [string]$TeamFoundationCollectionUri = "https://51degrees.visualstudio.com/DefaultCollection/"
	static [string]$ProductionProject = "Pipeline"
	static [string]$TestProject = "APIs%20Release%20Test%20Environment"
	static [string]$MandatoryRepositoryName = "MandatoryRepository"
	static [string]$Reviewer = "CIUser"
	
	# ids
	static hidden [string]$ProductionProjectId = $null
	static hidden [string]$TestProjectId = $null
	static hidden [string]$ReviewerId = $null
	
	# Project default predefined variables
	static [string]$DefaultQueueName = "Azure Pipelines"
	static [string]$YamlCiTrigger = '{
				"branchFilters": [],
				"pathFilters": [],
				"settingsSourceType": 2,
				"batchChanges": false,
				"maxConcurrentBuildsPerBranch": 1,
				"triggerType": "continuousIntegration"
			}'
			
	# Static methods
	<#
	  .Description
	  Return the production project id
	  
	  .Outputs
	  The id of the production project. throw exception if error occurs
	#>
	static [string]GetProductionProjectId() {
		if ([string]::IsNullOrEmpty([TestEnvPredefinedVariables]::ProductionProjectId)) {
			# Get production project id
			$uri = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)_apis/projects/$([TestEnvPredefinedVariables]::ProductionProject)?api-version=6.0"
			$response = Invoke-WebRequest `
				-URI $uri `
				-Headers @{
					Authorization = "$([Authorization]::AuthorizationString)"
				} `
				-Method GET
			if (Test-RestResponse -Response $response) {
				$content = $response.content | Out-String | ConvertFrom-Json
				[TestEnvPredefinedVariables]::ProductionProjectId = $content.id
			} else {
				throw "# ERROR: Failed to obtain the project Id of project $([TestEnvPredefinedVariables]::ProductionProject)"
			}
		}
		return [TestEnvPredefinedVariables]::ProductionProjectId
	}
	
	<#
	  .Description
	  Return the test project id
	  
	  .Outputs
	  The id of the test project. throw exception if error occurs
	#>
	static [string]GetTestProjectId() {
		if ([string]::IsNullOrEmpty([TestEnvPredefinedVariables]::TestProjectId)) {
			$uri = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)_apis/projects/$([TestEnvPredefinedVariables]::TestProject)?api-version=6.0"
			Write-Host $uri
			$response = Invoke-WebRequest `
				-URI $uri `
				-Headers @{
					Authorization = "$([Authorization]::AuthorizationString)"
				} `
				-Method GET
			if (Test-RestResponse -Response $response) {
				$content = $response.content | Out-String | ConvertFrom-Json
				[TestEnvPredefinedVariables]::TestProjectId = $content.id
			} else {
				throw "# ERROR: Failed to obtain the project Id of project $([TestEnvPredefinedVariables]::TestProject)"
			}
		}
		return [TestEnvPredefinedVariables]::TestProjectId
	}
	
	<#
	  .Description
	  Return the Id of the default reviewer
	  
	  .Outputs
	  The id of the default reviewer. throw exception if error occurs
	#>
	static [string]GetReviewerId() {
		# Get reviewer id. Currently only support a reviewer.
		$uri = "https://vsaex.dev.azure.com/51Degrees/_apis/userentitlements?api-version=6.1-preview.3"
		$response = Invoke-WebRequest `
			-URI $uri `
			-Headers @{
				Authorization = "$([Authorization]::AuthorizationString)"
			} `
			-Method GET
		if (Test-RestResponse -Response $response) {
			$content = $response.content | Out-String | ConvertFrom-Json
			[TestEnvPredefinedVariables]::ReviewerId = $($content.members | Where-Object {$_.user.displayName -eq "$([TestEnvPredefinedVariables]::Reviewer)"})[0].id
		} else {
			throw "# ERROR: Failed to obtain the reviewer id for reviewer $([TestEnvPredefinedVariables]::Reviewer)"
		}
		return [TestEnvPredefinedVariables]::ReviewerId
	}
}

<#
  .Description
  Wrapper function for [TestEnvPredefinedVariables]::GetProductionProjectId()
#>
function Get-ProductionProjectId {
	return [TestEnvPredefinedVariables]::GetProductionProjectId()
}

<#
  .Description
  Wrapper function for [TestEnvPredefinedVariables]::GetTestProjectId()
#>
function Get-TestProjectId {
	return [TestEnvPredefinedVariables]::GetTestProjectId()
}

<#
  .Description
  Wrapper function for [TestEnvPredefinedVariables]::Get-ReviewerId()
#>
function Get-ReviewerId {
	return [TestEnvPredefinedVariables]::GetReviewerId()
}

# When using this script locally uncomment and update the below environment accordingly.
# $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI = "https://51degrees.visualstudio.com/DefaultCollection/"
# $env:SYSTEM_TEAMPROJECTID = "APIs%20Release%20Test%20Environment"