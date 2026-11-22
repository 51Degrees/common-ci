<#
  ===================== Release =====================
  .Description
  This module contains functions that perform package
  release actions.
  For more information, please read description of
  each function.
#>

Using module 51DGitModule
Using module 51DPackageModule

# Read-only script variables. These variables are accessed for script read-only information.
# No functions should make changes to these variables.
$script:releaseConfig = ""
$script:repositories = ""

# Shared script list of repositories that require action and repositories
# that have been processed. These are allowed to be updated by
# Get-*-Action functions.
$script:actionTable = @{} # key is repository name, value is true or false
$script:traveledTable = @{} # key is repository name, value is true or false

<#
  .Description
  Get whether a repository release version need action.
  The function will update the list of traveled nodes
  and the list of action required nodes.
  
  .Parameter RepositoryName
  Name of the repository
  
  .Parameter Version
  The target version
  
  .Parameter TeamProjectName
  Name ofthe repository team project
#>
function Get-LeafAction {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$Version,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	# If a tag exist, don't do anything and return.
	if(!$script:traveledTable[$RepositoryName]) {
		if (!$(Test-TagExist `
			-RepositoryName $RepositoryName `
			-Version $Version `
			-TeamProjectName $TeamProjectName)) {
			Write-Host "# Repository '$RepositoryName' requires actions."
			$script:actionTable[$RepositoryName] = $true
		}
		$script:traveledTable[$RepositoryName] = $true
	}
}

<#
  .Description
  Get whether a repository release version need action.
  Further information of the dependencies are acquired
  from the script release configuration object.
  The function will update the list of traveled nodes
  and the list of action required nodes.

  .Parameter RepositoryName
  Name of the repository
  
  .Parameter Version
  The target version
  
  .Parameter Dependencies
  Dependencies of the repository
  
  .Parameter TeamProjectName
  Name ofthe repository team project
#>
function Get-NonLeafAction {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$Version,
		[Parameter(Mandatory)]
		[string[]]$Dependencies,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)

	# If a tag exist, don't do anything and return.
	if(!$script:traveledTable[$RepositoryName]) {
		if(!$(Test-TagExist `
			-RepositoryName $RepositoryName `
			-Version $Version `
			-TeamProjectName $TeamProjectName)) {
			$script:traveledTable[$RepositoryName] = $true			
			foreach ($dependency in $Dependencies) {
				# Check if action required for a dependency.
				if (!$script:traveledTable[$dependency]) {
					Get-Action `
						-RepositoryName $dependency `
						-TeamProjectName $TeamProjectName
				}
				
				# If action is required for a dependency,
				# then no action for this node.
				if ($script:actionTable[$dependency]) {
					return
				}
			}
			Write-Host "# Repository '$RepositoryName' requires actions"
			$script:actionTable[$RepositoryName] = $true
		}
	}
}

<#
  .Description
  Get whether a repository need action. The function
  will obtain the target version and other information
  from the script release configuration object.
  The function will update the list of traveled nodes
  and the list of action required nodes.
  The algorithm is straighforward, providing the script
  is single threaded.
  For a repository, if it is a leaf node, process to determine action.
  If it is not a leaf node, check the dependencies to determine action.
  Update the action required list and the traveled list in flight.
  
  .Parameter RepositoryName
  Name of the repository
  
  .Parameter TeamProjectName
  Name ofthe repository team project
