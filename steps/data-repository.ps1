# Prints the folder of a shallow clone of the data repository,
# https://github.com/51Degrees/data, and clones it first if it is not there.
# In GitHub Actions the clone is in the job's temporary folder, so every call
# in a job uses the same clone, and the prefetch can restore the free data
# files into it. Elsewhere the clone belongs to this process, and the caller
# removes it.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$folder = if ($env:RUNNER_TEMP) {
    Join-Path $env:RUNNER_TEMP '51degrees-data'
} else {
    Join-Path ([IO.Path]::GetTempPath()) "data-$PID"
}
if (-not (Test-Path -LiteralPath (Join-Path $folder '.git'))) {
    git clone --quiet --depth 1 https://github.com/51Degrees/data.git $folder
}
$folder
