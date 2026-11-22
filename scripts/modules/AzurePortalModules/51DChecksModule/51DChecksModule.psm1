<#
  ==================== Checks =====================
  .Description
  This module contains functions to check various aspects of Azure Resources.
#>


# Check if a service is available by polling an Uri. Returns the status code 
# recevied after a number of retrys. An interval can be specified to wait 
# between retries.
function Get-UriHTTPStatus {
    param (
        # The URI of the service to test, e.g. https://51degrees.com
        [Parameter(Mandatory=$true)]
        [string]$Uri,

        # The number of tries before aborting the test.
        [Parameter(Mandatory=$true)]
        [int]$NumberOfTries,

        # The delay between tries in seconds.
        [Parameter(Mandatory=$true)]
        [int]$SecondsBetweenTries
    )

    Write-Host -NoNewline "Waiting for response from $Uri"

    $Tries = 0
    $HTTP_Status = $null
    While ($HTTP_Status -ne 200 -And $Tries -le $NumberOfTries) {

        # Wait before querying Uri
        Start-Sleep -Seconds $SecondsBetweenTries

        # Get HTTP status code from invoking a request for the Uri.
        try{
            $HTTP_Status = (Invoke-WebRequest -Uri $Uri -UseBasicParsing -DisableKeepAlive).StatusCode
        }
        catch [Net.WebException]
        {
            # If there is a Web Exception then get the status code
            $HTTP_Status = [int]$_.Exception.Response.StatusCode
        }
        catch [Exception]
        {
            # If there is a general exception then assume a status of null
            # (no response).
            $HTTP_Status = $null
        }

        $Tries = $Tries +1
        Write-Host -NoNewLine "."
    }
    
    Write-Host ""

    # Return status code if service is not accepting requests else return 0
    if ($HTTP_Status -ne 200 -or $null -eq $HTTP_Status) {
        Write-Host "Service is not accepting requests for Uri '$($Uri)'"
        return $HTTP_Status
    } else {
        Write-Host "Service is responding for Uri '$($Uri)'"
        return 0
    }
   
}

Export-ModuleMember -Function Get-UriHTTPStatus