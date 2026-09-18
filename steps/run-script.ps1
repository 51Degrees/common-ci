param (
    [Parameter(Mandatory=$true,Position=0)]
    [string]$Script,
    [Parameter(Position=1)]
    $Options = @{}
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

Write-Host "Running '$Script' with parameters: $($Parameters.psbase.Keys)"
# Must be $global:. A plain assignment creates a script-scoped variable
# that shadows the automatic one, so the call below updates the global
# whilst the check underneath reads the shadow and sees 0 for every
# script. That is the same shadowing removed from dotnet/run-unit-tests.ps1
# in eb02339, which closed issue 231.
$global:LASTEXITCODE = 0
& $Script @Parameters
if ($LASTEXITCODE -ne 0) {
    throw "$Script failed with code $LASTEXITCODE"
}
