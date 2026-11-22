<#
  ===================== Testing =====================
  .Description
  This module contains functions that supports testing
  of the release process.
  For more information, please read description of
  each function.
#>

Using module 51DAuthorizationModule
Using module .\SharedVariables.psm1

<#
  .Description
  This function removes all Cross-Repository 'Required reviewers' policies
  of Release Test Environment, as other policies are most likely default
  policies.
  
  .Outputs
  true or false
#>
function Remove-AllPolicies {
	Write-Host ""
	Write-Host "Remove all Cross-Repository policies"
	Write-Host "===================================="
	
	$url = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/policy/configurations?api-version=6.0"
	
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	if (!$(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to get all policies.")) {
		return $false
	}
	
	$content = $response.content | Out-String | ConvertFrom-Json
	foreach ($policy in $content.value) {
		# Only remove policies that adds required reviewers
		if ($policy.type.name -ne "Required reviewer") {
			$url = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/policy/configurations/$($policy.id)?api-version=6.0"
			$response = Invoke-WebRequest `
			-URI $url `
			-Headers @{
				Authorization = "$([Authorization]::AuthorizationString)"
			} `
			-Method DELETE
			if (!$(Test-RestResponse `
				-Response $response `
				-ErrorMessage "Failed to delete policy $($policy.id).")) {
				return $false
			}
		}
	}
	return $true
}

<#
  .Description
  This function removes all definitions of Release Test
  Environments
  
  .Outputs
  true or false
#>
function Remove-AllDefinitions {
	Write-Host ""
	Write-Host "Remove all definitions"
	Write-Host "======================"
	
	$url = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/build/definitions?api-version=6.0"
	
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	if (!$(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to get all definitions.")) {
		return $false
	}
	
	$content = $response.content | Out-String | ConvertFrom-Json
	foreach ($definition in $content.value) {
		$url = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/build/definitions/$($definition.id)?api-version=6.0"
		$response = Invoke-WebRequest `
		-URI $url `
		-Headers @{
			Authorization = "$([Authorization]::AuthorizationString)"
		} `
		-Method DELETE
		if (!$(Test-RestResponse `
			-Response $response `
			-ErrorMessage "Failed to delete definition $($definition.id).")) {
			return $false
		}
	}
	return $true
}

<#
  .Description
  WARNINGS: Be very careful when using this function. This function
  will try it best to prevent deleting anything related to Production,
  but user should also take caution when using it. User Account used
  to run this function should never be granted permission to 'Force Push'
  in Production environment. Deleted repositories will be moved to
  'Recycle Bin' so it is possible to restore them once they have been
  deleted. However, if they have been deleted from the 'Recycle Bin'
  then unless a copy of the repository is kept elsewhere, the repository
  cannot be restored.
  Remove a repository from a test environment.

  .Parameter Repository
  A repository object returned by the AzureDevops api
  
  .Outputs
  true or false
#>
function Remove-Repository {
	param (
		[Parameter(Mandatory)]
		[object]$Repository
	)

	Write-Host ""
	Write-Host "Deleting repository '$($Repository.name)'"
	Write-Host "======================================="
	if ($Repository.name -eq $([TestEnvPredefinedVariables]::MandatoryRepositoryName)) {
		Write-Host "# ERROR: '$([TestEnvPredefinedVariables]::MandatoryRepositoryName)' is a mandatory, so cannot be deleted."
		return $false
	}
	
	$url = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/git/repositories/$($Repository.id)?api-version=6.0"
	
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method DELETE
	
	return $(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to delete repository '$($Repository.name)'.")
}

<#
  .Description
  WARNINGS: Be very careful when using this function. This function
  will try it best to prevent deleting anything related to Production,
  but user should also take caution when using it. User Account used
  to run this function should never be granted permission to 'Force Push'
  in Production environment. Deleted repositories will be moved to
  'Recycle Bin' so it is possible to restore them once they have been
  deleted. However, if they have been deleted from the 'Recycle Bin'
  then unless a copy of the repository is kept elsewhere, the repository
  cannot be restored.
  Remove all repositories and the properties that associate with them.
  
  .Parameter Force
  Force to perform delete. Bypass prompt.
  WARNINGS: Be very careful when eanble this parameter.
  
  .Outputs
  true or false
#>
function Clear-TestEnvironment {
	param (
		[switch]$Force = $false
	)
	Write-Host ""
	Write-Host "Remove all repositories and their associated attributes"
	Write-Host "======================================================="
	Write-Host "# All repositories in project $([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject) will be deleted."
	Write-Host "# Please confirm that you want to proceed."
	Write-Host "# Y[Yes] N[No]"
	if (!$Force) {
		$answer = Read-Host -Prompt "# Answer"
		if (!$($answer -match "Y|Yes")) {
			Write-Host "# Stopped"
			return $true
		}
	}
	
	Write-Host "# Proceed to delete..."
	# Get all existing repositories
	$url = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/git/repositories?api-version=6.0"
	
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	if ($(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to get all repositories.")){
		$content = $response.content | Out-String | ConvertFrom-Json
		foreach ($repository in $content.value) {
			# Remove the repository except the mandatory one.
			if ($repository.name -ne $([TestEnvPredefinedVariables]::MandatoryRepositoryName) `
				-and !$(Remove-Repository -Repository $repository)) {
				Write-Host "# ERROR: Failed to remove repository '$($repository.name)'"
				return $false
			}
		}
	} else {
		return $false
	}
	
	# Clear all pipelines
	if (!$(Remove-AllDefinitions)) {
		Write-Host "# ERROR: Failed to remove all pipelines."
		return $false
	}
	
	# Clear all policies
	if (!$(Remove-AllPolicies)) {
		Write-Host "# ERROR: Failed to remove all policies."
		return $false
	}
	
	return $true
}

<#
  .Description
  Get a branch object of a repository
  
  .Parameter RepositoryName
  Name of a repository that a branch belongs to
  
  .Parameter BranchName
  Name of a branch
  
  .Outputs
  A branch object or $null
#>
function Get-Branch {
	param (
		[Parameter(mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$BranchName
	)	
	# Get based branch id
	$uri = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/git/repositories/$RepositoryName/refs?filter=heads/$($BranchName)&api-version=6.0"
	$response = Invoke-WebRequest -URI $uri `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET

	$branchObj = $null
	if (!$(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to get objectId of $BranchName of repository $RepositoryName")) {
		return $null
	} else {
		$content = $($response.content | Out-String | ConvertFrom-Json)
		if ($content.value.count -eq 0) {
			Write-Host "# ERROR: No branch matches branch $BranchName"
			return $null
		}
		$branchObj = $content.value[0]
	}
	return $branchObj
}

<#
  .Description
  Add branch to a repository.
  
  .Parameter RepositoryName
  Name of a repository object specified in the configuration file.

  .Parameter Branch
  Branch object from config file.
  
  .Outputs
  true or false
#>
function Add-RepositoryBranch {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$Branch
	)
	
	$branchObj = Get-Branch -RepositoryName $RepositoryName -BranchName $Branch.base
	if ($branchObj -eq $null) {
		Write-Host "# ERROR: Failed to get base branch $($Branch.base) of repository $RepositoryName"
		return $false
	}
	
	# Create the branch
	$uri = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/git/repositories/$RepositoryName/refs?api-version=6.0"
	$jsonBody = @"
	[
		{
			"name": "refs/heads/$($Branch.name)",
			"oldObjectId": "0000000000000000000000000000000000000000",
			"newObjectId": "$($branchObj.objectId)"
		}
	]
"@

	$response = Invoke-WebRequest -URI $uri `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method POST `
	-Body $jsonBody `
	-ContentType "application/json"

	if (!$(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to add branch $($Branch.name) to repository $RepositoryName")) {
		return $false
	}
	return $true
}

<#
  .Description
  Add branches to a repository.
  
  .Parameter RepositoryName
  Name of a repository object specified in the configuration file.

  .Parameter RepositoryConfig
  The configuration associated with the repository.
  
  .Outputs
  true or false
#>
function Add-RepositoryBranches {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$RepositoryConfig
	)
	Write-Host ""
	Write-Host "# Adding branches for repository $RepositoryName"
	foreach ($branch in $RepositoryConfig.branches) {
		if (!$(Add-RepositoryBranch -RepositoryName $RepositoryName -Branch $branch)) {
			Write-Host "# ERROR: Failed to create branch $($branch.refName) for repository $RepositoryName"
			return $false;
		}
	}
	
	return $true
}

<#
  .Description
  Add a tag to a repository. This will always
  be done on the main|master branch at the last
  commit.
  
  .Parameter RepositoryName
  Name of a repository object specified in the configuration file.

  .Parameter Tag
  Tag name.
  
  .Outputs
  true or false
#>
function Add-RepositoryTag {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[string]$Tag
	)
	
	# Get 'main' branch id
	$mainBranch = Get-MainBranch `
		-TeamProjectName $([TestEnvPredefinedVariables]::TestProject) `
		-RepositoryName $RepositoryName `
		-AuthorizationHeader $([Authorization]::AuthorizationString)
	if ($mainBranch -eq $null) {
		Write-Host "# ERROR: a 'main' or 'master' branch does not exist."
		return $false
	}
	
	# Create the tag
	$uri = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/git/repositories/$($RepositoryName)/annotatedtags?api-version=6.1-preview.1"
	$jsonBody = @"
	{
		"name": "$Tag",
		"taggedObject": {
			"objectId": "$($mainBranch.objectId)"
		},
		"message": "$Tag"
	}
"@

	$response = Invoke-WebRequest -URI $uri `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method POST `
	-Body $jsonBody `
	-ContentType "application/json"

	if (!$(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to add tag $Tag to repository $RepositoryName")) {
		return $false
	}
	return $true
}

<#
  .Description
  Add tags to a repository.
  
  .Parameter RepositoryName
  Name of a repository object specified in the configuration file.

  .Parameter RepositoryConfig
  The configuration associated with the repository.
  
  .Outputs
  true or false
#>
function Add-RepositoryTags {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$RepositoryConfig
	)
	Write-Host ""
	Write-Host "# Adding tags to repository $RepositoryName"
	foreach ($tag in $RepositoryConfig.tags) {
		if (!$(Add-RepositoryTag -RepositoryName $RepositoryName -Tag $tag)) {
			Write-Host "# ERROR: Failed to create tag $tag for repository $RepositoryName"
			return $false;
		}
	}
	
	return $true
}

<#
  .Description
  Update package versions of repository.
  
  .Parameter RepositoryName
  Name of a repository object specified in the configuration file.

  .Parameter RepositoryConfig
  The configuration associated with the repository.
  
  .Outputs
  true or false
#>
function Update-RepositoryPackageVersions {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$RepositoryConfig
	)
	# NOTE: Currently not needed as updateing versions does not
	# depend on original veresion number.
	return $true
}

<#
  .Description
  Add a repository. The repository will first be cloned from the
  'Production' environment. They will then be configured accordingly.
  
  .Parameter RepositoryName
  Name of a repository object specified in the configuration file.

  .Parameter RepositoryConfig
  The configuration associated with the repository.
  
  .Outputs
  true or false
#>
function Add-Repository {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$RepositoryConfig
	)
	Write-Host ""
	Write-Host "Add repository $RepositoryName"
	Write-Host "=============================="

	# Get repository id
	$repoId = Get-RepositoryId -ProjectName $([TestEnvPredefinedVariables]::ProductionProject) -RepositoryName $RepositoryName
	if ($repoId -eq $null) {
		Write-Host "# ERROR: Failed to get Id of repository $RepositoryName from project $([TestEnvPredefinedVariables]::ProductionProject)"
		return $false
	}
	
	# Fork from production
	$uri = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/git/repositories?api-version=6.1-preview.1"
	$jsonBody = @"
	{
		"name": "$RepositoryName",
		"project": {
			"id": "$(Get-TestProjectId)"
		},
		"parentRepository": {
			"id": "$repoId",
			"name": "$($repositoryName)",
			"project": {
				"id": "$(Get-ProductionProjectId)"
			}
		}
	}
"@
	$response = Invoke-WebRequest -URI $uri `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method POST `
	-Body $jsonBody `
	-ContentType "application/json"
	
	if (!$(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed fork the repository $RepositoryName from production environment")) {
		return $false
	}
	
	# Sleep for 2 seconds to allow time for branch to be created.
	Start-Sleep 2
	
	# Added information to config the repositories such as tag, trugger, definition...
	
	# Add branches
	if (!$(Add-RepositoryBranches -RepositoryName $RepositoryName -RepositoryConfig $repositoryConfig)) {
		Write-Host "# ERROR: Failed to add specified branches."
		return $false
	}
	
	# Add tags
	if (!$(Add-RepositoryTags -RepositoryName $RepositoryName -RepositoryConfig $repositoryConfig)) {
		Write-Host "# ERROR: Failed to add specified tags."
		return $false
	}
	
	# Update package versions
	if (!$(Update-RepositoryPackageVersions -RepositoryName $RepositoryName -RepositoryConfig $repositoryConfig)) {
		Write-Host "# ERROR: Failed to update specified package version."
		return $false
	}
	
	return $true
}

<#
  .Description
  Add the repositories based on what specified in the configuration file.
  Repositories will first be cloned from the 'Production' environment. They
  will then be configured accordingly.
  
  .Parameter Configuration
  A configuration object, reflecting what is specified in the configuration file
  
  .Outputs
  true or false
#>
function Add-Repositories {
	param (
		[Parameter(Mandatory)]
		[object]$Configuration
	)
	
	Write-Host ""
	Write-Host "Add repositories"
	Write-Host "================"
	if ($Configuration.repositories -ne $null) {
		foreach ($repoProperty in $($Configuration.repositories | Get-Member -MemberType NoteProperty)) {
			if (!(Add-Repository -RepositoryName $repoProperty.Name -RepositoryConfig $Configuration.repositories."$($repoProperty.Name)")) {
				Write-Host "# ERROR: Failed to add repository $repository"
				return $false
			}
		}
	}
	
	return $true
}

<#
  .Description
  Get a definition object
  
  .Parameter DefinitionName
  Name of a definition
  
  .Outputs
  A definition object based on response from Azure Devops api. $null if fails
#>
function Get-Definition {
	param (
		[Parameter(Mandatory)]
		[string]$DefinitionName
	)
	
	# Get all definitions
	$uri = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/build/definitions?api-version=6"
	$response = Invoke-WebRequest -URI $uri `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET 
	
	if (Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to get all definitions") {
		$content = $response.content | Out-String | ConvertFrom-Json
		# Get the definition that match the definition name
		$definition = $($content.value | Where-Object {$_.name -eq "$DefinitionName"})
		if ($definition -ne $null) {
			return $definition[0]
		} else {
			Write-Host "# ERROR: No definition has been found for name $DefinitionName"
			return $null
		}
	} else {
		return $null
	}
	return $null
}

<#
  .Description
  Get Id of an agent pool
  
  .Parameter AgentPoolName
  Name of an agent pool
  
  .Outputs
  Id of an agent or $null
#>
function Get-AgentPoolId {
	param (
		[Parameter(Mandatory)]
		[string]$AgentPoolName
	)
	
	$uri = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)/_apis/distributedtask/pools?api-version=6"
	$response = Invoke-WebRequest -URI $uri `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	$poolId = $null
	if (Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to get agent pools") {
		$content = $response.content | Out-String | ConvertFrom-Json
		$poolId = $($content.value | Where-Object { $_.name -eq $AgentPoolName })[0].id
	} else {
		return $null
	}
	return $poolId
}

<#
  .Description
  Get Agent queue object
  
  .Parameter AgentQueueName
  Name of an agent queue
  
  .Outputs
  An agent queue object or $null
#>
function Get-AgentQueue {
	param (
		[Parameter(Mandatory)]
		[string]$AgentQueueName
	)
	
	$uri = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/distributedtask/queues?api-version=6.0-preview.1"
	$response = Invoke-WebRequest -URI $uri `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	$queue = $null
	if (Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to get agent queues") {
		$content = $response.content | Out-String | ConvertFrom-Json
		$queue = $($content.value | Where-Object { $_.name -eq $AgentQueueName })[0]
	} else {
		return $null
	}
	return $queue
}

<#
  .Description
  Add a definition for a repository.
  NOTE: This currently only copy with buildCompletion trigger type.
  
  .Parameter RepositoryName
  Name of a repository that the definitions belong to.
  
  .Parameter Definition
  The definition object as specified in the config file.
  
  .Outputs
  true or false
#>
function Add-RepositoryDefinition {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$Definition
	)
	# Sleep for 1 second to make sure all definitions are available
	Start-Sleep 1
	
	# Get default queue
	$queue = Get-AgentQueue -AgentQueueName $([TestEnvPredefinedVariables]::DefaultQueueName)
	if ($queue -eq $null) {
		Write-Host "# ERROR: Would not find the default queue of '$defaultQueueName'"
		return $false
	}
	
	# Create a definition
	$uri = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/build/definitions?api-version=6.0 "
	
	# Construct the json body
	$jsonBody = @"
	{
		"name": "$($Definition.name)",
		"repository": {
			"defaultBranch": "$($Definition.defaultBranch)",
			"name": "$RepositoryName",
			"type": "TfsGit"
		},
		"process":{
			"yamlFilename":"$($Definition.yamlFilename)",
			"type":2
		},
		"type": "build",
		"queue": $($queue | ConvertTo-Json),
		"triggers": [
			$([TestEnvPredefinedVariables]::YamlCiTrigger)
		]
	}
"@

	$response = Invoke-WebRequest -URI $uri `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method POST `
	-Body $jsonBody `
	-ContentType "application/json"

	if (!$(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to add definition $($Definition.name) for repository $RepositoryName")) {
		return $false
	}
	return $true
}

<#
  .Description
  Add definitions for a repository.
  
  .Parameter RepositoryName
  Name of a repository that the definitions belong to.
  
  .Parameter RepositoryConfig
  The configuration object of each repository.
  
  .Outputs
  true or false
#>
function Add-RepositoryDefinitions {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$RepositoryConfig
	)
	foreach ($definition in $RepositoryConfig.definitions) {
		if (!$(Add-RepositoryDefinition `
			-RepositoryName $RepositoryName `
			-Definition $definition)) {
			Write-Host "# ERROR: Failed to add definition $($definition.name) for repository $RepositoryName"
			return $false
		}
	}
	
	return $true
}

<#
  .Description
  Add definitions.
  
  .Parameter Configuration
  A configuration object, reflecting what is specified in the configuration file
  
  .Outputs
  true or false
#>
function Add-Definitions {
	param (
		[Parameter(Mandatory)]
		[object]$Configuration
	)
	
	Write-Host ""
	Write-Host "Add definitions"
	Write-Host "==============="
	foreach ($repoProperty in $($Configuration.repositories | Get-Member -MemberType NoteProperty)) {
		Write-Host ""
		Write-Host "# Adding build definitions for repository $($repoProperty.Name)"
		if (!(Add-RepositoryDefinitions -RepositoryName $repoProperty.Name -RepositoryConfig $Configuration.repositories."$($repoProperty.Name)")) {
			Write-Host "# ERROR: Failed to add definitions for repository $repository"
			return $false
		}
	}
	
	return $true
}

<#
  .Description
  Add build triggers for a definition of a repository.
  NOTE: This currently only copy with buildCompletion trigger type.
  
  .Parameter RepositoryName
  Name of a repository that the definitions belong to.
  
  .Parameter Definition
  The definition object as specified in the config file.
  
  .Outputs
  true or false
#>
function Add-RepositoryDefinitionBuildTriggers {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$Definition
	)
	# Sleep for 1 second to make sure all definitions are available
	Start-Sleep 1
	
	# Get current details of the definition
	$curDefinition = Get-Definition -DefinitionName $Definition.name
	if ($curDefinition -eq $null) {
		Write-Host "# ERROR: Failed to get Id for definition $($Definition.name)"
		return $false
	}
	
	# Create a definition
	$uri = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/build/definitions/$($curDefinition.id)?api-version=6.0 "

	# Construct triggers
	$triggers = "[`n"
	if ($Definition.triggers -ne $null) {
		[int32]$validTriggerFound = 0
		for ($i = 0; $i -lt $Definition.triggers.count; $i++) {
			$trigger = $Definition.triggers[$i]
			switch ($trigger.triggerType) {
				"buildCompletion"
				{
					Write-Host "# Including 'buildCompletion' trigger."
					$triggerDefinition = Get-Definition -DefinitionName $trigger.definitionName
					if ($triggerDefinition -eq $null) {
						Write-Host "# ERROR: Failed to get Id for trigger definition $($trigger.name)"
						return $false
					}
	
					# Add square brackets for branchFilters array
					$branchFilters = ""
					if ($trigger.branchFilters.count -eq 1) {
						$branchFilters += "["
					}
					$branchFilters += $($trigger.branchFilters | ConvertTo-Json | Out-String)
					if ($trigger.branchFilters.count -eq 1) {
						$branchFilters += "]"
					}
					
					$triggerDef = @"
					{
						"definition": {
							"id": $($triggerDefinition.id),
							"path": "\\",
							"queueStatus": "enabled",
							"project": {
								"id": "$(Get-TestProjectId)",
								"state": "wellFormed",
								"visibility": "private"
							}
						},
						"requiresSuccessfulBuild": $($trigger.requiresSuccessfulBuild | ConvertTo-Json),
						"branchFilters": $branchFilters,
						"triggerType": "$($trigger.triggerType)"
					}
					
"@	
					if ($validTriggerFound -gt 0) {
						$triggers += ",`n"
					}
					$triggers += $triggerDef
					$validTriggerFound += 1
				}
			}
		}
	}
	
	# Make sure to includ the CI trigger defined in yaml file.
	if ($validTriggerFound -gt 0) {
		$triggers += ",`n"
	}
	$triggers += $([TestEnvPredefinedVariables]::YamlCiTrigger)
	
	$triggers += "`n]"
	
	# Construct the json body
	$jsonBody = @"
	{
		"id": $($curDefinition.id),
		"revision": $($curDefinition.revision),
		"name": "$($Definition.name)",
		"repository": {
			"defaultBranch": "$($Definition.defaultBranch)",
			"name": "$RepositoryName",
			"type": "TfsGit"
		},
		"process":{
			"yamlFilename":"$($Definition.yamlFilename)",
			"type":2
		},
		"triggers": $triggers,
		"type": "build",
		"queue": $($curDefinition.queue | ConvertTo-Json)
	}
"@

	$response = Invoke-WebRequest -URI $uri `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method PUT `
	-Body $jsonBody `
	-ContentType "application/json"

	if (!$(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to add definition $($Definition.name) for repository $RepositoryName")) {
		return $false
	}
	return $true
}

<#
  .Description
  Add build triggers for a repository.
  
  .Parameter RepositoryName
  Name of a repository that the definitions belong to.
  
  .Parameter RepositoryConfig
  The configuration object of each repository.
  
  .Outputs
  true or false
#>
function Add-RepositoryBuildTriggers {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$RepositoryConfig
	)
	foreach ($definition in $RepositoryConfig.definitions) {
		if (!$(Add-RepositoryDefinitionBuildTriggers `
			-RepositoryName $RepositoryName `
			-Definition $definition)) {
			Write-Host "# ERROR: Failed to add build triggers for definition $($definition.name) for repository $RepositoryName"
			return $false
		}
	}
	
	return $true
}

<#
  .Description
  Add build triggers.
  
  .Parameter Configuration
  A configuration object, reflecting what is specified in the configuration file
  
  .Outputs
  true or false
#>
function Add-BuildTriggers {
	param (
		[Parameter(Mandatory)]
		[object]$Configuration
	)
	
	Write-Host ""
	Write-Host "Add build triggers"
	Write-Host "=================="
	foreach ($repoProperty in $($Configuration.repositories | Get-Member -MemberType NoteProperty)) {
		Write-Host ""
		Write-Host "# Adding build triggers for repository $($repoProperty.Name)"
		if (!(Add-RepositoryBuildTriggers -RepositoryName $repoProperty.Name -RepositoryConfig $Configuration.repositories."$($repoProperty.Name)")) {
			Write-Host "# ERROR: Failed to add build triggers for repository $repository"
			return $false
		}
	}
	
	return $true
}

<#
  .Description
  Return an Id of a repository
  
  .Parameter ProjectName
  Name of a team project
  
  .Parameter RepositoryName
  Name of a repository
  
  .Outputs
  Id of a repository or $null
#>
function Get-RepositoryId {
	param (
		[Parameter(Mandatory)]
		[string]$ProjectName,
		[Parameter(Mandatory)]
		[string]$RepositoryName
	)
	
	# Get all existing repositories
	$url = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$ProjectName/_apis/git/repositories?api-version=6.0"
	
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	if (Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to get all repositories") {
		# Get the definition that match the definition name
		$content = $response.content | Out-String | ConvertFrom-Json
		$definition = $($content.value | Where-Object {$_.name -eq "$RepositoryName"})
		if ($definition -ne $null) {
			return $definition[0].id
		} else {
			Write-Host "# ERROR: No repository name match $RepositoryName"
			return $null
		}
	}
	return $null
}

<#
  .Description
  Get an ID of a policy type
  
  .Parameter TypeName
  Name of a policy type
  
  .Outputs
  An id of the input policy or $null
#>
function Get-PolicyTypeId {
	param (
		[Parameter(Mandatory)]
		[string]$TypeName
	)
	
	$url = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/policy/types?api-version=6.1-preview.1"
	$response = Invoke-WebRequest `
	-URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method GET
	
	if (Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed to get all policy types") {
		# Get the definition that match the definition name
		$content = $response.content | Out-String | ConvertFrom-Json
		$policy = $($content.value | Where-Object {$_.displayName -eq "$TypeName"})
		if ($policy -ne $null) {
			return $policy[0].id
		} else {
			Write-Host "# ERROR: No policy type matched $TypeName"
			return $null
		}
	}
}

<#
  .Description
  Add policy to a repository. If a repository name is not
  supplied, create a generic one.
  
  .Parameter RepositoryName
  Name of a repository. Null if want to apply to everything.
  
  .Parameter Policy
  A policy object based on the configuration file.
  
  .Outputs
  true or false
#>
function Add-RepositoryPolicy {
	param (
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$Policy
	)
	
	Write-Host "# Adding policy '$($Policy.type)' to repository $RepositoryName"
	
	# Obtain repository Id
	$repositoryId = $null
	if (![string]::IsNullOrEmpty($RepositoryName)) {
		$repositoryId = Get-RepositoryId -ProjectName $([TestEnvPredefinedVariables]::TestProject) -RepositoryName $RepositoryName
		if ($repositoryId -eq $null) {
			Write-Host "# Failed to get id of repository $RepositoryName"
			return $false
		}
	}
	
	# Get the type id
	$typeId = Get-PolicyTypeId -TypeName $Policy.type
	if ($typeId -eq $null) {
		Write-Host "# ERROR Invalid policy type $($Policy.type)"
		return $false
	}
	
	# Build policy settings
	$settings = $null
	switch ($Policy.type) {
		"Build"
		{
			$definition = Get-Definition -DefinitionName $Policy.definition
			if ($definition -ne $null) {
				$settings = @"
				{
					"buildDefinitionId": $($definition.id),
					"queueOnSourceUpdateOnly": false,
					"manualQueueOnly": false,
					"displayName": null,
					"validDuration": 0.0,
					"scope": [
						{
							"refName": "$($Policy.refName)",
							"matchKind": "$($Policy.matchKind)",
							"repositoryId": "$repositoryId"
						}
					]
				}
"@
			} else {
				Write-Host "# ERROR: Failed to obtain id for definition $($Policy.definition)"
				return $false
			}
		}
		"Required reviewers"
		{
			$settings = @"
			{
				"requiredReviewerIds": [
					"$(Get-ReviewerId)"
				],
				"minimumApproverCount": 1,
				"creatorVoteCounts": false,
				"scope": [
					{
						"refName": null,
						"matchKind": "DefaultBranch",
						"repositoryId": "$repositoryId"
					}
				]
			}
"@
		}
		Default
		{
			Write-Host "# ERROR: $($Policy.type) is not supported"
			return $false
		}
	}
	
	# Add the policy
	$url = "$([TestEnvPredefinedVariables]::TeamFoundationCollectionUri)$([TestEnvPredefinedVariables]::TestProject)/_apis/policy/configurations?api-version=6.1-preview.1"
	$jsonBody = @"
	{
		"isEnabled": true,
		"isBlocking": true,
		"isDeleted": false,
		"settings": $settings,
		"isEnterpriseManaged": false,
		"type": {
			"id": "$typeId",
		}
	}
"@

	$response = Invoke-WebRequest -URI $url `
	-Headers @{
		Authorization = "$([Authorization]::AuthorizationString)"
	} `
	-Method POST `
	-Body $jsonBody `
	-ContentType "application/json"
	
	if (!$(Test-RestResponse `
		-Response $response `
		-ErrorMessage "Failed fork the repository $RepositoryName from production environment")) {
		return $false
	}
	
	return $true
}

<#
  .Description
  Add repository branch policies.
  
  .Parameter RepositoryName
  Name of a repository object specified in the configuration file.

  .Parameter RepositoryConfig
  The configuration associated with the repository.
  
  .Outputs
  true or false
#>
function Add-RepositoryPolicies {
	param (
		[Parameter(Mandatory)]
		[string]$RepositoryName,
		[Parameter(Mandatory)]
		[object]$RepositoryConfig
	)
	
	foreach ($policy in $RepositoryConfig.policies) {
		if (!$(Add-RepositoryPolicy -RepositoryName $RepositoryName -Policy $policy)) {
			Write-Host "# ERROR: Failed to add policy for repository $Repository"
			return $false
		}	
	}
	return $true
}

<#
  .Description
  Add policies
  
  .Parameter Configuration
  A configuration object, reflecting what is specified in the configuration file
  
  .Outputs
  true or false
#>
function Add-Policies {
	param (
		[Parameter(Mandatory)]
		[object]$Configuration
	)
	
	Write-Host ""
	Write-Host "Add policies"
	Write-Host "============"
	# Add general policies which apply on all repository and branches
	Write-Host ""
	Write-Host "# Adding cross-repository policies"
	foreach ($policy in $Configuration.policies) {
		if (!(Add-RepositoryPolicy -RepositoryName $null -Policy $policy)) {
			Write-Host "# ERROR: Failed to add general policy '$policy'"
			return $false
		}
	}
	
	# Add policies which are specific to each repository
	foreach ($repoProperty in $($Configuration.repositories | Get-Member -MemberType NoteProperty)) {
		Write-Host ""
		Write-Host "# Adding policies for repository $($repoProperty.Name)"
		if (!(Add-RepositoryPolicies -RepositoryName $repoProperty.Name -RepositoryConfig $Configuration.repositories."$($repoProperty.Name)")) {
			Write-Host "# ERROR: Failed to add policies for repository $repository"
			return $false
		}
	}
	
	return $true
}

<#
  .Description
  Add PullRequests..

  .Parameter Configuration
  A configuration object, reflecting what is specified in the configuration file
  
  .Outputs
  true or false
#>
function Add-PullRequests {
	param (
		[Parameter(Mandatory)]
		[object]$Configuration
	)
	
	Write-Host ""
	Write-Host "Add pull requests"
	Write-Host "============"
	foreach ($repoProperty in $($Configuration.repositories | Get-Member -MemberType NoteProperty)) {
		Write-Host ""
		Write-Host "# Adding pull request for repository $($repoProperty.Name)"
		$repositoryConfig = $Configuration.repositories."$($repoProperty.Name)"
		foreach ($pullRequest in $repositoryConfig.pullrequests) {
			Write-Host "# Add pull request from $($pullRequest.source) to $($pullRequest.target) for repository $($repoProperty.Name)"
			$response = $(New-PullRequest `
				-TeamProjectName $([TestEnvPredefinedVariables]::TestProject) `
				-RepositoryName $repoProperty.Name `
				-SourceBranchRef "refs/heads/$($pullRequest.source)" `
				-TargetBranchRef "refs/heads/$($pullRequest.target)" `
				-AuthorizationHeader $([Authorization]::AuthorizationString))
			if ($response -eq $null) {
				Write-Host "# ERROR: Failed to create pull request from $($pullRequest.source) to $($pullRequest.target) for repository $($repoProperty.Name)"
				return $false;
			}
			
			# At the moment, we only allow adding a comment to indicate
			# there is unresolved issue.
			if ($pullRequest.comment) {
				if (!(Add-PullRequestComment `
					-TeamProjectName $([TestEnvPredefinedVariables]::TestProject) `
					-RepositoryName $repoProperty.Name `
					-PullRequestId $response.pullRequestId `
					-Comment "Comment" `
					-AuthorizationHeader $([Authorization]::AuthorizationString))) {
					Write-Host "# ERROR: Failed to add comments to pull request"
					return $false
				}
			}
			
			# NOTE: Vote cannot be added through Rest API as voting for others is not allowed
		}
	}
	
	return $true
}

<#
  .Description
  Create a new test environment
  
  .Parameter ConfigurationFile
  A full path to a configuration file
  
  .Outputs
  true or false
#>
function New-TestEnvironment {
	param (
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
	
	# Validate configuration file
	if (!(Test-ConfigFile -Configuration $config)) {
		Write-Host "# ERROR: $ConfigurationFile is invalid."
		return $false
	}
	
	# NOTE: The reason the creation is done in the order of
	# repositories, definitions, build triggers, policies and pull requests
	# because:
	# 1. Definitions depend on all repositories to be available.
	# 2. Build triggers depend on all definitions to be available.
	# 3. Policies depend on all definitions to be available.
	# 4. Pull requests depends on everything before.
	
	# Process repositories
	if (!(Add-Repositories -Configuration $config)) {
		Write-Host "# ERROR: Failed to add the specified repositories."
		return $false
	}
	
	# Add definitions
	if (!(Add-Definitions -Configuration $config)) {
		Write-Host "# ERROR: Failed to add the specified definitions."
		return $false
	}
	
	# Add build triggers
	if (!(Add-BuildTriggers -Configuration $config)) {
		Write-Host "# ERROR: Failed to add the specified triggers."
		return $false
	}
	
	# Add policies
	if (!(Add-Policies -Configuration $config)) {
		Write-Host "# ERROR: Failed to add the specified policies."
		return $false
	}
	
	# Add pull requests
	if (!(Add-PullRequests -Configuration $config)) {
		Write-Host "# ERROR: Failed to add the specified pull requests."
		return $false
	}
	
	return $true
}