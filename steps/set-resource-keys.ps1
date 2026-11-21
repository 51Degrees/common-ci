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

    Exported, each to the current process environment (so later scripts in the
    same job inherit it) and, under GitHub Actions, to $GITHUB_ENV (so later
    steps in the same job inherit it too):
      * every supplied secret whose name matches the resource-key convention
        (by default any name beginning with "_51DEGREES_RESOURCE_KEY", e.g.
        the organisation secrets _51DEGREES_RESOURCE_KEY_FREE and
        _51DEGREES_RESOURCE_KEY_PAID);
      * every supplied secret whose name is a current name in
        environment-variables.json, such as _51DEGREES_LICENSE_KEY_BESPOKE;
      * each current name whose entry has filledInCiFrom, when it has no value
        of its own, from the secret that entry names. Only _51DEGREES_ names
        are used: an old name never fills anything, even when it has a
        secret.

    _51DEGREES_RESOURCE_KEY_51DID and _51DEGREES_RESOURCE_KEY_BASIC each come
    only from the secret of their own name. Neither is filled from another
    secret, so without that secret each stays empty.

    _51DEGREES_LICENSE_KEY_51DID is never exported. It reads only results made
    with the 51Did resource key, so each repository's own Cloud 51Did workflow
    sets it from its secret, beside _51DEGREES_RESOURCE_KEY_51DID.

    A value the job already set is never replaced. Each resource or license key
    that is still empty is named in the log, so a test that skips for want of
    it can be traced. Nothing fails for want of a key.

    To make a NEW resource key available to every repository, add the secret at
    the organisation level following the _51DEGREES_RESOURCE_KEY_* convention.
    It is picked up here automatically, with no change to any repository's CI.

    Secret values are never written to the log, only names; GitHub masks
    registered secret values regardless.

.PARAMETER Keys
    The secrets available to the job, as a hashtable of name -> value. In the
    common-ci framework this is the $Options.Keys hashtable (the secrets
    context passed in as ${{ toJSON(secrets) }}). GitHub gives secret names in
    capitals, so names are matched without regard to letter case.

.PARAMETER Prefix
    The naming convention that identifies a resource key. Any supplied key whose
    name begins with this prefix (case-insensitively) is exported. This is the
    central knob for the convention.

.PARAMETER ListPath
    The list of agreed names. The default is environment-variables.json at the
    root of this repository.
#>
param(
    [hashtable]$Keys = @{},
    [string]$Prefix = "_51DEGREES_RESOURCE_KEY",
    [string]$ListPath = (Join-Path $PSScriptRoot '..' 'environment-variables.json')
)
$ErrorActionPreference = "Stop"

# The names of the keys whose absence is worth naming in the log.
$KeyPattern = '^_51DEGREES_(RESOURCE|LICENSE)_KEY(_|$)'

# The names never exported here. The 51Did license key reads only results
# made with the 51Did resource key, so only the Cloud 51Did workflows set it.
$NotExported = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('_51DEGREES_LICENSE_KEY_51DID'),
    [System.StringComparer]::OrdinalIgnoreCase)

# The secrets, with names matched without regard to letter case.
$secrets = [System.Collections.Generic.Dictionary[string, string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase)
if ($null -ne $Keys) {
    foreach ($entry in $Keys.GetEnumerator()) {
        $secrets[[string]$entry.Key] = [string]$entry.Value
    }
}

$variables = @()
if (Test-Path -LiteralPath $ListPath) {
    $variables = @((Get-Content -Raw -LiteralPath $ListPath | ConvertFrom-Json).variables)
}
else {
    Write-Host "No list of agreed names at '$ListPath'; only the '$Prefix*' secrets are exported."
}

function Test-Value ([string]$Value) {
    return -not [string]::IsNullOrWhiteSpace($Value)
}

function Get-Secret ([string]$Name) {
    $value = $null
    if ($secrets.TryGetValue($Name, [ref]$value) -and (Test-Value $value)) {
        return $value
    }
    return $null
}

function Set-Variable51 ([string]$Name, [string]$Value) {
    # Process environment: inherited by later scripts in this same job.
    Set-Item -Path "Env:$Name" -Value $Value

    # GitHub Actions environment file: inherited by later steps in this job.
    # Keys are single-line tokens, so a plain name=value line is safe.
    if (-not [string]::IsNullOrEmpty($env:GITHUB_ENV)) {
        "$Name=$Value" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
    }
}

# The secrets to export under their own names: the resource keys, and every
# current name in the list.
$agreed = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase)
foreach ($variable in $variables) { [void]$agreed.Add([string]$variable.name) }

$exported = [System.Collections.Generic.List[string]]::new()
foreach ($name in @($secrets.Keys | Sort-Object)) {
    if ($name -notlike "$Prefix*" -and -not $agreed.Contains($name)) { continue }
    if ($NotExported.Contains($name)) {
        Write-Host "Not exporting '$name': only the Cloud 51Did workflows set it."
        continue
    }
    $value = Get-Secret $name
    if ($null -eq $value) {
        Write-Host "Skipping '$name': no value (secret not set)."
        continue
    }
    Set-Variable51 $name $value
    $exported.Add($name)
}
if ($exported.Count -gt 0) {
    Write-Host "Set $($exported.Count) environment variable(s) from secrets of the same name: $($exported -join ', ')"
}
else {
    Write-Host "No secret is a resource key or an agreed name; none set under its own name."
}

# Each current name with no value is filled from the _51DEGREES_ secret its
# entry names, unless the job set it.
foreach ($variable in $variables) {
    $name = [string]$variable.name
    $source = [string]$variable.filledInCiFrom
    if (-not (Test-Value $source)) { continue }
    if ($NotExported.Contains($name)) { continue }
    if (Test-Value ([Environment]::GetEnvironmentVariable($name))) { continue }
    if (-not $source.StartsWith('_51DEGREES_', [StringComparison]::Ordinal)) {
        Write-Host "Not filling $name from $source, which does not start _51DEGREES_."
        continue
    }
    $value = Get-Secret $source
    if ($null -eq $value) { continue }
    Set-Variable51 $name $value
    Write-Host "Filled $name from $source."
}

# Name each key still empty, for the tests that skip without it.
$missing = @($variables | ForEach-Object { [string]$_.name } |
    Where-Object { $_ -cmatch $KeyPattern -and -not $NotExported.Contains($_) } |
    Where-Object { -not (Test-Value ([Environment]::GetEnvironmentVariable($_))) })
foreach ($name in $missing) {
    Write-Host "No value for $name. Tests that need it should skip and say so."
}
