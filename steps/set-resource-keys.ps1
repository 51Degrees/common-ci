<#
.SYNOPSIS
    Exports 51Degrees resource key secrets as environment variables for the
    steps and tests that follow.

.DESCRIPTION
    51Degrees cloud tests read their resource key from an environment variable.
    Some read a single key; others (for example the 51Did cloud test) iterate
    over every available tier, running once per key. Rather than have each
    repository wire the keys up in its own CI, this is the single, central place
    that knows the resource-key naming convention and makes the keys available
    everywhere.

    Every supplied secret whose name matches the resource-key convention (by
    default any name beginning with "_51DEGREES_RESOURCE_KEY", e.g. the
    organisation secrets _51DEGREES_RESOURCE_KEY_FREE and
    _51DEGREES_RESOURCE_KEY_PAID) is exported:
      * to the current process environment, so later scripts in the same job
        (build-project, run-unit-tests, run-integration-tests, ...) inherit it;
      * and, when running under GitHub Actions, appended to $GITHUB_ENV, so
        later steps in the same job inherit it too.

    To make a NEW resource key available to every repository, add the secret at
    the organisation level following the _51DEGREES_RESOURCE_KEY_* convention.
    It is picked up here automatically, with no change to any repository's CI.

    Secret values are never written to the log; GitHub masks registered secret
    values regardless.

.PARAMETER Keys
    The secrets available to the job, as a hashtable of name -> value. In the
    common-ci framework this is the $Options.Keys hashtable (the secrets
    context passed in as ${{ toJSON(secrets) }}).

.PARAMETER Prefix
    The naming convention that identifies a resource key. Any supplied key whose
    name begins with this prefix (case-insensitively) is exported. This is the
    central knob for the convention.
#>
param(
    [hashtable]$Keys = @{},
    [string]$Prefix = "_51DEGREES_RESOURCE_KEY"
)
$ErrorActionPreference = "Stop"

if ($null -eq $Keys -or $Keys.Count -eq 0) {
    Write-Host "No keys supplied; no resource key environment variables to set."
    return
}

$exported = [System.Collections.Generic.List[string]]::new()
foreach ($entry in $Keys.GetEnumerator()) {
    $name = [string]$entry.Key
    $value = [string]$entry.Value

    if ($name -notlike "$Prefix*") { continue }
    if ([string]::IsNullOrWhiteSpace($value)) {
        Write-Host "Skipping '$name': no value (secret not set)."
        continue
    }

    # Process environment: inherited by later scripts in this same job.
    Set-Item -Path "Env:$name" -Value $value

    # GitHub Actions environment file: inherited by later steps in this job.
    # Resource keys are single-line tokens, so a plain name=value line is safe.
    if (-not [string]::IsNullOrEmpty($env:GITHUB_ENV)) {
        "$name=$value" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
    }

    $exported.Add($name)
}

if ($exported.Count -gt 0) {
    Write-Host "Set $($exported.Count) resource key environment variable(s): $($exported -join ', ')"
}
else {
    Write-Host "No keys matching '$Prefix*' were supplied; nothing to set."
}
