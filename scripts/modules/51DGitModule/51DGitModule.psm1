<#
  ===================== Git =====================
  .Description
  This module contains functions that perform Git
  actions.
  For more information, please read description of
  each function.
#>

Using module 51DAuthorizationModule
Using module 51DEnvironmentModule

# This to redirect all stderr to stdout for git.
$env:GIT_REDIRECT_STDERR = '2>&1'

# For testing purpose only
$script:releaseConfig = $null
$script:repositories = $null

class GitHandler {
	static [boolean]Clean () {
		$output = $(git clean -f -d)
		$exitCode = $LASTEXITCODE
		[boolean]$rtnCode = $exitCode -eq 0
		if (!$rtnCode) {
			Write-Host $output
			Write-Host "# WARNING: Could not clean current dir properly. Exit code $exitCode."
		}
		return $rtnCode
	}

	static [boolean]UpdateSubmodules() {
		$output = $(git submodule update --init --recursive)
		$exitCode = $LASTEXITCODE
		[boolean]$rtnCode = $exitCode -eq 0
		if (!$rtnCode) {
			Write-Host $output
			Write-Host "# WARNING: Could not update submodules recursively. Exit code $exitCode."
		}
		return $rtnCode
	}
	
	static [boolean]Checkout ([string]$branchName) {
		Write-Host "# Checkout $branchName"
		$output = $(git checkout "$branchName")
		$exitCode = $LASTEXITCODE
		[boolean]$rtnCode = $exitCode -eq 0
		if (!$rtnCode) {
			Write-Host $output
			Write-Host "# ERROR: Failed to checkout '$branchName' recursively. Exit code $exitCode."
			return $rtnCode
		}

		$rtnCode = [GitHandler]::UpdateSubmodules()
		if (!$rtnCode) {
			return $rtnCode
		}

		return [GitHandler]::Clean()
	}
	
	static [boolean]CheckoutTrack ([string]$branchName) {
		Write-Host "# Checkout track $branchName"
		$output = $(git checkout --track "$branchName")
		$exitCode = $LASTEXITCODE
		[boolean]$rtnCode = $exitCode -eq 0
		if (!$rtnCode) {
			Write-Host $output
			Write-Host "# ERROR: Failed to checkout '$branchName' recursively. Exit code $exitCode."
			return $rtnCode
		}

		$rtnCode = [GitHandler]::UpdateSubmodules()
		if (!$rtnCode) {
			return $rtnCode
		}

		return [GitHandler]::Clean()
	}
	
	static [boolean]CheckoutNew ([string]$branchName) {
		Write-Host "# Checkout New $branchName"
		$output = $(git checkout -b "$branchName")
		return [GitHandler]::ProcessExitCode($LASTEXITCODE, $output)
		
	}
	
	static [boolean]Pull () {
		Write-Host "# Git pull"
		$output = $(git pull)
		return [GitHandler]::ProcessExitCode($LASTEXITCODE, $output)
	}
	
	static [boolean]FetchAllTags () {
		Write-Host "# Fetch all tags"
		# git -c http.extraheader="AUTHORIZATION: bearer $env:SYSTEM_ACCESSTOKEN" fetch --all --tags
		$output = $(git -c http.extraheader="AUTHORIZATION: $([Authorization]::AuthorizationString)" fetch --all --tags)
		return [GitHandler]::ProcessExitCode($LASTEXITCODE, $output)
	}
	
	static [boolean]Push ([string]$branchName) {
		if ([string]::IsNullOrEmpty($branchName)) {
			Write-Host "# Git Push $branchName to origin"
			$output = $(git -c http.extraheader="AUTHORIZATION: $([Authorization]::AuthorizationString)" push)
		} else {
			Write-Host "# Git Push"
			$output = $(git -c http.extraheader="AUTHORIZATION: $([Authorization]::AuthorizationString)" push origin "$branchName")
		}
		return [GitHandler]::ProcessExitCode($LASTEXITCODE, $output)
	}
	
	static [boolean]Commit ([string]$message) {
		Write-Host "# Git commit"
		$output = $(git commit -m "$message")
		return [GitHandler]::ProcessExitCode($LASTEXITCODE, $output)
	}
	
