<#
.SYNOPSIS
    Compares the current performance figures against historic runs and,
    optionally, renders and publishes the trend graphs.

.DESCRIPTION
    Reads results_<name>.json from the working directory, pulls prior figures
    from this repository's performance-result artifacts, and checks each metric
    against its acceptable band. With -Publish it also renders the trend graphs
    with ScottPlot and commits them to the images branch (gh-images on main,
    perf-images/<branch> otherwise), pushing unless -DryRun is set.

    The script signals its outcome through the process exit code so a caller can
    tell a genuine performance verdict apart from an infrastructure failure:

        0  Success. Figures were compared and, when -Publish is set, the graphs
           were rendered and committed/pushed. Also used for the benign
           "not enough history yet" and "no current results file" cases, which
           are expected and must not fail CI.

        1  Performance regression. A metric with sufficient history (>= 10
           points) is outside its acceptable band. A real, actionable verdict.

        2  Infrastructure failure while publishing. The graph toolchain or the
           git operations that (re)create and update the images branch failed
           (for example `git switch --orphan`, the ScottPlot install, or the
           commit / push of the rendered graphs). This is NOT a performance
           verdict: the run could not do its job and must always be surfaced,
           never swallowed as an "expected" outcome.

.PARAMETER RepoName
    Name of the repository checkout directory; git and graph operations run
    against it and it names the artifact/branch used for publishing.

.PARAMETER OrgName
    GitHub organisation that owns the repository, used to query historic
    performance artifacts.

.PARAMETER AllOptions
    Collection of configuration objects to process; each with a Name and a
    RunPerformance flag. Only entries with RunPerformance are compared.

.PARAMETER Branch
    Branch the figures belong to. 'main' publishes to gh-images; any other
    branch publishes to perf-images/<branch>. Defaults to 'main'.

.PARAMETER Publish
    Render the trend graphs and commit them to the images branch. Without it
    the script only compares figures and writes the run summary.

.PARAMETER DryRun
    With -Publish, render and commit the graphs but do not push them.

.NOTES
    Exit codes are described under DESCRIPTION above.
#>
param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$OrgName,
    [Parameter(Mandatory)]$AllOptions,
    [string]$Branch = "main",
    [switch]$Publish,
    [bool]$DryRun = $false
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true
$ProgressPreference = "SilentlyContinue" # Disable progress bars

Set-StrictMode -Version 1.0

function Get-Artifact-Result {
    param (
        [Parameter(Mandatory)]$Artifact,
        [Parameter(Mandatory)][string]$Name
    )
    $result = $null
    try {
        Invoke-WebRequest -Uri $Artifact.archive_download_url -Headers @{"Authorization" = "Bearer $($env:GITHUB_TOKEN)"} -Outfile "$($Artifact.id).zip"
        Expand-Archive -Path "$($Artifact.id).zip" -DestinationPath $Artifact.id -Force
        $resultsFile = "$($Artifact.id)/results_$Name.json"
        if (Test-Path $resultsFile) {
            $result = Get-Content $resultsFile | ConvertFrom-Json -AsHashtable
            $result.Artifact = $Artifact
        }
    } catch {
        Write-Warning "Can't get artifact[$($Artifact.id)] result: $_"
    }
    return $result
}

