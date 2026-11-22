<#
  .Description
  Test if there exist a definition for each submodule.
  
  .Parameter Configuration
  The full configuration of the test environment
  
  .Parameter Submodules
  The list of submodules to be tested
  
  .Outputs
  true or false
#>
function Test-Submodules {
	param(
		[Parameter(Mandatory)]
		[object]$Configuration,
		[Parameter(Mandatory)]
		[string[]]$Submodules
	)
	
	foreach ($submodule in $Submodules) {
		if ($Configuration.repositories."$submodule" -eq $null) {
			Write-Host "# ERROR: No definition of submodule '$submodule' found."
			return $false
		}
	}
	return $true
}

<#
  .Description
  Test if tags are in valid format
  
  .Parameter Tags
  List of tags to be tested
  
  .Outputs
  true or false
#>
function Test-Tags {
	param(
		[Parameter(Mandatory)]
		[string[]]$Tags
	)
	
	foreach ($tag in $Tags) {
		if (!($tag -match "\d+\.\d+\.\d+")) {
			Write-Host "# ERROR: Invalid tag number '$tag'"
			return $false
		}
	}
	return $true
}

<#
  .Description
  Test if pull request definitions are valid
  
  .Parameter PullRequests
  List of pull requests to be tested.
  
  .Outputs
  true or false
#>
function Test-PullRequests {
	param(
		[Parameter(Mandatory)]
		[object[]]$PullRequests
	)
	
	foreach ($pr in $PullRequests) {
		if ($pr.source -eq $null) {
			Write-Host "# ERROR: No source reference is defined for pull request '$pr'"
			return $false
		}
		
		if ($pr.target -eq $null) {
			Write-Host "# ERROR: No target reference is defined for pull request '$pr'"
			return $false
		}

		# Validate comment option
		if ($pr.comment -ne $null `
			-and "$($pr.comment)" -ne "true" `
			-and "$($pr.comment)" -ne "$false") {
			Write-Host "# ERROR: Pull request comment option can only be true or false."
			return $false
		}
	}
	return $true
}

<#
  .Description
  Test if definitions triggers are valid. We currently
  only consider 'buildCompletion' trigger.
  
  .Parameter Triggers
  List of triggers to be tested
  
  .Outputs
  true or false
#>
function Test-Triggers {
	param(
		[Parameter(Mandatory)]
		[object[]]$Triggers
	)
	
	foreach ($trigger in $Triggers) {
		if ([string]::IsNullOrEmpty($trigger.definitionName)) {
			Write-Host "# ERROR: 'definitionName' is not defined in 'trigger' configuration. '$trigger'"
			return $false
		}
		
		if ("$trigger.requiresSuccessfulBuild" -ne "true" `
			-and "$trigger.requiresSuccessfulBuild" -ne "true") {
			Write-Host "# ERROR: 'requiresSuccessfulBuild' is not defined or not a boolean type. '$trigger'"
			return $false
		}
		
		if ($trigger.branchFilters -eq $null `
			-or $trigger.branchFilters.count -eq 0) {
			Write-Host "# ERROR: 'branchFilters' array cannot be undefined or empty. '$trigger'"
			return $false
		}
		
		if ($trigger.triggerType -eq "buildCompletion") {
			Write-Host "# ERROR: 'triggerType' can only be 'buildCompletion'. '$trigger'"
			return $false
		}
	}
	return $true
}

<#
  .Description
  Test if definitions are valid
  
  .Parameter Definitions
  List of defnitions to be tested
  
  .Outputs
  true or false
#>
function Test-Definitions {
	param(
		[Parameter(Mandatory)]
		[object[]]$Definitions
	)
	
	foreach ($definition in $Definitions) {
		# Test general settings
		if ([string]::IsNullOrEmpty($definition.name)) {
			Write-Host "# ERROR: Definition name cannot be empty or not defined. '$definition'"
			return $false
		}
		
		if ([string]::IsNullOrEmpty($definition.defaultBranch)) {
			Write-Host "# ERROR: 'defaultBranch' is not defined. '$definition'"
			return $false
		}
		
		if ([string]::IsNullOrEmpty($definition.yamlFileName)) {
			Write-Host "# ERROR: 'yamlFileName' is not defined. '$definition'"
			return $false
		}
		
		# Test triggers. We currently only consider 'buildCompletion' trigger.
		if (!(Test-Triggers -Triggers $definition.triggers)) {
			return $false
		}
	}
	return $true
}

