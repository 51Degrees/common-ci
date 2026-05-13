param(
    [string]$Metrics = $env:metrics,
    [switch]$Save = ($env:save -eq 'true'),
    [string]$Branch = ($env:branch ? $env:branch : 'performance-results')
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if (!$Metrics) { Write-Error "Current metrics must be provided" }

$workTree = "$env:RUNNER_TEMP/$Branch"
git worktree add $workTree $Branch

Push-Location $workTree
try {
    Write-Output '### Performance graphs' >> $env:GITHUB_STEP_SUMMARY
    $currentTime = [DateTime]::UtcNow.ToString("s")
    foreach ($_ in ($Metrics | ConvertFrom-Json -AsHashtable).GetEnumerator()) {
        $metric, $value = $_.Key, $_.Value
        Write-Output "$currentTime`t$value" >> "$metric.tsv"
        $lines = Get-Content -Tail 10 "$metric.tsv"
        $lines | Set-Content "$metric.tsv"
        $table = foreach ($line in $lines) {,($line -split '\s+', 2)}
        $dates = foreach ($row in $table) {([datetime]$row[0]).ToString('%M-%d')}
        $values = foreach ($row in $table) {[double]$row[1]}

@"
~~~mermaid
xychart
    title "$metric"
    x-axis [$($dates.ForEach({"`"$_`""}) -join ',')]
    y-axis "" 0 --> $(($values | Measure-Object -Maximum).Maximum)
    bar [$($values -join ',')]
~~~
"@ | Tee-Object "$metric.md" >> $env:GITHUB_STEP_SUMMARY
    }

    if ($Save) {
        git add .
        git -c 'user.name=github-actions[bot]' -c 'user.email=41898282+github-actions[bot]@users.noreply.github.com' commit --amend --no-edit --reset-author
        git push --force
    }
} finally { Pop-Location }
