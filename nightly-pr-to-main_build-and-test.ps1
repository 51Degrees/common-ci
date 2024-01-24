
param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [Parameter(Mandatory=$true)]
    [string]$GitHubToken,
    [string]$GitHubUser = "",
    [string]$GitHubEmail = "",
    [Parameter(Mandatory=$true)]
    [string]$GitHubOutput,
    [Parameter(Mandatory=$true)]
    [string]$PullRequestId,
    [Parameter(Mandatory=$true)]
    [Hashtable]$Options,
    [bool]$DryRun = $False
)

. ./constants.ps1

if ($GitHubUser -eq "") {
    $GitHubUser = $DefaultGitUser
}
if ($GitHubEmail -eq "") {
    $GitHubEmail = $DefaultGitEmail
}

# This token is used by the gh command.
Write-Output "Setting GITHUB_TOKEN"
$env:GITHUB_TOKEN="$GitHubToken"

Write-Output "::group::Configure Git"
./steps/configure-git.ps1 -GitHubToken $GitHubToken -GitHubUser $GitHubUser -GitHubEmail $GitHubEmail
Write-Output "::endgroup::"

Write-Output "::group::Clone $RepoName"
./steps/clone-repo.ps1 -RepoName $RepoName -OrgName $OrgName -Branch $BranchName
Write-Output "::endgroup::"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Output "::group::Checkout PR"
./steps/checkout-pr.ps1 -RepoName $RepoName -PullRequestId $PullRequestId -VariableName "PullRequestSha"
Write-Output pr-sha="$PullRequestSha" | Out-File -FilePath $GitHubOutput -Encoding utf8 -Append
Write-Output "::endgroup::"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Output "::group::Fetch Assets"
./steps/run-repo-script.ps1 -RepoName $RepoName -OrgName $OrgName -ScriptName "fetch-assets.ps1" -Options ($Options.Keys ?? @{}) -DryRun $DryRun
Write-Output "::endgroup::"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Output "::group::Setup Environment"
./steps/run-repo-script.ps1 -RepoName $RepoName -OrgName $OrgName -ScriptName "setup-environment.ps1" -Options $Options -DryRun $DryRun
Write-Output "::endgroup::"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Output "::group::Build Project"
./steps/run-repo-script.ps1 -RepoName $RepoName -OrgName $OrgName -ScriptName "build-project.ps1" -Options $Options -DryRun $DryRun
Write-Output "::endgroup::"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Output "::group::Run Unit Tests"
./steps/run-repo-script.ps1 -RepoName $RepoName -OrgName $OrgName -ScriptName "run-unit-tests.ps1" -Options $Options -DryRun $DryRun
Write-Output "::endgroup::"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Output "::group::Run Integration Tests"
./steps/run-repo-script.ps1 -RepoName $RepoName -OrgName $OrgName -ScriptName "run-integration-tests.ps1" -Options $Options -DryRun $DryRun
Write-Output "::endgroup::"

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if ($Options.RunPerformance -eq $True) {
    Write-Output "::group::Run Performance Tests"
    ./steps/run-repo-script.ps1 -RepoName $RepoName -OrgName $OrgName -ScriptName "run-performance-tests.ps1" -Options $Options -DryRun $DryRun
    Write-Output "::endgroup::"

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }    
}
else {
    Write-Output "Skipping performance tests as they are not configured for '$($Options.Name)'"
}

if ($Options.RunUpdateDataflow -eq $True -and $PullRequestId -ne 0) {
    Write-Output "::group::Run Update Dataflow"
    ./steps/run-repo-script.ps1 -RepoName $RepoName -OrgName $OrgName -ScriptName "run-update-dataflow.ps1" -Options $Options -DryRun $DryRun
    Write-Output "::endgroup::"

    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
