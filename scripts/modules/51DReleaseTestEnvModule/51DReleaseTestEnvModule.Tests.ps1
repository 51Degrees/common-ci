# All tests for 'Clear-TestEnvironment' function
Describe 'Clear-TestEnvironment' {
    It 'clear all repositories, except mandatory repository' {
		# Mock response for getting all repositories
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 200
				content = '{
					"value": [
						{
							"name": "MandatoryRepository"
						},
						{
							"name": "repo1"
						}
					]
				}'
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories.*" -and $Method -eq "GET"
		} `
		-ModuleName 51DReleaseTestEnvModule

		# Mock reponse for deleting a repository
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 200
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories/.*\?.*" `
				-and $Method -eq "DELETE"
		} `
		-ModuleName 51DReleaseTestEnvModule
		
		Mock Remove-AllDefinitions { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Remove-AllPolicies { return $true } `
			-ModuleName 51DReleaseTestEnvModule
	
		# Clear the test environment
        $result = Clear-TestEnvironment -Force
        $result | Should -BeExactly $true
    }
	
	It 'fails to clear all repositories' {
		# Mock response for getting all repositories
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 200
				content = '{
					"value": [
						{
							"name": "MandatoryRepository"
						},
						{
							"name": "repo1"
						}
					]
				}'
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories.*" -and $Method -eq "GET"
		} `
		-ModuleName 51DReleaseTestEnvModule

		# Mock reponse for deleting a repository
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 500
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories/.*\?.*" `
				-and $Method -eq "DELETE"
		} `
		-ModuleName 51DReleaseTestEnvModule
	
		# Clear the test environment
        { Clear-TestEnvironment -Force } | Should -Throw
    }
	
	It 'fails to get all repositories before the clearance' {
		# Mock response for getting all repositories
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 500
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories.*" -and $Method -eq "GET"
		} `
		-ModuleName 51DReleaseTestEnvModule

		# Mock reponse for deleting a repository
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 200
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories/.*\?.*" `
				-and $Method -eq "DELETE"
		} `
		-ModuleName 51DReleaseTestEnvModule
	
		# Clear the test environment
        { Clear-TestEnvironment -Force } | Should -Throw
    }
	
	It 'fails to clear all definitions' {
		# Mock response for getting all repositories
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 200
				content = '{
					"value": [
						{
							"name": "MandatoryRepository"
						},
						{
							"name": "repo1"
						}
					]
				}'
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories.*" -and $Method -eq "GET"
		} `
		-ModuleName 51DReleaseTestEnvModule

		# Mock reponse for deleting a repository
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 200
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories/.*\?.*" `
				-and $Method -eq "DELETE"
		} `
		-ModuleName 51DReleaseTestEnvModule
		
		Mock Remove-AllDefinitions { return $false } `
			-ModuleName 51DReleaseTestEnvModule
	
		# Clear the test environment
        $result = Clear-TestEnvironment -Force
        $result | Should -BeExactly $false
    }
	
	It 'Fails to clear all added "Required Reviewers" cross-repository policies' {
		# Mock response for getting all repositories
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 200
				content = '{
					"value": [
						{
							"name": "MandatoryRepository"
						},
						{
							"name": "repo1"
						}
					]
				}'
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories.*" -and $Method -eq "GET"
		} `
		-ModuleName 51DReleaseTestEnvModule

		# Mock reponse for deleting a repository
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 200
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories/.*\?.*" `
				-and $Method -eq "DELETE"
		} `
		-ModuleName 51DReleaseTestEnvModule
		
		Mock Remove-AllDefinitions { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Remove-AllPolicies { return $false } `
			-ModuleName 51DReleaseTestEnvModule
	
		# Clear the test environment
        $result = Clear-TestEnvironment -Force
        $result | Should -BeExactly $false
    }
}

