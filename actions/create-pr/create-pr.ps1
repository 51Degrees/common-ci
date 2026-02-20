$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

if (!$env:title) { Write-Error "title variable is required" }

$status = git status --porcelain
if (-not $status) {
    Write-Host "No changes"
    exit 0
}
Write-Host "Changes:`n$status"

Write-Host "Committing..."
git -c 'user.name=github-actions[bot]' -c 'user.email=41898282+github-actions[bot]@users.noreply.github.com' commit -am $env:title
Write-Host "Pushing..."
git push ($env:force -eq 'true' ? '--force-with-lease' : $null) origin HEAD

$from = git branch --show-current
$to = $env:to ? $env:to : (git rev-parse --abbrev-ref origin/HEAD) -replace '^[^/]+/'

if ((gh pr list -H $from -B $to --json number --jq length) -lt 1) {
    Write-Host "Creating PR..."
    gh pr create -H $from -B $to -t $env:title -b $env:title
} else {
    Write-Host 'PR already exists'
}
