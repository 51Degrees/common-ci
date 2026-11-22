<#
  ==================== Deploy =====================
  .Description
  This module contains functions to aid with deployment to Azure Services.
#>

# Get HTTP status where querying a Uri, return even if the client throws an
# exception.
function Get-StatusCode {

    param(
        [string]$Uri
    )

    try{
        (Invoke-WebRequest -Uri $Uri -UseBasicParsing -DisableKeepAlive).StatusCode
    }
    catch [Net.WebException]
    {
        [int]$_.Exception.Response.StatusCode
    }
    catch [Exception]
    {
        return 0
    }
}

# Check if a service has started by polling an endoint, if the number of retrys 
# has been exhausted and the service is not running (no 200 status code returned)
# then exit with status code 1.
function Get-SlotStatus {
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

    # Wait for the service to start
    Write-Host -NoNewline "Waiting for response from $Uri "

    $Tries = 0
    $HTTP_Status = Get-StatusCode -Uri $Uri -Path $Path
    While ($HTTP_Status -ne 200 -And $Tries -le $NumberOfTries) {
        Start-Sleep -Seconds $SecondsBetweenTries
        $Tries = $Tries +1
        $HTTP_Status = Get-StatusCode -Uri $Uri -Path $Path
        Write-Host -NoNewLine "."
    }
    Write-Host ""
    # Exit if service is not accepting requests
    if($HTTP_Status -ne 200) {
        Write-Host "Service is not accepting requests."
        exit 1
    }
    Write-Host "Service has started"
}

Export-ModuleMember -Function Get-SlotStatus