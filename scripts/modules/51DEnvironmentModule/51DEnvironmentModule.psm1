class EnvironmentHandler {
	<#
	  .Description
	  This function check what value caller should see in current environment.
	  This is normally used to make sure that in a test environment, a fake
	  value is always used so that we don't accidentally change the production
	  environment.
	  
	  .Parameter envVarValue
	  Actual environment value
	  
	  .Outputs
	  The input value or default if in test environment
	#>
	static [object]GetEnvironmentVariable([object]$envVarValue) {
		if ($Env:51D_ENVIRONMENT -eq 'Test') {
			return "default"
		} else {
			return $envVarValue
		}
	}
}