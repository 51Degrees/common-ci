param(
    [string]$CurrentResults = $env:current_results,
    [string]$Branch = $env:branch,
    [switch]$IgnoreFailure = ($env:ignore_failure -eq 'true'),
    [switch]$HigherIsBetter = ($env:higher_is_better -eq 'true')
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if (!$CurrentResults) { Write-Error "Current result must be provided" }
if (!$Branch) { $Branch = 'performance-results' }

Write-Host "Installing ScottPlot..."
$plotTmp = [System.IO.Path]::GetTempPath() + "plot." + (New-Guid)
New-Item -ItemType directory -Force -Path $plotTmp # NOTE: not deleted automatically due to Windows not allowing deleting opened files
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

function Compare-Performance {
    param(
        [Parameter(Mandatory)][double[]]$Dates,
        [Parameter(Mandatory)][double[]]$Values,
        [string]$Metric,
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

    Write-Host "Generating graph..."
    $plot = [ScottPlot.Plot]::new()
    [void] $plot.ShowLegend([ScottPlot.Alignment]::UpperLeft)
    [void] $plot.Title($Metric)
    [void] $plot.XLabel("Date")
    [void] $plot.YLabel($Metric)
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
    $plot.SavePng("$Metric.png", 400, 300)

    # Check if current result is within acceptable bounds
    $Passed = $False
    if ($HigherIsBetter) {
        Write-Host "Checking '$currentResult' > '$lowerBound'"
        $Passed = $currentResult -ge $lowerBound
    } else {
        Write-Host "Checking '$currentResult' < '$higherBound'"
        $Passed = $currentResult -le $higherBound
    }
    if (-not $Passed) {
        Write-Warning "The performance of '$Metric' is outside of the acceptable limits relative to the mean"
        if ($Values.Count -lt 10) {
            Write-Warning "There are only '$($Values.Count - 1)' historic results, so this will not be considered a failure"
        } else {
            return $false
        }
    }
    return $true
}

& { $PSNativeCommandUseErrorActionPreference=$false; git switch $Branch }
if ($LASTEXITCODE -ne 0) {
    git switch --orphan $Branch
    git -c 'user.name=github-actions[bot]' -c 'user.email=41898282+github-actions[bot]@users.noreply.github.com' commit --allow-empty -m 'Update performance results'
}

Write-Host "Appending current results..."
$currentTime = [DateTime]::UtcNow.ToString("s")
foreach ($line in ($CurrentResults -split '\r?\n')) {
    $metric, $value = $line.Trim() -split '\s+', 2
    "$currentTime`t$value" >> "$metric.tsv"
}

$failed = $false
foreach ($_ in (Get-ChildItem -File *.tsv)) {
    $metric = $_.Name -replace '\.tsv$'
    Write-Host "Trimming old measurements of $metric..."
    $lines = Get-Content -Tail 10 $_
    $table = foreach ($line in $lines) {,($line -split '\s+', 2)}
    Write-Host $table
    $dates = foreach ($row in $table) {Write-Host $row[0];([datetime]$row[0]).ToOADate()}
    Write-Host $dates
    $values = foreach ($row in $table) {[double]$row[1]}
    Write-Host $values
    $lines | Set-Content $_
    if (-not (Compare-Performance -Dates:$dates -Values:$values -Metric:$metric -HigherIsBetter:$HigherIsBetter)) {
        if ($IgnoreFailure) {
            Write-Warning "IgnoreFailure was passed, ignoring failure"
        } else {
            $failed = $true
        }
    }
}

git add .
git commit --amend --no-edit
git push --force
git switch -

exit $failed ? 1 : 0
