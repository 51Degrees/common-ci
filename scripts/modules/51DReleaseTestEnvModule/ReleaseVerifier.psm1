<#
  ===================== Release Verifier =====================
  .Description
  This module contains functions that verifies if the release
  process has produced the expected results as described in
  the input configuration. This input configuration is the release
  configuration used by the release process.
#>

Using module 51DEnvironmentModule
Using module 51DGitModule
Using module 51DPackageModule


<#
  .Description
  Verify dependencies of all Maven packages in a repository.
  
  .Parameter RepositoryName
  Name of the current repository
  
  .Parameter RepositoryConfig
  A configuration object which contains expected release results
  as described in the config file.
  
  .Parameter Repositories
  A repositories object which contains all release repositories
  as described in the config file.
  
  .Outputs
  true or false
#>
function Test-MavenPackageDependencies {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$RepositoryConfig,
		[Parameter(Mandatory)]
		[object]$Repositories
	)
	
	Write-Host ""
	Write-Host "Test Maven Package Dependencies"
	Write-Host "================================="
	
	$dependencies = $Repositories."$RepositoryName".dependencies
	if ($dependencies -ne $null -and $dependencies.count -gt 0) {
		# Check if pom.xml exists
		if (Test-Path pom.xml) {
			$pomContent = $(Get-Content pom.xml -Raw)
			foreach ($dependency in $dependencies) {
				Write-Host "# Checking dependency '$dependency'"
				$versionVariableName = $Repositories."$dependency".versionVariableName
				if ([string]::IsNullOrEmpty($versionVariableName)) { continue }
				if ($pomContent -match "\<$versionVariableName\>(?<version>.*)\</$versionVariableName\>") {
					Write-Host "# Version variable matches dependency '$versionVariableName'."
					$dependencyVersion = $Repositories."$dependency".version
					if ($Matches['version'] -ne $dependencyVersion) {
						Write-Host "# FAIL: Version '$($Matches['version'])' of $dependency does not match $dependencyVersion"
						return $false
					}
				}
			}
		} else {
			Write-Host "# WARNING: No pom file is found at this directory. Nothing to verify."
		}
	} else {
		Write-Host "# There is no dependencies defined in configuration file. Skipped."
	}
	
	Write-Host "# OK"
	return $true
}

<#
  .Description
  Verify dependencies of all Dotnet packages in a repository.
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter RepositoryConfig
  A configuration object which contains expected release results
  as described in the config file.
  
  .Parameter Repositories
  A repositories object which contains all release repositories
  as described in the config file.
  
  .Outputs
  true or false
