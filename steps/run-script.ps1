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
    if ($cmd.Parameters.ContainsKey($opt.Key) -and $opt.Value) {
        $Parameters[$opt.Key] = $opt.Value
    }
}

Write-Output "Running '$Script' with parameters: $($Parameters.psbase.Keys)"
. $Script @Parameters
