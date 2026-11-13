param (
    [Parameter(Mandatory=$true)]
    [string]$RepoName,
    [Parameter(Mandatory=$true)]
    [string[]]$Packages,
    [string[]]$WithExtensions
)

foreach ($package in $Packages) {
    Push-Location $RepoName/$package
    try {
        if ($package -in $WithExtensions) {
            Write-Output "Building extensions of $package"
            python setup.py build_clib build_ext --inplace
        }

        Write-Output "Building $package"
        pip install . || $(throw "failed to build $package")

        # The source folder under src/ has the package folder's own name. A
        # monorepo passes the package as a path, such as
        # pipeline-python/fiftyone_pipeline_core, so take the last part of it.
        $sourceName = Split-Path -Path $package -Leaf

        # Special case - if package is a '.' we can't just lint the subdir with
        # the same name, so instead we'll lint the first subdir with the name
        # that starts with 'fiftyone*'
        if ($package -eq '.') {
            $sourceName = (get-item src/fiftyone_*)[0].Name
        }

        Write-Output "Linting $sourceName"
        pylint --version
        $sourcePath = Join-Path -Path (Get-Item src) -ChildPath $sourceName
        pylint --rcfile=.pylintrc $sourcePath || $(throw "pylint failed for $sourceName")
    } finally {
        Pop-Location
    }
}
