<#
.SYNOPSIS
    Exports the job's secrets and variables into the environment, each under
    its own name.

.DESCRIPTION
    Two kinds of name are exported, and nothing else.

    A name a customer uses, in the demos and the examples, starts with
    _51DEGREES_. Every secret and every variable with that prefix is exported
    to every job, so an organization secret or variable with a _51DEGREES_
    name reaches the tests and the examples with no change to this
    repository.

    A secret that only CI uses has no prefix, and its name says what it does.
    These names are listed in ci-secrets.psd1, by the jobs that take them, so
    that a job receives only what it uses. The names under Every go to every
    job, those under Publish only to a job that publishes, and those under Sign
    only to a job that signs.

    Nothing is renamed, filled from another name or defaulted.

    A name holds one thing. A name this step exports that is both a secret
    and a variable is an error, even in a class the job does not take, so the
    step fails naming it and exports nothing.

    The log carries the names alone.

.PARAMETER Secrets
    The job's secrets as JSON: ${{ toJSON(secrets) }}.

.PARAMETER Vars
    The job's variables as JSON: ${{ toJSON(vars) }}.

.PARAMETER Publish
    The job publishes, so it takes the names under Publish.

.PARAMETER Sign
    The job signs, so it takes the names under Sign.
#>
param(
    [Parameter(Mandatory)][string]$Secrets,
    [Parameter(Mandatory)][string]$Vars,
    [switch]$Publish,
    [switch]$Sign
)
$ErrorActionPreference = "Stop"

$prefix = '_51DEGREES_'
$ci = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'ci-secrets.psd1')

# Whether this step knows a name at all.
function Test-Known ([string]$Name) {
    return $Name.StartsWith($prefix, [StringComparison]::Ordinal) -or
        $Name -cin $ci.Every -or $Name -cin $ci.Publish -or $Name -cin $ci.Sign
}

# Whether this job takes a name it knows.
function Test-Taken ([string]$Name) {
    if ($Name -cin $ci.Publish) { return [bool]$Publish }
    if ($Name -cin $ci.Sign) { return [bool]$Sign }
    return $true
}

function Get-Named ([string]$Json) {
    $all = $Json | ConvertFrom-Json -AsHashtable
    if ($null -eq $all) { $all = @{} }
    $named = @{}
    foreach ($name in $all.Keys) {
        if (Test-Known $name) { $named[$name] = $all[$name] }
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
    Write-Host "No secret to export."
}
if ($exportedVars.Count -gt 0) {
    Write-Host "Exported $($exportedVars.Count) variable(s): $($exportedVars -join ', ')"
} else {
    Write-Host "No variable to export."
}