#>
function Get-Action {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	$version = $script:releaseConfig.repositories."$RepositoryName".version
	$isLeaf = $script:releaseConfig.repositories."$RepositoryName".isLeaf
	
	if ($isLeaf) {
		$needAction = Get-LeafAction `
			-RepositoryName $RepositoryName `
			-Version $version `
			-TeamProjectName $TeamProjectName
	} else {
		$dependencies = $script:releaseConfig.repositories."$RepositoryName".dependencies
		$needAction = Get-NonLeafAction `
			-RepositoryName $RepositoryName `
			-Version $version `
			-Dependencies $dependencies `
			-TeamProjectName $TeamProjectName
	}
}

<#
  .Description
  Bump release version. This checkout the 'main' branch and
  update the release GitVersion.
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter Version
  Target release version.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs true or false
#>
function Update-Version {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$Version,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	Write-Host "# Bump release version of repository $RepositoryName to $Version."
	
	# Checkout the repository main branch and extract the branch name
	$mainBranch = Get-MainBranchRef `
		-RepositoryName $RepositoryName `
		-TeamProjectName $TeamProjectName
	if ($mainBranch -match "refs/heads/(?<name>(master|main))") {
		$mainBranchName = $Matches['name']
	} else {
		Write-Host "# ERROR: Main branch name is not standard."
		return $false
	}
	
	$remoteUrl = Get-RepositoryRemoteUrl `
		-RepositoryName $RepositoryName `
		-TeamProjectName $TeamProjectName
	if ($remoteUrl -ne $null) {
		if ([GitHandler]::Clone($remoteUrl)) {
			Push-Location $RepositoryName

			# Configuration email address and user name before any commit for this repository.
			if (![GitHandler]::Config("ciuser@51degrees.com", "CIUser")) {
				Write-Host "# ERROR: Failed to configure email and user name"
				return $false
			}

			# Checkout the main branch
			if ($(git rev-parse --abbrev-ref HEAD) -notmatch "(master|main)") {
				if ([GitHandler]::Checkout($mainBranchName)) {
					Write-Host "# Successfully checkout main branch '$mainBranchName'."
				} elseif ([GitHandler]::CheckoutTrack('origin/$mainBranchName')) {
					Write-Host "# Successfully checkout and track main branch '$mainBranchName'."
				} else {
					Write-Host "# ERROR: Failed to checkout main branch."
					Pop-Location
					return $false
				}
			} else {
				Write-Host "# Currently on $mainBranchName."
			}
			
			[boolean]$rc = $false
			if ($(Test-Path GitVersion.yml)) {
				# Update the GitVersion number to the target release version.
				Write-Host "# GitVersion.yml exists. Update the file with the next version $Version."
				$versionFileContent = $(Get-Content GitVersion.yml -Raw)
				if ($versionFileContent -match ".*next-version.*") {
					$versionFileContent = $versionFileContent -replace "next-version.*(\r\n)?", "next-version: $Version`r`n"
				} else {
					$versionFileContent = "next-version: $Version`r`n" + $versionFileContent
				}
				$rc = [FileHandler]::SetContent("GitVersion.yml", $versionFileContent)
			} else {
				Write-Host "# GitVersion.yml does not exist. Create one."
				$rc = [FileHandler]::SetContent("GitVersion.yml", "next-version: $Version")
			}
			
			if (!$rc) {
				Write-Host "# ERROR: Failed to update the content of GitVersion.yml"
				Pop-Location
				return $false
			}
	
			# Stage the changes
			Write-Host "# Stage GitVersion.yml"
			if (![GitHandler]::Add("GitVersion.yml")) {
				Write-Host "# ERROR: Failed to stage GitVersion.yml"
				return $false
			}
			
			# Commit the changes
			Write-Host "# Commit changes"
			if (![GitHandler]::Commit("BUILD: Bump GitVersion next-version to $Version.")) {
				Write-Host "# ERROR: Failed to commit change."
				Pop-Location
				return $false
			}
	
			# Push the changes
			Write-Host "# Push changes"
			if (![GitHandler]::Push($null)) {
				Write-Host "# ERROR: Failed to push to remote."
				Pop-Location
				return $false
			}
			
			Pop-Location
		} else {
			Write-Host "# ERROR: Failed to clone repository $RepositoryName."
			return $false
		}
	} else {
		Write-Host "# ERROR: No remote url found for repository $RepositoryName."
		return $false
	}
	Write-Host "# OK"
	return $true
}

<#
  .Description
  Initialise the script variables
  
  .Parameter Configuration
  Configuration object obtained from a configration file
#>
function Initialize-GlobalVariables {
	param (
		[Parameter(Mandatory)]
		[object]$Configuration
	)
	
	# Obtain the config file content. Initialise the script variables
	$script:releaseConfig = $Configuration
	$script:repositories = $script:releaseConfig.repositories | Get-Member -MemberType NoteProperty
	$script:actionTable = @{} # key is repository name, value is true or false
	$script:traveledTable = @{} # key is repository name, value is true or false
	Write-Host "# Repositories found: $($script:repositories)"
}

<#
  .Description
  Get the action table. This is mainly for the purpose of testing.
  
  .Outputs
  script scoped action table
#>
function Get-ActionTable() {
	return $script:actionTable
}

<#
  .Description
  Get the traveled table. This is mainly for the purpose of testing.
  
  .Outputs
  script scoped traveled table
#>
function Get-TraveledTable() {
	return $script:traveledTable
}

<#
  .Description
  Main function. Trigger the release process.
  
  .Parameter ConfigFile
  Path to the configration file
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  True or False
#>
function Start-Release {
	param (
		[Parameter(Mandatory)]
		[string]$ConfigFile,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)

	# Reinitialise the script variables.
	$configuration = Get-Content $ConfigFile | Out-String | ConvertFrom-Json
	Initialize-GlobalVariables -Configuration $configuration
	
	# Loop through all repositories and determine the ones that need further action.
	Write-Host ""
	Write-Host "Check repositories for required actions."
	Write-Host "================================="
	foreach ($repository in $script:repositories) {
		Write-Host "# Check action for repository $($repository.Name)."
		# Assign output to log no none will be captured for return value
		$log = Get-Action `
			-RepositoryName $repository.Name `
			-TeamProjectName $TeamProjectName
	}
	
	# Perform actions on the repositories that require.
	Write-Host ""
	if ($script:actionTable.keys.count -gt 0) {
		Write-Host "# List of repositories that require actions"
		Write-Host $script:actionTable.keys
		foreach ($repository in $script:actionTable.keys) {
			Write-Host ""
			Write-Host "Take action on repository: $repository."
			Write-Host "================================="
			$version = $script:releaseConfig.repositories."$repository".version
			$releaseBranch = Get-ReleaseBranchRef `
				-RepositoryName $repository `
				-Version $version `
				-TeamProjectName $TeamProjectName
			if ($releaseBranch -ne $null) {
				Write-Host "# Process pull request on branch $releaseBranch."
				if (!$(Start-ProcessPullRequest `
					-RepositoryName $repository `
					-ReleaseBranch $releaseBranch `
					-TeamProjectName $TeamProjectName)) {
					Write-Host "# ERROR: Failed to process pull request."
					return $false
				}
			} else {
				Write-Host "# Bump the release version to $version."
				if (!$(Update-Version -RepositoryName $repository -Version $version)) {
					Write-Host "# ERROR: Failed to bump version."
					return $false
				}
			}
		}
	} else {
		Write-Host "# All target release versions have been tagged. No actions is required."
	}
	return $true
}

<#
  .Description
  This work on the current directory, performing updating of
  submodule references, updating package dependencies, commit
  the changes and create a pull request if needed.
  
  .Parameter Configuration
  A configuration object from a configuration file.
  
  .Parameter DepTeamProjectName
  Name of the repository team project to be used for
  dependency updates.
  
  .Parameter PrTeamProjectName
  Name of the repository team project to be used for
  creating pull request to main.
  
  .Outputs
  true or false
#>
function Update-CommitPushPullSub {
	param(
		[Parameter(Mandatory)]
		[object]$Configuration,
		[Parameter(Mandatory)]
		[string]$DepTeamProjectName,
		[Parameter(Mandatory)]
		[string]$PrTeamProjectName
	)
	
	Initialize-GlobalVariables -Configuration $Configuration
	
	# Check if the repository is part of the release
	$repoName = Get-RepositoryName
	$targetVersion = $script:releaseConfig.repositories."$repoName".version
	if ($targetVersion -eq $null) {
		Write-Host "# No release version is specified for $repoName. Stop."
		Write-Host "# Available repositories: $($script:repositories)"
		return $false
	}

	# If a tag already exists, don't update submodule or packages.
	if ($(Test-TagExist `
		-RepositoryName $repoName `
		-Version $targetVersion `
		-TeamProjectName $PrTeamProjectName)) {
		Write-Host "# ERROR: A tag for the target version $targetVersion already exists."
		return $false
	}
	
	# Checkout release branch to update
	Write-Host ""
	Write-Host "# Checkout release branch for version $targetVersion"
	if (!$(Get-ReleaseBranch `
		-Version $targetVersion `
		-TeamProjectName $PrTeamProjectName)) {
		return $false
	}

	# Update the submodule references
	Write-Host ""
	Write-Host "# Updating submodule references"
	$result = $(Update-SubmoduleReferences -Configuration $Configuration)
	Write-Host "Updated submodules: $result"
	if (!$result) {
		return $false
	}
	
	# Update the package dependencies
	Write-Host ""
	Write-Host "# Updating package dependencies"
	if (!$(Update-PackageDependencies `
		-Configuration $Configuration `
		-TeamProjectName $DepTeamProjectName)) {
		return $false
	}
	
	# Update the package version
	if (!$(Update-PackageVersion `
		-Configuration $Configuration `
		-TeamProjectName $PrTeamProjectName)) {
		return $false
	}

	# Commit and push any changes.
	Write-Host ""
	Write-Host "# Start commit and push changes"
	if (!$(Start-CommitAndPush)) {
		return $false
	}
	
	Write-Host ""
	Write-Host "Create Pull Request if one doesn't exist"
	Write-Host "================"
	$targetBranch = Get-TargetBranch -Version $targetVersion
	$pullRequest = Get-PullRequestToMain `
		-RepositoryName $repoName `
		-ReleaseBranch "refs/heads/$targetBranch" `
		-TeamProjectName $PrTeamProjectName
	if ($pullRequest -eq $null) {
		if (!(New-PullRequestToMain `
			-RepositoryName $repoName `
			-SourceBranchRef "refs/heads/$targetBranch" `
			-TeamProjectName $PrTeamProjectName)) {
			return $false
		}
	} else {
		Write-Host "# A pull request to 'main' already exists. No need to create a new one."
	}
	return $true
}

<#
  .Description
  This work on the current directory, performing updating of
  submodule references, updating package dependencies, commit
  the changes and create a pull request if needed.
  
  .Parameter ConfigFile
  Full path to the configuration file.
  
  .Parameter DepTeamProjectName
  Name of the repository team project to be used for
  dependency updates.
  
  .Parameter PrTeamProjectName
  Name of the repository team project to be used for
  creating pull request to main.
  
  .Outputs
  true or false
#>
function Update-CommitPushPull {
	param (
		[Parameter(Mandatory)]
		[string]$ConfigFile,
		[Parameter(Mandatory)]
		[string]$DepTeamProjectName,
		[Parameter(Mandatory)]
		[string]$PrTeamProjectName
	)

	# Reinitialise the script variables.
	$configuration = Get-Content $ConfigFile | Out-String | ConvertFrom-Json
	
	return Update-CommitPushPullSub `
		-Configuration $configuration `
		-DepTeamProjectName $DepTeamProjectName `
		-PrTeamProjectName $PrTeamProjectName
}

Export-ModuleMember -Function Start-Release
Export-ModuleMember -Function Update-CommitPushPullSub
Export-ModuleMember -Function Update-CommitPushPull