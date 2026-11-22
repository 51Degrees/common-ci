<#
  ===================== Pull Request =====================
  .Description
  This module contains functions that perform actions on
  Azure Devops pull requests.
  For more information, please read description of
  each function.
#>

Using module 51DAuthorizationModule
Using module 51DEnvironmentModule

# Global variables to be updated when one of the main APIs is called.
$script:releaseConfig = $null
$script:repositories = $null

<#
  .Description
  Get the existing pull request to 'main' branch.
  
  .Parameter RepositoryName
  Name of the repository
  
  .Parameter ReleaseBranch
  Ref of the release branch
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  A pull request object based on Azure Devops definition.
  $null if nothing is found.
#>
function Get-PullRequestToMain {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$ReleaseBranch,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/git/repositories/$RepositoryName/pullrequests?api-version=6.0"
	
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	if ($(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to get the list of existing pull requests for $RepositoryName.")){
		$content = $response.content | Out-String | ConvertFrom-Json
		for ($i = 0; $i -lt $content.value.count; $i++) {
			if ($content.value[$i].sourceRefName -match "$ReleaseBranch$" `
				-and $content.value[$i].targetRefName -match "refs/heads/(master|main)" `
				-and $content.value[$i].status -eq "active") {
				Write-Host "# Matching Pull Request: " $content.value[$i]
				return $content.value[$i]
			}
		}
	} else {
		Write-Host "# ERROR: Rest API call fails."
	}
	return $null
}

<#
  .Description
  Add a comment to a pull request
  
  .Parameter TeamRepositoryName
  Name of a Team Project
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter PullRequestId
  Id of a pull request
  
  .Parameter Comment
  Content of a comment
  
  .Parameter AuthorizationHeader
  A authorization header that contains the Access Token to the Azure Devops
  
  .Outputs
  true or false
#>
function Add-PullRequestComment {
	param (
		[Parameter(Mandatory)]
		[string]$TeamProjectName,
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[int32]$PullRequestId,
		[Parameter(Mandatory)]
		[string]$Comment,
		[string]$AuthorizationHeader
	)
	# Default Authorization Header
	if ([string]::IsNullOrEmpty($AuthorizationHeader)) {
		$AuthorizationHeader = "$([Authorization]::AuthorizationString)"
	}
	
	$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/git/repositories/$RepositoryName/pullrequests/$PullRequestId/threads?api-version=6.0"
	$jsonBody = @"
	{
		"status": "active",
		"comments": [
			{
				"commentType": "text",
				"content": "$Comment"
			}
		]
	}
"@

	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$AuthorizationHeader"
	} `
	-Method POST `
	-ContentType "application/json" `
	-Body $jsonBody
	
	return $(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to add a comment to pull request $PullRequestId.")
}

<#
  .Description
  Create a pull request.
  
  .Parameter TeamProjectName
  Name of a Team project
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter SourceBranchRef
  Full reference of the source branch. (i.e. prefixed with 'refs/heads')
  
  .Parameter TargetBranchRef
  Full reference of the target branch. (i.e. prefixed with 'refs/heads')
  
  .Parameter AuthorizationHeader
  A authorization header that contains the Access Token to the Azure Devops
  
  .Outputs
  response content or $null
#>
function New-PullRequest {
	param (
		[Parameter(Mandatory)]
		[string]$TeamProjectName,
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$SourceBranchRef,
		[Parameter(Mandatory)]
		[string]$TargetBranchRef,
		[string]$AuthorizationHeader
	)
	
	# Default Authorization Header
	if ([string]::IsNullOrEmpty($AuthorizationHeader)) {
		$AuthorizationHeader = "$([Authorization]::AuthorizationString)"
	}
	
	$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/git/repositories/$RepositoryName/pullrequests?api-version=6.0"
	# Extract source and target branch names. This is to match the branch name to be extracted later.
	$rc = $SourceBranchRef -match "refs/heads/(?<srcbranch>.*)"
	$srcBranch = $Matches['srcbranch']
	$rc = $TargetBranchRef -match "refs/heads/(?<tgtbranch>.*)"
	$tgtBranch = $Matches['tgtbranch']
	$prTitle = "Merge branch '$srcBranch' into '$tgtBranch'"
	$jsonBody = @"
	{
		"title" : "$prTitle",
		"sourceRefName" : "$SourceBranchRef",
		"TargetRefName" : "$TargetBranchRef"
	}
"@

	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$AuthorizationHeader"
	} `
	-Method POST `
	-ContentType "application/json" `
	-Body $jsonBody
	
	if (!$(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to create a pull request.")) {
		return $null	
	}
	return $($response.content | Out-String | ConvertFrom-Json)
}

<#
  .Description
  Create a pull to 'main' branch.
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter SourceBranchRef
  Full reference of the source branch. (i.e. prefixed with 'refs/heads')
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs true or false
#>
function New-PullRequestToMain {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$SourceBranchRef,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	$mainBranch = $(Get-MainBranchRef `
		-RepositoryName $RepositoryName `
		-TeamProjectName $TeamProjectName)
	if($(New-PullRequest `
		-TeamProjectName $TeamProjectName `
		-RepositoryName $RepositoryName `
		-SourceBranchRef $SourceBranchRef `
		-TargetBranchRef $mainBranch `
		-AuthorizationHeader "$([Authorization]::AuthorizationString)") -eq $null) {
		Write-Host "# ERROR: Failed to create pull request to main"
		return $false
	}
	return $true
}

<#
  .Description
  Decide an action on a release branch. Either request a test pipeline
  if a pull request eixsts, or create a new one.
  
  .Parameter RepositoryName
  Name of the repository
  
  .Parameter ReleaseBranch
  Full reference of the release branch.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  True or False
#>
function Start-ProcessPullRequest {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$ReleaseBranch,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	# Check if a Pull Request already exist
	$pullRequest = Get-PullRequestToMain `
		-RepositoryName $RepositoryName `
		-ReleaseBranch $ReleaseBranch `
		-TeamProjectName $TeamProjectName
	
	if ($pullRequest -ne $null) {
		Write-Host "# Pull request exists. Requeue the test pipeline."
		#Rerun the build-and-test pipeline for this pull request.
		return $(Restart-TestBuild `
			-RepositoryName $RepositoryName `
			-PullRequestId $pullRequest.pullRequestId `
			-TeamProjectName $TeamProjectName)
	} else {
		Write-Host "# Pull request does not exist. Create one."
		#Create a pull request which should trigger the build-and-test pipeline.
		return $(New-PullRequestToMain `
			-RepositoryName $RepositoryName `
			-SourceBranchRef $ReleaseBranch `
			-TeamProjectName $TeamProjectName)
	}
}

<#
  .Description
  Check if all required votes for a pull requests have been approved.
  
  .Parameter RepositoryName
  Name of the repository that the PR belongs to
  
  .Parameter PullRequestId
  Id number of a pull request.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs true or false
#>
function Test-PullRequestVotes {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[int32]$PullRequestId,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/git/repositories/$RepositoryName/pullrequests/$($PullRequestId)?api-version=6.0"
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	if ($(Test-RestResponse -Response $response -ErrorMessage "Failed to get pull request details.")) {
		$content = $response.content | Out-String | ConvertFrom-Json
		foreach ($reviewer in $content.reviewers) {
			if ($reviewer.isRequired `
				-and $reviewer.vote -ne 10 `
				-and $reviewer.vote -ne 5) {
				Write-Host "# Required reviewer has not accepted the PR."
				return $false
			}
		}
		return $true
	}
	return $false
}

<#
  .Description
  Check if all comments have been resolved for a pull request.
  
  .Parameter RepositoryName
  Name of a repository that a pull request belongs to.
  
  .Parameter PullRequestId
  Id number of a pull request.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs true or false.
#>
function Test-PullRequestComments {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[int32]$PullRequestId,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/git/repositories/$RepositoryName/pullrequests/$($PullRequestId)/threads?api-version=6.0"
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	if ($(Test-RestResponse -Response $response -ErrorMessage "Failed to get pull request threads.")) {
		$content = $response.content | Out-String | ConvertFrom-Json
		foreach ($thread in $content.value) {
			if ($thread.status -eq "active") {
				Write-Host "# Comment has not been resolved."
				return $false
			}
		}
		return $true
	}
	return $false
}

<#
  .Description
  Complete a pull request.
  
  .Parameter RepositoryName
  Name of a repository that the pull request belongs to.
  
  .Parameter PullRequestId
  Id number of a pull request.
  
  .Parameter ApprovalRequired.
  Whether approval is required to complete.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs true or false.
#>
function Complete-PullRequest {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[int32]$PullRequestId,
		[Parameter(Mandatory)]
		[bool]$ApprovalRequired,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	$canComplete = $false
	if (!$ApprovalRequired) {
		Write-Host "# No approval is required. Bypass any policies."
		$canComplete = $true
	} elseif (($(Test-PullRequestVotes `
		-RepositoryName $RepositoryName `
		-PullRequestId $PullRequestId `
		-TeamProjectName $TeamProjectName) `
		-and $(Test-PullRequestComments `
		-RepositoryName $RepositoryName `
		-PullRequestId $PullRequestId `
		-TeamProjectName $TeamProjectName))) {
		Write-Host "# Pull request has been approved and no comments left unresolved."
		$canComplete = $true
	}
	
	if ($canComplete) {
		# Get Last Merge Source Commit
		$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/git/repositories/$RepositoryName/pullrequests/$($PullRequestId)?api-version=6.0"
		Write-Host "$url"
		$response = Invoke-WebRequest `
		-URI $url `
		-Headers @{
			Authorization = "$([Authorization]::AuthorizationString)"
		} `
		-Method GET
	
		if ($(Test-RestResponse -Response $response -ErrorMessage "Failed to get pull request info.")) {
			$content = $response.content | Out-String | ConvertFrom-Json
			$lastMergeSourceCommit = $content.lastMergeSourceCommit.commitId
			
			$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/git/repositories/$RepositoryName/pullrequests/$($PullRequestId)?api-version=6.0"
			$jsonBody = @"
			{
				"lastMergeSourceCommit" : {
					"commitId" : "$lastMergeSourceCommit"
				},
				"status" : "completed",
				"completionOptions" : {
					"bypassPolicy" : true,
					"bypassReason" : "Auto Release Process"
				}
			}
"@

			$response = Invoke-WebRequest `
			-URI $url `
			-Headers @{
				Authorization = "$([Authorization]::AuthorizationString)"
			} `
			-Method PATCH `
			-ContentType "application/json" `
			-Body $jsonBody
			
			return $(Test-RestResponse -Response $response -ErrorMessage "Failed to complete pull request.")
		} else {
			return $false
		}
		
	} else {
		Write-Host "# Can't complete pull request as comments has not been resolved or reviewer has not approved."
		return $false
	}
}

<#
  .Description
  Check if a pull request is from a release/hotfix branch to main.
  
  .Parameter PullRequestId
  The id number of a pull request
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  true or false
#>
function Test-IsReleasePullRequest {
	param (
		[Parameter(Mandatory)]
		[int32]$PullRequestId,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	$prSourceBranch = [EnvironmentHandler]::GetEnvironmentVariable($Env:SYSTEM_PULLREQUEST_SOURCEBRANCH)
	$prTargetBranch = [EnvironmentHandler]::GetEnvironmentVariable($Env:SYSTEM_PULLREQUEST_TARGETBRANCH)
	$repoName = [EnvironmentHandler]::GetEnvironmentVariable($Env:BUILD_REPOSITORY_NAME) # This should always be available.
	# If the source or target branch is not available from environment variables
	# Try the query it using the REST api.
	if ($prSourceBranch -eq $null `
		-or $prTargetBranch -eq $null) {
		$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/git/repositories/$repoName/pullrequests/$($PullRequestId)?api-version=6.0"
		$response = Invoke-WebRequest `
		-URI $url `
		-Headers @{
			Authorization = "$([Authorization]::AuthorizationString)"
		} `
		-Method GET
		
		if (Test-RestResponse `
			-Response $response `
			-ErrorMessage "Failed to query pull request details.") {
			$content = $response.content | Out-String | ConvertFrom-Json
			$prSourceBranch = $content.sourceRefName
			$prTargetBranch = $content.targetRefName
		} else {
			Write-Host "# ERROR: Can obtain source and target branch of the pull request $PullRequestId."
			return $false
		}
	}
	
	if ($prSourceBranch -match "refs/heads/(release|hotfix)/v?(?<version>\d+\.\d+\.\d+)") {
		Write-Host "# Pull request is from a release/hotfix branch."
		$prVersion = $Matches['version']
	} else {
		Write-Host "# Pull request is not from a release/hotfix branch."
		return $false
	}
	
	if (!$($prTargetBranch -match "refs/heads/(main|master)")) {
		Write-Host "# Pull request is not to the 'main' branch."
		return $false
	}
	
	# Check if the pull request is from a release target versions.
	# Get the module name
	$targetVersion = $script:repositories."$repoName".version
	if ($prVersion -eq $targetVersion) {
		Write-Host "# Pull request matches the target release version. Proceed to complete."
	} else {
		Write-Host "# Pull request does not match the target release version. `
			The pull request version is $prVersion, while the target version is $targetVersion. `
			Do not proceed."
		return $false
	}
	return $true
}

<#
  .Description
  Initialise the global variables
  
  .Parameter Configuration
  A configuration object
#>
function Initialize-GlobalVariables {
	param (
		[object]$Configuration
	)
	
	# Obtain the config file content. Initialise the global variables
	$script:releaseConfig = $Configuration
	$script:repositories = $script:releaseConfig.repositories
	Write-Host "# Init config: " + $script:releaseConfig
	Write-Host "# Init repositories: " + $script:repositories
}

<#
  .Description
  If the script is called in a build running on a pullrequest branch, try
  to complete the corresponding pull request.
	
  .Parameter ConfigFile
  Path to the configration file
  
  .Outputs
  true or false
  NOTE: The only time when this should return false is when the build is
  triggered by a pull request and it failed to complete the pull request.
#>
function Complete-CorrespondingPullRequest {
	param (
		[string]$ConfigFile
	)

	# Initialise global variables
	$configuration = Get-Content $ConfigFile | Out-String | ConvertFrom-Json
	Initialize-GlobalVariables -Configuration $configuration

	# Get pull request
	Write-Host "Build.SourceBranch: " [EnvironmentHandler]::GetEnvironmentVariable($Env:BUILD_SOURCEBRANCH)
	Write-Host "System.PullRequest.SourceBranch: " [EnvironmentHandler]::GetEnvironmentVariable($Env:SYSTEM_PULLREQUEST_SOURCEBRANCH)
	Write-Host "System.PullRequest.TargetBranch: " [EnvironmentHandler]::GetEnvironmentVariable($Env:SYSTEM_PULLREQUEST_TARGETBRANCH)
	Write-Host "Build.Repository.Name: " [EnvironmentHandler]::GetEnvironmentVariable($Env:BUILD_REPOSITORY_NAME)
	$sourceBranch = [EnvironmentHandler]::GetEnvironmentVariable($Env:BUILD_SOURCEBRANCH)
	if ($sourceBranch -match "refs/pull/(?<content>\d+)/merge") {
		Write-Host "# Triggered by a pull request."
		$pullRequestId = $Matches['content']
		if ($(Test-IsReleasePullRequest `
			-PullRequestId $pullRequestId `
			-TeamProjectName "$([EnvironmentHandler]::GetEnvironmentVariable($Env:SYSTEM_TEAMPROJECTID))")) {
			if ($(Update-SubmoduleReferences -Configuration $configuration)) {
				# Check if any changes are required. If there are, submodules are not up to date.
				if ($(git diff --cached --name-only).count -eq 0 ) {
					Write-Host "# All submodules are up to date. Complete the corresponding pull request now."
					# Complete the pull request
					if (!$(Complete-PullRequest `
						-RepositoryName "$([EnvironmentHandler]::GetEnvironmentVariable($Env:BUILD_REPOSITORY_NAME))" `
						-PullRequestId $pullRequestId `
						-ApprovalRequired $script:releaseConfig.approvalRequired `
						-TeamProjectName "$([EnvironmentHandler]::GetEnvironmentVariable($Env:SYSTEM_TEAMPROJECTID))")) {
						Write-Host "# ERROR: Cannot complete the pull request $pullRequestId."
						return $false
					}
				} else {
					Write-Host "# ERROR: Not all submodules are up to date. Don't complete the pull request."
					return $false
				}
			} else {
				Write-Host "# ERROR: Failed to check if all submodules are up to date."
				return $false
			}
		} else {
			Write-Host "# Not a release pull request. Nothing to complete."
			return $false
		}
	} else {
		Write-Host "# Not triggered by a pull request. Nothing to complete."
		return $false
	}
	return $true
}

Export-ModuleMember -Function Get-PullRequestToMain
Export-ModuleMember -Function Add-PullRequestComment
Export-ModuleMember -Function New-PullRequest
Export-ModuleMember -Function New-PullRequestToMain
Export-ModuleMember -Function Start-ProcessPullRequest
Export-ModuleMember -Function Complete-CorrespondingPullRequest