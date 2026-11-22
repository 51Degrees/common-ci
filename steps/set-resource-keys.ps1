<#
.SYNOPSIS
    Exports the job's _51DEGREES_ secrets into the environment, each under its
    own name.

.DESCRIPTION
    Every secret whose name starts with _51DEGREES_ is set in the process
    environment and, under GitHub Actions, written to $GITHUB_ENV for the steps
    that follow. Nothing else is exported. Nothing is renamed, filled from
    another name or defaulted, and no list of names is kept here: an
    organisation secret with a _51DEGREES_ name reaches the job with no change
    to this repository.

    The log carries the names alone.

.PARAMETER Secrets
    The job's secrets as JSON: ${{ toJSON(secrets) }}.
#>
param(
    [Parameter(Mandatory)][string]$Secrets
)
$ErrorActionPreference = "Stop"

$all = $Secrets | ConvertFrom-Json -AsHashtable
if ($null -eq $all) { $all = @{} }

$exported = [System.Collections.Generic.List[string]]::new()

foreach ($name in @($all.Keys | Sort-Object)) {
    if (-not $name.StartsWith('_51DEGREES_', [StringComparison]::Ordinal)) { continue }

    $value = [string]$all[$name]
    if ([string]::IsNullOrEmpty($value)) { continue }

    # This process, for a script run in the same step.
    Set-Item -Path "Env:$name" -Value $value

    # The steps that follow. The delimited form carries a value of any number
    # of lines, such as a certificate or a key file.
    if (-not [string]::IsNullOrEmpty($env:GITHUB_ENV)) {
        $delimiter = "END_$([guid]::NewGuid().ToString('N'))"
        Add-Content -Path $env:GITHUB_ENV -Value "$name<<$delimiter", $value, $delimiter
    }

    $exported.Add($name)
}

if ($exported.Count -gt 0) {
    Write-Host "Exported $($exported.Count) secret(s): $($exported -join ', ')"
} else {
    Write-Host "No _51DEGREES_ secret to export."
}