# Steps

## Introduction

Steps are individual parts of a workflow, written in a way that is agnostic when it comes to both Operating System, and CI platform.
They are written as PowerShell scripts, so can be called locally, or in CI.

This document does not seek to describe the exact parameters of each script. For that, see the scripts themselves.

Most scripts take the name of the repository as a parameter, and will change to the directory of the cloned repo before carrying out their tasks.

## Checkout PR
**Script: `checkout-pr.ps1`**

Takes a pull request id, and repo name, and checks out the commit being merged.

This also makes sure to update any submodules.

The repository must be clones before calling this.

## Clone Repo
**Script: `clone-repo.ps1`**

Clones the repo by name into the working directory. Optionally, a branch name can be provided.

All repos are assumed to be in the 51Degrees organization. For example the name `"common-ci"` would be cloned from the URL `https://github.com/51degrees/common-ci`.

## Commit Changes
**Script: `commit-changes.ps1`**

Stages all changes in the repository, and commits them with the message provided.

## Publish Performance Results
**Script: `publish-performance-results.ps1`**

Validates the results JSON a performance example or test emitted and copies it
to `[repo]/test-results/performance-summary/results_[name].json`, where
`compare-performance.ps1` reads it. Every language's `run-performance-tests.ps1`
uses this rather than parsing an example's console output.

For a more in depth description of this, see [Performance Tests](/DESIGN.md#performance-tests)

## Compare Performance
**Script: `compare-performance.ps1`**

Compares the performance test results with previous runs, and outputs a graph to the summary.

For a more in depth description of this, see [Performance Tests](/DESIGN.md#performance-tests)

## Configure Git
**Script: `configure-git.ps1`**

Configures the default Git behavior in the following ways:
- Sets the auth token to use for any Git operations,
- Sets the user and email for any commits,
- Disables pulling of Git LFS files by default.

## Download Data File
**Script: `download-data-file.ps1`**

Attempts to download a data file from the 51Degrees Distributor service. The type of file and license must be provided.

## Fetch CSV Assets
**Script: `fetch-csv-assets.ps1`**

Uses the `download-data-file` script to download a 51Degrees CSV data file.

## Fetch Hash Assets
**Script: `fetch-hash-assets.ps1`**

Uses the `download-data-file` script to download a 51Degrees Hash V4.1 data file.

## Generate Accessors
**Script: `generate-accessors.ps1`**

Generates the strongly types accessors from the 51Degrees data file.

This will also copy the generated classes to the directory specified.

## Get PRs
**Script: `get-pull-requests.ps1`**

Gets the open PRs for the repo, and sets the ids of valid PRs as an array under a variable name provided.

A PR is considered valid if it was created by one of the following roles:
- `OWNER`
- `COLLABORATOR`
- `MEMBER`
or was approved by a member of the 51Degrees Github organisation.

If one or more reviewers have been assigned to the PR, then the PR will only
be included if all reviewers have approved.

## Get Next Package Version
**Script: `get-next-package-version.ps1`**

Runs GitVersion in the repo, and stores the result object under the variable name provided.

This will use the GitVersion config in the repo, or the path to a common config can be supplied.

## GUnzip File
**Script: `gunzip-file.ps1`**

Unzips a GZip file.

## Has Changed?
**Script: `has-changed.ps1`**

Checks if there are any changes in the repo. If there are then a non-zero exit code is returned, otherwise zero.

## Merge PR
**Script: `merge-pr.ps1`**

Completes the pull request with the id provided.

## Package Update Required?
**Script: `package-update-required.ps1`**

Takes the prospective version for the repo, and compares to the existing tags.

If the version does not already exist, then a non-zero exit code is returned, otherwise zero.

## PR to Main
**Script: `pull-request-to-main.ps1`**

Creates a pull request to the main branch of the repository.

## Push Changes
**Script: `push-changes.ps1`**

Push any committed changes in the repo to the branch that is currently checked out.

## Run Repo Script
**Script: `run-script.ps1`**

Runs a named script from within the `ci` directory of the repo supplied by name.
Any options are passed to this script as a hashtable. They are then parsed, checked against the parameters
required by the repo script, and used when calling the repo script.

The `RepoName`, `OrgName`, and `DryRun` parameters will always be available to the repo script, and do not need to be added to the options object.

For a more detailed description of options usage, see [Options](/DESIGN.md#build-options).

## Set Resource Keys
**Script: `set-resource-keys.ps1`**

Exports the 51Degrees resource key secrets as environment variables for the steps and tests that follow.

Takes the secrets available to the job as a hashtable (in the framework this is `$Options.Keys`) and exports every key whose name follows the resource-key convention (any name beginning with `_51DEGREES_RESOURCE_KEY`, for example `_51DEGREES_RESOURCE_KEY_FREE` and `_51DEGREES_RESOURCE_KEY_PAID`). Each is set in the process environment and, under GitHub Actions, appended to `$GITHUB_ENV`.

This is the single, central place that knows the resource-key convention. To make a new resource key available to every repository, add the secret at the organisation level using the `_51DEGREES_RESOURCE_KEY_*` convention; it is picked up automatically with no change to any repository's CI. Secret values are never written to the log.

## Update Sub-Modules
**Script: `update-sub-modules.ps1`**

Updates any submodule references in the repo to point to the latest commit in the main branch.

## Update Tag
**Script: `update-tag.ps1`**

Tags the repository with the version supplied, and pushed to GitHub.

A GitHub release is then created from the tag containing a description generated from the PRs linked to the tag.

## Version directives

`+semver: minor` and `+semver: major` in a commit message are **never** taken
automatically. A directive makes the next release a new minor or major version
of every package the repository publishes, and a published version number can
never be reclaimed: NuGet cannot delete, crates.io cannot unpublish, and PyPI
burns the number even when a release is deleted.

`steps/version-directive.ps1` refuses such a pull request unless someone other
than the author, with write access, has applied the label
`version bump approved`. `steps/get-pull-requests.ps1` calls it, so the nightly
will not merge one on its own.

This is enforced here rather than through branch protection, because an
automation with bypass walks straight through a required review. On
18 September 2026 one directive, in the body of one commit, took sixteen NuGet
packages, three npm packages, five PyPI projects and three crates to 4.6
overnight, merged and published with nobody reading it.

## Version bumps at publish

`steps/check-version-bump.ps1` refuses a publish whose version moves the major
or minor place, comparing it with the highest version the repository has
already tagged. `nightly-publish.yml` runs it in the Configure job, straight
after the version is worked out and before anything is built or pushed.

It is at the publish rather than the merge on purpose. A version can arrive by
a `+semver` directive, a tag pushed by hand, a version committed in a file, or
one typed into a dispatch. Gating any one of those leaves the others open. The
publish is where they all meet.

To release a bump deliberately, run the workflow with `allow-version-bump`
set. That is a decision with somebody's name on it rather than something a
commit message does quietly.
