Using module 51DEnvironmentModule

Describe 'GetEnvironmentVariable' {
	It 'Successfully get default in test environment' {
		$curEnv = $Env:51D_ENVIRONMENT
		# Set test environment
		$Env:51D_ENVIRONMENT = "Test"
		$result = [EnvironmentHandler]::GetEnvironmentVariable("test")

		# Restore the current environment
		$Env:51D_ENVIRONMENT = $curEnv
		$result | Should -Be "default"
	}
	
	It 'Successfully get value in production environment' {
		$curEnv = $Env:51D_ENVIRONMENT
		# Set test environment
		$Env:51D_ENVIRONMENT = "Production"
		$result = [EnvironmentHandler]::GetEnvironmentVariable("test")

		# Restore the current environment
		$Env:51D_ENVIRONMENT = $curEnv
		$result | Should -Be "test"
	}
}