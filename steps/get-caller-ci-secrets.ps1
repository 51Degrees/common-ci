<#
.SYNOPSIS
    Saves the calling repository's list of the CI secrets its own build and
    test scripts read, for steps/export-secrets.ps1.

.DESCRIPTION
    Reads ci/ci-secrets.psd1 from the repository through the GitHub API. A
    pull request job reads it from the branch the pull request goes into, and
    a publish job from the branch it builds. Saves it at Path. When the
    repository has no such file, nothing is saved, any file already at Path
    is removed, and the export step exports nothing more.

    The file is a PowerShell data file with the names under Scripts:

        @{
            Scripts = @(
                'NAME_ONE'
            )
        }

    gh reads the token from GH_TOKEN.

.PARAMETER Repository
    The calling repository, as owner/name.

.PARAMETER Ref
    The branch to read the list from.

.PARAMETER Path
    Where to save the list.
#>
param(
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$Ref,
    [Parameter(Mandatory)][string]$Path
)
$ErrorActionPreference = "Stop"

$escaped = [Uri]::EscapeDataString($Ref)
$content = gh api -H "Accept: application/vnd.github.raw" "repos/$Repository/contents/ci/ci-secrets.psd1?ref=$escaped" 2>$null
if ($LASTEXITCODE -ne 0) {
    # gh exits non-zero on a 404, and on any other failure. Tell them apart.
    $status = gh api "repos/$Repository/contents/ci/ci-secrets.psd1?ref=$escaped" --jq '.type' 2>&1
    if ("$status" -match 'HTTP 404') {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        $global:LASTEXITCODE = 0
        Write-Host "$Repository lists no CI secrets of its own at $Ref."
        return
    }
    throw "Could not read ci/ci-secrets.psd1 from $Repository at ${Ref}: $status"
}
Set-Content -LiteralPath $Path -Value ($content -join "`n")
$names = @((Import-PowerShellDataFile -LiteralPath $Path).Scripts | Where-Object { $_ })
Write-Host "$Repository lists $($names.Count) CI secret(s) of its own at ${Ref}: $($names -join ', ')"
