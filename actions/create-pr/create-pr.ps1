param (
    [string]$Title = $env:title,
    [string]$To = $env:to,
    [switch]$Force = ($env:force -eq 'true'),
    [switch]$AutoMerge = ($env:auto_merge -eq 'true')
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if (!$Title) { Write-Error "Title must be provided" }

$status = git status --porcelain
if (-not $status) {
    Write-Host "No changes"
    exit 0
}
Write-Host -Separator `n 'Changes:' $status

Write-Host "Committing..."
git -c 'user.name=github-actions[bot]' -c 'user.email=41898282+github-actions[bot]@users.noreply.github.com' commit -am $Title
Write-Host "Pushing..."
git push ($Force ? '--force' : $null) origin HEAD

$from = git branch --show-current
$to = $To ? $To : (git rev-parse --abbrev-ref '@{-1}') # @{-1} means previous branch

if ((gh pr list -H $from -B $to --json number --jq length) -lt 1) {
    Write-Host "Creating PR..."
    $pr = gh pr create -H $from -B $to -t $Title -b $Title
    Write-Host $pr
    if ($AutoMerge) {
        Write-Host "Enabling auto-merge..."
        gh pr merge --auto --squash $pr
    }
} else {
    Write-Host 'PR already exists'
}
