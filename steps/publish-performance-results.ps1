<#
.SYNOPSIS
Publishes the performance results JSON a performance example or test emitted.

.DESCRIPTION
The single step every language's run-performance-tests.ps1 uses to hand a
performance figure to the graphs. The performance example or test writes the
results itself, in the shared schema, and this step validates the file and
copies it to test-results/performance-summary/results_<Name>.json, where
steps/compare-performance.ps1 reads it.

Adapters must not parse an example's console output. A figure scraped from
printed text is tied to the exact wording and number formatting of that output,
so a cosmetic change to an example silently stops the graph updating. Emitting
the JSON from the example makes the contract structured instead of textual.

The shared schema is a JSON object with a HigherIsBetter member, a
LowerIsBetter member, or both. Each maps metric names to numbers:

    {
      "HigherIsBetter": { "DetectionsPerSecond": 1234567 },
      "LowerIsBetter":  { "AvgMillisecsPerDetection": 0.00081 }
    }

Metric names are the series keys on the graph, so they must stay stable across
runs of the same configuration.

.PARAMETER SourceFile
Path to the results JSON the performance example or test wrote.

.PARAMETER Name
The configuration name from options.json. The published file is named
results_<Name>.json and the graph history is keyed on it.

.PARAMETER RepoName
The directory the repository is checked out into. The summary directory is
resolved relative to it.

.PARAMETER SummaryDir
The directory the results are published to, relative to RepoName. Only override
this when a repository lays its test results out differently.

.EXAMPLE
./steps/publish-performance-results.ps1 -SourceFile $RepoName/summary.json -Name $Name -RepoName $RepoName
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

# Both members are optional individually, but a file with neither carries no
# figure and would leave the graph with a gap that is easy to miss.
$sections = @("HigherIsBetter", "LowerIsBetter").Where({ $null -ne $results.$_ })
if ($sections.Count -eq 0) {
    Write-Host "Contents of '$SourceFile':"
    Write-Host $contents
    Write-Error "'$SourceFile' has neither a 'HigherIsBetter' nor a 'LowerIsBetter' member, so it carries no performance figure."
}

# Every metric must be a number. A null or a string here reaches the graph as a
# broken data point, and the cause is far easier to see now than in the plot.
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
