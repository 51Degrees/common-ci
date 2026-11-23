param (
    [bool]$DryRun = $False
)

# twine reads the token from TWINE_PASSWORD, set here from the publishing
# secret. The job that publishes exports it as PYPI_TOKEN.
$env:TWINE_USERNAME = "__token__"

pip install twine || $(throw "pip install failed")
if (!$DryRun) {
    if ([string]::IsNullOrWhiteSpace($env:PYPI_TOKEN)) {
        throw "PYPI_TOKEN is not set, so publishing cannot succeed."
    }
    $env:TWINE_PASSWORD = $env:PYPI_TOKEN
    # twine stops at the first file PyPI rejects, so a publish of several
    # packages can fail with some of them already released. PyPI never accepts
    # the same file twice, so without --skip-existing a re-run fails on the
    # first package that did go up and the rest are never released.
    # check-version-bump.ps1 refuses an unintended version before this runs, so
    # skipping a file already there cannot hide a wrong number.
    twine upload --skip-existing (Get-ChildItem -Path package) || $(throw "package upload failed")
} else {
    Write-Output "Dry run: skipping package upload"
}