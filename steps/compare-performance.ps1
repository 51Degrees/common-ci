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
            Write-Output "| $($Dates[$i]) | $($Values[$i]) |" >> $env:GITHUB_STEP_SUMMARY
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
        Write-Host "Installing ScottPlot..."
        dotnet new classlib -o $plotTmp
        dotnet add $plotTmp package ScottPlot --version 5.0.55
        dotnet dotnet publish $plotTmp --output $plotTmp/scottplot
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
        $results = ($artifacts | Sort-Object -Property created_at | ForEach-Object {
            Write-Host "Getting $_.name"
            (Get-Artifact-Result -Artifact $_ -Name $Options.Name) ?? @()
        }) + $currentResult

        # Generate the performance results for all metrics
        $higherIsBetterResults = $results.Where({$null -ne $_.HigherIsBetter})
        foreach ($metric in $currentResult.HigherIsBetter.Keys) {
            Write-Host "Checking '$metric' (HigherIsBetter)"
            [double[]]$dates = foreach ($_ in $higherIsBetterResults) { $_.Artifact.created_at.ToOADate() }
            [double[]]$values = foreach ($_ in $higherIsBetterResults) { $_.HigherIsBetter[$metric] }
            Generate-PerformanceResults -Name $Options.Name -MetricName $metric -Dates $dates -Values $values -HigherIsBetter
        }
        $lowerIsBetterResults = $results.Where({$null -ne $_.LowerIsBetter})
        foreach ($metric in $CurrentResult.LowerIsBetter.Keys) {
            Write-Host "Checking '$metric' (LowerIsBetter)"
            [double[]]$dates = foreach ($_ in $lowerIsBetterResults) { $_.Artifact.created_at.ToOADate() }
            [double[]]$values = foreach ($_ in $lowerIsBetterResults) { $_.LowerIsBetter[$metric] }
            Generate-PerformanceResults -Name $Options.Name -MetricName $metric -Dates $dates -Values $values
        }
    }

    if ($Publish) {
        $pngCount = (Get-ChildItem -filter "*.png" .).count
        if ($pngCount -ne 0) {
            # Commit the images, and change back to the original branch
            git -C $RepoName add '*.png'
            git -C $RepoName status
            git -C $RepoName commit -m "Add performance graphs"
            if ($DryRun) {
                Write-Host "Dry run, not pushing graphs."
            } else {
                git -C $RepoName push --force-with-lease origin HEAD
            }
        }
        else {
            Write-Host "No PNG files to commit"
        }
    }
} finally {
    # Fails on Windows :(
    # Remove-Item -Recurse -Force $plotTmp
    Write-Host "Please remove '$plotTmp' manually 🙂"
}