# All tests for 'New-TestEnvironment' function
Describe 'New-TestEnvironment' {
	It 'create full environment' {
		Mock Test-Path { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-Content { return 'testing' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock ConvertFrom-Json { return '{}' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Test-ConfigFile { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-Repositories { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-Definitions { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-BuildTriggers { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-Policies { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-PullRequests { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$result = New-TestEnvironment -ConfigurationFile "//Non-Existent-Folder"
        $result | Should -BeExactly $true
    }
	
	It 'non-existent configuration file' {
		$result = New-TestEnvironment -ConfigurationFile "//Non-Existent-Folder"
        $result | Should -BeExactly $false
    }
	
	It 'invalid JSON content in configuration file' {
		Mock Test-Path { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-Content { return 'testing' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock ConvertFrom-Json { throw [ArgumentException]"Invalid JSON content" } `
			-ModuleName 51DReleaseTestEnvModule
		{ New-TestEnvironment -ConfigurationFile "//Random_file" } | Should -Throw
    }
	
	# There is a separate test group to test the Test-ConfigFile function
	It 'invalid settings in configuration file' {
		Mock Test-Path { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-Content { return 'testing' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock ConvertFrom-Json { return '{}' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Test-ConfigFile { return $false } `
			-ModuleName 51DReleaseTestEnvModule
        $result = New-TestEnvironment -ConfigurationFile "//Testing-File"
		$result | Should -BeExactly $false
    }
	
	It 'fails to fork a repository from production to test environment' {
		Mock Test-Path { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-Content { return 'testing' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock ConvertFrom-Json { return '{}' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Test-ConfigFile { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-Repositories { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$result = New-TestEnvironment -ConfigurationFile "//Testing-File"
        $result | Should -BeExactly $false
    }
	
	It 'fails to create required definitions' {
		Mock Test-Path { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-Content { return 'testing' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock ConvertFrom-Json { return '{}' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Test-ConfigFile { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-Repositories { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-Definitions { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$result = New-TestEnvironment -ConfigurationFile "//Testing-File"
        $result | Should -BeExactly $false
    }
	
	It 'fails to create build triggers' {
		Mock Test-Path { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-Content { return 'testing' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock ConvertFrom-Json { return '{}' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Test-ConfigFile { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-Repositories { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-Definitions { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-BuildTriggers { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$result = New-TestEnvironment -ConfigurationFile "//Testing-File"
        $result | Should -BeExactly $false
    }
	
	It 'fails to create required policies' {
		Mock Test-Path { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-Content { return 'testing' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock ConvertFrom-Json { return '{}' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Test-ConfigFile { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-Repositories { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-Definitions { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-BuildTriggers { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-Policies { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$result = New-TestEnvironment -ConfigurationFile "//Testing-File"
        $result | Should -BeExactly $false
    }
	
	It 'fails to create required pull requests' {
		Mock Test-Path { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-Content { return 'testing' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock ConvertFrom-Json { return '{}' } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Test-ConfigFile { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-Repositories { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-Definitions { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-BuildTriggers { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-Policies { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-PullRequests { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$result = New-TestEnvironment -ConfigurationFile "//Non-Existent-Folder"
        $result | Should -BeExactly $false
    }
}

# All tests for 'Add-Repositories function
Describe 'Add-Repositories' {
	It 'Add no repositories' {
		$configJson = '{
			"repositories": []
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-Repositories -Configuration $config
		$result | Should -BeExactly $true
	}
	
	It 'Add all repositories' {
		Mock Add-Repository { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"ci-test-repo-1": {},
				"ci-test-repo-3": {}
			}
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-Repositories -Configuration $config
		$result | Should -BeExactly $true
	}
	
	It 'Fails to add a repository' {
		Mock Add-Repository { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"ci-test-repo-1": {},
				"ci-test-repo-3": {}
			}
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-Repositories -Configuration $config
		$result | Should -BeExactly $false
	}
}

# All tests for 'Add-Repository' function
Describe 'Add-Repository' {
	It 'Add a repository' {
		Mock Get-RepositoryId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-ProductionProjectId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-TestProjectId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-ReviewerId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		# Mock a successful web request
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 200
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories\?.*" `
				-and $Method -eq "POST"
		} `
		-ModuleName 51DReleaseTestEnvModule
		Mock Add-RepositoryBranches { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-RepositoryTags { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Update-RepositoryPackageVersions { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$result = Add-Repository -RepositoryName "TestRepo" -RepositoryConfig $(New-Object -TypeName Object)
		$result | Should -BeExactly $true
	}
	
	It 'Non-existent reposity name' {
		Mock Get-RepositoryId { return $null } `
			-ModuleName 51DReleaseTestEnvModule
		$result = Add-Repository -RepositoryName "TestRepo" -RepositoryConfig $(New-Object -TypeName Object)
		$result | Should -BeExactly $false
	}
	
	It 'Fails to fork from production evironment' {
		Mock Get-RepositoryId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		# Mock a bad web request
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 500
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories\?.*" `
				-and $Method -eq "POST"
		} `
		-ModuleName 51DReleaseTestEnvModule
		{ Add-Repository `
			-RepositoryName "TestRepo" `
			-RepositoryConfig $(New-Object `
			-TypeName Object)} | Should -Throw
	}
	
	It 'Fails to add branches' {
		Mock Get-RepositoryId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-ProductionProjectId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-TestProjectId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-ReviewerId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		# Mock a successful web request
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 200
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories\?.*" `
				-and $Method -eq "POST"
		} `
		-ModuleName 51DReleaseTestEnvModule
		Mock Add-RepositoryBranches { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$result = Add-Repository -RepositoryName "TestRepo" -RepositoryConfig $(New-Object -TypeName Object)
		$result | Should -BeExactly $false
	}
	
	It 'Fails to add tags' {
		Mock Get-RepositoryId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-ProductionProjectId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-TestProjectId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-ReviewerId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		# Mock a successful web request
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 200
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories\?.*" `
				-and $Method -eq "POST"
		} `
		-ModuleName 51DReleaseTestEnvModule
		Mock Add-RepositoryBranches { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-RepositoryTags { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$result = Add-Repository -RepositoryName "TestRepo" -RepositoryConfig $(New-Object -TypeName Object)
		$result | Should -BeExactly $false
	}
	
	It 'Fails to update package versions' {
		Mock Get-RepositoryId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-ProductionProjectId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-TestProjectId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Get-ReviewerId { return 1 } `
			-ModuleName 51DReleaseTestEnvModule
		# Mock a successful web request
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 200
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories\?.*" `
				-and $Method -eq "POST"
		} `
		-ModuleName 51DReleaseTestEnvModule
		Mock Add-RepositoryBranches { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-RepositoryTags { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Update-RepositoryPackageVersions { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$result = Add-Repository -RepositoryName "TestRepo" -RepositoryConfig $(New-Object -TypeName Object)
		$result | Should -BeExactly $false
	}
}

# All tests for Add-RepositoryBranches
Describe 'Add-RepositoryBranches' {
	It 'Add all branches' {
		Mock Add-RepositoryBranch { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{
			"branches": [
				"branch1",
				"branch2"
			]
		}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryBranches -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $true
	}
	
	It 'No branch to add' {
		Mock Add-RepositoryBranch { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryBranches -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $true
	}
	
	It 'Fails to add a branch' {
		Mock Add-RepositoryBranch { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{
			"branches": [
				"branch1",
				"branch2"
			]
		}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryBranches -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $false
	}
}

# All tests for Add-RepositoryBranch
Describe 'Add-RepositoryBranch' {
	It 'Add a branch' {
		Mock Get-Branch { return $('{ "objectId" : "0" }' | ConvertFrom-Json) } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 200
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories/.*/refs\?.*" `
				-and $Method -eq "POST"
		} `
		-ModuleName 51DReleaseTestEnvModule
		$testBranch = '{ "base": "testSource", "name": "testTarget" }' | ConvertFrom-Json
		$result = Add-RepositoryBranch -RepositoryName "TestRepo" -Branch $testBranch
		$result | Should -BeExactly $true
	}
	
	It 'Fails to get default branch' {
		Mock Get-Branch { return $null } `
			-ModuleName 51DReleaseTestEnvModule
		$testBranch = '{ "base": "testSource", "name": "testTarget" }' | ConvertFrom-Json
		$result = Add-RepositoryBranch -RepositoryName "TestRepo" -Branch $testBranch
		$result | Should -BeExactly $false
	}
	
	It 'Fails to create a branch' {
		Mock Get-Branch { return $('{ "objectId" : "0" }' | ConvertFrom-Json) } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 500
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories/.*/refs\?.*" `
				-and $Method -eq "POST"
		} `
		-ModuleName 51DReleaseTestEnvModule
		$testBranch = '{ "source": "testSource", "target": "testTarget" }' | ConvertFrom-Json
		{ Add-RepositoryBranch `
			-RepositoryName "TestRepo" `
		-Branch $testBranch } | Should -Throw
	}
}

# All tests for Add-RepositoryTags
Describe 'Add-RepositoryTags' {
	It 'Add all tags' {
		Mock Add-RepositoryTag { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{
			"tags": [
				"tag1",
				"tag2"
			]
		}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryTags -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $true
	}
	
	It 'No tag to add' {
		Mock Add-RepositoryTag { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryTags -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $true
	}
	
	It 'Fails to add a tag' {
		Mock Add-RepositoryTag { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{
			"tags": [
				"tag1",
				"tag2"
			]
		}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryTags -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $false
	}
}

# All tests for Add-RepositoryTag
Describe 'Add-RepositoryTag' {
	It 'Add a tag' {
		Mock Get-MainBranch { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		# Mock a successful web request
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 200
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories/.*/annotatedtags\?.*" `
				-and $Method -eq "POST"
		} `
		-ModuleName 51DReleaseTestEnvModule
		$result = Add-RepositoryTag -RepositoryName "TestRepo" -Tag "TestTag"
		$result | Should -BeExactly $true
	}
	
	It 'Main branch does not exist' {
		Mock Get-MainBranch { return $null } `
			-ModuleName 51DReleaseTestEnvModule
		$result = Add-RepositoryTag -RepositoryName "TestRepo" -Tag "TestTag"
		$result | Should -BeExactly $false
	}
	
	It 'Main branch does not exist' {
		Mock Get-MainBranch { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Invoke-WebRequest {
			return @{
				StatusCode = 500
			} 
		} `
		-ParameterFilter {
			$URI -match ".*repositories/.*/annotatedtags\?.*" `
				-and $Method -eq "POST"
		} `
		-ModuleName 51DReleaseTestEnvModule
		{ Add-RepositoryTag `
			-RepositoryName "TestRepo" `
			-Tag "TestTag" } | Should -Throw
	}
}

## All tests for Update-RepositoryPackageVersion
## NOTE: Currently not needed as updating versions does
## not depend on original version number.
# Describe 'Update-RepositoryPackageVersion' {
# 	It 'Update all package versions for Java' {
# 		$false | Should -BeExactly $true
# 	}
# 	
# 	It 'Update all package versions for Dotnet' {
# 		$false | Should -BeExactly $true
# 	}
# 
# 	It 'Update all package versions for Node' {
# 		$false | Should -BeExactly $true
# 	}
# 	
# 	It 'Update all package versions for Python' {
# 		$false | Should -BeExactly $true
# 	}
# 	
# 	# A place holder for word press
# 	It 'Fails to update package versions for WordPress' {
# 		$false | Should -BeExactly $true
# 	}
# 	
# 	It 'Fails to update all package versions for Java' {
# 		$false | Should -BeExactly $true
# 	}
# 	
# 	It 'Fails to update all package versions for Dotnet' {
# 		$false | Should -BeExactly $true
# 	}
# 
# 	It 'Fails to update all package versions for Node' {
# 		$false | Should -BeExactly $true
# 	}
# 	
# 	It 'Fails to update all package versions for Python' {
# 		$false | Should -BeExactly $true
# 	}
# }

# All tests for Add-Definitions
Describe 'Add-Definitions' {
	It 'Add all definitions' {
		Mock Add-RepositoryDefinitions { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"repo1": {
					"definitions": [
						"definition1"
					]
				}
			}
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-Definitions -Configuration $config
		$result | Should -BeExactly $true
	}
	
	It 'No definitions to add' {
		Mock Add-RepositoryDefinitions { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"repo1": {}
			}
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-Definitions -Configuration $config
		$result | Should -BeExactly $true
	}
	
	It 'Fails to add a definition' {
		Mock Add-RepositoryDefinitions { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"repo1": {
					"definitions": [
						"definition1"
					]
				}
			}
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-Definitions -Configuration $config
		$result | Should -BeExactly $false
	}
}

# All tetes for Add-RepositoryDefinitions
Describe 'Add-RepositoryDefinitions' {
	It 'Add all repository definitions' {
		Mock Add-RepositoryDefinition { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{
			"definitions": [
				"definition1",
				"definition2"
			]
		}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryDefinitions -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $true
	}
	
	It 'No definitions to add' {
		Mock Add-RepositoryDefinition { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryDefinitions -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $true
	}
	
	It 'Fails to add a definition' {
		Mock Add-RepositoryDefinition { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{
			"definitions": [
				"definition1",
				"definition2"
			]
		}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryDefinitions -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $false
	}
}

# All tests for Add-BuildTriggers
Describe 'Add-BuildTriggers' {
	It 'Add all build triggers' {
		Mock Add-RepositoryBuildTriggers { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"repo1": {
					"definitions": [
						"definition1"
					]
				}
			}
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-BuildTriggers -Configuration $config
		$result | Should -BeExactly $true
	}
	
	It 'No definitions to add' {
		Mock Add-RepositoryBuildTriggers { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"repo1": {}
			}
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-BuildTriggers -Configuration $config
		$result | Should -BeExactly $true
	}
	
	It 'Fails to add build triggers for a definition' {
		Mock Add-RepositoryBuildTriggers { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"repo1": {
					"definitions": [
						"definition1"
					]
				}
			}
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-BuildTriggers -Configuration $config
		$result | Should -BeExactly $false
	}
}

# All tetes for Add-RepositoryDefinitions
Describe 'Add-RepositoryBuildTriggers' {
	It 'Add all repository definitions' {
		Mock Add-RepositoryDefinitionBuildTriggers { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{
			"definitions": [
				"definition1",
				"definition2"
			]
		}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryBuildTriggers -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $true
	}
	
	It 'No definitions to add' {
		Mock Add-RepositoryDefinitionBuildTriggers { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryBuildTriggers -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $true
	}
	
	It 'Fails to add build triggers for a definition' {
		Mock Add-RepositoryDefinitionBuildTriggers { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{
			"definitions": [
				"definition1",
				"definition2"
			]
		}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryBuildTriggers -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $false
	}
}

# All tests for Add-Policies
Describe 'Add-Policies' {
	It 'Add all policies' {
		Mock Add-RepositoryPolicy { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-RepositoryPolicies { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"repo1": {
					"policies": [
						"repoPolicy1"
					]
				}
			},
			"policies": [
				"policy1"
			]
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-Policies -Configuration $config
		$result | Should -BeExactly $true
	}
	
	It 'No policies to add' {
		Mock Add-RepositoryPolicy { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-RepositoryPolicies { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"repo1": {}
			}
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-Policies -Configuration $config
		$result | Should -BeExactly $true
	}
	
	It 'Fails to add a global policy' {
		Mock Add-RepositoryPolicy { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"repo1": {}
			},
			"policies": [
				"policy1"
			]
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-Policies -Configuration $config
		$result | Should -BeExactly $false
	}
	
	It 'Fails to add repository policies' {
		Mock Add-RepositoryPolicy { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-RepositoryPolicies { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"repo1": {
					"policies": [
						"repoPolicy1"
					]
				}
			},
			"policies": [
				"policy1"
			]
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-Policies -Configuration $config
		$result | Should -BeExactly $false
	}
}

# All tests for Add-RepositoryPolicies
Describe 'Add-RepositoryPolicies' {
	It 'Add all repository policies' {
		Mock Add-RepositoryPolicy { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{
			"policies": [
				"policy1",
				"policy2"
			]
		}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryPolicies -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $true
	}
	
	It 'No policies to add' {
		Mock Add-RepositoryPolicy { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryPolicies -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $true
	}
	
	It 'Fails to add a policy' {
		Mock Add-RepositoryPolicy { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$repoJson = '{
			"policies": [
				"policy1",
				"policy2"
			]
		}'
		$repoConfig = $repoJson | Out-String | ConvertFrom-Json
		$result = Add-RepositoryPolicies -RepositoryName "TestRepo" -RepositoryConfig $repoConfig
		$result | Should -BeExactly $false
	}
}

# All tests for Add-PullRequests
Describe 'Add-PullRequests' {
	It 'Add all pull requests' {
		Mock New-PullRequest { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-PullRequestComment { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"repo1": {
					"pullrequests": [
						{
							"source" : "sourceRef",
							"target" : "targetRef",
							"comment" : true
						}
					]
				}
			}
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-PullRequests -Configuration $config
		$result | Should -BeExactly $true
	}
	
	It 'No pull requests to add' {
		Mock New-PullRequest { return $('{"pullRequestId" : 1}' | ConvertFrom-Json) } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-PullRequestComment { return $true } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"repo1": {}
			}
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-PullRequests -Configuration $config
		$result | Should -BeExactly $true
	}
	
	It 'Fails to add a pull request' {
		Mock New-PullRequest { return $null } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"repo1": {
					"pullrequests": [
						{
							"source" : "sourceRef",
							"target" : "targetRef"
						}
					]
				}
			}
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-PullRequests -Configuration $config
		$result | Should -BeExactly $false
	}
	
	It 'Fails to add a pull request with comment' {
		Mock New-PullRequest { return $('{"pullRequestId" : 1}' | ConvertFrom-Json) } `
			-ModuleName 51DReleaseTestEnvModule
		Mock Add-PullRequestComment { return $false } `
			-ModuleName 51DReleaseTestEnvModule
		$configJson = '{
			"repositories": {
				"repo1": {
					"pullrequests": [
						{
							"source" : "sourceRef",
							"target" : "targetRef",
							"comment" : true
						}
					]
				}
			}
		}'
		$config = $configJson | Out-String | ConvertFrom-Json
		$result = Add-PullRequests -Configuration $config
		$result | Should -BeExactly $false
	}
	
	# Cannot vote using Rest APIs.
	It 'Fails to add a pull request with votes' {
		$true | Should -BeExactly $true
	}

	# We don't check build validation because the pull request completion
	# is only performed once the build and test succeeded.
	It 'Fails to add a pull request with failed build validation' {
		$true | Should -BeExactly $true
	}
}
