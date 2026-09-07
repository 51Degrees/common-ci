<#
.SYNOPSIS
Validates the results JSON a performance example or test emitted and copies it
to test-results/performance-summary/results_<Name>.json, where
steps/compare-performance.ps1 reads it.

.DESCRIPTION
The file must have a HigherIsBetter member, a LowerIsBetter member, or both,
each mapping metric names to numbers. Any other members are preserved. Metric
names are the graph's series keys, so they must stay stable across runs of the
same configuration. See DESIGN.md#performance-tests.

    {
      "HigherIsBetter": { "DetectionsPerSecond": 1234567 },
      "LowerIsBetter":  { "AvgMillisecsPerDetection": 0.00081 }
    }

.PARAMETER Name
The configuration name from options.json. The graph history is keyed on it.

.PARAMETER SummaryDir
Where the results are published, relative to RepoName. Only override this when a
repository lays its test results out differently.
#>
param(
    [Parameter(Mandatory)][string]$SourceFile,
    [Parameter(Mandatory)][string]$Name,
    [string]$RepoName = ".",
    [string]$SummaryDir = "test-results/performance-summary"
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

Set-StrictMode -Version 1.0

if (!(Test-Path -Path $SourceFile -PathType Leaf)) {
    Write-Error "The performance example did not produce '$SourceFile'. The example is expected to write its results JSON itself; see DESIGN.md#performance-tests."
}

$contents = Get-Content -Raw -Path $SourceFile
try {
    $results = $contents | ConvertFrom-Json -AsHashtable
} catch {
    Write-Host "Contents of '$SourceFile':"
    Write-Host $contents
    Write-Error "'$SourceFile' is not valid JSON: $_"
}

# A file with neither member carries no figure, and would leave the graph with a
# gap that is easy to miss.
$sections = @("HigherIsBetter", "LowerIsBetter").Where({ $null -ne $results.$_ })
if ($sections.Count -eq 0) {
    Write-Host "Contents of '$SourceFile':"
    Write-Host $contents
    Write-Error "'$SourceFile' has neither a 'HigherIsBetter' nor a 'LowerIsBetter' member, so it carries no performance figure."
}

# A null or a string reaches the graph as a broken data point, so reject it here
# rather than in the plot.
$metricCount = 0
foreach ($section in $sections) {
    foreach ($metric in $results.$section.Keys) {
        $value = $results.$section[$metric]
        if ($value -isnot [int] -and $value -isnot [long] -and $value -isnot [double] -and $value -isnot [decimal]) {
            $shown = $null -eq $value ? "null" : "'$value'"
            Write-Error "Metric '$section.$metric' in '$SourceFile' is $shown, which is not a number."
        }
        Write-Host "  $section.$metric = $value"
        $metricCount++
    }
}
if ($metricCount -eq 0) {
    Write-Error "'$SourceFile' declares no metrics, so it carries no performance figure."
}

$destinationDir = New-Item -ItemType Directory -Force -Path (Join-Path $RepoName $SummaryDir)
$destinationFile = Join-Path $destinationDir "results_$Name.json"
Copy-Item -Path $SourceFile -Destination $destinationFile -Force
Write-Host "Published $metricCount metric(s) to '$destinationFile'"
