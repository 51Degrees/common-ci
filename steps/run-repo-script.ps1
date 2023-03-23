param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$ScriptName,
    [string]$ResultName
)

$RepoPath = [IO.Path]::Combine($pwd, $RepoName)

$BuildScript = [IO.Path]::Combine($RepoPath, "ci", $ScriptName)

Write-Output "Running script '$BuildScript'"
# TODO Check if the script accepts results param and exists
. $BuildScript -ResultName $ResultName

Write-Output "Setting '`$$ResultName'"
$InnerResult = Get-Variable -Name $ResultName
Set-Variable -Name $ResultName -Value $InnerResult -Scope 1