function Generate-PerformanceResults {
    param(
        [Parameter(Mandatory)][double[]]$Dates,
        [Parameter(Mandatory)][double[]]$Values,
        [string]$Name,
        [string]$MetricName,
        [switch]$HigherIsBetter
    )

    # Calculate the stats
    $stats = $Values | Measure-Object -Average -StandardDeviation
    $maxDiff = (($stats.Average*0.1), ($stats.StandardDeviation*2) | Measure-Object -Maximum).Maximum
    $lowerBound = $stats.Average - $maxDiff
    $higherBound = $stats.Average + $maxDiff

    $currentResult = $Values[-1]
    Write-Host "Average: $($stats.Average)"
    Write-Host "Standard deviation: $($stats.StandardDeviation) (x2 = $($stats.StandardDeviation*2))"
    Write-Host "Acceptable values: $($HigherIsBetter ? ">$lowerBound" : "<$higherBound")"
    Write-Host "Current result: $currentResult"

    if ($Publish) {
        Write-Host "Generating graph..."

        $plot = [ScottPlot.Plot]::new()
        [void] $plot.ShowLegend([ScottPlot.Alignment]::UpperLeft)
        [void] $plot.Title("Config: '$Name'")
        [void] $plot.XLabel("Date of Performance Test")
        [void] $plot.YLabel($MetricName)
        [void] $plot.Axes.Margins(0.2, 0.5)
        [void] $plot.Axes.DateTimeTicksBottom()
        [void] $plot.Add.VerticalSpan($lowerBound, $higherBound) # Acceptable variation

        # Circle around current performance figure
        $current = $plot.Add.Marker($Dates[-1], $Values[-1], [ScottPlot.MarkerShape]::OpenCircle, 15)
        $current.LegendText = "current"

        # Historic figures
        $historic = $plot.Add.Scatter($Dates, $Values)
        $historic.MarkerShape = [ScottPlot.MarkerShape]::FilledCircle
        $historic.MarkerSize = 5
        $historic.LegendText = "historic"

        # Write to the output image
        $plot.Font.Set([ScottPlot.Fonts]::Monospace)
        Write-Host "Default font: $([ScottPlot.Fonts]::Monospace)"
        $plot.SavePng("$RepoName/perf-graph-$Name-$MetricName-latest.png", 400, 300)
    } else {
        Write-Host "Not publishing graphs, skipping graph generation"
    }

    # Write out the summary for GitHub actions
    if ($env:CI) {
        Write-Output "## Performance Figures - $Name - $MetricName" >> $env:GITHUB_STEP_SUMMARY

        # TODO: Embedded ASCII graph
        
        Write-Output "| Date | $MetricName |" >> $env:GITHUB_STEP_SUMMARY
        Write-Output "| --- | --- |" >> $env:GITHUB_STEP_SUMMARY
        for ($i=0; $i -lt $Dates.Length; ++$i) {
            Write-Output "| $([DateTime]::FromOADate($Dates[$i])) | $($Values[$i]) |" >> $env:GITHUB_STEP_SUMMARY
        }
    }

    # Check if current result is within acceptable bounds
    $Passed = $False
    if ($HigherIsBetter) {
        Write-Output "Checking '$currentResult' > '$LowerBound'"
        $Passed = $currentResult -ge $lowerBound
    } else {
        Write-Output "Checking '$currentResult' < '$HigherBound'"
        $Passed = $currentResult -le $higherBound
    }
    if (-not $Passed) {
        Write-Warning "The performance of '$MetricName' is outside of the acceptable limits relative to the mean for '$Name'"
        if ($Values.Count -lt 10) {
            Write-Warning "There are only '$($Values.Count - 1)' historic results, so this will not be considered a failure"
        } else {
            exit 1
        }
    }
}

