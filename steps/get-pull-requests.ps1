param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][string]$OrgName,
    [string]$Branch = "main",
    [string]$SetVariable = "PullRequestIds"
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$Collaborators = gh api /repos/$OrgName/$RepoName/collaborators | ConvertFrom-Json

function Test-WriteAccess ([Parameter(Mandatory,Position=0)][string]$User) {
    $permissions = ($Collaborators | Where-Object login -EQ $User).permissions
    return $permissions.admin -or $permissions.maintain -or $permissions.push
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

$Ids = gh pr list -R $OrgName/$RepoName -B $Branch --json number,isDraft --jq '.[]|select(.isDraft|not).number'
if ($Ids) {
    $ValidIds = @()

    foreach ($Id in $Ids) {
        # Only select PRs which are eligeble for automation.
        Write-Output "Checking PR #$Id"
        if ((Test-Pr $Id) -and (Test-VersionDirective $Id)) {
            $ValidIds += $Id
        }
    }

    if ($ValidIds.Count -gt 0) {
        Write-Output "Pull request ids are: $([string]::Join(",", $ValidIds))"
        Set-Variable -Scope 1 -Name $SetVariable -Value $ValidIds
    }
    else {
        Write-Output "No pull requests to be checked."
        Set-Variable -Scope 1 -Name $SetVariable -Value @(0)
    }

} else {
    Write-Output "No pull requests to be checked."
    Set-Variable -Scope 1 -Name $SetVariable -Value @(0)
}
