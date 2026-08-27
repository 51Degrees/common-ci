param (
    [Parameter(Mandatory)][string]$RepoName,
    [Parameter(Mandatory)][hashtable]$Keys,
    [Parameter(Mandatory)][boolean]$DryRun
)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$registryUrl = 'https://registry.npmjs.org/'
# The npm config key for a registry credential is the registry URL without its scheme.
$authTokenConfigKey = '//registry.npmjs.org/:_authToken'

# npm answers an unauthorised publish with '404 Not Found' rather than 401/403, so that it
# never discloses whether a package name exists. That reads like a missing package and sends
# anyone debugging a failed nightly down the wrong path, so say what it actually means.
$authTokenHint = "The NPMAuthToken secret is missing, expired, revoked, or has lost publish " +
    "rights on the fiftyone.* packages. Note that npm answers an unauthorised publish with " +
    "'404 Not Found' instead of 401/403, so a 404 here does not mean the package is absent."

if ([string]::IsNullOrWhiteSpace($Keys.NPMAuthToken)) {
    $message = "NPMAuthToken is not set, so publishing cannot succeed. $authTokenHint"
    # A dry run never authenticates against the registry, so an absent token is not fatal there.
    if ($DryRun) { Write-Warning $message } else { throw $message }
}

npm config set $authTokenConfigKey $Keys.NPMAuthToken

# Fail fast on an unusable token, while the message can still name the real cause.
try {
    $npmUser = npm whoami --registry $registryUrl
    Write-Host "Authenticated with $registryUrl as '$npmUser'"
} catch {
    # A network fault reaches here too, so let the npm output above decide which it was.
    $message = "'npm whoami' failed against $registryUrl, so the token could not be verified. " +
        "If the output above is an authentication error rather than a network error: $authTokenHint"
    if ($DryRun) { Write-Warning $message } else { throw $message }
}

foreach ($pkg in (Get-ChildItem -Filter *.tgz package)) {
    $tag = $pkg -cmatch '-\d+.\d+.\d+-(\w+).\d+.tgz$' ? $Matches.1 : 'latest'
    try {
        npm publish ($DryRun ? '--dry-run' : $null) --access public --tag $tag $pkg
    } catch {
        # This also catches failures unrelated to auth, so point at the output above
        # rather than asserting that the token is at fault.
        Write-Host ("::error::Failed to publish '$($pkg.Name)' with tag '$tag'. If the output " +
            "above reports 'E404 ... is not in this registry', npm is masking an authorisation " +
            "failure rather than reporting a missing package. $authTokenHint")
        throw
    }
}
