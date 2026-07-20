param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][hashtable]$Keys,
    [Parameter(Mandatory)][boolean]$DryRun
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

npm config set //registry.npmjs.org/:_authToken $Keys.NPMAuthToken
foreach ($pkg in (Get-ChildItem -Filter *.tgz package)) {
    $tag = $pkg -cmatch '-\d+.\d+.\d+-(\w+).\d+.tgz$' ? $Matches.1 : 'latest'
    npm publish ($DryRun ? '--dry-run' : $null) --access public --tag $tag $pkg
}
