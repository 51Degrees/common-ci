<#
  ===================== Packages =====================
  .Description
  This module contains functions that perform actions
  on managing packages.
  For more information, please read description of
  each function.
#>

Using module 51DGitModule

# Global variables to be updated when one of the main APIs is called.
$script:releaseConfig = $null
$script:repositories = $null

class FileHandler {
	static [boolean]SetContent([string]$target, [string]$value) {
		Set-Content -NoNewline "$target" -Value $value
		return $?
	}
}

<#
  .Description
  Initialise the script variables
  
  .Parameter Configuration
  A Configuration object
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
  Update the pom.xml content with dependency version.
  
  .Parameter Dependencies
  An array of dependencies of the current repository
  
  .Parameter PomContent
  Content of the pom.xml to be updated.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  Updated content or $null of error occurs.
#>
function Update-MavenPackageFileContent {
	param (
		[Parameter(Mandatory)]
		[string[]]$Dependencies,
		[Parameter(Mandatory)]
		[string]$PomContent,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	Write-Host "Pom content $PomContent"
	foreach ($dependency in $Dependencies) {
		$versionVariableName = $script:repositories."$dependency".versionVariableName
		Write-Host "Version variable: " $versionVariableName
		if ([string]::IsNullOrEmpty($versionVariableName)) { continue }
		if ($PomContent -match "\<$versionVariableName\>") {
			Write-Host "# Version variable matches dependency $versionVariableName. Update."
			$dependencyVersion = $script:repositories."$dependency".version
			
			# Make sure that the version exists for the dependency. Else bail out.
			if (!$(Test-TagExist `
				-RepositoryName $dependency `
				-Version $dependencyVersion `
				-TeamProjectName $TeamProjectName)) {
				Write-Host "# ERROR: Tag $dependencyVersion for repository $dependency does not exist."
				return $null
			}
			
			$PomContent = $PomContent -replace `
				"\<$versionVariableName\>.*\</$versionVariableName\>", `
				"<$versionVariableName>$dependencyVersion</$versionVariableName>"
		} else {
			Write-Host "# Nothing to update for dependency $versionVariableName"
		}
	}
	return $PomContent
}

<#
  .Description
  Update dependencies of all Maven packages in a repository.
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  true or false
#>
function Update-MavenPackageDependencies {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	Write-Host ""
	Write-Host "Update Maven Package Dependencies"
	Write-Host "================================="
	
	$dependencies = $script:repositories."$RepositoryName".dependencies
	if ($dependencies -ne $null -and $dependencies.count -gt 0) {
		# Check if pom.xml exists
		if (Test-Path pom.xml) {
			$pomContent = $(Get-Content pom.xml -Raw)
			$updatedContent = Update-MavenPackageFileContent `
				-Dependencies $dependencies `
				-PomContent $pomContent `
				-TeamProjectName $TeamProjectName
			
			# Check if pom has been updated.
			if ($updatedContent -ne $null) {
				if ($updatedContent -ne $pomContent) {
					Write-Host "# Dependency version has been updated. Update the pom.xml content."
					if (![FileHandler]::SetContent("pom.xml", $updatedContent)) {
						Write-Host "# ERROR: Failed to update the pom.xml content."
						return $false
					}
					
					# Stage the change
					if (![GitHandler]::Add("pom.xml")) {
						Write-Host "# ERROR: Failed to stage the change."
						return $false
					}
				}
			} else {
				Write-Host "# ERROR: error occurs while updating the content of pom.xml"
				return $false
			}
		} else {
			Write-Host "# ERROR: No pom file is found at this directory. Nothing to update."
			return $false
		}
	} else {
		Write-Host "# There is no dependencies defined in configuration file. Skipped."
	}
	
	return $true
}

<#
  .Description
  Update dotnet package file content.
  
  .Parameter Dependencies
  A list of dependencies of the project that package file belongs to.
  
  .Parameter ProjectFileContent
  Content to be update of a project file.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  Updated file content or $null of error occured
#>
function Update-DotnetPackageFileContent {
	param (
		[Parameter(Mandatory)]
		[string[]]$Dependencies,
		[Parameter(Mandatory)]
		[string]$ProjectFileContent,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	# Update each .csproj file with dependency versions.
	foreach ($dependency in $Dependencies) {
		$packageName = $script:repositories."$dependency".packageName
		if ([string]::IsNullOrEmpty($packageName)) { continue }
		# Version 1 of xml markup for <PackageReference/>
		# This pattern has a match group names 'prefix' and 'suffix'.
		# That will be used to preserv the remaining of the markup,
		# apart from the version which will be updated.
		$dependencyVersion = $script:repositories."$dependency".version
		$matchPattern = "(?<prefix>\<PackageReference \s*Include=\`"$packageName.*\`" \s*Version=\`").*(?<suffix>\`"\s*/\>)"
		if ($ProjectFileContent -match "$matchPattern") {
			Write-Host "# Version variable matches dependency $packageName. Update."
			
			# Make sure that the version exists for the dependency. Else bail out.
			if (!$(Test-TagExist `
				-RepositoryName $dependency `
				-Version $dependencyVersion `
				-TeamProjectName $TeamProjectName)) {
				Write-Host "# ERROR: Tag $dependencyVersion for repository $dependency does not exist."
				return $null
			}
			
			# This reuse the matched group so make sure we don't lose the original package name.
			$replaceString = '${prefix}' + "$dependencyVersion" + '${suffix}'
			$ProjectFileContent = $ProjectFileContent -replace "$matchPattern",$replaceString
		}
		
		# Version 2 of xml markup for <PackageReference></PackageReference>
		$matchPattern = "(?<prefix>\<PackageReference \s*Include=\`"$packageName.*\`"\s*\>.*\r\n.*\<Version\>)(?<version>.*)(?<suffix>\</Version\>.*\r\n.*\</PackageReference\>)"
		if ($ProjectFileContent -match "$matchPattern") {
			Write-Host "# Version variable matches dependency $packageName. Update."
			
			# Make sure that the version exists for the dependency. Else bail out.
			if (!$(Test-TagExist `
				-RepositoryName $dependency `
				-Version $dependencyVersion `
				-TeamProjectName $TeamProjectName)) {
				Write-Host "# ERROR: Tag $dependencyVersion for repository $dependency does not exist."
				return $null
			}
			
			# This reuse the matched group so make sure we don't lose the original package name.
			$replaceString = '${prefix}' + "$dependencyVersion" + '${suffix}'
			$ProjectFileContent = $ProjectFileContent -replace "$matchPattern",$replaceString
		}
	}
	return $ProjectFileContent
}

