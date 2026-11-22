param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$OrgName,
    [Parameter(Mandatory=$true)]
    [string]$Tag,
    [bool]$DryRun
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# The release carries every file in the package folder, a folder zipped first.
# The files go in the call that creates the release, because gh then publishes
# the release only once they are attached, and a mirror of the releases, such
# as SourceForge's, does not see files added after a release is published.
$files = @()
if (Test-Path "package") {
    foreach ($item in Get-ChildItem "package") {
        if ($item.Name -eq "dummy.txt") { continue }
        if ($item.PSIsContainer) {
            $archive = "package/$($item.Name).zip"
            Write-Output "Compressing '$($item.Name)' to '$archive'"
            Compress-Archive -Path $item -DestinationPath $archive -Force
            $item = Get-Item $archive
        }
        $files += $item.FullName
    }
}
$files = @($files | Select-Object -Unique)

Write-Output "Tagging '$Tag'"
git -C $RepoName tag $Tag

if ($DryRun) {
    Write-Output "Dry run - not pushing tag '$Tag'"
    Write-Output "Dry run - not creating a release with $($files.Count) files"
} else {
    Write-Output "Pushing tag '$Tag'"
    git -C $RepoName push origin $Tag

    Write-Output "Creating a GitHub release with $($files.Count) files"
    $arguments = @('-R', "$OrgName/$RepoName", 'release', 'create',
        '--verify-tag', '--generate-notes')
    if ($Tag -cmatch '-alpha(\.\d+)?$') { $arguments += '--prerelease' }
    $arguments += $Tag
    $arguments += $files
    gh @arguments
}
