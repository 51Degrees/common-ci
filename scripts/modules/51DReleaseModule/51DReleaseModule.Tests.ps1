# All tests for 'Update-CommitPushPullSub' function
Describe 'Update-CommitPushPullSub' {
	It 'Successfully update commit push and create pull request' {
		Mock Get-RepositoryName { return "repository1" } `
			-ModuleName 51DReleaseModule
		Mock Test-TagExist { return $false } `
			-ModuleName 51DReleaseModule
		Mock Get-ReleaseBranch { return $true } `
			-ModuleName 51DReleaseModule
		Mock Update-SubmoduleReferences { return $true } `
			-ModuleName 51DReleaseModule
		Mock Update-PackageDependencies { return $true } `
			-ModuleName 51DReleaseModule
		Mock Start-CommitAndPush { return $true } `
			-ModuleName 51DReleaseModule
		Mock Get-TargetBranch { return New-Object -TypeName Object } `
			-ModuleName 51DReleaseModule
		Mock Get-PullRequestToMain { return $null } `
			-ModuleName 51DReleaseModule
		Mock New-PullRequestToMain { return $true } `
			-ModuleName 51DReleaseModule
		$configuration = '{
			"repositories": {
				"repository1": {
					"version": "0.1.0"
				}
			}
		}' | ConvertFrom-Json
		$result = Update-CommitPushPullSub -Configuration $configuration -DepTeamProjectName "testproj" -PrTeamProjectName "testproj"
		$result | Should -BeExactly $true
	}
	
	It 'Tag already exists' {
		Mock Get-RepositoryName { return "repository1" } `
			-ModuleName 51DReleaseModule
		Mock Test-TagExist { return $true } `
			-ModuleName 51DReleaseModule
		$configuration = '{
			"repositories": {
				"repository1": {
					"version": "0.1.0"
				}
			}
		}' | ConvertFrom-Json
		$result = $(Update-CommitPushPullSub -Configuration $configuration -DepTeamProjectName "testproj" -PrTeamProjectName "testproj")
		$result | Should -BeExactly $false
	}
	
	It 'Fails to get release branch' {
		Mock Get-RepositoryName { return "repository1" } `
			-ModuleName 51DReleaseModule
		Mock Test-TagExist { return $false } `
			-ModuleName 51DReleaseModule
		Mock Get-ReleaseBranch { return $false } `
			-ModuleName 51DReleaseModule
		$configuration = '{
			"repositories": {
				"repository1": {
					"version": "0.1.0"
				}
			}
		}' | ConvertFrom-Json
		$result = $(Update-CommitPushPullSub -Configuration $configuration -DepTeamProjectName "testproj" -PrTeamProjectName "testproj")
		$result | Should -BeExactly $false
	}
	
	It 'Fails to update submodule references' {
		Mock Get-RepositoryName { return "repository1" } `
			-ModuleName 51DReleaseModule
		Mock Test-TagExist { return $false } `
			-ModuleName 51DReleaseModule
		Mock Get-ReleaseBranch { return $true } `
			-ModuleName 51DReleaseModule
		Mock Update-SubmoduleReferences { return $false } `
			-ModuleName 51DReleaseModule
		$configuration = '{
			"repositories": {
				"repository1": {
					"version": "0.1.0"
				}
			}
		}' | ConvertFrom-Json
		$result = Update-CommitPushPullSub -Configuration $configuration -DepTeamProjectName "testproj" -PrTeamProjectName "testproj"
		$result | Should -BeExactly $false
	}
	
	It 'Fails to update package dependencies' {
		Mock Get-RepositoryName { return "repository1" } `
			-ModuleName 51DReleaseModule
		Mock Test-TagExist { return $false } `
			-ModuleName 51DReleaseModule
		Mock Get-ReleaseBranch { return $true } `
			-ModuleName 51DReleaseModule
		Mock Update-SubmoduleReferences { return $true } `
			-ModuleName 51DReleaseModule
		Mock Update-PackageDependencies { return $false } `
			-ModuleName 51DReleaseModule
		$configuration = '{
			"repositories": {
				"repository1": {
					"version": "0.1.0"
				}
			}
		}' | ConvertFrom-Json
		$result = Update-CommitPushPullSub -Configuration $configuration -DepTeamProjectName "testproj" -PrTeamProjectName "testproj"
		$result | Should -BeExactly $false
	}
	
	It 'Fails to commit and push changes' {
		Mock Get-RepositoryName { return "repository1" } `
			-ModuleName 51DReleaseModule
		Mock Test-TagExist { return $false } `
			-ModuleName 51DReleaseModule
		Mock Get-ReleaseBranch { return $true } `
			-ModuleName 51DReleaseModule
		Mock Update-SubmoduleReferences { return $true } `
			-ModuleName 51DReleaseModule
		Mock Update-PackageDependencies { return $true } `
			-ModuleName 51DReleaseModule
		Mock Start-CommitAndPush { return $false } `
			-ModuleName 51DReleaseModule
		$configuration = '{
			"repositories": {
				"repository1": {
					"version": "0.1.0"
				}
			}
		}' | ConvertFrom-Json
		$result = Update-CommitPushPullSub `
			-Configuration $configuration `
			-DepTeamProjectName "testproj" `
			-PrTeamProjectName "testproj"
		$result | Should -BeExactly $false
	}
	
	It 'A pull request already exists' {
		Mock Get-RepositoryName { return "repository1" } `
			-ModuleName 51DReleaseModule
		Mock Test-TagExist { return $false } `
			-ModuleName 51DReleaseModule
		Mock Get-ReleaseBranch { return $true } `
			-ModuleName 51DReleaseModule
		Mock Update-SubmoduleReferences { return $true } `
			-ModuleName 51DReleaseModule
		Mock Update-PackageDependencies { return $true } `
			-ModuleName 51DReleaseModule
		Mock Start-CommitAndPush { return $true } `
			-ModuleName 51DReleaseModule
		Mock Get-TargetBranch { return New-Object -TypeName Object } `
			-ModuleName 51DReleaseModule
		Mock Get-PullRequestToMain { return New-Object -TypeName Object } `
			-ModuleName 51DReleaseModule
		$configuration = '{
			"repositories": {
				"repository1": {
					"version": "0.1.0"
				}
			}
		}' | ConvertFrom-Json
		$result = Update-CommitPushPullSub -Configuration $configuration -DepTeamProjectName "testproj" -PrTeamProjectName "testproj"
		$result | Should -BeExactly $true
	}
	
	It 'Fails to create a pull request to main' {
		Mock Get-RepositoryName { return "repository1" } `
			-ModuleName 51DReleaseModule
		Mock Test-TagExist { return $false } `
			-ModuleName 51DReleaseModule
		Mock Get-ReleaseBranch { return $true } `
			-ModuleName 51DReleaseModule
		Mock Update-SubmoduleReferences { return $true } `
			-ModuleName 51DReleaseModule
		Mock Update-PackageDependencies { return $true } `
			-ModuleName 51DReleaseModule
		Mock Start-CommitAndPush { return $true } `
			-ModuleName 51DReleaseModule
		Mock Get-TargetBranch { return New-Object -TypeName Object } `
			-ModuleName 51DReleaseModule
		Mock Get-PullRequestToMain { return $null } `
			-ModuleName 51DReleaseModule
		Mock New-PullRequestToMain { return $false } `
			-ModuleName 51DReleaseModule
		$configuration = '{
			"repositories": {
				"repository1": {
					"version": "0.1.0"
				}
			}
		}' | ConvertFrom-Json
		$result = Update-CommitPushPullSub -Configuration $configuration -DepTeamProjectName "testproj" -PrTeamProjectName "testproj"
		$result | Should -BeExactly $false
	}
}

InModuleScope 51DReleaseModule {
	Describe 'Start-Release' {
		It 'successfully determine action for each project. Leaf action required' {
			Write-Host "Start-Release tests"
			$mockConfig = '{
				"repositories": {
					"repo1": {
						"version": "4.3.0",
						"isLeaf": true
					},
					"repo2": {
						"version": "4.3.0",
						"isLeaf": false,
						"dependencies": [
							"repo1"
						]
					}
				},
				"approvalRequired": false
			}'
			Mock Get-Content { return $mockConfig } `
				-ModuleName 51DReleaseModule
			Mock Test-TagExist { return $false } `
				-ModuleName 51DReleaseModule
			Mock Get-ReleaseBranchRef { return "refs/heads/release/4.3.0" } `
				-ModuleName 51DReleaseModule
			Mock Start-ProcessPullRequest { return $true } `
				-ModuleName 51DReleaseModule
			Start-Release -ConfigFile "someFile" -TeamProjectName "testproj"
			$actionTable = Get-ActionTable
			$traveledTable = Get-TraveledTable
			Write-Host "# Test action table"
			$actionTable.keys.count | Should -BeExactly 1
			$actionTable.keys[0] | Should -Be 'repo1'
			Write-Host "# Test traveled table $($traveledTable.keys[0])"
			$traveledTable.keys.count | Should -BeExactly 2
			$traveledTable['repo1'] | Should -Be $true
			$traveledTable['repo2'] | Should -Be $true
		}
		
		It 'successfully determine action for each project. None leaf action required' {
			Write-Host "Start-Release tests"
			$mockConfig = '{
				"repositories": {
					"repo1": {
						"version": "4.3.0",
						"isLeaf": true
					},
					"repo2": {
						"version": "4.3.0",
						"isLeaf": false,
						"dependencies": [
							"repo1"
						]
					}
				},
				"approvalRequired": false
			}'
			Mock Get-Content { return $mockConfig } `
				-ModuleName 51DReleaseModule
			Mock Test-TagExist { return $false } `
				-ModuleName 51DReleaseModule `
				-ParameterFilter { $RepositoryName -eq "repo2" }
			Mock Test-TagExist { return $true } `
				-ModuleName 51DReleaseModule `
				-ParameterFilter { $RepositoryName -eq "repo1" }
			Mock Get-ReleaseBranchRef { return "refs/heads/release/4.3.0" } `
				-ModuleName 51DReleaseModule
			Mock Start-ProcessPullRequest { return $true } `
				-ModuleName 51DReleaseModule
			Start-Release -ConfigFile "someFile" -TeamProjectName "testproj"
			$actionTable = Get-ActionTable
			$traveledTable = Get-TraveledTable
			Write-Host "# Test action table"
			$actionTable.keys.count | Should -BeExactly 1
			$actionTable.keys[0] | Should -Be 'repo2'
			Write-Host "# Test traveled table $($traveledTable.keys[0])"
			$traveledTable.keys.count | Should -BeExactly 2
			$traveledTable['repo1'] | Should -Be $true
			$traveledTable['repo2'] | Should -Be $true
		}
	}
}