<#
  .Description
  Update dependencies of all Dotnet packages in a repository.
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  true or false
#>
function Update-DotnetPackageDependencies {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	Write-Host ""
	Write-Host "Update Dotnet Package Dependencies"
	Write-Host "================================="
	
	$dependencies = $script:repositories."$RepositoryName".dependencies
	# Make sure only update if there are dependencies
	if ($dependencies -ne $null -and $dependencies.count -gt 0) {
		# Update each .csproj file.
		foreach ($project in $(Get-ChildItem -Filter *.csproj -Recurse)) {
			$projFileContent = $(Get-Content $project.FullName -Raw)
			$updatedContent = Update-DotnetPackageFileContent `
				-Dependencies $dependencies `
				-ProjectFileContent $projFileContent `
				-TeamProjectName $TeamProjectName
			
			# Check if .csproj has been updated.
			if ($updatedContent -ne $null) {
				if ($updatedContent -ne $projFileContent) {
					Write-Host "# Dependency version has been updated. Update the $($project.FullName) content."
					if (![FileHandler]::SetContent($project.FullName, $updatedContent)) {
						Write-Host "# ERROR: Failed to update the $project.FullName content."
						return $false
					}
					
					# Stage the change
					if (![GitHandler]::Add("$($project.FullName)")) {
						Write-Host "# ERROR: Failed to stage the change."
						return $false
					}
				}
			} else {
				Write-Host "# ERROR: error occurs while updating content of package file."
				return $false
			}
		}
	} else {
		Write-Host "# There is no dependencies defined in configuration file. Skipped."
	}
	
	return $true
}

<#
  .Description
  Take a package file content and update the input repository version.
  
  .Parameter RepositoryName
  Name of the dependency to update
  
  .Parameter PackageFileContent
  Content of the package file to update
  
  .Parameter IsRemotePackage
  Whether the current package file is remote_package.json.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  Updated file content. $null if something goes wrong.
#>
function Update-NodePackageDependency {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$PackageFileContent,
		[Parameter(Mandatory)]
		[boolean]$IsRemotePackage,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	$packageName = $script:repositories."$RepositoryName".packageName
	if ([string]::IsNullOrEmpty($packageName)) { return $PackageFileContent }
	# This pattern has a match group name 'name'. That will be used to preserve the actual matched package name.
	$matchPattern = "\`"(?<name>$packageName(\.[A-Za-z]+)*)\`"\s*:\s*\`".*\`""
	if ($PackageFileContent -match "$matchPattern") {
		Write-Host "# Version variable matches dependency $packageName. Try to update."
		$dependencyVersion = $script:repositories."$RepositoryName".version
		# Make sure that the version exists for the dependency. Else bail out.
		if (!$IsRemotePackage -and 
			!$(Test-TagExist `
				-RepositoryName $RepositoryName `
				-Version $dependencyVersion `
				-TeamProjectName $TeamProjectName)) {
			Write-Host "# ERROR: Tag $dependencyVersion for repository $RepositoryName does not exist."
			return $null
		}
		
		# This reuse the matched group so make sure we don't lose the original package name.
		$replaceString = '"${name}": "^' + $dependencyVersion + '"'
		$PackageFileContent = $PackageFileContent -replace "$matchPattern",$replaceString
	} else {
		Write-Host "# Nothing to update for dependency $packageName"
	}
	return $PackageFileContent
}

