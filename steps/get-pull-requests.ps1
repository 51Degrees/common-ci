param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$OrgName,
    [string]$Branch = "main",
    # Pull request numbers given by hand, comma separated. When given, only
    # these are checked, rather than the open pull requests into the branch.
    [string]$Ids = "",
    [string]$SetVariable = "PullRequests"
)

function Test-WriteAccess ([Parameter(Mandatory,Position=0)][string]$User) {
    $permissions = ($script:Collaborators | Where-Object login -EQ $User).permissions
    return $permissions.admin -or $permissions.maintain -or $permissions.push
}

# Only pull requests from branches in this repository are selected. A
# contributor's change is built once someone in the organization pushes that
# exact commit to a branch in the repository and opens a pull request from it.
function Test-SameRepository ([Parameter(Mandatory,Position=0)]$Pr) {
    if ($null -eq $Pr.PSObject.Properties['isCrossRepository']) {
        Write-Host "Skipping PR $($Pr.number): gh did not say whether its head is a branch in this repository"
        return $false
    }
    if ($Pr.isCrossRepository -ne $false) {
        Write-Host "Skipping PR $($Pr.number): its head is not a branch in this repository"
        return $false
    }
    if (-not $Pr.headRefOid) {
        Write-Host "Skipping PR $($Pr.number): gh gave no head commit"
        return $false
    }
    return $true
}

function Test-Pr ([Parameter(Mandatory,Position=0)][string]$Id) {
    $Pr = gh pr view -R $OrgName/$RepoName $Id --json author,reviewRequests,latestReviews | ConvertFrom-Json

    if ($Pr.reviewRequests) {
        Write-Host "Skipping PR ${Id}: needs review from: $($Pr.reviewRequests.login)"
        return $false
    }

    $WriteApproved = $false # will be true if at least one approver has write access
    foreach ($review in $Pr.latestReviews) {
        if ($review.state -ne 'APPROVED') {
            Write-Host "Skipping PR $Id, reason: $($review.state) by $($review.author.login)"
            return $false
        } elseif (Test-WriteAccess $review.author.login) {
            Write-Host "PR $Id has been approved by $($review.author.login), who has write access"
            $WriteApproved = $true
        }
    }

    if ($WriteApproved) {
        return $true
    } elseif (Test-WriteAccess $Pr.author.login) {
        Write-Host "PR $Id author ($($Pr.author.login)) has write access"
        return $true
    }

    Write-Host "PR $Id author ($($Pr.author.login)) doesn't have write access, and the pull request is not approved by anyone with write access to the repository"
    return $false
}

function Test-VersionDirective ([Parameter(Mandatory,Position=0)][string]$Id) {
    # A '+semver: minor' or 'major' in any commit makes the next release a new
    # minor or major version of every package this repository publishes, and a
    # published version number can never be reclaimed. So it is a release
    # decision rather than a code change and it needs a second person.
    #
    # Checked here, in the nightly's own selection, rather than through branch
    # protection. An automation with bypass walks straight through a required
    # review, which is how one directive reached four registries overnight on
    # 18 September 2026.
    & "$PSScriptRoot/version-directive.ps1" -Repository "$OrgName/$RepoName" -PullRequest $Id
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Skipping PR ${Id}: version bump not agreed by a second person"
        return $false
    }
    return $true
}

# The pull requests to build, each with the head commit it was selected at,
# which the build and the merge use. Pull request 0, with no commit, is the
# branch itself.
function Get-PullRequests ([string]$Ids = "") {
    $Selected = @()

    if ($Ids) {
        # Numbers given by hand skip the approval rules, and are likewise built
        # only from branches in this repository.
        foreach ($Text in ($Ids -split ',')) {
            $Text = $Text.Trim()
            if ($Text -notmatch '^[0-9]+$') {
                throw "'$Text' is not a pull request number"
            }
            if ([int]$Text -eq 0) {
                $Selected += [ordered]@{ id = 0; sha = '' }
                continue
            }
            $Pr = gh pr view -R $OrgName/$RepoName $Text --json number,isCrossRepository,headRefOid | ConvertFrom-Json
            if (Test-SameRepository $Pr) {
                $Selected += [ordered]@{ id = [int]$Pr.number; sha = [string]$Pr.headRefOid }
            }
        }
    } else {
        $Open = @(gh pr list -R $OrgName/$RepoName -B $Branch --json number,isDraft,isCrossRepository,headRefOid | ConvertFrom-Json |
            Where-Object { -not $_.isDraft })
        foreach ($Pr in $Open) {
            # Only select PRs which are eligible for automation.
            Write-Host "Checking PR #$($Pr.number)"
            if ((Test-SameRepository $Pr) -and (Test-Pr $Pr.number) -and (Test-VersionDirective $Pr.number)) {
                $Selected += [ordered]@{ id = [int]$Pr.number; sha = [string]$Pr.headRefOid }
            }
        }
    }

    # With nothing selected from the open pull requests, the branch itself is
    # built. Numbers given by hand that are all refused build nothing.
    if ($Selected.Count -eq 0 -and -not $Ids) {
        Write-Host "No pull requests to be checked."
        $Selected = @([ordered]@{ id = 0; sha = '' })
    }
    return $Selected
}

# Dot-sourcing, as the tests do, only defines the functions.
if ($MyInvocation.InvocationName -eq '.') {
    return
}

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$script:Collaborators = gh api /repos/$OrgName/$RepoName/collaborators | ConvertFrom-Json

$PullRequests = @(Get-PullRequests -Ids $Ids)
Write-Output "Pull requests are: $(($PullRequests | ForEach-Object { "#$($_.id) $($_.sha)" }) -join ', ')"
Set-Variable -Scope 1 -Name $SetVariable -Value $PullRequests
