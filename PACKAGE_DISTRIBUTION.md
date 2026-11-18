# Package distribution

Where each 51Degrees package is listed publicly, and what each package
release must update. Account details for these sites are kept by 51Degrees
and are not in this repository.

## The rule

**Every package release updates every place the package is listed.** Each
place below either updates by itself from the release, or needs a named
step. When a package is listed somewhere new, the site is added to this
document.

A release publishes only the packages that changed, and
[steps/check-release-interval.ps1](steps/check-release-interval.ps1)
refuses a release less than a week after the last, because several
registries hide pages that release too often or are too new (see
[Release frequency](#release-frequency)).

## Where each package is listed

| Repository | Package registry | Other listings |
| --- | --- | --- |
| [51degrees-cxx](https://github.com/51Degrees/51degrees-cxx) | None. Files on each [GitHub release](https://github.com/51Degrees/51degrees-cxx/releases) | [SourceForge fiftyone-c](https://sourceforge.net/projects/fiftyone-c/), [Context7](https://context7.com/51degrees/51degrees-cxx) |
| [51degrees-dotnet](https://github.com/51Degrees/51degrees-dotnet) | [NuGet](https://www.nuget.org/profiles/51Degrees), the FiftyOne.* packages | SourceForge and Context7, both planned |
| [caching-dotnet](https://github.com/51Degrees/caching-dotnet) | [NuGet](https://www.nuget.org/packages/FiftyOne.Caching), FiftyOne.Caching | None |
| [51degrees-go](https://github.com/51Degrees/51degrees-go) | The Go module proxy and [pkg.go.dev](https://pkg.go.dev/github.com/51Degrees/51degrees-go/device-detection/v4), four modules | SourceForge and Context7, both planned |
| [51degrees-java](https://github.com/51Degrees/51degrees-java) | [Maven Central](https://central.sonatype.com/namespace/com.51degrees), the com.51degrees artifacts | [SourceForge fiftyone-java](https://sourceforge.net/projects/fiftyone-java/), Context7 planned |
| [51degrees-nginx](https://github.com/51Degrees/51degrees-nginx) | None. Pre-built modules on each [GitHub release](https://github.com/51Degrees/51degrees-nginx/releases) | SourceForge and Context7, both planned |
| [51degrees-node](https://github.com/51Degrees/51degrees-node) | [npm](https://www.npmjs.com/org/51degrees), the 51degrees organization | SourceForge and Context7, both planned |
| [ua-parser-js](https://github.com/51Degrees/ua-parser-js) | [npm](https://www.npmjs.com/package/@51degrees/ua-parser-js), @51degrees/ua-parser-js | None |
| [51degrees-php](https://github.com/51Degrees/51degrees-php) | [Packagist](https://packagist.org/packages/51degrees/), the 51degrees vendor, read from read-only mirror repositories | [SourceForge fiftyone](https://sourceforge.net/projects/fiftyone/), Context7 planned |
| [51degrees-python](https://github.com/51Degrees/51degrees-python) | [PyPI](https://pypi.org/user/51Degrees.mobi/), the fiftyone-* projects | SourceForge and Context7, both planned |
| [51degrees-rust](https://github.com/51Degrees/51degrees-rust) | [crates.io](https://crates.io/crates/fiftyone-device-detection) and [docs.rs](https://docs.rs/crate/fiftyone-device-detection/latest), the fiftyone-* crates | SourceForge and Context7, both planned |
| [51degrees-varnish](https://github.com/51Degrees/51degrees-varnish) | None. Built from source, with each [GitHub release](https://github.com/51Degrees/51degrees-varnish/releases) | The [Vinyl Cache VMOD list](https://vinyl-cache.org/vmods/), SourceForge and Context7, both planned |
| [pipeline-wordpress](https://github.com/51Degrees/pipeline-wordpress) | [WordPress.org](https://wordpress.org/plugins/51degrees-optimize-by-device-location/), the 51Degrees plugin | None |

The PHP mirrors Packagist reads are
[device-detection-php](https://github.com/51Degrees/device-detection-php),
[location-php](https://github.com/51Degrees/location-php),
[pipeline-php-cloudrequestengine](https://github.com/51Degrees/pipeline-php-cloudrequestengine),
[pipeline-php-core](https://github.com/51Degrees/pipeline-php-core),
[pipeline-php-did](https://github.com/51Degrees/pipeline-php-did) and
[pipeline-php-engines](https://github.com/51Degrees/pipeline-php-engines).

Each 51degrees-* repository gets one SourceForge project, which describes the
package and links to GitHub for the code, issues and documentation. Its
Files area copies the repository's GitHub releases through SourceForge's
GitHub Integration, and no code or tickets are imported.

## What a release updates

| Place | Updated by | Step needed |
| --- | --- | --- |
| The registry page (NuGet, npm, PyPI, Maven Central, crates.io, WordPress.org) | The repository's `ci/publish-package.ps1`, run by [nightly-publish.package.ps1](nightly-publish.package.ps1). 51degrees-dotnet runs that script from a job in its own publish workflow, and 51degrees-rust publishes from its own workflow | None. The description, keywords and README come from the package, so change them in the same pull request as the code |
| Packagist | The version tag, which 51degrees-php's mirror workflow copies to each mirror. Each mirror's webhook tells Packagist | None |
| pkg.go.dev | The module tags, such as `device-detection/v4.5.173`, pushed by 51degrees-go's `ci/publish-package.ps1`. pkg.go.dev shows a version once the module proxy has fetched it | None. A version can be requested sooner, as [pkg.go.dev's About page](https://pkg.go.dev/about#adding-a-package) describes |
| docs.rs | crates.io, which docs.rs builds from | None |
| The GitHub release | [steps/update-tag.ps1](steps/update-tag.ps1), which pushes the tag and creates the release | None |
| SourceForge Files | SourceForge's GitHub Integration, which copies each new GitHub release | None once the integration is on for the project. SourceForge does not see files added after a release is published, so the files must be attached in the call that creates the release |
| Libraries.io, deps.dev, Snyk, jsDelivr and unpkg | Each site's own copy of the registries | None |
| Context7 | The repository's `main` branch, read when the library is refreshed | A maintainer refreshes the library on its Context7 page after the release reaches `main`, unless Context7 has already done so |
| The SourceForge project text (name, summary, description, features and tags) | 51Degrees staff, by hand | Only when the listing text changes |
| The Vinyl Cache VMOD list | A pull request to the list's source, linked from the list | Only when the repository, the supported Varnish versions or the description change |
| WordPress.org "Tested up to" | The plugin's readme.txt | At each WordPress release, not each package release, because WordPress.org hides a plugin whose "Tested up to" falls behind |

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
- **WordPress.org** hides a plugin whose "Tested up to" falls behind the
  current WordPress release.

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
GitHub release exists. 51degrees-dotnet runs the same script from a job in
its own publish workflow, so a step added to the script runs there too.
51degrees-rust publishes and creates its releases in its own workflow, so a
step has to be added to that workflow as well.