	static [boolean]Config ([string]$email, [string]$name) {
		Write-Host "# Git config email '$email' and name '$name'"
		$output = $(git config user.email "$email")
		$rtnCode = [GitHandler]::ProcessExitCode($LASTEXITCODE, $output)

		$output = $(git config user.name "$name")
		return $rtnCode -and [GitHandler]::ProcessExitCode($LASTEXITCODE, $output)
	}
	
	static [boolean]Add ([string]$path) {
		Write-Host "# Git stage '$path'"
		$output = $(git add "$path")
		return [GitHandler]::ProcessExitCode($LASTEXITCODE, $output)
	}
	
	static [boolean]CheckoutWithAuthorization ([string]$branchName) {
		Write-Host "# Checkout with authorization $branchName"
		# git -c http.extraheader="AUTHORIZATION: bearer $env:SYSTEM_ACCESSTOKEN" checkout "$branchName"
		$output = $(git -c http.extraheader="AUTHORIZATION: $([Authorization]::AuthorizationString)" checkout "$branchName")
		return [GitHandler]::ProcessExitCode($LASTEXITCODE, $output)
	}
	
	static [boolean]Clone ([string]$url) {
		Write-Host "# Clone $url"
		# git -c http.extraheader="AUTHORIZATION: Bearer $env:SYSTEM_ACCESSTOKEN" clone "$url"
		$output = $(git -c http.extraheader="AUTHORIZATION: $([Authorization]::AuthorizationString)" clone "$url")
		return [GitHandler]::ProcessExitCode($LASTEXITCODE, $output)
	}
	
	static hidden [boolean]ProcessExitCode ([int]$exitCode, [string]$commandOutput) {
		[boolean]$rtnCode = $exitCode -eq 0
		if (!$rtnCode) {
			Write-Host $commandOutput
			Write-Host "WARNING: Failed with exit code $exitCode"
		}
		return $rtnCode
	}
}

<#
  .Description
  Initialise the script variables
  
  .Parameter Configuration
  A configuration object
#>
function Initialize-GlobalVariables {
	param (
		[Parameter(Mandatory)]
		[object]$Configuration
	)
	
	# Obtain the config file content. Initialise the script variables
	$script:releaseConfig = $Configuration
	$script:repositories = $script:releaseConfig.repositories
	Write-Host "# Init config: " + $script:releaseConfig
	Write-Host "# Init repositories: " + $script:repositories
}

<#
  .Description
  Determine whether a release is a major release or a hotfix.
  
  .Parameter Version
  Version of a repository
  
  .Outputs
  Type of release
#>
function Get-ReleaseType {
	param (
		[string]$Version
	)
	
	# Determine if version is minor or major
	$isMajor = $Version -match '\d+\.\d+\.0'

	# Determine the target release/hotfix branch
	if ($isMajor) {
		$type = "release"
	} else {
		$type = "hotfix"
	}
	return $type
}

