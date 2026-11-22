<#
.SYNOPSIS
    Exports the job's _51DEGREES_ secrets and variables into the environment,
    each under its own name.

.DESCRIPTION
    Every secret and every variable whose name starts with _51DEGREES_ is set
    in the process environment and, under GitHub Actions, written to
    $GITHUB_ENV for the steps that follow. Nothing else is exported. Nothing
    is renamed, filled from another name or defaulted, and no list of names is
    kept here: an organization secret or variable with a _51DEGREES_ name
    reaches the job with no change to this repository.

    A job receives only what it uses. A name that starts with
    _51DEGREES_PUBLISH_ is exported only to a job that publishes, and a name
    that starts with _51DEGREES_SIGN_ only to a job that signs. The start of
    the name decides, so a new publishing or signing secret needs no change
    here either.

    A name holds one thing. A _51DEGREES_ name that is both a secret and a
    variable is an error: the step fails naming it and exports nothing.

    The log carries the names alone.

.PARAMETER Secrets
    The job's secrets as JSON: ${{ toJSON(secrets) }}.

.PARAMETER Vars
    The job's variables as JSON: ${{ toJSON(vars) }}.

.PARAMETER Publish
    The job publishes, so it takes the _51DEGREES_PUBLISH_ names.

.PARAMETER Sign
    The job signs, so it takes the _51DEGREES_SIGN_ names.
#>
param(
    [Parameter(Mandatory)][string]$Secrets,
    [Parameter(Mandatory)][string]$Vars,
    [switch]$Publish,
    [switch]$Sign
)
$ErrorActionPreference = "Stop"

$prefix = '_51DEGREES_'

# Whether this job takes a name, by the class the name starts with.
function Test-Taken ([string]$Name) {
    if ($Name.StartsWith("${prefix}PUBLISH_", [StringComparison]::Ordinal)) { return [bool]$Publish }
    if ($Name.StartsWith("${prefix}SIGN_", [StringComparison]::Ordinal)) { return [bool]$Sign }
    return $true
}

function Get-Named ([string]$Json) {
    $all = $Json | ConvertFrom-Json -AsHashtable
    if ($null -eq $all) { $all = @{} }
    $named = @{}
    foreach ($name in $all.Keys) {
        if ($name.StartsWith($prefix, [StringComparison]::Ordinal)) { $named[$name] = $all[$name] }
    }
    return $named
}

$namedSecrets = Get-Named $Secrets
$namedVars = Get-Named $Vars

$both = @($namedVars.Keys | Where-Object { $namedSecrets.ContainsKey($_) } | Sort-Object)
if ($both.Count -gt 0) {
    throw "Both a secret and a variable, and a name holds one thing: $($both -join ', ')"
}

function Export-Named ([hashtable]$Named) {
    $exported = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @($Named.Keys | Sort-Object)) {
        if (-not (Test-Taken $name)) { continue }
        $value = [string]$Named[$name]
        if ([string]::IsNullOrEmpty($value)) { continue }

        # This process, for a script run in the same step.
        Set-Item -Path "Env:$name" -Value $value

        # The steps that follow. The delimited form carries a value of any
        # number of lines, such as a certificate or a key file.
        if (-not [string]::IsNullOrEmpty($env:GITHUB_ENV)) {
            $delimiter = "END_$([guid]::NewGuid().ToString('N'))"
            Add-Content -Path $env:GITHUB_ENV -Value "$name<<$delimiter", $value, $delimiter
        }

        $exported.Add($name)
    }
    return $exported
}

$exportedSecrets = Export-Named $namedSecrets
$exportedVars = Export-Named $namedVars

if ($exportedSecrets.Count -gt 0) {
    Write-Host "Exported $($exportedSecrets.Count) secret(s): $($exportedSecrets -join ', ')"
} else {
    Write-Host "No $prefix secret to export."
}
if ($exportedVars.Count -gt 0) {
    Write-Host "Exported $($exportedVars.Count) variable(s): $($exportedVars -join ', ')"
} else {
    Write-Host "No $prefix variable to export."
}