<#
  .Description
  Update a package file with a input list of dependencies.
  
  .Parameter RepositoryName
  Name of the current repository
  
  .Parameter dependencies
  List of dependencies obtained from configration file.
  
  .Parameter PackageFileName
  Name of the package file
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  true or false
#>
function Update-NodeDependenciesSub {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string[]]$Dependencies,
		[Parameter(Mandatory)]
		[string]$PackageFileName,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	# Update each file.
	foreach ($project in $(Get-ChildItem -Filter $PackageFileName -Recurse)) {
		$pkgFileContent = $(Get-Content $project.FullName -Raw)
		$changeMade = $false
		# Update each package file with dependency versions.
		foreach ($dependency in $Dependencies) {
			$returnedContent = Update-NodePackageDependency `
				-RepositoryName $dependency `
				-PackageFileContent $pkgFileContent `
				-IsRemotePackage $false `
				-TeamProjectName $TeamProjectName
			if ($returnedContent -eq $null) {
				Write-Host "# ERROR: Failed to update dependency $dependency"
				return $false
			}
			
			if ($returnedContent -ne $pkgFileContent) {
				$pkgFileContent = $returnedContent
				$changeMade = $true
			}
		}
		
		# If is remote_package.json, then also update internal dependencies.
		if ($PackageFileName -match "remote_package.json") {
			$returnedContent = Update-NodePackageDependency `
				-RepositoryName $RepositoryName `
				-PackageFileContent $pkgFileContent `
				-IsRemotePackage $true `
				-TeamProjectName $TeamProjectName
			if ($returnedContent -eq $null) {
				Write-Host "# ERROR: Failed to update dependency $dependency"
				return $false
			}
			
			if ($returnedContent -ne $pkgFileContent) {
				$pkgFileContent = $returnedContent
				$changeMade = $true
			}
		}
		
		# Check if package files have been updated.
		if ($changeMade) {
			Write-Host "# Dependency version has been updated. Update the $($project.FullName) content."
			if (![FileHandler]::SetContent($project.FullName, $pkgFileContent)) {
				Write-Host "# ERROR: Failed to update the $project.FullName content."
				return $false
			}
			
			# Stage the change
			if (![GitHandler]::Add("$($project.FullName)")) {
				Write-Host "# ERROR: Failed to stage the change."
				return $false
			}
		}
	}
	return $true
}

<#
  .Description
  Update dependencies of all Node packages in a repository.
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  true or false
#>
function Update-NodePackageDependencies {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	Write-Host ""
	Write-Host "Update Node Package Dependencies"
	Write-Host "================================="
	
	$dependencies = $script:repositories."$RepositoryName".dependencies
	# Make sure only update if there are dependencies
	if ($dependencies -ne $null -and $dependencies.count -gt 0) {
		# Update package.json files
		Write-Host "# Update package.json files"
		if (!$(Update-NodeDependenciesSub `
			-RepositoryName $RepositoryName `
			-Dependencies $dependencies `
			-PackageFileName "package.json" `
			-TeamProjectName $TeamProjectName)) {
			Write-Host "# ERROR: Failed to update 'package.json'"
			return $false
		}
		
		# Update remote-package.json files
		Write-Host "# Update remote_package.json files"
		if (!$(Update-NodeDependenciesSub `
			-RepositoryName $RepositoryName `
			-Dependencies $dependencies `
			-PackageFileName "remote_package.json" `
			-TeamProjectName $TeamProjectName)) {
			Write-Host "# ERROR: Failed to update 'remote_package.json'"
			return $false
		}
	} else {
		Write-Host "# There is no dependencies defined in configuration file. Skipped."
	}
	
	return $true
}

