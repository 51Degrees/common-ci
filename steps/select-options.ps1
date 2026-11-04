param (
    [Parameter(Mandatory)][string]$RepoName,
    # The branch the pull request merges into.
    [Parameter(Mandatory)][string]$Branch,
    # Every entry of the repository's ci/options.json, as JSON.
    [Parameter(Mandatory)][string]$Options,
    [string]$SetVariable = "Options"
)
# Chooses the ci/options.json entries a pull request is built on, from the
# files it changes, and sets $SetVariable to them as JSON.
#
# A change to documentation alone builds nothing. That is every Markdown file
# and anything in a docs folder, the files steps/package-update-required.ps1
# leaves out of a release, less .github, because a workflow change has to be
# tried. Otherwise the repository's ci/select-options.ps1 chooses. It is given
# every entry and the changed files that are not documentation, and returns
# the entries to build, which it may change, for example to add a Depth that
# its own scripts read. Where it declares a CommentOnlyFiles parameter, it is
# also given those of the files whose change touches only comments.
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

. $PSScriptRoot/comment-only.ps1

# The text of a file at a revision, or null where the file is not there.
function Get-FileText([string]$Revision, [string]$Path) {
    $PSNativeCommandUseErrorActionPreference = $false
    $text = git -C $RepoName show "${Revision}:$Path" 2>$null
    if ($LASTEXITCODE -ne 0) {
        $global:LASTEXITCODE = 0
        return $null
    }
    return $text -join "`n"
}

# The pull request is checked out with $Branch merged in, so the merge base
# with $Branch leaves only the pull request's own changes. --no-renames lists
# both sides of a move.
$base = git -C $RepoName merge-base "origin/$Branch" HEAD
$changed = @(git -C $RepoName -c core.quotePath=false diff --name-only `
    --no-renames $base HEAD)
Write-Host "$($changed.Count) files changed against $Branch"
$changed | ForEach-Object { Write-Host "  $_" }

$entries = @(ConvertFrom-Json $Options -AsHashtable)
$code = @($changed | Where-Object {
    $_ -notmatch '(?i)\.md$' -and $_ -notmatch '(^|/)docs/'
})

if ($changed.Count -gt 0 -and $code.Count -eq 0) {
    Write-Host "Only documentation changed, so no entry is built"
    $selected = @()
} else {
    $select = (Resolve-Path (Join-Path $RepoName ci/select-options.ps1)).Path
    $arguments = @{ Options = $entries; ChangedFiles = $code }
    if ((Get-Command $select).Parameters.ContainsKey('CommentOnlyFiles')) {
        # Only files whose comments are known are read, so a binary file or a
        # submodule is never loaded.
        $arguments.CommentOnlyFiles = @($code | Where-Object {
            (Get-CommentStyle $_) -and (Test-CommentOnlyChange $_ `
                (Get-FileText $base $_) (Get-FileText HEAD $_))
        })
        $arguments.CommentOnlyFiles | ForEach-Object {
            Write-Host "Only comments changed in $_"
        }
    }
    # An exit code is checked as well as an exception, as run-script.ps1 does,
    # so a failing script stops the build rather than choosing nothing.
    $global:LASTEXITCODE = 0
    $selected = @(& $select @arguments)
    if ($LASTEXITCODE -ne 0) {
        throw "ci/select-options.ps1 failed with code $LASTEXITCODE"
    }
}

# Anything the script writes to its output is read as an entry, so a stray
# message fails here rather than building something unexpected.
$names = @($entries | ForEach-Object { $_.Name })
$kept = @()
foreach ($entry in $selected) {
    if ($entry -isnot [System.Collections.IDictionary] -or
        $names -cnotcontains $entry.Name -or $kept -ccontains $entry.Name) {
        $what = $entry -is [System.Collections.IDictionary] ? $entry.Name : $entry
        throw "ci/select-options.ps1 returned '$what', which is not a single entry of ci/options.json"
    }
    $kept += $entry.Name
}
foreach ($name in $names) {
    Write-Host ($kept -ccontains $name ? "Building $name" : "Not building $name")
}

$json = ConvertTo-Json -InputObject $selected -Depth 10 -Compress
Set-Variable -Scope 1 -Name $SetVariable -Value $json
