param (
    [Parameter(Mandatory=$true,Position=0)]
    [string]$Script,
    [Parameter(Position=1)]
    $Options = @{},
    # Set this where a non zero exit code from the script is expected and the
    # workflow is meant to carry on anyway. The code is still written to the
    # log as a warning, so a tolerated failure stays visible.
    [switch]$IgnoreExitCode
)
$ErrorActionPreference = "Stop"

$cmd = Get-Command -Name $Script
if (!$cmd.Parameters) {
    throw "Failed to load command parameters (check for syntax errors): $Script"
}

$Parameters = @{}

foreach ($opt in $Options.GetEnumerator()) {
    if ($cmd.Parameters.ContainsKey($opt.Key) -and $null -ne $opt.Value) {
        $Parameters[$opt.Key] = $opt.Value
    }
}

Write-Output "Running '$Script' with parameters: $($Parameters.psbase.Keys)"

# Start from a known code. $LASTEXITCODE is global and survives from one script
# to the next, so without this a code left behind by an earlier step could be
# read as this script's result.
$global:LASTEXITCODE = 0

# The script block matters. A script that ends in 'exit 1' would otherwise end
# this runner too, and the caller would carry on with nothing to look at. Run
# through a block and the exit stops at the block, leaving the code in
# $LASTEXITCODE for the check below. Dot sourcing inside the block keeps the
# script's own scope behaviour as it was.
& { . $Script @Parameters }

$ScriptExitCode = $LASTEXITCODE

if ($ScriptExitCode -ne 0) {
    $Message = "'$Script' failed with exit code $ScriptExitCode"
    if ($IgnoreExitCode) {
        Write-Output "::warning title=Script failed::$Message. The step is set to ignore it."
    }
    else {
        Write-Output "::error title=Script failed::$Message"
        throw $Message
    }
}
