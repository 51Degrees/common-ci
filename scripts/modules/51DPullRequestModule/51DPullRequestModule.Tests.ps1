Describe 'Complete-CorrespondingPullRequest' {
	It 'fail if is not a release pull request' {
		# Set required environment variable
		# Save current source branch env variable
		$buildSrcBranch = $Env:BUILD_SOURCEBRANCH
		$Env:BUILD_SOURCEBRANCH = "refs/pull/123/merge"
		Mock Test-IsReleasePullRequest { return $false } `
			-ModuleName 51DPullRequestModule
		Mock Get-Content { return "{}" } `
			-ModuleName 51DPullRequestModule
		
		$result = Complete-CorrespondingPullRequest -ConfigFile "afile"
		# Unset required environment variable
		$Env:BUILD_SOURCEBRANCH = $buildSrcBranch
		
		$result | Should -BeExactly $false
	}
	
	It 'fail to update submodule references' {
		# Set required environment variable
		$buildSrcBranch = $Env:BUILD_SOURCEBRANCH
		$Env:BUILD_SOURCEBRANCH = "refs/pull/123/merge"
		Mock Test-IsReleasePullRequest { return $true } `
			-ModuleName 51DPullRequestModule
		Mock Update-SubmoduleReferences { return $false } `
			-ModuleName 51DPullRequestModule
		Mock Get-Content { return "{}" } `
			-ModuleName 51DPullRequestModule
		
		$result = Complete-CorrespondingPullRequest -ConfigFile "afile"
		# Unset required environment variable
		$Env:BUILD_SOURCEBRANCH = $buildSrcBranch
		
		$result | Should -BeExactly $false
	}
}

InModuleScope '51DPullRequestModule' {
	Describe 'Complete-PullRequest' {
		It 'Successfully complete without approval' {
			# Mock get last merge commit
			Mock Invoke-WebRequest {
				return @{
					StatusCode = 200
				} 
			} `
			-ParameterFilter {
				$Method -eq "GET"
			} `
			-ModuleName 51DPullRequestModule
			# Mock complete pull request
			Mock Invoke-WebRequest {
				return @{
					StatusCode = 200
				} 
			} `
			-ParameterFilter {
				$Method -eq "PATCH"
			} `
			-ModuleName 51DPullRequestModule
			$result = Complete-PullRequest `
				-RepositoryName "repo1" `
				-PullRequestId '1234' `
				-ApprovalRequired $false `
				-TeamProjectName "testproj"
			$result | Should -BeExactly $true
		}
		
		It 'Successfully complete with approval' {
			Mock Test-PullRequestVotes { return $true  } `
				-ModuleName 51DPullRequestModule
			Mock Test-PullRequestComments { return $true  } `
				-ModuleName 51DPullRequestModule
			# Mock get last merge commit
			Mock Invoke-WebRequest {
				return @{
					StatusCode = 200
				} 
			} `
			-ParameterFilter {
				$Method -eq "GET"
			} `
			-ModuleName 51DPullRequestModule
			# Mock complete pull request
			Mock Invoke-WebRequest {
				return @{
					StatusCode = 200
				} 
			} `
			-ParameterFilter {
				$Method -eq "PATCH"
			} `
			-ModuleName 51DPullRequestModule
			$result = Complete-PullRequest `
				-RepositoryName "repo1" `
				-PullRequestId '1234' `
				-ApprovalRequired $true `
				-TeamProjectName "testproj"
			$result | Should -BeExactly $true
		}
		
		It 'requires approval but missing votes' {
			Mock Test-PullRequestVotes { return $false  } `
				-ModuleName 51DPullRequestModule
			Mock Test-PullRequestComments { return $true  } `
				-ModuleName 51DPullRequestModule
			# Mock get last merge commit
			Mock Invoke-WebRequest {
				return @{
					StatusCode = 200
				} 
			} `
			-ParameterFilter {
				$Method -eq "GET"
			} `
			-ModuleName 51DPullRequestModule
			# Mock complete pull request
			Mock Invoke-WebRequest {
				return @{
					StatusCode = 200
				} 
			} `
			-ParameterFilter {
				$Method -eq "PATCH"
			} `
			-ModuleName 51DPullRequestModule
			$result = Complete-PullRequest `
				-RepositoryName "repo1" `
				-PullRequestId '1234' `
				-ApprovalRequired $true `
				-TeamProjectName "testproj"
			$result | Should -BeExactly $false
		}
		
		It 'requires approval but comment unresolved' {
			Mock Test-PullRequestVotes { return $false  } `
				-ModuleName 51DPullRequestModule
			Mock Test-PullRequestComments { return $true  } `
				-ModuleName 51DPullRequestModule
			# Mock get last merge commit
			Mock Invoke-WebRequest {
				return @{
					StatusCode = 200
				} 
			} `
			-ParameterFilter {
				$Method -eq "GET"
			} `
			-ModuleName 51DPullRequestModule
			# Mock complete pull request
			Mock Invoke-WebRequest {
				return @{
					StatusCode = 200
				} 
			} `
			-ParameterFilter {
				$Method -eq "PATCH"
			} `
			-ModuleName 51DPullRequestModule
			$result = Complete-PullRequest `
				-RepositoryName "repo1" `
				-PullRequestId '1234' `
				-ApprovalRequired $true `
				-TeamProjectName "testproj"
			$result | Should -BeExactly $false
		}
	}
	
	Describe 'Start-ProcessPullRequest' {
		It 'successfull complete pull request to main' {
			Mock Get-PullRequestToMain { return New-Object -TypeName Object } `
				-ModuleName 51DPullRequestModule
			Mock Restart-TestBuild { return $true } `
				-ModuleName 51DPullRequestModule
			$result = Start-ProcessPullRequest `
				-RepositoryName "repo1" `
				-ReleaseBranch "release1" `
				-TeamProjectName "testproj"
			$result | Should -BeExactly $true
		}
		
		It 'pull request to main already exist' {
			Mock Get-PullRequestToMain { return $null } `
				-ModuleName 51DPullRequestModule
			Mock New-PullRequestToMain { return $true } `
				-ModuleName 51DPullRequestModule
			$result = Start-ProcessPullRequest `
				-RepositoryName "repo1" `
				-ReleaseBranch "release1" `
				-TeamProjectName "testproj"
			$result | Should -BeExactly $true
		}
	}
}