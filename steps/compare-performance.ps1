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

# Every metric is a rate or a time, so anything but a finite number above zero
# is a broken measurement and not a result.
function Test-UsableFigure {
    param($Figure)
    $isNumber = $Figure -is [int] -or $Figure -is [long] -or
        $Figure -is [double] -or $Figure -is [decimal]
    return $isNumber -and [double]::IsFinite($Figure) -and $Figure -gt 0
}

# Rewrites a results file without its unusable figures and returns what it left
# out. The workflow uploads this file as history however this script ends.
function Remove-UnusableFigures {
    param([Parameter(Mandatory)][string]$Path)
    $kept = Get-Content $Path | ConvertFrom-Json -AsHashtable
    $dropped = foreach ($section in 'HigherIsBetter', 'LowerIsBetter') {
        foreach ($metric in [string[]]$kept[$section].Keys) {
            $figure = $kept[$section][$metric]
            if (-not (Test-UsableFigure $figure)) {
                Write-Host "::error::'$section.$metric' in '$Path' is '$figure', which is not a number above zero. It is left out of the graph and the history."
                [void] $kept[$section].Remove($metric)
                "$Path $section.$metric"
            }
        }
    }
    if ($dropped) {
        $kept | ConvertTo-Json -Depth 100 | Set-Content $Path
    }
    return $dropped
}

# Gets the dates and figures to plot, leaving out any run with no usable figure.
function Get-UsableFigures {
    param(
        [Parameter(Mandatory)]$Results,
        [Parameter(Mandatory)][string]$Section,
        [Parameter(Mandatory)][string]$Metric
    )
    $dates = [System.Collections.Generic.List[double]]::new()
    $values = [System.Collections.Generic.List[double]]::new()
    foreach ($result in $Results) {
        $figure = $result[$Section][$Metric]
        if (Test-UsableFigure $figure) {
            $dates.Add($result.Artifact.created_at.ToOADate())
            $values.Add($figure)
        } elseif ($null -ne $figure) {
            Write-Warning "Dropped '$Metric' figure '$figure' from the run of $($result.Artifact.created_at), as it is not a number above zero"
        }
    }
    return @{ Dates = $dates.ToArray(); Values = $values.ToArray() }
}

