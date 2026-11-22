InModuleScope ReleaseVerifier {
	Describe 'Test-Repositories' {
		It 'pass all repositories verification' {
			Mock New-Item {} `
				-ModuleName ReleaseVerifier
			Mock Pop-Location {} `
				-ModuleName ReleaseVerifier
			Mock Push-Location {} `
				-ModuleName ReleaseVerifier
			Mock Test-Path { return $true } `
				-ModuleName ReleaseVerifier
			Mock Test-Repository { return $true } `
				-ModuleName ReleaseVerifier
			$repositories = '{
				"repo1": {
					"version": "0.0.0"
				}
			}' | ConvertFrom-Json
			$result = Test-Repositories `
				-Repositories $repositories `
				-Force `
				-TeamProjectName "testproj"
			$result | Should -BeExactly $true
		}
		
		It 'fail a repository verification' {
			Mock New-Item {} `
				-ModuleName ReleaseVerifier
			Mock Pop-Location {} `
				-ModuleName ReleaseVerifier
			Mock Push-Location {} `
				-ModuleName ReleaseVerifier
			Mock Test-Path { return $true } `
				-ModuleName ReleaseVerifier
			Mock Test-Repository { return $false } `
				-ModuleName ReleaseVerifier
			$repositories = '{
				"repo1": {
					"version": "0.0.0"
				}
			}' | ConvertFrom-Json
			$result = Test-Repositories `
				-Repositories $repositories `
				-Force `
				-TeamProjectName "testproj"
			$result | Should -BeExactly $false
		}
	}
	
	Describe 'Test-Repository' {
		It 'pass all verification' {
			Mock Use-Repository { return $true } `
				-ModuleName ReleaseVerifier
			Mock Test-TagExist { return $true } `
				-ModuleName ReleaseVerifier
			Mock Get-ReleaseBranchRef { return $(New-Object -TypeName Object) } `
				-ModuleName ReleaseVerifier
			Mock Test-GitVersion { return $true } `
				-ModuleName ReleaseVerifier
			Mock Test-SubmoduleReferences { return $true } `
				-ModuleName ReleaseVerifier
			Mock Test-PackageDependencies { return $true } `
				-ModuleName ReleaseVerifier
			Mock Push-Location {} `
				-ModuleName ReleaseVerifier
			Mock Pop-Location {} `
				-ModuleName ReleaseVerifier
			$repositories = '{
				"repo1": {
					"version": "0.0.0"
				}
			}' | ConvertFrom-Json
			$result = Test-Repository `
				-RepositoryName "repo1" `
				-RepositoryConfig $('{ "version": "test-version" }' | ConvertFrom-Json) `
				-Repositories $repositories `
				-TeamProjectName "testproj"
			$result | Should -BeExactly $true
		}
		
		It 'fail to check out repository' {
			Mock Use-Repository { return $false } `
				-ModuleName ReleaseVerifier
			Mock Push-Location {} `
				-ModuleName ReleaseVerifier
			Mock Pop-Location {} `
				-ModuleName ReleaseVerifier
			$repositories = '{
				"repo1": {
					"version": "0.0.0"
				}
			}' | ConvertFrom-Json
			$result = Test-Repository `
				-RepositoryName "repo1" `
				-RepositoryConfig $(New-Object -TypeName Object) `
				-Repositories $repositories `
				-TeamProjectName "testproj"
			$result | Should -BeExactly $false
		}
		
		It 'fail the tag verification' {
			Mock Use-Repository { return $true } `
				-ModuleName ReleaseVerifier
			Mock Test-TagExist { return $false } `
				-ModuleName ReleaseVerifier
			Mock Push-Location {} `
				-ModuleName ReleaseVerifier
			Mock Pop-Location {} `
				-ModuleName ReleaseVerifier
			$repositories = '{
				"repo1": {
					"version": "0.0.0"
				}
			}' | ConvertFrom-Json
			$result = Test-Repository `
				-RepositoryName "repo1" `
				-RepositoryConfig $('{ "version": "test-version" }' | ConvertFrom-Json) ` `
				-Repositories $repositories `
				-TeamProjectName "testproj"
			$result | Should -BeExactly $false
		}
		
		It 'fail the GitVersion.yml verification' {
			Mock Use-Repository { return $true } `
				-ModuleName ReleaseVerifier
			Mock Test-TagExist { return $true } `
				-ModuleName ReleaseVerifier
			Mock Get-ReleaseBranchRef { return $null } `
				-ModuleName ReleaseVerifier
			Mock Test-GitVersion { return $false } `
				-ModuleName ReleaseVerifier
			Mock Push-Location {} `
				-ModuleName ReleaseVerifier
			Mock Pop-Location {} `
				-ModuleName ReleaseVerifier
			$repositories = '{
				"repo1": {
					"version": "0.0.0"
				}
			}' | ConvertFrom-Json
			$result = Test-Repository `
				-RepositoryName "repo1" `
				-RepositoryConfig $('{ "version": "test-version" }' | ConvertFrom-Json) ` `
				-Repositories $repositories `
				-TeamProjectName "testproj"
			$result | Should -BeExactly $false
		}
		
		It 'fail the submodule references verification' {
			Mock Use-Repository { return $true } `
				-ModuleName ReleaseVerifier
			Mock Test-TagExist { return $true } `
				-ModuleName ReleaseVerifier
			Mock Get-ReleaseBranchRef { return $(New-Object -TypeName Object) } `
				-ModuleName ReleaseVerifier
			Mock Test-GitVersion { return $true } `
				-ModuleName ReleaseVerifier
			Mock Test-SubmoduleReferences { return $false } `
				-ModuleName ReleaseVerifier
			Mock Push-Location {} `
				-ModuleName ReleaseVerifier
			Mock Pop-Location {} `
				-ModuleName ReleaseVerifier
			$repositories = '{
				"repo1": {
					"version": "0.0.0"
				}
			}' | ConvertFrom-Json
			$result = Test-Repository `
				-RepositoryName "repo1" `
				-RepositoryConfig $('{ "version": "test-version" }' | ConvertFrom-Json) ` `
				-Repositories $repositories `
				-TeamProjectName "testproj"
			$result | Should -BeExactly $false
		}
		
		It 'fail the package dependencies verification' {
			Mock Use-Repository { return $true } `
				-ModuleName ReleaseVerifier
			Mock Test-TagExist { return $true } `
				-ModuleName ReleaseVerifier
			Mock Get-ReleaseBranchRef { return $(New-Object -TypeName Object) } `
				-ModuleName ReleaseVerifier
			Mock Test-GitVersion { return $true } `
				-ModuleName ReleaseVerifier
			Mock Test-SubmoduleReferences { return $true } `
				-ModuleName ReleaseVerifier
			Mock Test-PackageDependencies { return $false } `
				-ModuleName ReleaseVerifier
			Mock Push-Location {} `
				-ModuleName ReleaseVerifier
			Mock Pop-Location {} `
				-ModuleName ReleaseVerifier
			$repositories = '{
				"repo1": {
					"version": "0.0.0"
				}
			}' | ConvertFrom-Json
			$result = Test-Repository `
				-RepositoryName "repo1" `
				-RepositoryConfig $('{ "version": "test-version" }' | ConvertFrom-Json) ` `
				-Repositories $repositories `
				-TeamProjectName "testproj"
			$result | Should -BeExactly $false
		}
	}
	
	Describe 'Use-Repository' {
	#	It 'successfully checkout a repository branch' {
	#		# Since it is not possible to guarantee any repo will exist
	#		# in the future. Use the current repository of the script to
	#		# test.
	#		$remoteUrl = git remote get-url origin
	#		if ($remoteUrl -match ".*/_git/(?<repo>.*$)") {
	#			$testRepo = $Matches['repo']
	#		} else {
	#			$false | Should -BeExactly $true -Because "# ERROR: current directory is not a git directory"
	#		}
	#		
	#		if([string]::IsNullOrEmpty($(git branch -r | Select-String "origin/main"))) {
	#			$branch = "refs/heads/master"
	#		} else {
	#			$branch = "refs/heads/main"
	#		}
	#		Mock Get-MainBranchRef { return $branch } `
	#			-ModuleName ReleaseVerifier
	#		Mock Get-RepositoryRemoteUrl { return $remoteUrl } `
	#			-ModuleName ReleaseVerifier
	#		
	#		$result = Use-Repository -RepositoryName $testRepo
	#		$result | Should -BeExactly $true
	#		
	#		# Verify if the repository is as expected
	#		Push-Location $testRepo
	#		$? | Should -BeExactly $true
	#		
	#		# Check if on main or master branch
	#		$isMasterMain = $(git rev-parse --abbrev-ref HEAD) -match "(master|main)"
	#		Pop-Location
	#		$? | should -BeExactly $true
	#		
	#		$isMasterMain | Should -BeExactly $true
	#	}
	
		It 'fails get main branch ref' {
			Mock Get-MainBranchRef { return 'nothing' } `
				-ModuleName ReleaseVerifier
			$result = Use-Repository -RepositoryName "testName" -TeamProjectName "testproj"
			$result | Should -BeExactly $false
		}
	
		It 'fails get repository remote url' {
			Mock Get-MainBranchRef { return 'refs/heads/main' } `
				-ModuleName ReleaseVerifier
			Mock Get-RepositoryRemoteUrl { return $null } `
				-ModuleName ReleaseVerifier
			$result = Use-Repository -repositoryName "testName" -TeamProjectName "testproj"
			$result | Should -BeExactly $false
		}
	}
	
	Describe 'Test-GitVersion' {
		It 'correct git version update' {
			$testVersion = "4.3.0"
			Mock Test-Path { return $true } `
				-ModuleName ReleaseVerifier
			Mock Get-Content { return "next-version: $testVersion" } `
				-ModuleName ReleaseVerifier
			$configStr = @"
			{
				"version": "$testVersion"
			}
"@
			$config = $configStr | ConvertFrom-Json

			$result = Test-GitVersion -RepositoryConfig $config
			$result | Should -BeExactly $true
		}
		
		It 'no GitVersion.yml exists' {
			Mock Test-Path { return $false } `
				-ModuleName ReleaseVerifier
			$result = Test-GitVersion -RepositoryConfig $(New-Object -TypeName Object)
			$result | Should -BeExactly $false
		}
		
		It 'no next-version exists' {
			Mock Test-Path { return $true } `
				-ModuleName ReleaseVerifier
			Mock Get-Content { return "nothing" } `
				-ModuleName ReleaseVerifier
			$configStr = @"
			{
				"version": "4.3.0"
			}
"@
			$config = $configStr | ConvertFrom-Json

			$result = Test-GitVersion -RepositoryConfig $config
			$result | Should -BeExactly $false
		}
		
		It 'incorrect next-version exists' {
			$testVersion = "4.3.0"
			Mock Test-Path { return $true } `
				-ModuleName ReleaseVerifier
			Mock Get-Content { return "next-version: 0.0.0" } `
				-ModuleName ReleaseVerifier
			$configStr = @"
			{
				"version": "4.3.0"
			}
"@
			$config = $configStr | ConvertFrom-Json

			$result = Test-GitVersion -RepositoryConfig $config
			$result | Should -BeExactly $false
		}
	}
	
	Describe 'Test-SubmoduleReferences' {
		# Alot of the steps are require git repo, submodules
		# branches and tags to exists. It is also not possible
		# to mock git without any unnecessary wrapping functions.
	}
	
	Describe 'Test-PackageDependencies' {
		It 'all packages dependencies are up to date' {
			# Java packages
			$repoName = "test-java"
			Mock Test-MavenPackageDependencies { return $true } `
				-ModuleName ReleaseVerifier
			$result = Test-PackageDependencies `
				-RepositoryName $repoName `
				-RepositoryConfig $(New-Object -TypeName Object) `
				-Repositories $(New-Object -TypeName Object)
			$result | Should -BeExactly $true
			
			# Dotnet packages
			$repoName = "test-dotnet"
			Mock Test-DotnetPackageDependencies { return $true } `
				-ModuleName ReleaseVerifier
			$result = Test-PackageDependencies `
				-RepositoryName $repoName `
				-RepositoryConfig $(New-Object -TypeName Object) `
				-Repositories $(New-Object -TypeName Object)
			$result | Should -BeExactly $true
			
			# Node packages
			$repoName = "test-node"
			Mock Test-NodePackageDependencies { return $true } `
				-ModuleName ReleaseVerifier
			$result = Test-PackageDependencies `
				-RepositoryName $repoName `
				-RepositoryConfig $(New-Object -TypeName Object) `
				-Repositories $(New-Object -TypeName Object)
			$result | Should -BeExactly $true
			
			# Python packages
			$repoName = "test-python"
			Mock Test-PythonPackageDependencies { return $true } `
				-ModuleName ReleaseVerifier
			$result = Test-PackageDependencies `
				-RepositoryName $repoName `
				-RepositoryConfig $(New-Object -TypeName Object) `
				-Repositories $(New-Object -TypeName Object)
			$result | Should -BeExactly $true
		}
		
		It 'Maven packages dependencies are not up to date' {
			# Java packages
			$repoName = "test-java"
			Mock Test-MavenPackageDependencies { return $false } `
				-ModuleName ReleaseVerifier
			$result = Test-PackageDependencies `
				-RepositoryName $repoName `
				-RepositoryConfig $(New-Object -TypeName Object) `
				-Repositories $(New-Object -TypeName Object)
			$result | Should -BeExactly $false
		}
		
		It 'Dotnet packages dependencies are not up to date' {
			$repoName = "test-dotnet"
			Mock Test-DotnetPackageDependencies { return $false } `
				-ModuleName ReleaseVerifier
			$result = Test-PackageDependencies `
				-RepositoryName $repoName `
				-RepositoryConfig $(New-Object -TypeName Object) `
				-Repositories $(New-Object -TypeName Object)
			$result | Should -BeExactly $false
		}
		
		It 'Node packages dependencies are not up to date' {
			$repoName = "test-node"
			Mock Test-NodePackageDependencies { return $false } `
				-ModuleName ReleaseVerifier
			$result = Test-PackageDependencies `
				-RepositoryName $repoName `
				-RepositoryConfig $(New-Object -TypeName Object) `
				-Repositories $(New-Object -TypeName Object)
			$result | Should -BeExactly $false
		}
		
		It 'Python package dependencies are not up to date' {
			$repoName = "test-python"
			Mock Test-PythonPackageDependencies { return $false } `
				-ModuleName ReleaseVerifier
			$result = Test-PackageDependencies `
				-RepositoryName $repoName `
				-RepositoryConfig $(New-Object -TypeName Object) `
				-Repositories $(New-Object -TypeName Object)
			$result | Should -BeExactly $false
		}
	}
	
	Describe 'Test-MavenPackageDependencies' {
		It 'all package dependencies are up to date' {
			$depRepo = "dependent-java"
			$repoName = "test-java"
			$repoConfigStr = @"
			{
				"version": "4.3.0",
				"packageName": "test",
				"versionVariableName": "test.version",
				"dependencies": [
					"$depRepo"
				]
			}
"@
			$repoConfig = $repoConfigStr | ConvertFrom-Json
			$reposStr = @"
			{
				"$repoName": $repoConfigStr,
				"$depRepo": {
					"version": "4.3.0",
					"packageName": "dep",
					"versionVariableName": "dep.version"
				}
			}
"@
			$repos = $reposStr | ConvertFrom-Json
			
			Mock Test-Path { return $true } `
				-ModuleName ReleaseVerifier
			Mock Get-Content { return '<dep.version>4.3.0</dep.version>' } `
				-ModuleName ReleaseVerifier
			
			$result = Test-MavenPackageDependencies `
				-RepositoryName $repoName `
				-RepositoryConfig $repoConfig `
				-Repositories $repos
			
			$result | Should -BeExactly $true
		}
		
		It 'a package dependency is not up to date' {
			$depRepo = "dependent-java"
			$repoName = "test-java"
			$repoConfigStr = @"
			{
				"version": "4.3.0",
				"packageName": "test",
				"versionVariableName": "test.version",
				"dependencies": [
					"$depRepo"
				]
			}
"@
			$repoConfig = $repoConfigStr | ConvertFrom-Json
			$reposStr = @"
			{
				"$repoName": $repoConfigStr,
				"$depRepo": {
					"version": "4.3.0",
					"packageName": "dep",
					"versionVariableName": "dep.version"
				}
			}
"@
			$repos = $reposStr | ConvertFrom-Json
			
			Mock Test-Path { return $true } `
				-ModuleName ReleaseVerifier
			Mock Get-Content { return '<dep.version>4.2.9</dep.version>' } `
				-ModuleName ReleaseVerifier
			
			$result = Test-MavenPackageDependencies `
				-RepositoryName $repoName `
				-RepositoryConfig $repoConfig `
				-Repositories $repos
			
			$result | Should -BeExactly $false
		}
	}
	
	Describe 'Test-DotnetPackageDependencies' {
		BeforeAll {
			function Test-DotnetPackageDependenciesOnelineBase {
				param (
					[string]$ExpectedVersion,
					[string]$ActualVersion,
					[string]$ConfigDepPackageName,
					[string]$ActualDepPackageName,
					[boolean]$ExpectedResult
				)
				$depRepo = "dependent-dotnet"
				$repoName = "test-dotnet"
				$repoConfigStr = @"
				{
					"version": "4.3.0",
					"packageName": "test.dotnet",
					"dependencies": [
						"$depRepo"
					]
				}
"@
				$repoConfig = $repoConfigStr | ConvertFrom-Json
				$reposStr = @"
				{
					"$repoName": $repoConfigStr,
					"$depRepo": {
						"version": "$ExpectedVersion",
						"packageName": "$ConfigDepPackageName"
					}
				}
"@
				$repos = $reposStr | ConvertFrom-Json
				
				Mock Test-Path { return $true } `
					-ModuleName ReleaseVerifier
				Mock Get-ChildItem { return @($('{ "FullName": "file1.csproj" }' | ConvertFrom-Json)) } `
					-ModuleName ReleaseVerifier
				Mock Get-Content { return "<PackageReference Include=`"$ActualDepPackageName)`" Version=`"$ActualVersion`" />" } `
					-ModuleName ReleaseVerifier
				
				$result = Test-DotnetPackageDependencies `
					-RepositoryName $repoName `
					-RepositoryConfig $repoConfig `
					-Repositories $repos
				
				$result | Should -BeExactly $ExpectedResult
			}
			
			function Test-DotnetPackageDependenciesOneline {
				param (
					[string]$ExpectedVersion,
					[string]$ActualVersion,
					[boolean]$ExpectedResult
				)
				Test-DotnetPackageDependenciesOnelineBase `
					-ExpectedVersion $ExpectedVersion `
					-ActualVersion $ActualVersion `
					-ConfigDepPackageName "dep.dotnet" `
					-ActualDepPackageName "dep.dotnet" `
					-ExpectedResult $ExpectedResult
			}
			
			function Test-DotnetPackageDependenciesOnelineRegex {
				param (
					[string]$ExpectedVersion,
					[string]$ActualVersion,
					[boolean]$ExpectedResult
				)
				Test-DotnetPackageDependenciesOnelineBase `
					-ExpectedVersion $ExpectedVersion `
					-ActualVersion $ActualVersion `
					-ConfigDepPackageName "dep.(dotnet|SomethingElse)" `
					-ActualDepPackageName "dep.dotnet" `
					-ExpectedResult $ExpectedResult
			}
			
			function Test-DotnetPackageDependenciesMultilinesBase {
				param (
					[string]$ExpectedVersion,
					[string]$ActualVersion,
					[string]$ConfigDepPackageName,
					[string]$ActualDepPackageName,
					[boolean]$ExpectedResult
				)
				$depRepo = "dependent-dotnet"
				$repoName = "test-dotnet"
				$repoConfigStr = @"
				{
					"version": "4.3.0",
					"packageName": "test.dotnet",
					"dependencies": [
						"$depRepo"
					]
				}
"@
				$repoConfig = $repoConfigStr | ConvertFrom-Json
				$reposStr = @"
				{
					"$repoName": $repoConfigStr,
					"$depRepo": {
						"version": "$ExpectedVersion",
						"packageName": "$ConfigDepPackageName"
					}
				}
"@
				$repos = $reposStr | ConvertFrom-Json
				
				Mock Test-Path { return $true } `
					-ModuleName ReleaseVerifier
				Mock Get-ChildItem { return @($('{ "FullName": "file1.csproj" }' | ConvertFrom-Json)) } `
					-ModuleName ReleaseVerifier
				Mock Get-Content { return "<PackageReference Include=`"$ActualDepPackageName`">`r`n<Version>$ActualVersion</Version>`r`n</PackageReference>" } `
					-ModuleName ReleaseVerifier
				
				$result = Test-DotnetPackageDependencies `
					-RepositoryName $repoName `
					-RepositoryConfig $repoConfig `
					-Repositories $repos
				
				$result | Should -BeExactly $ExpectedResult
			}
			
			function Test-DotnetPackageDependenciesMultilines {
				param (
					[string]$ExpectedVersion,
					[string]$ActualVersion,
					[boolean]$ExpectedResult
				)
				Test-DotnetPackageDependenciesMultilinesBase `
					-ExpectedVersion $ExpectedVersion `
					-ActualVersion $ActualVersion `
					-ConfigDepPackageName "dep.dotnet" `
					-ActualDepPackageName "dep.dotnet" `
					-ExpectedResult $ExpectedResult
			}
			
			function Test-DotnetPackageDependenciesMultilinesRegex {
				param (
					[string]$ExpectedVersion,
					[string]$ActualVersion,
					[boolean]$ExpectedResult
				)
				Test-DotnetPackageDependenciesMultilinesBase `
					-ExpectedVersion $ExpectedVersion `
					-ActualVersion $ActualVersion `
					-ConfigDepPackageName "dep.(dotnet|SomethingElse)" `
					-ActualDepPackageName "dep.dotnet" `
					-ExpectedResult $ExpectedResult
			}
			
			function Test-DotnetPackageDependenciesNetFrameworkProjectBase {
				param (
					[string]$ExpectedVersion,
					[string]$ActualVersion,
					[string]$ConfigDepPackageName,
					[string]$ActualDepPackageName,
					[boolean]$ExpectedResult
				)
				$depRepo = "dependent-dotnet"
				$repoName = "test-dotnet"
				$repoConfigStr = @"
				{
					"version": "4.3.0",
					"packageName": "test.dotnet",
					"dependencies": [
						"$depRepo"
					]
				}
"@
				$repoConfig = $repoConfigStr | ConvertFrom-Json
				$reposStr = @"
				{
					"$repoName": $repoConfigStr,
					"$depRepo": {
						"version": "$ExpectedVersion",
						"packageName": "$ConfigDepPackageName"
					}
				}
"@
				$repos = $reposStr | ConvertFrom-Json
				
				Mock Test-Path { return $true } `
					-ModuleName ReleaseVerifier
				Mock Get-ChildItem { return @($('{ "FullName": "file1.csproj" }' | ConvertFrom-Json)) } `
					-ModuleName ReleaseVerifier
				Mock Get-Content { return "<HintPath>..\..\..\..\..\packages\$($ActualDepPackageName).test.$($ActualVersion)\lib\netstandard2.0\dep.dotnet.test.dll</HintPath>" } `
					-ModuleName ReleaseVerifier
				
				$result = Test-DotnetPackageDependencies `
					-RepositoryName $repoName `
					-RepositoryConfig $repoConfig `
					-Repositories $repos
				
				$result | Should -BeExactly $ExpectedResult
			}
			
			function Test-DotnetPackageDependenciesNetFrameworkProject {
				param (
					[string]$ExpectedVersion,
					[string]$ActualVersion,
					[boolean]$ExpectedResult
				)
				Test-DotnetPackageDependenciesNetFrameworkProjectBase `
					-ExpectedVersion $ExpectedVersion `
					-ActualVersion $ActualVersion `
					-ConfigDepPackageName "dep.dotnet" `
					-ActualDepPackageName "dep.dotnet" `
					-ExpectedResult $ExpectedResult
			}
			
			function Test-DotnetPackageDependenciesNetFrameworkProjectRegex {
				param (
					[string]$ExpectedVersion,
					[string]$ActualVersion,
					[boolean]$ExpectedResult
				)
				Test-DotnetPackageDependenciesNetFrameworkProjectBase `
					-ExpectedVersion $ExpectedVersion `
					-ActualVersion $ActualVersion `
					-ConfigDepPackageName "dep.(dotnet|SomethingElse)" `
					-ActualDepPackageName "dep.dotnet" `
					-ExpectedResult $ExpectedResult
			}
			
			function Test-DotnetPackageDependenciesPackagesConfigBase {
				param (
					[string]$ExpectedVersion,
					[string]$ActualVersion,
					[string]$ConfigDepPackageName,
					[string]$ActualDepPackageName,
					[boolean]$ExpectedResult
				)
				$depRepo = "dependent-dotnet"
				$repoName = "test-dotnet"
				$repoConfigStr = @"
				{
					"version": "4.3.0",
					"packageName": "test.dotnet",
					"dependencies": [
						"$depRepo"
					]
				}
"@
				$repoConfig = $repoConfigStr | ConvertFrom-Json
				$reposStr = @"
				{
					"$repoName": $repoConfigStr,
					"$depRepo": {
						"version": "$ExpectedVersion",
						"packageName": "$ConfigDepPackageName"
					}
				}
"@
				$repos = $reposStr | ConvertFrom-Json
				
				Mock Test-Path { return $true } `
					-ModuleName ReleaseVerifier
				Mock Get-ChildItem { return @($('{ "FullName": "packages.config" }' | ConvertFrom-Json)) } `
					-ModuleName ReleaseVerifier
				Mock Get-Content { return "<package id=`"$($ActualDepPackageName).test`" version=`"$ActualVersion`" targetFramework=`"net472`" />" } `
					-ModuleName ReleaseVerifier
				
				$result = Test-DotnetPackageDependencies `
					-RepositoryName $repoName `
					-RepositoryConfig $repoConfig `
					-Repositories $repos
				
				$result | Should -BeExactly $ExpectedResult
			}
			
			function Test-DotnetPackageDependenciesPackagesConfig {
				param (
					[string]$ExpectedVersion,
					[string]$ActualVersion,
					[boolean]$ExpectedResult
				)
				Test-DotnetPackageDependenciesPackagesConfigBase `
					-ExpectedVersion $ExpectedVersion `
					-ActualVersion $ActualVersion `
					-ConfigDepPackageName "dep.dotnet" `
					-ActualDepPackageName "dep.dotnet" `
					-ExpectedResult $ExpectedResult
			}
			
			function Test-DotnetPackageDependenciesPackagesConfigRegex {
				param (
					[string]$ExpectedVersion,
					[string]$ActualVersion,
					[boolean]$ExpectedResult
				)
				Test-DotnetPackageDependenciesPackagesConfigBase `
					-ExpectedVersion $ExpectedVersion `
					-ActualVersion $ActualVersion `
					-ConfigDepPackageName "dep.(dotnet|SomethingElse)" `
					-ActualDepPackageName "dep.dotnet" `
					-ExpectedResult $ExpectedResult
			}
		}

		It 'all package dependencies are up to date with syntax `<PackageReference `/`>' {
			Test-DotnetPackageDependenciesOneline -ExpectedVersion "4.3.0" -ActualVersion "4.3.0" -ExpectedResult $true
		}
		
		It 'all package dependencies are up to date with syntax `<PackageReference `/`> with regex' {
			Test-DotnetPackageDependenciesOnelineRegex -ExpectedVersion "4.3.0" -ActualVersion "4.3.0" -ExpectedResult $true
		}
		
		It 'a package dependency is not up to date with syntax `<PackageReference `/`>' {
			Test-DotnetPackageDependenciesOneline -ExpectedVersion "4.3.0" -ActualVersion "4.2.9" -ExpectedResult $false
		}
		
		It 'a package dependency is not up to date with syntax `<PackageReference `/`> with regex' {
			Test-DotnetPackageDependenciesOnelineRegex -ExpectedVersion "4.3.0" -ActualVersion "4.2.9" -ExpectedResult $false
		}
		
		It 'all package dependencies are up to date  with syntax `<PackageReference`>`<`/PackageReference`>' {
			Test-DotnetPackageDependenciesMultilines -ExpectedVersion "4.3.0" -ActualVersion "4.3.0" -ExpectedResult $true
		}
		
		It 'all package dependencies are up to date  with syntax `<PackageReference`>`<`/PackageReference`> with regex' {
			Test-DotnetPackageDependenciesMultilinesRegex -ExpectedVersion "4.3.0" -ActualVersion "4.3.0" -ExpectedResult $true
		}
		
		It 'a package dependency is not up to date  with syntax `<PackageReference`>`<`/PackageReference`>' {
			Test-DotnetPackageDependenciesMultilines -ExpectedVersion "4.3.0" -ActualVersion "4.2.9" -ExpectedResult $false
		}
		
		It 'a package dependency is not up to date  with syntax `<PackageReference`>`<`/PackageReference`> with regex' {
			Test-DotnetPackageDependenciesMultilinesRegex -ExpectedVersion "4.3.0" -ActualVersion "4.2.9" -ExpectedResult $false
		}
		
		It 'all package dependencies are up to date  with dotnet framework .csproj syntax' {
			Test-DotnetPackageDependenciesNetFrameworkProject -ExpectedVersion "4.3.0" -ActualVersion "4.3.0" -ExpectedResult $true
		}
		
		It 'all package dependencies are up to date  with dotnet framework .csproj syntax with regex' {
			Test-DotnetPackageDependenciesNetFrameworkProjectRegex -ExpectedVersion "4.3.0" -ActualVersion "4.3.0" -ExpectedResult $true
		}
		
		It 'a package dependency is not up to date  with dotnet framework .csproj syntax' {
			Test-DotnetPackageDependenciesNetFrameworkProject -ExpectedVersion "4.3.0" -ActualVersion "4.2.9" -ExpectedResult $false
		}
		
		It 'a package dependency is not up to date  with dotnet framework .csproj syntax with regex' {
			Test-DotnetPackageDependenciesNetFrameworkProjectRegex -ExpectedVersion "4.3.0" -ActualVersion "4.2.9" -ExpectedResult $false
		}
		
		It 'all package dependencies are up to date with packages.config file' {
			Test-DotnetPackageDependenciesPackagesConfig -ExpectedVersion "4.3.0" -ActualVersion "4.3.0" -ExpectedResult $true
		}
		
		It 'all package dependencies are up to date with packages.config file with regex' {
			Test-DotnetPackageDependenciesPackagesConfigRegex -ExpectedVersion "4.3.0" -ActualVersion "4.3.0" -ExpectedResult $true
		}
		
		It 'a package dependency is not up to date with packages.config file' {
			Test-DotnetPackageDependenciesPackagesConfig -ExpectedVersion "4.3.0" -ActualVersion "4.2.9" -ExpectedResult $false
		}
		
		It 'a package dependency is not up to date with packages.config file with regex' {
			Test-DotnetPackageDependenciesPackagesConfigRegex -ExpectedVersion "4.3.0" -ActualVersion "4.2.9" -ExpectedResult $false
		}
	}
	
	Describe 'Test-NodePackageDependencies' {
		It 'all package dependencies are up to date' {
			$depRepo = "dependent-node"
			$repoName = "test-node"
			$repoConfigStr = @"
			{
				"version": "4.3.0",
				"packageName": "test.node",
				"dependencies": [
					"$depRepo"
				]
			}
"@
			$repoConfig = $repoConfigStr | ConvertFrom-Json
			$reposStr = @"
			{
				"$repoName": $repoConfigStr,
				"$depRepo": {
					"version": "4.3.0",
					"packageName": "dep.node"
				}
			}
"@
			$repos = $reposStr | ConvertFrom-Json
			Mock Test-NodeDependenciesSub { return $true } `
				-ModuleName ReleaseVerifier
			
			$result = Test-NodePackageDependencies `
				-RepositoryName $repoName `
				-RepositoryConfig $repoConfig `
				-Repositories $repos
			
			$result | Should -BeExactly $true
		}
		
		It 'a package dependency is not up to date' {
			$depRepo = "dependent-node"
			$repoName = "test-node"
			$repoConfigStr = @"
			{
				"version": "4.3.0",
				"packageName": "test.node",
				"dependencies": [
					"$depRepo"
				]
			}
"@
			$repoConfig = $repoConfigStr | ConvertFrom-Json
			$reposStr = @"
			{
				"$repoName": $repoConfigStr,
				"$depRepo": {
					"version": "4.3.0",
					"packageName": "dep.node"
				}
			}
"@
			$repos = $reposStr | ConvertFrom-Json
			Mock Test-NodeDependenciesSub { return $false } `
				-ModuleName ReleaseVerifier
			
			$result = Test-NodePackageDependencies `
				-RepositoryName $repoName `
				-RepositoryConfig $repoConfig `
				-Repositories $repos
			
			$result | Should -BeExactly $false
		}
	}
	
	Describe 'Test-NodeDependenciesSub' {
		It 'All packages dependencies are up to date' {
			$depRepo = "dependent-node"
			$repoName = "test-node"
			$repoConfigStr = @"
			{
				"version": "4.3.0",
				"packageName": "test.node",
				"dependencies": [
					"$depRepo"
				]
			}
"@
			$repoConfig = $repoConfigStr | ConvertFrom-Json
			$reposStr = @"
			{
				"$repoName": $repoConfigStr,
				"$depRepo": {
					"version": "4.3.0",
					"packageName": "dep.node"
				}
			}
"@
			$repos = $reposStr | ConvertFrom-Json
			Mock Get-ChildItem { return $('{ "FullName" : "package.json" }' | ConvertFrom-Json) } `
				-ModuleName ReleaseVerifier
			Mock Get-Content { return "something" } `
				-ModuleName ReleaseVerifier
			Mock Test-NodePackageDependency { return $true } `
				-ModuleName ReleaseVerifier
			
			$result = Test-NodeDependenciesSub `
				-RepositoryName $repoName `
				-Repositories $repos `
				-PackageFileName 'package.json'
			
			$result | Should -BeExactly $true
		}
		
		It 'A package dependency in package.json is not up to date' {
			$depRepo = "dependent-node"
			$repoName = "test-node"
			$repoConfigStr = @"
			{
				"version": "4.3.0",
				"packageName": "test.node",
				"dependencies": [
					"$depRepo"
				]
			}
"@
			$repoConfig = $repoConfigStr | ConvertFrom-Json
			$reposStr = @"
			{
				"$repoName": $repoConfigStr,
				"$depRepo": {
					"version": "4.3.0",
					"packageName": "dep.node"
				}
			}
"@
			$repos = $reposStr | ConvertFrom-Json
			Mock Get-ChildItem { return $('{ "FullName" : "package.json" }' | ConvertFrom-Json) } `
				-ModuleName ReleaseVerifier
			Mock Get-Content { return "something" } `
				-ModuleName ReleaseVerifier
			Mock Test-NodePackageDependency { return $false } `
				-ModuleName ReleaseVerifier
			
			$result = Test-NodeDependenciesSub `
				-RepositoryName $repoName `
				-Repositories $repos `
				-PackageFileName 'package.json'
			
			$result | Should -BeExactly $false
		}
		
		It 'A package dependency in remote_package.json is not up to date' {
			$depRepo = "dependent-node"
			$repoName = "test-node"
			$repoConfigStr = @"
			{
				"version": "4.3.0",
				"packageName": "test.node"
			}
"@
			$repoConfig = $repoConfigStr | ConvertFrom-Json
			$reposStr = @"
			{
				"$repoName": $repoConfigStr,
				"$depRepo": {
					"version": "4.3.0",
					"packageName": "dep.node"
				}
			}
"@
			$repos = $reposStr | ConvertFrom-Json
			Mock Get-ChildItem { return $('{ "FullName" : "remote_package.json" }' | ConvertFrom-Json) } `
				-ModuleName ReleaseVerifier
			Mock Get-Content { return "something" } `
				-ModuleName ReleaseVerifier
			Mock Test-NodePackageDependency { return $false } `
				-ModuleName ReleaseVerifier
			
			$result = Test-NodeDependenciesSub `
				-RepositoryName $repoName `
				-Repositories $repos `
				-PackageFileName 'remote_package.json'
			
			$result | Should -BeExactly $false
		}
	}
	
	Describe 'Test-NodePackageDependency' {
		It 'All packages dependencies are up to date' {
			$depRepo = "dependent-node"
			$repoName = "test-node"
			$repoConfigStr = @"
			{
				"version": "4.3.0",
				"packageName": "test.node"
			}
"@
			$repoConfig = $repoConfigStr | ConvertFrom-Json
			$reposStr = @"
			{
				"$repoName": $repoConfigStr,
				"$depRepo": {
					"version": "4.3.0",
					"packageName": "dep.node"
				}
			}
"@
			$repos = $reposStr | ConvertFrom-Json
			$packageFileContent = '"dep.node.test" : "^4.3.0"'
			
			$result = Test-NodePackageDependency `
				-RepositoryName $depRepo `
				-Repositories $repos `
				-PackageFileContent $packageFileContent `
				-IsRemotePackage $false
			
			$result | Should -BeExactly $true
		}
		
		It 'A package dependency is not up to date' {
			$depRepo = "dependent-node"
			$repoName = "test-node"
			$repoConfigStr = @"
			{
				"version": "4.3.0",
				"packageName": "test.node"
			}
"@
			$repoConfig = $repoConfigStr | ConvertFrom-Json
			$reposStr = @"
			{
				"$repoName": $repoConfigStr,
				"$depRepo": {
					"version": "4.3.0",
					"packageName": "dep.node"
				}
			}
"@
			$repos = $reposStr | ConvertFrom-Json
			$packageFileContent = '"dep.node.test" : "^4.2.9"'
			
			$result = Test-NodePackageDependency `
				-RepositoryName $depRepo `
				-Repositories $repos `
				-PackageFileContent $packageFileContent `
				-IsRemotePackage $false
			
			$result | Should -BeExactly $false
		}
	}
	
	Describe 'Test-PythonPackageDependencies' {
		It 'all package dependencies are up to date' {
			$depRepo = "dependent-python"
			$repoName = "test-python"
			$repoConfigStr = @"
			{
				"version": "4.3.0",
				"packageName": "test",
				"versionVariableName": "testVersion",
				"dependencies": [
					"$depRepo"
				]
			}
"@
			$repoConfig = $repoConfigStr | ConvertFrom-Json
			$reposStr = @"
			{
				"$repoName": $repoConfigStr,
				"$depRepo": {
					"version": "4.3.0",
					"packageName": "dep",
					"versionVariableName": "depVersion"
				}
			}
"@
			$repos = $reposStr | ConvertFrom-Json
			
			Mock Test-Path { return $true } `
				-ModuleName ReleaseVerifier
			Mock Get-Content { return "name: depVersion`r`nvalue: '==4.3.0'" } `
				-ModuleName ReleaseVerifier
			
			$result = Test-PythonPackageDependencies `
				-RepositoryName $repoName `
				-RepositoryConfig $repoConfig `
				-Repositories $repos
			
			$result | Should -BeExactly $true
		}
		
		It 'a package dependency is not up to date' {
			$depRepo = "dependent-python"
			$repoName = "test-python"
			$repoConfigStr = @"
			{
				"version": "4.3.0",
				"packageName": "test",
				"versionVariableName": "testVersion",
				"dependencies": [
					"$depRepo"
				]
			}
"@
			$repoConfig = $repoConfigStr | ConvertFrom-Json
			$reposStr = @"
			{
				"$repoName": $repoConfigStr,
				"$depRepo": {
					"version": "4.3.0",
					"packageName": "dep",
					"versionVariableName": "depVersion"
				}
			}
"@
			$repos = $reposStr | ConvertFrom-Json
			
			Mock Test-Path { return $true } `
				-ModuleName ReleaseVerifier
			Mock Get-Content { return "name: depVersion`r`nvalue: '==4.2.9'" } `
				-ModuleName ReleaseVerifier
			
			$result = Test-PythonPackageDependencies `
				-RepositoryName $repoName `
				-RepositoryConfig $repoConfig `
				-Repositories $repos
			
			$result | Should -BeExactly $false
		}
	}
}