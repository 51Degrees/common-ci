param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [string]$Branch = "main",
    [string]$SetVariable = "PullRequestIds"
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$Collaborators = gh api /repos/$OrgName/$RepoName/collaborators | ConvertFrom-Json

function Test-WriteAccess {
    param (
        [Parameter(Mandatory, Position=0)]
        [int]$UserId
    )
    $permissions = ($Collaborators | Where-Object id -EQ $UserId).permissions
    return $permissions.admin -or $permissions.maintain -or $permissions.push
}

function Test-Pr {
    param (
        [Parameter(Mandatory, Position=0)]
        [string]$RepoName,
        [Parameter(Mandatory, Position=1)]
        [string]$Id
    )

    $Pr = gh api /repos/$OrgName/$RepoName/pulls/$Id | ConvertFrom-Json
    $Reviews = gh api /repos/$OrgName/$RepoName/pulls/$Id/reviews | ConvertFrom-Json

    if ($Pr.requested_reviewers) {
        Write-Host "Skipping PR ${Id}: needs review from: $($Pr.requested_reviewers)"
        return $false
    }

    # GitHub returns a history of all reviews that seems to be ordered in time.
    # We want to consider only the last review of each reviewer.
    $LastReviews = [ordered]@{}
    foreach ($review in $Reviews) {
        $LastReviews[$review.user.id] = $review
    }

    $WriteApproved = $false # will be true if at least one approver has write access
    foreach ($review in $LastReviews.Values) {
        if ($review.state -ne 'APPROVED') {
            Write-Host "Skipping PR $Id, reason: $($review.state) by $($review.user.login)"
            return $false
        } elseif (Test-WriteAccess $review.user.id) {
            Write-Host "PR $Id has been approved by $($review.user.login), who has write access"
            $WriteApproved = $true
        }
    }

    if ($WriteApproved) {
        return $true
    } elseif (Test-WriteAccess $Pr.user.id) {
        Write-Host "PR $Id author ($($Pr.user.login)) has write access"
        return $true
    }

    Write-Host "PR $Id author ($($Pr.user.login)) doesn't have write access, and the pull request is not approved by anyone with write access to the repository"
    return $false
}

$Ids = gh pr list -R $OrgName/$RepoName -B $Branch --json number,isDraft --jq '.[]|select(.isDraft|not).number'
if ($Ids) {
    $ValidIds = @()

    foreach ($Id in $Ids) {
        # Only select PRs which are eligeble for automation.
        Write-Output "Checking PR #$Id"
        if (Test-Pr $RepoName $Id) {
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