function Generate-PerformanceResults {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][double[]]$Dates,
        [Parameter(Mandatory)][AllowEmptyCollection()][double[]]$Values,
        [string]$Name,
        [string]$MetricName,
        # The current figure was dropped, so the last value is a historic one.
        [switch]$NoCurrentFigure,
        [switch]$HigherIsBetter
    )

    $hasFigures = $Values.Count -gt 0
    if ($hasFigures) {
        # Calculate the stats
        $stats = $Values | Measure-Object -Average -StandardDeviation
        $maxDiff = (($stats.Average*0.1), ($stats.StandardDeviation*2) | Measure-Object -Maximum).Maximum
        $lowerBound = [Math]::Max(0.0, $stats.Average - $maxDiff)
        $higherBound = $stats.Average + $maxDiff

        Write-Host "Average: $($stats.Average)"
        Write-Host "Standard deviation: $($stats.StandardDeviation) (x2 = $($stats.StandardDeviation*2))"
        Write-Host "Acceptable values: $($HigherIsBetter ? ">$lowerBound" : "<$higherBound")"
    } else {
        Write-Warning "There are no usable figures for '$MetricName' for '$Name'"
    }

    if (-not $NoCurrentFigure) {
        $currentResult = $Values[-1]
        Write-Host "Current result: $currentResult"
    }

    if ($Publish) {
        Write-Host "Generating graph..."

        $plot = [ScottPlot.Plot]::new()
        [void] $plot.ShowLegend([ScottPlot.Alignment]::UpperLeft)
        [void] $plot.Title("Config: '$Name'")
        [void] $plot.XLabel("Date of Performance Test")
        [void] $plot.YLabel($MetricName)
        [void] $plot.Axes.Margins(0.2, 0.5)
        [void] $plot.Axes.DateTimeTicksBottom()

        if ($hasFigures) {
            [void] $plot.Add.VerticalSpan($lowerBound, $higherBound) # Acceptable variation

            # Circle around current performance figure
            if (-not $NoCurrentFigure) {
                $current = $plot.Add.Marker($Dates[-1], $Values[-1], [ScottPlot.MarkerShape]::OpenCircle, 15)
                $current.LegendText = "current"
            }

            # Historic figures
            $historic = $plot.Add.Scatter($Dates, $Values)
            $historic.MarkerShape = [ScottPlot.MarkerShape]::FilledCircle
            $historic.MarkerSize = 5
            $historic.LegendText = "historic"

            # The margin would otherwise carry the axis below zero
            [void] $plot.Axes.AutoScale()
            $limits = $plot.Axes.GetLimits()
            if ($limits.Bottom -lt 0) {
                [void] $plot.Axes.SetLimitsY(0, $limits.Top)
            }
        } else {
            # An empty graph, because the documentation embeds this file and the
            # images branch only holds what is drawn tonight
            $now = (Get-Date).ToOADate()
            [void] $plot.Axes.SetLimits($now - 1, $now + 1, 0, 1)
        }

        # Write to the output image
        $plot.Font.Set([ScottPlot.Fonts]::Monospace)
        Write-Host "Default font: $([ScottPlot.Fonts]::Monospace)"
        $plot.SavePng("$RepoName/perf-graph-$Name-$MetricName-latest.png", 400, 300)

        $limits = $plot.Axes.GetLimits()
        Write-Host "Y axis: from $($limits.Bottom) to $($limits.Top)"
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

    if ($NoCurrentFigure) {
        Write-Warning "There is no usable current figure for '$MetricName' for '$Name', so it was not checked"
        return
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

# Done first, so that no failure below can leave a broken figure in the files
# uploaded as history. The figures read here still include them, because a metric
# with a dropped figure must keep its graph.
$currentResults = @{}
$droppedFigures = @()
foreach ($options in $AllOptions) {
    $currentResultsPath = "results_$($options.Name).json"
    if ($options.RunPerformance -and (Test-Path $currentResultsPath)) {
        $currentResults[$options.Name] = Get-Content $currentResultsPath | ConvertFrom-Json -AsHashtable
        $droppedFigures += @(Remove-UnusableFigures -Path $currentResultsPath)
    }
}

$plotTmp = [System.IO.Path]::GetTempPath() + "plot." + (New-Guid)
New-Item -ItemType directory -Force -Path $plotTmp
try {
    if ($Publish) {
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
    } else {
        Write-Host "Not publishing graphs"
    }

    Write-Host "Getting artifacts..."
    $artifactName = "publish_performance_results@$($Branch -replace '[":<>|*?/\\\r\n]', '-')"
    $artifacts = $(gh api -X GET -f per_page=9 -f "name=$artifactName" /repos/$OrgName/$RepoName/actions/artifacts | ConvertFrom-Json).artifacts

    $stoppedGraphs = @()
    foreach ($options in $AllOptions) {
        if (-not $Options.RunPerformance) {
            continue
        }
        Write-Host "Running for '$($options.Name)'"

        # Get the artifact for the current run
        $currentResultsPath = "results_$($options.Name).json"
        if (!(Test-Path $currentResultsPath)) {
            # Earlier results mean this configuration's graph has stopped updating.
            # Without any, the configuration has no graph to keep up to date.
            if ($artifacts | Where-Object { Get-Artifact-Result -Artifact $_ -Name $options.Name }) {
                $stoppedGraphs += $options.Name
            }
            Write-Output "::warning::The file '$currentResultsPath' did not exist, so '$($options.Name)' was not compared"
            continue
        }
        # Get the result for the current artifact
        $currentResult = $currentResults[$options.Name]
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
            $figures = Get-UsableFigures -Results $higherIsBetterResults -Section HigherIsBetter -Metric $metric
            $noCurrentFigure = -not (Test-UsableFigure $currentResult.HigherIsBetter[$metric])
            Generate-PerformanceResults -Name $Options.Name -MetricName $metric -Dates $figures.Dates -Values $figures.Values -NoCurrentFigure:$noCurrentFigure -HigherIsBetter
        }
        ### NOTE: currently all LowerIsBetter metrics are derivatives of
        ### HigherIsBetter metrics, no reason to do the comparison twice
        # $lowerIsBetterResults = $results.Where({$null -ne $_.LowerIsBetter})
        # foreach ($metric in $CurrentResult.LowerIsBetter.Keys) {
        #     Write-Host "Checking '$metric' (LowerIsBetter)"
        #     $figures = Get-UsableFigures -Results $lowerIsBetterResults -Section LowerIsBetter -Metric $metric
        #     $noCurrentFigure = -not (Test-UsableFigure $currentResult.LowerIsBetter[$metric])
        #     Generate-PerformanceResults -Name $Options.Name -MetricName $metric -Dates $figures.Dates -Values $figures.Values -NoCurrentFigure:$noCurrentFigure
        # }
    }

    if ($Publish -and (Test-Path "$RepoName/perf-graph-*-latest.png")) {
        # Commit the images, and change back to the original branch
        git -C $RepoName add '*.png'
        git -C $RepoName status
        git -C $RepoName commit -m "Add performance graphs"
        if ($DryRun) {
            Write-Host "Dry run, not pushing graphs."
        } else {
            git -C $RepoName push --force origin HEAD
        }
    }

    if ($stoppedGraphs) {
        throw "No results for '$($stoppedGraphs -join "', '")' although earlier runs produced them, so the graphs have stopped updating"
    }
} finally {
    # Fails on Windows :(
    # Remove-Item -Recurse -Force $plotTmp
    Write-Host "Please remove '$plotTmp' manually 🙂"
}

# Last, so that one broken figure costs neither the other graphs nor the push.
# No release depends on this exit code.
if ($droppedFigures.Count -gt 0) {
    Write-Host "Failing, because these figures were dropped: $($droppedFigures -join ', ')"
    exit 1
}
