param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

# Moves each submodule to the head of the branch it follows, and only forward.
# A submodule stays at the commit the repository records when that head does
# not hold the commit, because the move would drop every commit between them.

$Warning = $env:CI -eq 'true' ? '::warning::' : ''

Write-Output "Updating Submodules"
$submodules = git -C $RepoName submodule foreach --quiet 'echo $sha1 $sm_path'
foreach ($submodule in $submodules) {
    $recorded, $path = $submodule -split ' ', 2
    $folder = Join-Path $RepoName $path

    git -C $RepoName submodule update --remote -- $path
    $head = git -C $folder rev-parse HEAD
    if ($head -eq $recorded) {
        continue
    }

    # The clone holds one commit of each submodule, and whether the head holds
    # the recorded commit can only be read from the head's whole history.
    if ((git -C $folder rev-parse --is-shallow-repository) -eq 'true') {
        git -C $folder fetch --quiet --unshallow
    }
    $PSNativeCommandUseErrorActionPreference = $false
    git -C $folder merge-base --is-ancestor $recorded $head
    $forward = $LASTEXITCODE -eq 0
    $PSNativeCommandUseErrorActionPreference = $true
    $global:LASTEXITCODE = 0

    if ($forward) {
        Write-Output "$path moves forward from $recorded to $head"
    } else {
        git -C $folder checkout --quiet $recorded
        Write-Output ("$Warning$path stays at $recorded, because $head, the head " +
            "of the branch it follows, does not hold that commit. A submodule " +
            "only moves forward.")
    }
}
