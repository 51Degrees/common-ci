<#
  ===================== Rest =====================
  .Description
  This module contains functions that are related to
  REST requests.
  For more information, please read description of
  each function.
#>

# Global constants for Rest APIs.
# Maximum retry count if rest api call fail with code between 400 and 599
$script:maximumRetryCount = 3
# Interval in seconds between retry if rest api call fail with code between 400 and 599
$script:retryIntervalSec = 1

<#
  .Description
  Get max number of retrys.
  
  .Outputs
  Number of retrys.
#>
function Get-MaxRetrys {
	return $script:maximumRetryCount
}

<#
  .Description
  Get retry interval in seconds.
  
  .Outputs
  Retry interval in seconds.
#>
function Get-RetryInterval {
	return $script:retryIntervalSec
}

Export-ModuleMember -Function *