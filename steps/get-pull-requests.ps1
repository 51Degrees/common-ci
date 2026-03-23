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

$Ids = gh pr list -R $OrgName/$RepoName -B $Branch --json number,isDraft --jq '.[]|select(.isDraft|not).number'
if ($Ids) {
    $ValidIds = @()

    foreach ($Id in $Ids) {
        # Only select PRs which are eligeble for automation.
        Write-Output "Checking PR #$Id"
        if (Test-Pr $Id) {
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