<#
  .Description
  Determine if a tag has been created
  for a version of a repository.

  .Parameter RepositoryName
  Name of the repository
  
  .Parameter Version
  Release version of the repository
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  true or false
#>
function Test-TagExist {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$Version,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/git/repositories/$RepositoryName/refs?api-version=6.0&filter=tags/$Version"
	
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	if ($(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to get all tags which started with $Version for $RepositoryName.")){
		$content = $response.content | Out-String | ConvertFrom-Json
		for ($i = 0; $i -le $content.value.count; $i++) {
			if ($content.value[$i].name -match "$Version(\+\d+)?$") {
				return $true
			}
		}
	}
	return $false
}

<#
  .Description
  Get the existing release branch.
  
  .Parameter RepositoryName
  Name of the repository
  
  .Parameter Version
  Target release version of the repository.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  Full name of the release branch, prefixed with 'refs/heads' or $null if not found.
#>
function Get-ReleaseBranchRef {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$Version,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	$releaseType = Get-ReleaseType -Version $Version
	
	$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/git/repositories/$RepositoryName/refs?api-version=6.0&filter=heads/$releaseType/"
	
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	if ($(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to get the list of existing branches for $RepositoryName.")){
		$content = $response.content | Out-String | ConvertFrom-Json
		for ($i = 0; $i -lt $content.value.count; $i++) {
			if ($content.value[$i].name -match "refs/heads/$releaseType/(v)?$Version$") {
				return $content.value[$i].name
			}
		}
	}
	return $null
}

<#
  .Description
  Construct a merge branch name from pull request Id.
  
  .Parameter PullRequestId
  Id number of a pull request
  
  .Outputs
  Full reference name of a merge branch.
#>
function Get-MergeBranchName {
	param (
		[int32]$PullRequestId
	)
	return "refs/pull/$PullRequestId/merge"
}

<#
  .Description
  Get the existing 'main' branch object based on Azure Devops Response.
  It should be 'main' but can also be 'master' for older repositories.
  
  .Parameter TeamProjectName
  Name of a team project
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter AuthorizationHeader
  Authorization Header that contain access token to the Azure Devops repositories
  
  .Outputs
  Branch object or $null.
#>
function Get-MainBranch {
	param (
		[Parameter(Mandatory)]
		[string]$TeamProjectName,
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[string]$AuthorizationHeader
	)
	
	if ([string]::IsNullOrEmpty($AuthorizationHeader)) {
		$AuthorizationHeader = "$([Authorization]::AuthorizationString)"
	}
	
	$potentialNames = $("master", "main")
	foreach ($name in $potentialNames) {
		$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/git/repositories/$RepositoryName/refs?filter=heads/$($name)&api-version=6.0-preview.1"
		
		$response = Invoke-WebRequest `
		-URI $url `
		-Headers @{
			Authorization = "$AuthorizationHeader"
		} `
		-Method GET
		
		if ($(Test-RestResponse `
			-Response $response `
			-ErrorMessage "Failed to query the existence of the 'main' branch.")){
			$content = $response.content | Out-String | ConvertFrom-Json
			if ($content.value.count -eq 1) {
				return $content.value[0]
			}
		}
	}
	return $null
}

<#
  .Description
  Get the existing 'main' branch reference. It should be 'main'
  but can also be 'master' for older repositories.
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  Full reference to the 'main' branch.
#>
function Get-MainBranchRef {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	$masterBranch = "master"
	$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/git/repositories/$RepositoryName/refs?filter=heads/$masterBranch&api-version=6.0-preview.1"
	
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	if ($(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to query the existence of the 'main' branch.")){
		$content = $response.content | Out-String | ConvertFrom-Json
		if ($content.value.count -eq 1) {
			return "refs/heads/$masterBranch"
		}
	}
	return "refs/heads/main"
}

<#
  .Description
  Get the remote Url to clone the repository.
  
  .Parameter RepositoryName
  Name of the repository
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  Remote Url or $null if not found.
#>
function Get-RepositoryRemoteUrl {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	$url = "$([EnvironmentHandler]::GetEnvironmentVariable($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI))$($TeamProjectName)/_apis/git/repositories/$($RepositoryName)?api-version=6.0"
	
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	if ($(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to query repository $RepositoryName.")){
		$content = $response.content | Out-String | ConvertFrom-Json
		return $content.remoteUrl
	}
	return $null
}

<#
  .Description
  Extract the submodule path from a git submodule entry.
  
  .Parameter GitSubmodulePath
  A git submodule entry.
  
  .Outputs
  A submodule path or $null if the submodule entry does not conform
  the standard format.
#>
function Find-SubmodulePath {
	param (
		[string]$GitSubmodulePath
	)
	
	if ($GitSubmodulePath -match "submodule\.(?<content>(.)+)\.path") {
		return $Matches['content']
	}
	return $null
}

<#
  .Description
  Determine the target branch to be assessed.
  
  .Parameter Version
  The version of a repository
  
  .Outputs
  Target branch without 'refs/heads'.
#>
function Get-TargetBranch {
	param (
		[string]$Version
	)
	
	$releaseType = Get-ReleaseType -Version $Version
	
	# Determine whether the name should contains 'v' or not.
	$remoteRepo = git config --get remote.origin.url
	if (!$(git ls-remote $remoteRepo "refs/heads/$releaseType/$Version") -eq $null) {
		return $releaseType + "/" + $Version
	}
	return $releaseType + "/v" + $Version
}

<#
  .Description
  Get the repository name of current branch.
  
  .Outputs
  Repo name or $null if not found.
#>
function Get-RepositoryName {
	$remoteUrl = git config --get remote.origin.url
	if ($remoteUrl -match ".*/(?<content>((?!/).)*)") {
		return $Matches['content']
	}
	return $null
}

<#
  .Description
  Check if a branch exist in the remote repository.
  This run on the current git directory.
  
  .Parameter Branch
  Name of the branch.
  
  .Outputs true or false
#>
function Test-BranchExistRemotely {
	param (
		[string]$Branch
	)
	
	$remoteRepo = git config --get remote.origin.url
	$exists = $false
	if ($(git ls-remote $remoteRepo "refs/heads/$Branch") -ne $null) {
		$exists = $true
	}
	return $exists
}

<#
  .Description
  Check out a release branch based on the detail in the release config file.
  If no release is required, return false.

  .Parameter Version
  Version to release
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  true or false
#>
function Get-ReleaseBranch {
	param (
		[Parameter(Mandatory)]
		[string]$Version,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	# Check if the release/hotfix branch exist. Create if it doesn't.
	Write-Host ""
	Write-Host "Verify release/hotfix branch existance"
	Write-Host "================"
	$targetBranch = Get-TargetBranch -Version $Version
	$remoteRepo = git config --get remote.origin.url
	if ($(git ls-remote $remoteRepo "refs/heads/$targetBranch") -eq $null) {
		Write-Host "# No $targetBranch exists. Create one."
		$repoName = Get-RepositoryName
		$mainBranchRef = Get-MainBranchRef `
			-RepositoryName $repoName `
			-TeamProjectName $TeamProjectName
		if ($mainBranchRef -eq $null) {
			Write-Host "ERROR: No main branch found."
			return $false
		}
		$mainBranchRef -match "refs/heads/(?<name>(master|main))"
		$mainBranchName = $Matches['name']

		if (![GitHandler]::Checkout($mainBranchName)) {
			if (![GitHandler]::CheckoutTrack("origin/$mainBranchName")) {
				Write-Host "# ERROR: Failed to checkout $mainBranchRef"
				return $false
			}
		}
		if (![GitHandler]::Pull()) {
			Write-Host "# ERROR: Failed to get the latest version of the main branch $mainBranchRef"
			return $false
		}

		if (![GitHandler]::CheckoutNew($targetBranch)) {
			Write-Host "# ERROR: Failed to create target release branch $targetBranch"
			$false
		}
	} else {
		Write-Host "# $targetBranch exists. Checkout."
		if (![GitHandler]::CheckoutTrack("origin/$targetBranch")) {
			if (![GitHandler]::Checkout($targetBranch)) {
				Write-Host "# ERROR: Failed to checkout target release branch $targetBranch"
				return $false
			}
		}
		if (![GitHandler]::Pull()) {
			Write-Host "# ERROR: Failed to get the latest version of target release branch $targetBranch"
			return $false
		}
	}
	Write-Host "# OK"
	return $true
}

<#
  .Description
  Update all submodule references of a current git directory.
  This will run on the current directory.
  
  .Parameter Configuration
  A Configuration object
  
  .Outputs
  true or false.
#>
function Update-SubmoduleReferences {
	param (
		[Parameter(Mandatory)]
		[object]$Configuration
	)

	# Load the configuration into script variables.
	Initialize-GlobalVariables -Configuration $Configuration
	
	# Check if all submodules have been deployed
	Write-Host ""
	Write-Host "Update all submodules"
	Write-Host "================"
	foreach ($submodule in $(git config --file .gitmodules --name-only --get-regexp path)) {
		Write-Host ""
		Write-Host "# Process submodule path $submodule."
		$submodulePath = Find-SubmodulePath -GitSubmodulePath $submodule
		if ($submodulePath -ne $null) {
			Write-Host "# Path $submodulePath extracted."
			Push-Location $submodulePath
			if (!$?) {
				Write-Host "# ERROR: Failed to navigate to submodule $submodulePath"
				return $false
			}
			
			# Get repo name
			$subRepoName = Get-RepositoryName
			Write-Host "# Processing module $subRepoName."
			
			# Check and update the submodule to the correct tag.
			$targetTag = $script:repositories."$subRepoName".version
			Write-Host "# Checking tag $targetTag"
			
			$tagUpdated = $false
			$targetSpecified = $null -ne $targetTag

			if ($targetSpecified) {
				# Get all tag
				Write-Host "# Fetch all tags"
				if (![GitHandler]::FetchAllTags()) {
					Write-Host "# ERROR: Failed to fetch tags. Cannot reliably check submodule deployment."
					Pop-Location
					return $false
				}

				$remoteRepo = git -c http.extraheader="AUTHORIZATION: $([Authorization]::AuthorizationString)" config --get remote.origin.url
				Write-Host "# Remote repository found '$remoteRepo'"
				# Make sure to sort the tag, so only pick up the biggest tag.
				# e.g. If 4.3.0 and 4.3.0+1 then pick the later.
				foreach ($tag in $(git -c http.extraheader="AUTHORIZATION: $([Authorization]::AuthorizationString)" ls-remote --tags --sort=-v:refname $remoteRepo "$($targetTag)*")) {
					Write-Host "# Check tag '$tag' against target tag '$targetTag'"
					# By presorted the tags, the first only that match the tag format will be the latest one.
					if ($tag -match ".*/(?<content>$targetTag(\+(\d)+)?)$") {
						Write-Host "# Tag $targetTag found with value $($Matches['content']). The submodule has been been deployed."
	
						if (![GitHandler]::CheckoutWithAuthorization("tags/$($Matches['content'])")) {
							Write-Host "# ERROR: Failed to checkout the tag $($Matches['content'])."
							break
						}
						
						$tagUpdated = $true
						break
					}
				}
			} else {
				# If no version is found from the configuration file.
				# Treat it as nothing to be changed for this submodule.
				Write-Host "# No target version has been specified for $subRepoName. No update required."
				$tagUpdated = $true
			}
			
			Pop-Location
						
			if($targetSpecified) {
				# Exit if not all tags have been found.
				if (!$tagUpdated) {
					Write-Host "# ERROR: Failed to update Submodule $subRepoName to tag $targetTag."
					return $false
				}

				# Stage the submodule update
				Write-Host "# Stage the submodule $submodulePath"
				if (![GitHandler]::Add($submodulePath)) {
					Write-Host "# ERROR: Failed to stage the submodule $subRepoName."
					return $false
				}
			}
		} else {
			Write-Host "# ERROR: Failed to extract module path from $submodulePath"
			return $false
		}
	}
	
	Write-Host "# OK"
	return $true
}

<#
  .Description
  Commit any staged changes and push to remote repository.
  
  .Outputs
  true or false
#>
function Start-CommitAndPush {
	# Commit changes
	Write-Host ""
	Write-Host "# Commit and push staged changes."
	Write-Host "================"
	$branchName = git rev-parse --abbrev-ref HEAD
	$existingBranch = Test-BranchExistRemotely -Branch $branchName
	if (![GitHandler]::Config("ciuser@51degrees.com", "CIUser")) {
		Write-Host "# ERROR: Failed to configure email and user name"
		return $false
	}
	
	if ($(git diff --cached --name-only).count -gt 0 ) {
		Write-Host "# There are changes. Commit now."
		if (![GitHandler]::Commit("REF: Update submodules references.")) {
			Write-Host "# ERROR: Failed to commit the submodules updates."
			return $false
		}
		
		# Push changes
		Write-Host "# Push the changes."
		[boolean]$rc = $false
		if (!$existingBranch) {
			git -c http.extraheader="AUTHORIZATION: $([Authorization]::AuthorizationString)" push origin "$branchName"
			$rc = [GitHandler]::Push("$branchName")
		} else {
			$rc = [GitHandler]::Push($null)
		}
		
		if (!$rc) {
			Write-Host "# ERROR: Failed to push changes."
			return $false
		}
	} else {
		Write-Host "# There is nothing to commit."
	}
	return $true
}
