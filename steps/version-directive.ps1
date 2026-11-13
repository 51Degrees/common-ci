<#
.SYNOPSIS
Whether a pull request asks for a new minor or major version, and whether a
second person has agreed to it.

.DESCRIPTION
GitVersion bumps the patch unless a commit message carries a directive such
as `+semver: minor`. One such directive, in the body of one commit, moves
every package a repository publishes to a new minor version.

That is not a small thing. The published documentation is versioned, so a
minor bump means a new documentation version. A version number can never be
reclaimed once published: NuGet cannot delete, crates.io cannot unpublish,
and PyPI burns the number even when a release is deleted. On 18 September
2026 a single directive in one commit took sixteen NuGet packages, three npm
packages, five PyPI projects and three crates to 4.6 overnight, merged and
published by automation with nobody reading it.

So a directive is treated here as a release decision rather than a code
change, and it needs two people. The author writes it. Someone else with
write access agrees by applying the approval label. This is checked in this
script rather than in branch protection, because an automation with bypass
would otherwise walk straight through a required review.

.PARAMETER Repository
Owner and name, such as 51Degrees/pipeline-dotnet.

.PARAMETER PullRequest
The pull request number.

.PARAMETER Label
The label a second person applies to agree the bump.
#>
param (
    [Parameter(Mandatory)][string]$Repository,
    [Parameter(Mandatory)][string]$PullRequest,
    [string]$Label = "version bump approved"
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Matches the directive GitVersion reads, in any commit message, allowing the
# spacing GitVersion allows. Only minor and major are gated: a patch directive
# asks for what would happen anyway.
$DirectivePattern = '\+semver:\s*(minor|major)'

function Get-VersionDirective {
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$PullRequest)
    $commits = gh pr view $PullRequest -R $Repository --json commits | ConvertFrom-Json
    foreach ($c in $commits.commits) {
        $message = ($c.messageHeadline + "`n" + $c.messageBody)
        $m = [regex]::Match($message, $DirectivePattern, 'IgnoreCase')
        if ($m.Success) {
            return [pscustomobject]@{
                Kind = $m.Groups[1].Value.ToLowerInvariant()
                Commit = $c.oid
            }
        }
    }
    return $null
}

function Get-DirectiveApprover {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string]$PullRequest,
        [Parameter(Mandatory)][string]$Author,
        [Parameter(Mandatory)][string]$Label
    )
    # Who applied the label, not merely that it is present, because the author
    # applying their own label is one person and not two.
    $events = gh api "repos/$Repository/issues/$PullRequest/timeline" --paginate | ConvertFrom-Json
    foreach ($e in $events) {
        if ($e.event -eq 'labeled' -and $e.label.name -eq $Label) {
            if ($e.actor.login -and $e.actor.login -ne $Author) {
                return $e.actor.login
            }
        }
    }
    return $null
}

$pr = gh pr view $PullRequest -R $Repository --json author | ConvertFrom-Json
$directive = Get-VersionDirective -Repository $Repository -PullRequest $PullRequest

if ($null -eq $directive) {
    Write-Output "No version directive in PR $PullRequest."
    exit 0
}

$approver = Get-DirectiveApprover -Repository $Repository -PullRequest $PullRequest `
    -Author $pr.author.login -Label $Label

if ($approver) {
    Write-Output "PR $PullRequest asks for a $($directive.Kind) version bump in commit $($directive.Commit), agreed by $approver."
    exit 0
}

Write-Output "::error title=Version bump needs a second person::PR $PullRequest carries '+semver: $($directive.Kind)' in commit $($directive.Commit)."
Write-Output ""
Write-Output "That directive makes the next release a new $($directive.Kind) version of every package this repository publishes."
Write-Output "Before it can merge, someone other than $($pr.author.login), with write access, has to apply the label '$Label'."
Write-Output ""
Write-Output "What a bump costs, so the person applying the label knows what they are agreeing to:"
Write-Output "  * The published documentation is versioned, so a new minor means a new documentation version."
Write-Output "  * The number can never be reclaimed. NuGet cannot delete, crates.io cannot unpublish, and PyPI burns the number even when a release is deleted."
Write-Output "  * Callers on the previous line do not receive it, so a fix released this way does not reach them."
Write-Output ""
Write-Output "If the bump was not intended, remove the directive from the commit message and force the branch, or reword the commit."
exit 1