<#
  .Description
  Update dependencies of all Python packages in a repository.
  In Python, package version is determined by what being
  present at run time. Thus, this function only update the
  package version being used for testing pipeline.
  
  .Parameter Dependencies
  An array of dependencies
  
  .Parameter SharedVariableContent
  Content to be updated.
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  Updated content. $null if error occurs
#>
function Update-PythonPackageContent {
	param (
		[Parameter(Mandatory)]
		[string[]]$Dependencies,
		[Parameter(Mandatory)]
		[string]$SharedVariableContent,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	foreach ($dependency in $Dependencies) {
		$versionVariableName = $script:repositories."$dependency".versionVariableName
		if ([string]::IsNullOrEmpty($versionVariableName)) { continue }
		$matchPattern = "(?<prefix>name\s*:\s*$versionVariableName\s*\r\n\s*value\s*:\s*)'==.*'"
		if ($SharedVariableContent -match $matchPattern) {
			Write-Host "# Version variable matches dependency $versionVariableName. Update."
			$dependencyVersion = $script:repositories."$dependency".version
			
			# Make sure that the version exists for the dependency. Else bail out.
			if (!$(Test-TagExist `
				-RepositoryName $dependency `
				-Version $dependencyVersion `
				-TeamProjectName $TeamProjectName)) {
				Write-Host "# ERROR: Tag $dependencyVersion for repository $dependency does not exist."
				return $null
			}
			
			$replaceString = '${prefix}' + "'==$dependencyVersion'"
			$SharedVariableContent = $SharedVariableContent -replace `
				$matchPattern, `
				$replaceString
		} else {
			Write-Host "# Nothing to update for dependency $versionVariableName"
		}
	}
	return $SharedVariableContent
}

<#
  .Description
  Update dependencies of all Python packages in a repository.
  In Python, package version is determined by what being
  present at run time. Thus, this function only update the
  package version being used for testing pipeline.
  
  .Parameter RepositoryName
  Name of a repository
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  true or false
#>
function Update-PythonPackageDependencies {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	Write-Host ""
	Write-Host "Update Python Package Dependencies"
	Write-Host "================================="
	
	$dependencies = $script:repositories."$RepositoryName".dependencies
	if ($dependencies -ne $null -and $dependencies.count -gt 0) {
		# Check if shared-variables.yml exists
		if (Test-Path ci\shared-variables.yml) {
			$sharedVariablesContent = $(Get-Content ci\shared-variables.yml -Raw)
			$updatedContent = Update-PythonPackageContent `
				-Dependencies $dependencies `
				-SharedVariableContent $sharedVariablesContent `
				-TeamProjectName $TeamProjectName
			
			if ($updatedContent -ne $null) {
				# Check if shared-variables.yml has been updated.
				if ($updatedContent -ne $sharedVariablesContent) {
					Write-Host "# Dependency version has been updated. Update the shared-variables.yml content."
					if (![FileHandler]::SetContent("ci\shared-variables.yml", $updatedContent)) {
						Write-Host "# ERROR: Failed to update the shared-variables.yml content."
						return $false
					}
					
					# Stage the change
					if (![GitHandler]::Add("ci\shared-variables.yml")) {
						Write-Host "# ERROR: Failed to stage the change."
						return $false
					}
				}
			} else {
				Write-Host "# ERROR: error occured during the update of the shared-variables.yml"
				return $false
			}
		} else {
			Write-Host "# No shared-variables.yml file is found at this directory. Nothing to update."
		}
	} else {
		Write-Host "# There is no dependencies defined in configuration file. Skipped."
	}
	
	return $true
}

<#
  .Description
  Update dependencies of all packages in a repository.
  This determine the type of package based on repository name.
  Any change will be automatically staged.
  
  NOTE: This check if a required version exist for
  each valid dependency. If none is found, it will result
  in a false.
  
  .Parameter Configuration
  A configuration object
  
  .Parameter TeamProjectName
  Name ofthe repository team project
  
  .Outputs
  true or false
#>
function Update-PackageDependencies {
	param (
		[Parameter(Mandatory)]
		[object]$Configuration,
		[Parameter(Mandatory)]
		[string]$TeamProjectName
	)
	
	Write-Host ""
	Write-Host "# Update package dependencies"
	Write-Host "============================"
	
	# Initialise the script variables
	Initialize-GlobalVariables -Configuration $Configuration
	
	# Get repository name
	$repoName = Get-RepositoryName
	
	$succeeded = $true
	# Determine the type of package based on languages
	switch -Wildcard ("$repoName") {
		"*java" {
			Write-Host "# $repoName is a Maven package."
			$succeeded = Update-MavenPackageDependencies `
				-RepositoryName $repoName -TeamProjectName $TeamProjectName
			Break
		}
		"*dotnet" {
			Write-Host "# $repoName is a Dotnet package."
			$succeeded = Update-DotnetPackageDependencies `
				-RepositoryName $repoName -TeamProjectName $TeamProjectName
			Break
		}
		"*node" {
			Write-Host "# $repoName is a Node package."
			$succeeded = Update-NodePackageDependencies `
				-RepositoryName $repoName -TeamProjectName $TeamProjectName
			Break
		}
		"*python" {
			Write-Host "# $repoName is a Python package."
			$succeeded = Update-PythonPackageDependencies `
				-RepositoryName $repoName -TeamProjectName $TeamProjectName
			Break
		}
		Default {
			Write-Host "# $repoName is of type that do not need to update package."
			Break
		}
	}
	
	return $succeeded
}

Export-ModuleMember -Function Update-PackageDependencies