$plotTmp = [System.IO.Path]::GetTempPath() + "plot." + (New-Guid)
New-Item -ItemType directory -Force -Path $plotTmp
try {
    if ($Publish) {
        try {
            Write-Host "Installing ScottPlot..."
            dotnet new classlib -o $plotTmp
            dotnet add $plotTmp package ScottPlot --version 5.0.55
            dotnet publish $plotTmp --output $plotTmp/scottplot
            $arch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLower()
            $skia = `
                $IsLinux   ? "linux-$arch/native/libSkiaSharp.so" :
                $IsWindows ? "win-$arch/native/libSkiaSharp.dll"  :
                $IsMacOS   ? "osx/native/libSkiaSharp.dylib"      :
                (Write-Error "Unsupported OS")
            New-Item -ItemType SymbolicLink -Force -Target "$plotTmp/scottplot/runtimes/$skia" -Path "$plotTmp/scottplot/$(Split-Path -Leaf $skia)"
            Add-Type -Path $plotTmp/scottplot/ScottPlot.dll

            # gh-images is used for main for compatibility, other branches use
            # perf-images/ prefix instead of gh-images/ to avoid collisions with
            # the gh-images branch
            $imagesBranch = $Branch -ceq 'main' ? 'gh-images' : "perf-images/$Branch"
            Write-Host "(Re)creating $imagesBranch branch..."
            git -C $RepoName update-ref -d refs/heads/$imagesBranch # delete local $imagesBranch if exists
            git -C $RepoName switch --orphan $imagesBranch
            git -C $RepoName rm -rf --ignore-unmatch .
        } catch {
            # Write-Error is non-terminating here (-ErrorAction Continue) so the
            # Stop preference doesn't throw before exit 2 sets the code.
            Write-Error "Infrastructure failure preparing graph publish: $_" -ErrorAction Continue
            exit 2
        }
    } else {
        Write-Host "Not publishing graphs"
    }

    Write-Host "Getting artifacts..."
    $artifactName = "publish_performance_results@$($Branch -replace '[":<>|*?/\\\r\n]', '-')"
    $artifacts = $(gh api -X GET -f per_page=9 -f "name=$artifactName" /repos/$OrgName/$RepoName/actions/artifacts | ConvertFrom-Json).artifacts

    foreach ($options in $AllOptions) {
        if (-not $Options.RunPerformance) {
            continue
        }
        Write-Host "Running for '$($options.Name)'"

        # Get the artifact for the current run
        $currentResultsPath = "results_$($options.Name).json"
        if (!(Test-Path $currentResultsPath)) {
            Write-Warning "The file '$currentResultsPath' did not exist"
            exit 0
        }
        # Get the result for the current artifact
        $currentResult = Get-Content $currentResultsPath | ConvertFrom-Json -AsHashtable
        $currentResult.Artifact = @{created_at = Get-Date}

        # Get the historic performance results from the artifacts
        [System.Collections.ArrayList]$results = @()
        $artifacts | Sort-Object -Property created_at | ForEach-Object {if ($result = Get-Artifact-Result -Artifact $_ -Name $Options.Name) {[void]$results.Add($result)}}
        [void]$results.Add($currentResult)
        Write-Host "Number of results: $($results.Count)"

        # Generate the performance results for all metrics
        $higherIsBetterResults = $results.Where({$null -ne $_.HigherIsBetter})
        foreach ($metric in $currentResult.HigherIsBetter.Keys) {
            Write-Host "Checking '$metric' (HigherIsBetter)"
            [double[]]$dates = foreach ($_ in $higherIsBetterResults) { $_.Artifact.created_at.ToOADate() }
            [double[]]$values = foreach ($_ in $higherIsBetterResults) { $_.HigherIsBetter[$metric] }
            Generate-PerformanceResults -Name $Options.Name -MetricName $metric -Dates $dates -Values $values -HigherIsBetter
        }
        ### NOTE: currently all LowerIsBetter metrics are derivatives of
        ### HigherIsBetter metrics, no reason to do the comparison twice
        # $lowerIsBetterResults = $results.Where({$null -ne $_.LowerIsBetter})
        # foreach ($metric in $CurrentResult.LowerIsBetter.Keys) {
        #     Write-Host "Checking '$metric' (LowerIsBetter)"
        #     [double[]]$dates = foreach ($_ in $lowerIsBetterResults) { $_.Artifact.created_at.ToOADate() }
        #     [double[]]$values = foreach ($_ in $lowerIsBetterResults) { $_.LowerIsBetter[$metric] }
        #     Generate-PerformanceResults -Name $Options.Name -MetricName $metric -Dates $dates -Values $values
        # }
    }

    if ($Publish) {
        try {
            # Commit the images, and change back to the original branch
            git -C $RepoName add '*.png'
            git -C $RepoName status
            git -C $RepoName commit -m "Add performance graphs"
            if ($DryRun) {
                Write-Host "Dry run, not pushing graphs."
            } else {
                git -C $RepoName push --force-with-lease origin HEAD
            }
        } catch {
            # Non-terminating (see note above) so exit 2 is reached.
            Write-Error "Infrastructure failure publishing graphs: $_" -ErrorAction Continue
            exit 2
        }
    }
} finally {
    # Fails on Windows :(
    # Remove-Item -Recurse -Force $plotTmp
    Write-Host "Please remove '$plotTmp' manually 🙂"
}