#>
function Test-DotnetPackageDependencies {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$RepositoryConfig,
		[Parameter(Mandatory)]
		[object]$Repositories
	)
	
	Write-Host ""
	Write-Host "Test Dotnet Package Dependencies"
	Write-Host "================================="
	
	$dependencies = $Repositories."$RepositoryName".dependencies
	# Make sure only test if there are dependencies
	if ($dependencies -ne $null -and $dependencies.count -gt 0) {
		# Test each .csproj file.
		foreach ($project in $(Get-ChildItem -Filter *.csproj -Recurse)) {
			Write-Host "# Working on project $project"
			$projFileContent = $(Get-Content $project.FullName -Raw)
			# Test each .csproj file with dependency versions.
			foreach ($dependency in $dependencies) {
				$packageName = $Repositories."$dependency".packageName
				if ([string]::IsNullOrEmpty($packageName)) { continue }
				
				# This pattern has a match group name 'name'. That will be used to preserve the actual matched package name.
				$matchPattern = "\<PackageReference \s*Include=\`"(?<name>$packageName.*)\`" \s*Version=\`"(?<version>\d+\.\d+\.\d+)\`"\s*/\>"
				if ($projFileContent -match "$matchPattern") {
					Write-Host "# Version variable matches dependency $packageName."
					$dependencyVersion = $Repositories."$dependency".version
					if ($Matches['version'] -ne $dependencyVersion) {
						Write-Host "# FAIL: Version '$($Matches['version'])' of $dependency does not match $dependencyVersion"
						return $false
					}
				}
				
				# This pattern has a match group name 'name'. That will be used to preserve the actual matched package name.
				$matchPattern = "(?<prefix>\<PackageReference \s*Include=\`"$packageName.*\`"\s*\>.*\r\n.*\<Version\>)(?<version>\d+\.\d+\.\d+)(?<suffix>\</Version\>.*\r\n.*\</PackageReference\>)"
				if ($projFileContent -match "$matchPattern") {
					Write-Host "# Version variable matches dependency $packageName."
					$dependencyVersion = $Repositories."$dependency".version
					if ($Matches['version'] -ne $dependencyVersion) {
						Write-Host "# FAIL: Version '$($Matches['version'])' of $dependency does not match $dependencyVersion"
						return $false
					}
				}
				
				# This pattern has a match group name 'name'. That will be used to preserve the actual matched package name.
				$matchPattern = "(?<prefix>\<HintPath\>\s*.*$packageName.*)(?<version>\d+\.\d+\.\d+)(?<suffix>\\lib.*\<\/HintPath\>)"
				if ($projFileContent -match "$matchPattern") {
					Write-Host "# Version variable matches dependency $packageName."
					$dependencyVersion = $Repositories."$dependency".version
					if ($Matches['version'] -ne $dependencyVersion) {
						Write-Host "# FAIL: Version '$($Matches['version'])' of $dependency does not match $dependencyVersion"
						return $false
					}
				}
			}
		}
		
		# Test each packages.config file.
		foreach ($project in $(Get-ChildItem -Filter packages.config -Recurse)) {
			Write-Host "# Working on project $project"
			$projFileContent = $(Get-Content $project.FullName -Raw)
			# Test each packages.config file with dependency versions.
			foreach ($dependency in $dependencies) {
				$packageName = $Repositories."$dependency".packageName
				if ([string]::IsNullOrEmpty($packageName)) { continue }
				# This pattern has a match group name 'name'. That will be used to preserve the actual matched package name.
				$matchPattern = "\<PackageReference \s*Include=\`"(?<name>$packageName.*)\`" \s*Version=\`"(?<version>\d+\.\d+\.\d+)\`"\s*/\>"
				$matchPattern = "(?<prefix>\<package \s*id=\`"$packageName.*\`" \s*version=\`")(?<version>\d+\.\d+\.\d+)(?<suffix>\`"\s*targetFramework=\`".*\`"\s*/\>)"
				if ($projFileContent -match "$matchPattern") {
					Write-Host "# Version variable matches dependency $packageName."
					$dependencyVersion = $Repositories."$dependency".version
					if ($Matches['version'] -ne $dependencyVersion) {
						Write-Host "# FAIL: Version '$($Matches['version'])' of $dependency does not match $dependencyVersion"
						return $false
					}
				}
			}
		}
	} else {
		Write-Host "# There is no dependencies defined in configuration file. Skipped."
	}
	
	
	Write-Host "# OK"
	return $true
}

<#
  .Description
  Take a package file content and verify the input repository version.
  
  .Parameter RepositoryName
  Name of the repository to verify
  
  .Parameter Repositories
  An object of all repositories as specified in the configuration file.
  
  .Parameter PackageFileContent
  Content of the package file to verify
  
  .Parameter IsRemotePackage
  Whether the current package file is remote_package.json.
  
  .Outputs
  true or false
#>
function Test-NodePackageDependency {
	param (
		[string]$RepositoryName,
		[object]$Repositories,
		[string]$PackageFileContent,
		[boolean]$IsRemotePackage
	)
	
	$packageName = $Repositories."$RepositoryName".packageName
	if ([string]::IsNullOrEmpty($packageName)) { return $PackageFileContent }

	# This pattern has a match group name 'name'. That will be used to preserve the actual matched package name.
	$matchPattern = "\`"(?<name>$packageName(\.[A-Za-z]+)*)\`"\s*:\s*\`"\^(?<version>\d+\.\d+\.\d+)\`""
	if ($PackageFileContent -match "$matchPattern") {
		Write-Host "# Version variable matches dependency $packageName."
		$dependencyVersion = $Repositories."$RepositoryName".version
		# Make sure that the version exists for the dependency. Else bail out.
		if ($Matches['version'] -ne $dependencyVersion) {
			Write-Host "# FAIL: Expected '$dependencyVersion' for $dependency but got $($Matches['version'])"
			return $false
		}
	} else {
		Write-Host "# Nothing to verify for dependency $packageName"
	}
	return $true
}

<#
  .Description
  Verify a package file with a input list of dependencies.
  
  .Parameter RepositoryName
  Name of the current repository
  
  .Parameter Repositories
  An object that contains all repositories configuration as specified
  in the configuration file.
  
  .Parameter PackageFileName
  Name of the package file
  
  .Outputs
  true or false
#>
function Test-NodeDependenciesSub {
	param (
		[string]$RepositoryName,
		[object]$Repositories,
		[string]$PackageFileName
	)
	
	# Verify each file.
	foreach ($package in $(Get-ChildItem -Filter $PackageFileName -Recurse)) {
		Write-Host "# Working on package '$($package.FullName)'"
		$pkgFileContent = $(Get-Content $package.FullName -Raw)
		$changeMade = $false
		$dependencies = $Repositories."$RepositoryName".dependencies
		# Verify each package file with dependency versions.
		foreach ($dependency in $dependencies) {
			Write-Host "# Verifying dependency '$dependency'"
			if (!$(Test-NodePackageDependency `
				-RepositoryName $dependency `
				-Repositories $Repositories `
				-PackageFileContent $pkgFileContent `
				-IsRemotePackage $false)) {
				return $false
			}
		}
		
		# If is remote_package.json, then also verify internal dependencies.
		if ($PackageFileName -match "remote_package.json") {
			Write-Host "# Is remote_package.json so varifying self."
			if (!$(Test-NodePackageDependency `
				-RepositoryName $RepositoryName `
				-Repositories $Repositories `
				-PackageFileContent $pkgFileContent `
				-IsRemotePackage $true)) {
				return $false
			}
		}
	}
	return $true
}

<#
  .Description
  Verify dependencies of all Node packages in a repository.
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter RepositoryConfig
  A configuration object which contains expected release results
  as described in the config file.
  
  .Parameter Repositories
  A repositories object which contains all release repositories
  as described in the config file.
  
  .Outputs
  true or false
#>
function Test-NodePackageDependencies {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$RepositoryConfig,
		[Parameter(Mandatory)]
		[object]$Repositories
	)
	
	Write-Host ""
	Write-Host "Verify Node Package Dependencies"
	Write-Host "================================="
	
	$dependencies = $RepositoryConfig.dependencies
	# Make sure only verify if there are dependencies
	if ($dependencies -ne $null -and $dependencies.count -gt 0) {
		# Verify package.json files
		Write-Host "# Verify package.json files"
		if (!$(Test-NodeDependenciesSub `
			-RepositoryName $RepositoryName `
			-Dependencies $dependencies `
			-Repositories $Repositories `
			-PackageFileName "package.json")) {
			Write-Host "# ERROR: 'package.json' is not up to date"
			return $false
		}
		
		# Verify remote-package.json files
		Write-Host "# Verify remote_package.json files"
		if (!$(Test-NodeDependenciesSub `
			-RepositoryName $RepositoryName `
			-Dependencies $dependencies `
			-Repositories $Repositories `
			-PackageFileName "remote_package.json")) {
			Write-Host "# ERROR: 'remote_package.json' is not up to date"
			return $false
		}
	} else {
		Write-Host "# There is no dependencies defined in configuration file. Skipped."
	}
	
	Write-Host "# OK"
	return $true
}

<#
  .Description
  Verify dependencies of all Python packages in a repository.
  
  .Parameter RepositoryName
  Name of the current repository
  
  .Parameter RepositoryConfig
  A configuration object which contains expected release results
  as described in the config file.
  
  .Parameter Repositories
  A repositories object which contains all release repositories
  as described in the config file.
  
  .Outputs
  true or false
#>
function Test-PythonPackageDependencies {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$RepositoryConfig,
		[Parameter(Mandatory)]
		[object]$Repositories
	)
	
	Write-Host ""
	Write-Host "Test Python Package Dependencies"
	Write-Host "================================="
	
	$dependencies = $RepositoryConfig.dependencies
	if ($dependencies -ne $null -and $dependencies.count -gt 0) {
		# Check if shared-variables.yml exists
		if (Test-Path ci\shared-variables.yml) {
			$sharedVariablesContent = $(Get-Content ci\shared-variables.yml -Raw)
			$changeMade = $false
			foreach ($dependency in $dependencies) {
				Write-Host "# Verifying dependency '$dependency'"
				$versionVariableName = $Repositories."$dependency".versionVariableName
				if ([string]::IsNullOrEmpty($versionVariableName)) { continue }
				if ($sharedVariablesContent -match "(?<prefix>name\s*:\s*$versionVariableName\s*\r\n\s*value\s*:\s*)'==(?<version>\d+\.\d+\.\d+)'") {
					Write-Host "# Version variable matches dependency $versionVariableName. Verify."
					Write-Host $Matches['prefix']
					$dependencyVersion = $Repositories."$dependency".version
					
					if ($Matches['version'] -ne $dependencyVersion) {
						Write-Host "# FAIL: Expected '$dependencyVersion' for '$dependency' but get '$($Matches['version'])"
						return $false
					}
				}
			}
		}
	} else {
		Write-Host "# There is no dependencies defined in configuration file. Skipped."
	}
	
	Write-Host "# OK"
	return $true
}

<#
  .Description
  Work on the local git repository. Verify if current repository
  matches all the expected package dependencies versions.
  
  .Parameter RepositoryName
  Name of the current repository
  
  .Parameter RepositoryConfig
  Expected configuration of a repository
  
  .Parameter Repositories
  A list of repositories configurations as specified
  in the configuration file.
  
  .Outputs
  true or false
#>
function Test-PackageDependencies {
	param(
		[Parameter(Mandatory)]
		[object]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$RepositoryConfig,
		[Parameter(Mandatory)]
		[object]$Repositories
	)
	
	Write-Host ""
	Write-Host "# Test package depedencies"
	Write-Host "============================"
	
	$pass = $true
	# Determine the type of package based on languages
	switch -Wildcard ("$RepositoryName") {
		"*java" {
			Write-Host "# $RepositoryName is a Maven package."
			$pass = Test-MavenPackageDependencies `
				-RepositoryName $RepositoryName `
				-RepositoryConfig $RepositoryConfig `
				-Repositories $Repositories
			Break
		}
		"*dotnet" {
			Write-Host "# $RepositoryName is a Dotnet package."
			$pass = Test-DotnetPackageDependencies `
				-RepositoryName $RepositoryName `
				-RepositoryConfig $RepositoryConfig `
				-Repositories $Repositories
			Break
		}
		"*node" {
			Write-Host "# $RepositoryName is a Node package."
			$pass = Test-NodePackageDependencies `
				-RepositoryName $RepositoryName `
				-RepositoryConfig $RepositoryConfig `
				-Repositories $Repositories
			Break
		}
		"*python" {
			Write-Host "# $RepositoryName is a Python package."
			$pass = Test-PythonPackageDependencies `
				-RepositoryName $RepositoryName `
				-RepositoryConfig $RepositoryConfig `
				-Repositories $Repositories
			Break
		}
		Default {
			Write-Host "# $RepositoryName is of type that do not require package dependencies."
			Break
		}
	}
	
	Write-Host "# OK"
	return $pass
}

<#
  .Description
  Work on the local git repository. Verify if current repository
  matches all the expected submodule references.
  
  .Parameter RepositoryConfig
  Expected configuration of a repository
  
  .Parameter Repositories
  A list of repositories configurations as specified
  in the configuration file.
  
  .Outputs
  true or false
#>
function Test-SubmoduleReferences {
	param(
		[Parameter(Mandatory)]
		[object]$RepositoryConfig,
		[Parameter(Mandatory)]
		[object]$Repositories
	)
	
	foreach ($submodule in $(git config --file .gitmodules --name-only --get-regexp path)) {
		Write-Host ""
		Write-Host "# Process submodule path $submodule."
		$submodulePath = Find-SubmodulePath -GitSubmodulePath $submodule
		if ($submodulePath -ne $null) {
			Write-Host "# Path $submodulePath extracted."
			Push-Location $submodulePath
			
			# Get repo name
			$subRepoName = Get-RepositoryName
			Write-Host "# Processing module $subRepoName."
			
			# Check and verify the submodule to the correct tag.
			$targetTag = $Repositories."$subRepoName".version
			Write-Host "# Checking tag $targetTag"
			
			# Get all tag
			Write-Host "# Fetch all tags"
			if (![GitHandler]::FetchAllTags()) {
				Write-Host "# ERROR: Failed to fetch tags. Cannot reliably check submodule deployment."
				Pop-Location
				return $false
			}
			
			$tagFound = $false
			if ($targetTag -ne $null) {
				$curTag = git describe --tags
				if ($curTag -match "\d+\.\d+\.\d+(\+\d+)?" `
					-and $curTag -like "$targetTag*") {
					$tagFound = $true
				} else {
					Write-Host "# FAIL: Current tag '$curTag' does not match expected tag '$targetTag'"
				}
			} else {
				# If no version is found from the configuration file.
				# Treat it as nothing to be changed for this submodule.
				Write-Host "# No target version has been specified for $subRepoName. No verification required."
				$tagFound = $true
			}
			
			Pop-Location
			
			# Exit if not all tags have been found.
			if (!$tagFound) {
				Write-Host "# ERROR: Current HEAD for submodule $submodule not referencing the correct tag."
				return $false
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
  Work on the local git repository. Verify if current repository
  matches all the branching and GitVersion.yml format.
  
  .Parameter RepositoryConfig
  Expected configuration of a repository
  
  .Outputs
  true or false
#>
function Test-GitVersion {
	param(
		[Parameter(Mandatory)]
		[object]$RepositoryConfig
	)
	
	# Check if GitVersion.yml exists and has the right format.
	if (Test-Path "$($(Get-Location).Path)\GitVersion.yml") {
		$gitVersionFileContent = Get-Content "$($(Get-Location).Path)\GitVersion.yml" -Raw
		if ($gitVersionFileContent `
			-match ".*next-version(\s)*:(\s)*(?<version>\d+\.\d+\.\d+).*") {
			if ($Matches['version'] -ne $RepositoryConfig.version) {
				Write-Host "# FAIL: GitVersion.yaml does not specify the correct version '$($RepositoryConfig.version)'"
				Write-Host "# FAIL: The found version is $($Matches['version'])"
				return $false
			}
		} else {
			Write-Host "# FAIL: not next-version found in GitVersion.yml"
			return $false
		}
	} else {
		Write-Host "# FAIL: GitVersion.yml does not exist"
		return $false
	}
	Write-Host "# OK"
	return $true
}

<#
  .Description
  Checkout a repository and its main branch
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  true or false
#>
function Use-Repository {
	param(
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	Write-Host ""
	Write-Host "# Clone repository $RepositoryName"
	
	$mainBranch = Get-MainBranchRef `
		-RepositoryName $RepositoryName `
		-TeamProjectName $TeamProjectName
	Write-Host "# Main branch ref is '$mainBranch'"
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
			
			Pop-Location
		} else {
			Write-Host "# ERROR: Failed to clone the remote url $remoteUrl"
			return $false
		}
	} else {
		Write-Host "# ERROR: No remote url found for repository $RepositoryName."
		return $false
	}
	return $true
}

<#
  .Description
  Verify if the current state of a repository match
  the expectation specified in the configuration file.
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter RepositoryConfig
  A repository configuration object
  
  .Parameter Repositories
  A list of repositories configurations as specified
  in the configuration file.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  true or false
#>
function Test-Repository {
	param(
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$RepositoryConfig,
		[Parameter(Mandatory)]
		[object]$Repositories,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	Write-Host ""
	Write-Host "# Verifying repository $RepositoryName"
	# Checkout the repository
	if (!$(Use-Repository -RepositoryName $RepositoryName -TeamProjectName $TeamProjectName)) {
		Write-Host "# ERROR: Failed to clone and checkout the 'main' branch of repository $RepositoryName"
		Pop-Location
		return $false
	}
	
	# CD to the repository
	Push-Location $RepositoryName
	
	# Verify if tag exist
	Write-Host ""
	Write-Host "# Verify if tag $($RepositoryConfig.version) exists"
	if (!$(Test-TagExist `
		-RepositoryName $RepositoryName `
		-Version $RepositoryConfig.version `
		-TeamProjectName $TeamProjectName)) {
		Write-Host "# FAIL: Not all tags exist"
		Pop-Location
		return $false
	}
	
	# Verify if release/hotfix branch and GitVersion.yml exist
	# Check if release/hotfix branch exists
	Write-Host ""
	Write-Host "# Check if GitVersion.yml exists. If not skip."
	if ($(Get-ReleaseBranchRef `
		-RepositoryName $RepositoryName `
		-Version $RepositoryConfig.version `
		-TeamProjectName $TeamProjectName) -eq $null) {
		if (!$(Test-GitVersion -RepositoryConfig $RepositoryConfig)) {
			Write-Host "# FAIL: GitVersion.yml is not updated as expected"
			Pop-Location
			return $false
		}
	}
	
	# Verify if submodules reference are up to date
	Write-Host ""
	Write-Host "# Check if submodule references are up to date"
	if (!$(Test-SubmoduleReferences `
		-RepositoryConfig $RepositoryConfig `
		-Repositories $Repositories)) {
		Write-Host "# FAIL: Not all submodule references are updated"
		Pop-Location
		return $false
	}
	
	# Verify if packages version are up to date
	Write-Host ""
	Write-Host "# Check if package dependency versions are up to date."
	if (!$(Test-PackageDependencies `
		-RepositoryName $RepositoryName `
		-RepositoryConfig $RepositoryConfig `
		-Repositories $Repositories)) {
		Write-Host "# FAIL: Not all package dependencies are updated"
		Pop-Location
		return $false
	}
	
	# CD output of the repository
	Pop-Location
	
	return $true
}

<#
  .Description
  Take a list of repositories configurations and
  verify the expected output. This creates a folder
  named 'workpace' at the current location to checkout
  the repositories for testing.
  
  .Parameter Repositories
  A list of repositories configurations as specified
  in the configuration file.
  
  .Parameter Force
  Force create a 'workplace' folder
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  true or false
#>
function Test-Repositories {
	param(
		[Parameter(Mandatory)]
		[object]$Repositories,
		[switch]$Force = $false,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	Write-Host ""
	Write-Host "Verify repositories"
	Write-Host "==================="
	
	Write-Host "# A folder named 'workplace' will be created to checkout the target repositories for testing."
	Write-Host "# Please confirm that you want to proceed."
	Write-Host "# Y[Yes] N[No]"
	if (!$Force) {
		$answer = Read-Host -Prompt "# Answer"
		if (!$($answer -match "Y|Yes")) {
			Write-Host "# Stopped"
			return $true
		}
	}

	Write-Host "# Create a working folder"
	$rc = New-Item -Type "directory" -Path workplace
	if (!(Test-Path "$($(Get-Location).Path)/workplace")) {
		Write-Host "# ERROR: Failed to create a working folder"
		return $false
	}
	$rc = Push-Location workplace
	
	foreach ($repository in $($Repositories | Get-Member -MemberType NoteProperty)) {
		Write-Host "# Processing repository '$($repository.Name)'"
		if (!$(Test-Repository `
			-RepositoryName $repository.Name `
			-RepositoryConfig $Repositories."$($repository.Name)" `
			-Repositories $Repositories `
			-TeamProjectName $TeamProjectName)) {
			Write-Host "# FAIL: Output for repository '$($repository.Name)' does not match expection."
			return $false
		}
	}
	$rc = Pop-Location
	return $true
}

<#
  .Description
  Read a config file and verify that the results
  specified has been met.
  
  .Parameter ConfigFile
  Full path to the configuration file
  
  .Outputs
  true or false
#>
function Test-Release {
	param(
		[Parameter(Mandatory)]
		[string]$ConfigurationFile
	)

	Write-Host ""
	Write-Host "Read input configuration file"
	Write-Host "============================="
	# Check file existance
	if (!(Test-Path $ConfigurationFile)) {
		Write-Host "# ERROR: File $ConfigurationFile does not exist."
		return $false
	}
	
	# Get content of configuration file
	$config = Get-Content $ConfigurationFile | Out-String | ConvertFrom-Json
	if (!$?) {
		Write-Host "# ERROR: Failed to get content of the configuration file $ConfigurationFile."
		return $false
	}
	
	$result = $(Test-Repositories `
		-Repositories $config.repositories `
		-TeamProjectName "$([EnvironmentHandler]::GetEnvironmentVariable($Env:SYSTEM_TEAMPROJECTID))")
	Write-Host "Result $result"
	
	# Verify all repositories
	if (!$result) {
		Write-Host "# FAIL: Actual results do not match what is specified."
		return $false
	}
	
	# Actual results match what is specified.
	Write-Host "# PASS"
	return $true
}