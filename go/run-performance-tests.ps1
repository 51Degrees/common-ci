param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$OrgName,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Example,
    [string]$ExamplesRepo,
    [string]$Branch = "main"
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$summaryDir = New-Item -ItemType directory -Path $RepoName/test-results/performance-summary -Force

Push-Location $RepoName
try {
    if ($ExamplesRepo) {
        Write-Host "Cloning examples..."
        ./steps/clone-repo.ps1 -OrgName $OrgName -RepoName $ExamplesRepo -Branch $Branch
    }

    Write-Host "Running performance test..."
    go run $Example

    switch -File performance_report.log -Regex {
        'Average ([^ ]+) ms per' { $MsPerDetection = [double]$matches.1 }
        'Average ([^ ]+) detections per second' { $DetectionsPerSecond = [double]$matches.1 }
    }

    if (-not $MsPerDetection -or -not $DetectionsPerSecond) {
        Get-Content performance_report.log | Write-Error
    }

    @{
        HigherIsBetter = @{
            DetectionsPerSecond = $DetectionsPerSecond
        }
        LowerIsBetter = @{
            AvgMillisecsPerDetection = $MsPerDetection
        }
    } | ConvertTo-Json | Out-File $summaryDir/results_$Name.json
} finally {
    Pop-Location
}
