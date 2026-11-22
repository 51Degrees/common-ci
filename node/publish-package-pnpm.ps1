param (
    [Parameter(Mandatory)][string]$RepoName,
    [boolean]$DryRun
)
$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $true

$tag = $package -cmatch '-\d+.\d+.\d+-(\w+).\d+.tgz$' ? $Matches.1 : 'latest'
# pnpm takes the registry credential from its config, set here from the
# publishing secret the job exported.
pnpm config set //registry.npmjs.org/:_authToken $env:_51DEGREES_PUBLISH_NPM_AUTH_TOKEN
pnpm publish ($DryRun ? '--dry-run' : $null) --access public --tag $tag ./package