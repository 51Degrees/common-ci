# Repository Scripts

These are scripts that must be present in the `ci` directory of each repository that uses the common workflows.

## Build Project

**Script: `build-project.ps1`**

Builds the project. This is passed any build configuration parameters required from the `options.json`, and should call language specific build scripts in `common-ci` where possible.

## Build Package

**Script: `build-package.ps1`**

Build a package ready for testing and publishing.

Any requirements from `build-package-requirements` will be downloaded to `package-files` before this script is called.

This should output any package files to the `package` directory.

## Build Package Requirements

**Script: `build-package-requirements.ps1`**

This should build any config specific requirements for the package. For example, native binaries that need to be built on different platforms before being combined in the final package.

This should output any files required for the package to the `package-files` directory.

## Fetch Assets

**Script: `fetch-assets.ps1`**

Fetches any assets needed for building or testing. This should reuse common asset steps. It is passed a `keys` object as a parameter, which is a hashtable of any named keys passed as secrets to the the workflow.

## Get Next Package Version

**Script: `get-next-package-version.ps1`**

Gets the next version for the package. This must take a parameter of `ParameterName`, which it then must set to a string containing the next version for the package.

This should make use of the common version which returns the versions from GitVersion as an object.

## Check Version Bump

**Script: `check-version-bump.ps1`** (optional)

Only for a repository that gives each package its own version, and only when `nightly-publish.yml` names the repository in its version check step. The publish then runs it in place of `steps/check-version-bump.ps1`, with `RepoName` and `Version`, from the `common-ci` root. It must exit with 1, and so stop the publish, when any package it is about to publish would move the major or minor place, unless `ALLOW_VERSION_BUMP` is `true`. Running `steps/check-version-bump.ps1` once for each package does this.

