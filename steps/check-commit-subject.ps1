<#
.SYNOPSIS
Refuses a commit subject that does not start with one of the allowed prefixes
and a colon.

.DESCRIPTION
Every commit subject must start with FEAT, BUG, OPTIM, TEST, REORG, DOC, REF
or BUILD, in capitals, followed straight away by a colon, as CONTRIBUTING.md
explains under "Commit Messages", such as 'BUG: Fixed the string length.'.
Each subject refused is named with the prefixes allowed, and the check exits
with 1 when any is refused.

.PARAMETER Subject
The commit subjects to check. Give this or -Range.

.PARAMETER Range
A range of commits, such as origin/rc..HEAD, whose subjects are checked. Merge
commits are left out, because git or GitHub writes their subjects. Give this
or -Subject.

.PARAMETER RepoName
With -Range, the directory the repository is checked out into. Defaults to
the current directory.
#>
# An unknown parameter stops the check, so a misspelt name cannot leave
# nothing checked.
[CmdletBinding()]
param (
    [AllowEmptyString()]
    [string[]]$Subject,
    [string]$Range,
    [string]$RepoName = '.'
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$Prefixes = @('FEAT', 'BUG', 'OPTIM', 'TEST', 'REORG', 'DOC', 'REF', 'BUILD')
$allowed = ($Prefixes | ForEach-Object { "${_}:" }) -join ', '
$pattern = '^(' + ($Prefixes -join '|') + '):'

if ($PSBoundParameters.ContainsKey('Subject')) {
    $subjects = @($Subject)
} elseif ($Range) {
    $subjects = @(git -C $RepoName log --no-merges --format=%s $Range)
} else {
    throw "Give -Subject, the commit subjects to check, or -Range, a range of commits such as origin/rc..HEAD."
}

if ($subjects.Count -eq 0) {
    Write-Output "No commit to check."
    exit 0
}

$refused = 0
foreach ($line in $subjects) {
    # -cmatch, as the prefixes are in capitals.
    if ($line -cmatch $pattern) {
        Write-Output "'$line' starts with an allowed prefix."
    } else {
        Write-Output ("::error title=Commit subject without a prefix::'$line' " +
            "does not start with one of the allowed prefixes and a colon: $allowed")
        $refused++
    }
}

if ($refused -gt 0) {
    Write-Output ""
    Write-Output ("$refused of $($subjects.Count) commit subjects do not start with " +
        "an allowed prefix, as https://github.com/51Degrees/common-ci/blob/main/CONTRIBUTING.md#commit-messages " +
        "explains. Reword them so each starts with one of $allowed")
    exit 1
}
Write-Output "Every commit subject starts with an allowed prefix."
exit 0
