# This is a wrapper script which runs the Get-SlotStatus function in the 
# 51DDeployModule, helpful if running from azure pipelines and need to pass in
# arguments.

param (
    # The path to the module folder which contains the 51DeployModule. This 
    # module contains the Get-SlotStatus function.
    [Parameter(Mandatory=$true)]
    [string]$ModulePath,

    # The URI of the service to test, e.g. https://51degrees.com
    [Parameter(Mandatory=$true)]
    [string]$Uri,

    # The number of tries before aborting the test.
    [int]$NumberOfTries=18,

    # The delay between tries in seconds.
    [int]$SecondsBetweenTries=10
)

# Install all modules
$Env:PSModulePath += "$([IO.Path]::PathSeparator)$($ModulePath)"
Write-Host "Module Path: $($Env:PSModulePath)"

# Execute Get-SlotStatus script. The function will exit with a status of 1 if 
# the service fails to respond with a HTTP 200 status code.
Get-SlotStatus -Uri $Uri -NumberOfTries $NumberOfTries -SecondsBetweenTries $SecondsBetweenTries