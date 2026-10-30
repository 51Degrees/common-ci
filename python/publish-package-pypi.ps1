param (
    [Parameter(Mandatory=$true)]
    [hashtable]$Keys,
    [bool]$DryRun = $False
)

$env:TWINE_USERNAME = "__token__"

pip install twine || $(throw "pip install failed")
if (!$DryRun) {
    $env:TWINE_PASSWORD = $Keys.PypiToken
    # twine stops at the first file PyPI rejects, so a publish of several
    # packages can fail with some of them already released. PyPI never accepts
    # the same file twice, so without --skip-existing a re-run fails on the
    # first package that did go up and the rest are never released.
    # check-version-bump.ps1 refuses an unintended version before this runs, so
    # skipping a file already there cannot hide a wrong number.
    twine upload --skip-existing (Get-ChildItem -Path package) || $(throw "package upload failed")
} else {
    # $env:TWINE_PASSWORD = $Keys.TestPypiToken
    # twine upload --repository testpypi (Get-ChildItem -Path package) || $(throw "package upload failed")
    Write-Output "Dry run: skipping package upload"
}