<#
  .Description
  Test if branches are valid
  
  .Parameter Branches
  List of branches to be tested
  
  .Outputs
  true or false
#>
function Test-Branches {
	param(
		[Parameter(Mandatory)]
		[object[]]$Branches
	)
	
	foreach ($branch in $Branches) {
		if ([string]::IsNullOrEmpty($branch.name)) {
			Write-Host "# ERROR: 'name' cannot be empty. '$branch'"
			return $false
		}
		
		if ([string]::IsNullOrEmpty($branch.base)) {
			Write-Host "# ERROR: 'base' cannot be empty. '$branch'"
			return $false
		}
	}
	return $true
}

<#
  .Description
  Test if policies are valid
  
  .Parameter Policies
  List of policies to be tested
  
  .Outputs
  true or false
#>
function Test-Policies {
	param(
		[Parameter(Mandatory)]
		[object[]]$Policies
	)
	
	foreach ($policy in $Policies) {
		switch ($policy.type) {
			"Build"
			{
				if ([string]::IsNullOrEmpty($policy.definition)) {
					Write-Host "# ERROR: 'definition' cannot be empty. '$policy'"
					return $false
				}
				
				if ([string]::IsNullOrEmpty($policy.refName)) {
					Write-Host "# ERROR: 'refName' cannot be empty. '$policy'"
					return $false
				} elseif (!($policy.refName -match "refs/.*")) {
					Write-Host "# ERROR: 'refName' must start with'refs/'"
					return $false
				}
				
				if ([string]::IsNullOrEmpty($policy.matchKind)) {
					Write-Host "# ERROR: 'matchKind' cannot be empty. '$policy'"
					return $false
				}
			}
			"Required reviewers"
			{
				# Currently for this type we will always add a default user
				# to all repositories.
				break
			}
			Default
			{
				Write-Host "# ERROR: Only 'Build' and 'Required reviewers' policies are currently supported."
				return $false
			}
		}
	}
	return $true
}

<#
  .Description
  Verify if a configuration file is valid.
  
  .Parameter Configuration
  A configuration object, reflecting what is specified in the configuration file
  
  .Outputs
  true or false
#>
function Test-ConfigFile {
	param (
		[Parameter(Mandatory)]
		[object]$Configuration
	)
	
	Write-Host ""
	Write-Host "Verify input configuration file"
	Write-Host "==============================="
	# Test if repositories are empty
	
	if ($Configuration.repositories -ne $null) {
		foreach ($repoProperty in $Configuration.repositories | Get-Member -MemberType "NoteProperty") {
			Write-Host ""
			Write-Host "# Processing repository '$($repoProperty.name)'"
			$repository = $Configuration.repositories."$($repoProperty.name)"
			
			# Test missing submodule definition
			if ($respository.submodules -ne $null `
				-and $repository.submodules.count -gt 0 `
				-and !$(Test-Submodules `
				-Configuration $Configuration `
				-Submodules $repository.submodules)) {
				return $false
			}
			
			# Test valid tag
			if ($respository.tags -ne $null `
				-and $repository.tags.count -gt 0 `
				-and !$(Test-Tags -Tags $repository.tags)) {
				return $false
			}
			
			# Test pull request configuration
			if ($respository.pullRequests -ne $null `
				-and $repository.pullRequests.count -gt 0 `
				-and !$(Test-PullRequests -PullRequests $repository.pullRequests)) {
				return $false
			}
			
			# Test definitions
			if ($respository.definitions -ne $null `
				-and $repository.definitions.count -gt 0 `
				-and !$(Test-Definitions -Definitions $repository.definitions)) {
				return $false
			}
			
			# Test branches
			if ($respository.branches -ne $null `
				-and $repository.branches.count -gt 0 `
				-and !$(Test-Branches -Branches $repository.branches)) {
				return $false
			}
			
			# Test policies
			if ($respository.policies -ne $null `
				-and $repository.policies.count -gt 0 `
				-and !$(Test-Policies -Policies $repository.policies)) {
				return $false
			}
		}
	} else {
		Write-Host "# WARNINGS: Cannot find 'repositories' entry."
	}
	
	# Test cross-repository policies
	if ($Configuration.policies -ne $null `
		-and $Configuration.policies.count -gt 0 `
		-and !$(Test-policies -Policies $Configuration.policies)) {
		return $false
	}
	return $true
}