`steps/check-version-bump.ps1 -RepoName $RepoName -Plan $plan` does it for every package of a release plan in one call. A repository that also checks a registry passes `-RegistryVersionScript`, a script that gives the highest version the registry has released of one package (see the script's help).

## Check Release Interval

**Script: `check-release-interval.ps1`** (optional)

Only for a repository that tags each package `<package>/<version>`, and only when `nightly-publish.yml` names the repository in its release interval step. When there is something to publish, the publish then runs it in place of `steps/check-release-interval.ps1`, with `RepoName`, `Repository` and `HowToAllow`, from the `common-ci` root. It must exit with 1, and so stop the publish, when any package it is about to publish was last released less than seven days before, unless `ALLOW_EARLY_RELEASE` is `true` or the rule has not started under `WEEKLY_RELEASES_FROM`. Running `steps/check-release-interval.ps1` with `-TagPrefix` once for each package does this, passing `Repository` and `HowToAllow` on, as it reads both variables itself.

`steps/check-release-interval.ps1 -RepoName $RepoName -Plan $plan`, with `Repository` and `HowToAllow`, does it for every package of a release plan in one call.

## Packages

**File: `packages.json`** (optional)

Only for a repository that gives each package its own version. An array with one entry for each package, which the repository's scripts read through [`steps/release-plan.ps1`](/steps/README.md#release-plan) to work out what a publish releases. Each entry has:

- `Name`, the package's name, which its tags start with, as `<Name>/<version>` or, for a Go module, `<Name>/v<version>`.
- `Path`, its folder from the repository root.
- `ExtraPaths`, optional, other folders it takes files from at build time, such as a submodule it vendors.
- `Ignore`, optional, globs from the repository root of files under those folders whose changes do not release the package.
- `IgnoreDefaults`, optional, `false` to count changes to the documentation, tests, examples and LICENSE files the release plan otherwise leaves out. When given it must be a JSON `true` or `false`, and the plan stops on anything else, such as the text `"false"`.
- `DependsOn`, the names of the packages it requires.
- `Publish`, false for a package that is never released, such as the examples.
- `FirstVersion`, the version of its first release, needed only while the package has no tag.

A repository can add fields of its own, which the release plan ignores.

## Release Plan Filter

**Script: `release-plan-filter.ps1`** (optional)

Only for a repository that gives each package its own version. [`steps/release-plan.ps1`](/steps/README.md#release-plan) runs it for each package with changed files left once the ignore globs have left theirs out, with `RepoPath`, `Package` (the package's entry from `packages.json`), `From` (the package's last tag) and `Files` (the changed files, from the repository root). It returns the files whose change releases the package, each exactly as it was given, and the plan stops on a path it was not given. A package with none left is not released. A repository uses it for a rule only its language can apply, such as leaving out a manifest whose only change is to a link.

A submodule in `Path` or `ExtraPaths` changes as one path, its own, so any move of it counts. Neither the ignore globs nor the filter see the files inside it.

## Install Package

**Script: `install-package.ps1`**

Install a prebuilt package locally from the `package` directory.

As an example, if a NuGet package is downloaded to the `package` directory. This script would install it using NuGet.

## Package Dependency Update

**Script: `package-dependency-update.ps1`**

Updated any package dependencies to the latest patch version. This should reuse language specific scripts in `common-ci` where possible.

## Publish Package

**Script: `publish-package.ps1`**

Publish the local package (which was built with `build-package.ps1` and installed locally with `install-package.ps1`) to the appropriate package manager. This should use language specific scripts in `common-ci` where possible.

Declare a `[bool]$DryRun` parameter and pass it to the language specific script. On a dry run that script prepares everything but does not upload.

## Run Integration Tests

**Script: `run-integration-tests.ps1`**

Run any integration tests for the project. For implementation guidelines, see [Integration Tests](/DESIGN.md#integration-tests). This should use language specific scripts in `common-ci` where possible.

Results should be written to the `[repo]/test-results/integration` directory. Supported formats can be found on the [publish-unit-test-result](https://github.com/EnricoMi/publish-unit-test-result-action#generating-test-result-files) action readme.

## Run Performance Tests

**Script: `run-performance-tests.ps1`**

Run any performance tests for the project. For implementation guidelines, see [Integration Tests](/DESIGN.md#integration-tests). This should use language specific scripts in `common-ci` where possible.

Results should be written to the `[repo]/test-results/performance` directory. Supported formats can be found on the [publish-unit-test-result](https://github.com/EnricoMi/publish-unit-test-result-action#generating-test-result-files) action readme.

Performance figures are different from test results. The performance example or
test writes them itself as a JSON file in the shared schema, and this script
publishes that file to the `[repo]/test-results/performance-summary/` directory
with [`steps/publish-performance-results.ps1`](/steps/publish-performance-results.ps1):

```powershell
./steps/publish-performance-results.ps1 -SourceFile $RepoName/summary.json -Name $Name -RepoName $RepoName
```

This script must not parse the example's console output to recover a figure.
See the [Performance Tests](/DESIGN.md#performance-tests) section for the schema
and the reasoning.

## Run Unit Tests

**Script: `run-unit-tests.ps1`**

Run any unit tests for the project. This should use language specific scripts in `common-ci` where possible.

Results should be written to the `[repo]/test-results/unit` directory. Supported formats can be found on the [publish-unit-test-result](https://github.com/EnricoMi/publish-unit-test-result-action#generating-test-result-files) action readme.

## Select Options

**Script: `select-options.ps1`** (optional)

Chooses the `options.json` entries a pull request is built on, so that a change is not built on every configuration when it only needs some. [`steps/select-options.ps1`](/steps/select-options.ps1) calls it from the pull request's Configure job with two parameters. `Options` is every entry, each as a hashtable. `ChangedFiles` is the files the pull request changes against the branch it merges into, less any Markdown file and anything in a docs folder. A change to those alone builds nothing, and the script is not called.

Where it declares a third parameter, `CommentOnlyFiles`, it is also given those of the changed files whose change touches only comments and blank lines. [`steps/comment-only.ps1`](/steps/comment-only.ps1) finds them by removing the comments from the old and the new text of each file and comparing what is left, for the languages it knows by file extension. A comment can still break a build, for example through a documentation comment that a compiler checks, so such a change should still be built, on fewer entries.

It writes the entries to build to its output, and may change them, for example setting `RunPerformance` to false or adding a `Depth` for the repository's own scripts to read. It writes anything else with `Write-Host`, because anything on its output is read as an entry. A failure, or an output that is not a single entry of `options.json`, stops the build. A path it does not recognise should build more rather than less.

It is not called for the branch itself, which is pull request 0, for a release pull request, or when `full-matrix` is set, so those build every entry as `options.json` gives it.

## Setup Environment

**Script: `setup-environment.ps1`**

Setup any environment variables, or install any tools required for building and testing. This should use scripts from `common-ci/environments` where possible. See [Environments](/environments/README.md).

## Options

**Script: `options.json`**

This is an array of options which are passed to the scripts as parameters. For a more detailed description, see [Options](/DESIGN.md#build-options).