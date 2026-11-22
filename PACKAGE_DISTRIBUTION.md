# Package distribution

The kinds of place a 51Degrees package is listed publicly, and what each
package release must update. Account details for these sites are kept by
51Degrees and are not in this repository.

## The rule

**Every package release updates every place the package is listed.** Each
kind of place below either updates by itself from the release, or needs a
named step. Each repository keeps the list of its own listings in its own
files. When a package is listed on a new kind of site, the kind is added to
this document.

A release publishes only the packages that changed, and
[steps/check-release-interval.ps1](steps/check-release-interval.ps1)
refuses a release less than a week after the last, because several
registries hide pages that release too often or are too new (see
[Release frequency](#release-frequency)).

## Where a package is listed

- **The package registry**, where the package's ecosystem has one. A
  package with no registry is distributed as files on its GitHub release.
- **Sites that copy a registry**, such as documentation hosts, package
  indexes and content delivery networks.
- **The GitHub release**, made with the version tag.
- **A SourceForge project**, one for each repository, which describes the
  package and links to GitHub for the code, issues and documentation. Its
  Files area copies the repository's GitHub releases through SourceForge's
  GitHub Integration, and no code or tickets are imported.
- **A Context7 library**, one for each repository.
- **Lists kept by other projects**, such as a host application's list of
  extensions.

## What a release updates

| Place | Updated by | Step needed |
| --- | --- | --- |
| The registry page | The repository's `ci/publish-package.ps1`, run by [nightly-publish.package.ps1](nightly-publish.package.ps1) | None. The description, keywords and README come from the package, so change them in the same pull request as the code |
| Sites that copy a registry | Each site's own copy of the registry | None |
| The GitHub release | [steps/update-tag.ps1](steps/update-tag.ps1), which pushes the tag and creates the release | None |
| SourceForge Files | SourceForge's GitHub Integration, which copies each new GitHub release | None once the integration is on for the project. SourceForge does not see files added after a release is published, so the files must be attached in the call that creates the release |
| Context7 | The repository's `main` branch, read when the library is refreshed | A maintainer refreshes the library on its Context7 page after the release reaches `main`, unless Context7 has already done so |
| The SourceForge project text (name, summary, description, features and tags) | 51Degrees staff, by hand | Only when the listing text changes |
| A list kept by another project | A pull request to the list's source | Only when the repository, the supported versions or the description change |

## Release frequency

Several registries hide a page from search for reasons a release controls.

- **NuGet** writes `<meta name="robots" content="noindex">` on a package page
  while the oldest of the package's 20 newest versions is under 90 days old,
  so a package should stay below 20 versions in any 90 days.
- **PyPI** writes `<meta name="googlebot" content="noindex">` for 30 days
  after a project is created, so a new package name costs a month out of
  search.
- **Packagist** writes `noindex, nofollow` on a package it judges suspect,
  meaning one with few installs and many page views, unless the vendor is
  verified.

## Context7

Each repository's `context7.json`, at its root, sets the library's title
and description, the folders Context7 leaves out, and the rules Context7
shows at the top of every answer. Context7 reads the file from `main`. The rules make the EUPL 1.2 and
its Article 5 notices clear. The file follows
https://context7.com/schema/context7.json and changes in the same pull
request as the code it describes.

## Where an automated step would go

[nightly-publish.package.ps1](nightly-publish.package.ps1) runs the
repository's `ci/publish-package.ps1`, then
[steps/update-tag.ps1](steps/update-tag.ps1) and
[steps/upload-release-assets.ps1](steps/upload-release-assets.ps1). A step
that updates a listing after a release belongs after "Update Tag" in that
script, so that it runs only once a version has been published and its
GitHub release exists. A repository that publishes from a workflow of its
own adds the step to that workflow.
