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

function Test-Approval {
    param (
        [Parameter(Position=0)]
        [Object[]]$Reviews,
        [Object[]]$RequestedReviewers
    )
    $InformationPreference = 'Continue'

    # First, check if all required reviewers approved the PR; fail early if not
    foreach ($reviewer in $RequestedReviewers) {
        if ($Reviews | Where-Object { $_.user.id -eq $reviewer.id -and $_.state -ne 'APPROVED' }) {
            Write-Information "The pull request is not approved by the requested reviewer: $($reviewer.login)"
            return $false
        }
    }

    # Check if there's at least one approver with write access to the repo
    $approvals = ($Reviews | Where-Object { $_.state -eq 'APPROVED' -and (Test-WriteAccess $_.user.id) }).user.login
    if ($approvals) {
        Write-Information "The creator doesn't have write access, but the pull request has been approved by: $approvals"
        return $true
    }

    Write-Information "The creator doesn't have write access, and the pull request is not approved by anyone with write access to the repository"
    return $false
}

function Test-Pr {
    param (
        [Parameter(Mandatory, Position=0)]
        [string]$RepoName,
        [Parameter(Mandatory, Position=1)]
        [string]$Id
    )
    $InformationPreference = 'Continue'

    $Pr = gh api /repos/$OrgName/$RepoName/pulls/$Id | ConvertFrom-Json
    $Reviews = gh api /repos/$OrgName/$RepoName/pulls/$Id/reviews | ConvertFrom-JSON
    if (Test-WriteAccess $Pr.user.id) {
        Write-Information "The creator has write access"
        return $True
    } else {
        return Test-Approval $Reviews -RequestedReviewers $Pr.requested_reviewers
    }
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
