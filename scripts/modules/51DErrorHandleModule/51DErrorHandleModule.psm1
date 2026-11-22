<#
  ===================== Error Handling =====================
  .Description
  This module contains functions that perform error handling
  actions.
  For more information, please read description of
  each function.
#>

<#
  .Description
  Check a Rest Response and return
  whether it is successful or not.

  .Parameter Response
  
  .Outputs true or false
#>
function Test-RestResponse {
	param (
		$Response,
		[string]$ErrorMessage
	)

	# Check that reponse is not null. This is for cases whereexception occurs
	# when call Invoke-WebRequest and no response is returned.
	if ($Response -eq $null) {
		Write-Host "# ERROR: Response object is null."
		Write-Host "# ERROR: $ErrorMessage"
		return $false
	}
	
	# Check for actual status code
	if ($Response.StatusCode -le 599 -and $Response.StatusCode -ge 400) {
		
		Write-Host "# ERROR: Status Code returned $($Response.StatusCode)"
		Write-Host "# ERROR: $ErrorMessage"
		throw "# ERROR: Rest api call failed."
	}
	return $true
}