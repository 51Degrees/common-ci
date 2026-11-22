# All tests for 'Test-ConfigFile' function
Describe 'Test-ConfigFile' {
	It 'valid config file' {
		$config = '{
			"name": "APIs Test Environment Configuration",
			"repositories": {
				"ci-test-repo-1": {
					"releaseVersion": "4.3.0",
					"tags": [
						"4.3.0"
					],
					"pullRequests": [
						{
							"source": "release/v4.3.0",
							"target": "main"
						}
					],
					"definitions": [
						{
							"name": "ci-test-repo-1",
							"defaultBranch": "main",
							"yamlFileName": "build-and-test.yml"
						}
					],
					"branches": [
						{
							"refName": "refs/heads/hotfix/v5.3.1",
							"refBase": "refs/heads/main"
						}
					],
					"submodules": []
				},
				"ci-test-repo-3": {
					"releaseVersion": "4.3.0",
					"tags": [
						"4.3.0"
					],
					"pullRequests": [
						{
							"source": "release/v4.3.0",
							"target": "main",
							"comment": true
						}
					],
					"definitions": [
						{
							"name": "ci-test-repo-3-test",
							"defaultBranch": "main",
							"yamlFileName": "build-and-test.yml",
							"triggers": [
								{
									"definitionName": "ci-test-repo-1-test",
									"requiresSuccessfulBuild": true,
									"branchFilters": [
										"+refs/heads/main"
									],
									"triggerType": "buildCompletion"
								}
							]
						}
					],
					"policies": [
						{
							"definition": "ci-test-repo-3-test",
							"type": "Build",
							"refName": "refs/heads/main",
							"matchKind": "Exact"
						}
					],
					"submodules": [
						"ci-test-repo-1"
					]
				}
			},
			"policies": [
				{
					"type": "Required reviewers"
				}
			]
		}' | ConvertFrom-Json
		$result = Test-ConfigFile -Configuration $config
		$result | Should -BeExactly $true
	}
	
	It 'missing submodule definition' {
		$config = '{
			"repositories": {
				"repo1": {
					"submodules": [
						"repo2"
					]
				}
			}
		}' | ConvertFrom-Json
		$result = Test-Submodules `
			-Configuration $config `
			-Submodules $config.repositories.repo1.submodules
		$result | Should -BeExactly $false
	}
	
	It 'invalid tag' {
		$result = Test-Tags -Tags $("a.b.c")
		$result | Should -BeExactly $false
	}
	
	It 'invalid pull request source and target' {
		# No 'source' is specified
		$pullrequests1 = '[
			{
				"target": "main"
			}
		]' | ConvertFrom-Json
		$result = Test-PullRequests -PullRequest $pullrequests1
		$result | Should -BeExactly $false
		
		# No 'target' is specified
		$pullrequests2 = '[
			{
				"source": "main"
			}
		]' | ConvertFrom-Json
		$result = Test-PullRequests -PullRequest $pullrequests2
		$result | Should -BeExactly $false
	}
	
	It 'invalid pull request comment' {
		# Invalid 'comment' value
		$pullrequests = '[
			{
				"source": "source",
				"target": "target",
				"comment": 1
			}
		]' | ConvertFrom-Json
		$result = Test-PullRequests -PullRequest $pullrequests
		$result | Should -BeExactly $false
	}
	
	It 'invalid definition general' {
		# No 'name' is pecified
		$definitions = '[
			{
				"defaultBranch": "main",
				"yamlFileName": "build-and-test.yml"
			}
		]' | ConvertFrom-Json
		$result = Test-Definitions -Definitions $definitions
		$result | Should -BeExactly $false
		
		# No 'defaultBranch' is pecified
		$definitions = '[
			{
				"name": "test-repo",
				"yamlFileName": "build-and-test.yml"
			}
		]' | ConvertFrom-Json
		$result = Test-Definitions -Definitions $definitions
		$result | Should -BeExactly $false
		
		# No 'yamlFileName' is pecified
		$definitions = '[
			{
				"name": "test-repo",
				"defaultBranch": "main"
			}
		]' | ConvertFrom-Json
		$result = Test-Definitions -Definitions $definitions
		$result | Should -BeExactly $false
	}
	
	It 'invalid definition triggers' {
		# No 'definitionName' is pecified
		$triggers = '[
			{
				"requiresSuccessfulBuild": true,
				"branchFilters": ["+refs/heads/main"],
				"triggerType": "buildCompletion"
			}
		]' | ConvertFrom-Json
		$result = Test-Triggers -Triggers $triggers
		$result | Should -BeExactly $false
		
		# Incorrect 'requiresSuccessfulBuild' is pecified
		$triggers = '[
			{
				"definitionName": "ci-test-repo-1-test",
				"requiresSuccessfulBuild": 1,
				"branchFilters": ["+refs/heads/main"],
				"triggerType": "buildCompletion"
			}
		]' | ConvertFrom-Json
		$result = Test-Triggers -Triggers $triggers
		$result | Should -BeExactly $false
		
		# No 'branchFilters' is pecified
		$triggers = '[
			{
				"definitionName": "ci-test-repo-1-test",
				"requiresSuccessfulBuild": true,
				"triggerType": "buildCompletion"
			}
		]' | ConvertFrom-Json
		$result = Test-Triggers -Triggers $triggers
		$result | Should -BeExactly $false
		
		# Empty 'branchFilters' is pecified
		$triggers = '[
			{
				"definitionName": "ci-test-repo-1-test",
				"requiresSuccessfulBuild": true,
				"branchFilters": [],
				"triggerType": "buildCompletion"
			}
		]' | ConvertFrom-Json
		$result = Test-Triggers -Triggers $triggers
		$result | Should -BeExactly $false
		
		# Incorrect 'triggerType' is pecified
		$triggers = '[
			{
				"definitionName": "ci-test-repo-1-test",
				"requiresSuccessfulBuild": true,
				"branchFilters": ["+refs/heads/main"],
				"triggerType": "Something else"
			}
		]' | ConvertFrom-Json
		$result = Test-Triggers -Triggers $triggers
		$result | Should -BeExactly $false
	}
	
	It 'invalid branches' {
		# 'refName' not specified
		$branches = '[
			{
				"base": "main"
			}
		]' | ConvertFrom-Json
		$result = Test-Branches -Branches $branches
		$result | Should -BeExactly $false
		
		# 'refBase' not specified
		$branches = '[
			{
				"name": "hotfix/v5.3.1"
			}
		]' | ConvertFrom-Json
		$result = Test-Branches -Branches $branches
		$result | Should -BeExactly $false
	}
	
	It 'invalid policies type' {
		# Invalid 'type'
		$policies = '[
			{
				"type": "Test type"
			}
		]' | ConvertFrom-Json
		$result = Test-Policies -Policies $policies
		$result | Should -BeExactly $false
	}
	
	It 'invalid policies type "Build"' {
		# No 'definition'
		$policies = '[
			{
				"type": "Build",
				"refName": "refs/heads/main",
				"matchKind": "Exact"
			}
		]' | ConvertFrom-Json
		$result = Test-Policies -Policies $policies
		$result | Should -BeExactly $false
		
		# No 'refName'
		$policies = '[
			{
				"definition": "ci-test-repo-3-test",
				"type": "Build",
				"matchKind": "Exact"
			}
		]' | ConvertFrom-Json
		$result = Test-Policies -Policies $policies
		$result | Should -BeExactly $false
		
		# Invalid 'refName'
		$policies = '[
			{
				"definition": "ci-test-repo-3-test",
				"type": "Build",
				"refName": "heads/main",
				"matchKind": "Exact"
			}
		]' | ConvertFrom-Json
		$result = Test-Policies -Policies $policies
		$result | Should -BeExactly $false
		
		# No 'matchKind'
		$policies = '[
			{
				"definition": "ci-test-repo-3-test",
				"type": "Build",
				"refName": "refs/heads/main"
			}
		]' | ConvertFrom-Json
		$result = Test-Policies -Policies $policies
		$result | Should -BeExactly $false
	}
	
	It 'Valid policies type "Required reviewers"' {
		$policies = '[
			{
				"type": "Required reviewers"
			}
		]' | ConvertFrom-Json
		$result = Test-Policies -Policies $policies
		$result | Should -BeExactly $true
	}
}