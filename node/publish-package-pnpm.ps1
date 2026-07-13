param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)]$Keys,
    [boolean]$DryRun
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$tag = $package -cmatch '-\d+.\d+.\d+-(\w+).\d+.tgz$' ? $Matches.1 : 'latest'
pnpm config set //registry.npmjs.org/:_authToken $Keys.NPMAuthToken
pnpm publish ($DryRun ? '--dry-run' : $null) --access public --tag $tag ./package
