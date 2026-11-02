param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string]$Version,
    [Parameter(Mandatory=$true)]
    [string[]]$Packages
)

# GitVersion emits a SemVer string. For `main` this is a clean release (e.g.
# 4.6.0) and for `version/*` branches a recognised prerelease (e.g. 4.6.0-alpha.1)
# - both of which setuptools/PEP 440 accept. Any other branch produces an
# arbitrary prerelease label taken from the branch name (e.g.
# 4.6.0-fix-utm-parameters.1), which is NOT a valid PEP 440 version, so modern
# setuptools rejects it and the package build fails. Convert such a label into a
# PEP 440 local-version segment so the package still builds on any branch.
if ($Version -match '^(\d+\.\d+\.\d+)-(?!(?:alpha|beta|rc)[.0-9]*$)(.+)$') {
    $local = ($Matches[2] -replace '[^0-9A-Za-z]+', '.').Trim('.')
    $Version = "$($Matches[1])+$local"
    Write-Output "Normalized non-PEP 440 branch version to '$Version'"
}

$packagesDir = New-Item -ItemType directory -Path package -Force

# Packages with a C/C++ extension are published as source distributions only.
# `python -m build` also makes a wheel tagged for the build machine
# (linux_x86_64), which PyPI rejects with a 400, and twine then stops without
# uploading the packages after it. The first IP Intelligence publish failed
# that way, leaving one of its six packages released. Matched on the package
# folder's own name, because a monorepo passes the package as a path such as
# device-detection-python/fiftyone_devicedetection_onpremise.
$sourceOnlyPackages = 'fiftyone_devicedetection_onpremise', 'fiftyone_ipintelligence_onpremise'

Push-Location $RepoName
try {
    # Should probably be done in setup-environment.ps1, but it isn't called by
    # build-package.ps1, so doing it here for now
    pip install --upgrade pip
    pip install setuptools wheel build Cython || $(throw "pip install failed")

    foreach ($package in $Packages) {
        Write-Output "Packaging $package"
        Push-Location $package
        try {
            $Version | Out-File version.txt
            if ((Split-Path -Path $package -Leaf) -in $sourceOnlyPackages) {
                python setup.py sdist || $(throw "failed to build package $package")
            } else {
                python -m build || $(throw "failed to build package $package")
            }
            Move-Item -Path dist/* -Destination $packagesDir || $(throw "failed to move $package package")
        } finally {
            Pop-Location
        }
    }
} finally {
    Pop-Location
}
