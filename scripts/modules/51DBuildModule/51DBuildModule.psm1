<#
  ===================== Build =====================
  .Description
  This module contains functions that perform actions
  on a or more Azure Devops build.
  For more information, please read description of
  each function.
#>

Using module 51DAuthorizationModule
Using module 51DEnvironmentModule

<#
  .Description
  Requeue a test build of a pull request.
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter PullRequestId
  Id number of a pull request

  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs true or false
#>
function Restart-TestBuild {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[int32]$PullRequestId,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	# Get the merge branch of the pull request
	$ref = Get-MergeBranchName -PullRequestId $PullRequestId

	# Obtain test pipeline id of a repository.
	$pipelineId = Get-PipelineId -Name "$RepositoryName-test" -TeamProjectName $TeamProjectName
	if ($pipelineId -eq $null) {
		Write-Host "# ERROR: Failed to get pipeline id"
		return $false
	}
	
	# Get all runs for the pipeline.
	$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/build/builds?api-version=6.0"
	$jsonBody = @"
	{
		"definition" : {
			"id" : $pipelineId
		},
		"sourceBranch" : "$ref"
	}
"@

	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method POST `
	-ContentType "application/json" `
	-Body $jsonBody
	
	return $(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to rerun the test pipeline for pull request $PullRequestId.")
}

<#
  .Description
  Requeue a test build of a pull request.
  
  .Parameter BuildId
  Id number of a build.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs Build object.
#>
function Get-Build {
	param (
		[Parameter(Mandatory)]
		[int32]$BuildId,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/build/builds/$($BuildId)?api-version=6.0"
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	if ($(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to get build object for build $BuildId.")) {
		$content = $response.content | Out-String | ConvertFrom-Json
		return $content
	} else {
		return $null
	}
}

<#
  .Description
  Cancel all other builds of a pipeline on a certain branch, except the specified build id.
  
  .Parameter PipelineName
  Name of a pipeline to check for the builds.
  
  .Parameter Branch
  Full reference name of a branch to check if the builds run on.
  
  .Parameter CurrentBuildId
  Build id.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs true or false
#>
function Stop-PreviousBuilds {
	param (
		[Parameter(Mandatory)]
		[string]$PipelineName,
		[Parameter(Mandatory)]
		[string]$Branch,
		[Parameter(Mandatory)]
		[string]$CurrentBuildId,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	Write-Host ""
	Write-Host "# Getting current builds."
	$pipelineId = Get-PipelineId -Name $PipelineName -TeamProjectName $TeamProjectName
	$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/build/builds?definitions=$pipelineId&branchName=$Branch&api-version=6.0"
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	if ($(Test-RestResponse -Response $response -ErrorMessage "Failed to get all current builds.")) {
		$content = $response.content | Out-String | ConvertFrom-Json
		$buildsToCancel = $content.value.Where({ ($_.status -eq 'inProgress') -and ($_.id -ne $CurrentBuildId) })
		$allCancelled = $true
		
		$currentBuild = Get-Build -BuildId $CurrentBuildId -TeamProjectName $TeamProjectName
		if ($currentBuild -eq $null) {
			Write-Host "# ERROR: Failed to obtain current build object."
			return $false
		}
		
		$currentBuildTime = Get-Date -Format yyyy-MM-ddTHH-mm-ss-ff $currentBuild.startTime
		foreach ($build in $buildsToCancel) {
			$buildTime = Get-Date -Format yyyy-MM-ddTHH-mm-ss-ff $build.startTime
			if ($buildTime -lt $currentBuildTime) {
				Write-Host ""
				Write-Host "# Cancelling build $($build.id)."
				$body = @"
				{
					"id" : $($build.id),
					"status" : "cancelling"
				}
"@	
		
				$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/build/builds/$($build.id)?api-version=6.0"
				$cancellingResponse = Invoke-WebRequest `
				-URI $url `
				-Headers @{
					Authorization = "$([Authorization]::AuthorizationString)"
				} `
				-Method PATCH `
				-ContentType "application/json" `
				-Body $body
				
				if ($(Test-RestResponse -Response $cancellingResponse -ErrorMessage "Failed to cancle build $($build.id)")) {
					Write-Host "# SUCCESS"
				} else {
					Write-Host "# FAIL"
					$allCancelled = $false
				}
			}
		}
		return $allCancelled
	}
	return $false
}

Export-ModuleMember -Function Restart-TestBuild
Export-ModuleMember -Function Stop-PreviousBuilds