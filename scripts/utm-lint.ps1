<#
.SYNOPSIS
Lints 51degrees.com links against the UTM tagging convention.

.DESCRIPTION
Checks every tracked text file in a repository for links to
51degrees.com and configure.51degrees.com, and fails when a link does
not follow the convention documented in UTM-LINK-TAGGING.md
(internal-common-ci):

  ?utm_source=<source>&utm_medium=<medium>&utm_campaign=<repo>
  &utm_content=<file-slug>&utm_term=<location>

Rules enforced
- Exactly the five parameters above, in that order, each once.
- utm_source and utm_medium from their closed sets.
- utm_campaign equals the repository name (lowercase).
- utm_content and utm_term are lowercase slugs, term at most 60 chars.
- Links use https and the bare domain (no http, www, or
  protocol-relative forms).
- XML file types carry &amp; separators, not raw &.
- Hosts that are functional endpoints carry no utm_ parameters.
- The retired Logo.ashx URL does not appear.
- A 51degrees.com link with no UTM parameters at all is reported as
  untagged unless the file is excluded or allow-listed.

Per-repo configuration is read from .utm-lint.json at the repo root:
  { "exclude": ["<path regex>", ...],
    "allowUntagged": ["<path regex>", ...] }

.EXAMPLE
./utm-lint.ps1 -RepoRoot . -Campaign device-detection-node
#>
param(
    [string]$RepoRoot = ".",
    [string]$Campaign = "",
    [string]$ConfigPath = "",
    # The current documentation site version. Versioned documentation
    # links must use this version or none at all.
    [string]$CurrentDocVersion = "4.5"
)

$ErrorActionPreference = "Stop"

if ($Campaign -eq "") {
    if ($env:GITHUB_REPOSITORY) {
        $Campaign = ($env:GITHUB_REPOSITORY -split '/')[-1].ToLowerInvariant()
    }
    else {
        $Campaign = (Get-Item $RepoRoot).Name.ToLowerInvariant()
    }
}

if ($ConfigPath -eq "") { $ConfigPath = Join-Path $RepoRoot ".utm-lint.json" }
$configExclude = @()
$allowUntagged = @()
# Mode: "require" (default) means navigational 51degrees.com links must
# carry the full UTM scheme. "forbid" is the inverse, for repositories
# whose content is published ON 51degrees.com (for example the
# documentation site): their links to 51degrees.com are internal, so a
# UTM tag would overwrite campaign attribution and trip SEO duplicate-URL
# checks. In forbid mode any UTM tag on a 51degrees.com link is a
# violation and untagged links are correct.
$mode = "require"
if (Test-Path $ConfigPath) {
    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    if ($config.exclude) { $configExclude = @($config.exclude) }
    if ($config.allowUntagged) { $allowUntagged = @($config.allowUntagged) }
    if ($config.mode) { $mode = $config.mode }
}
if ($mode -notin @("require", "forbid")) {
    throw "Unknown mode '$mode' in $ConfigPath (expected 'require' or 'forbid')."
}

# Paths never scanned. Tests hold fixture URLs, generated and vendored
# content is owned by its generator, and CI configuration is not
# navigational content.
$defaultExclude = @(
    '(^|/)\.github(/|$)',
    '(^|/)\.claude(/|$)',
    '(^|/)tests?(/|$)',
    '\.tests?(/|$)',
    '\.test\.',
    '(^|/)__tests__(/|$)',
    '(^|/)node_modules(/|$)',
    '(^|/)wwwroot/lib(/|$)',
    '(^|/)types(/|$)',
    '\.designer\.cs$',
    '(^|/)(license|licence)[^/]*$',
    '(^|/)changelog[^/]*$',
    '(^|/)package-lock\.json$',
    '(^|/)composer\.lock$'
)
$excludePatterns = $defaultExclude + $configExclude

$binaryExtensions = @('.png','.jpg','.jpeg','.gif','.ico','.gz','.zip',
    '.hash','.ipi','.trie','.dat','.bin','.dll','.exe','.pdb','.snk',
    '.woff','.woff2','.ttf','.eot','.pdf','.svg','.csv')

# URLs that are data or machine-fetched assets rather than navigation.
$urlAllowlist = @('million\.zip', '/reflector/', 'datareceiver',
    '/starsign/', 'square%20logo\.png', 'portals/0/logos',
    'nuget-fiftyone')

# Functional hosts that must never carry campaign parameters.
$excludedHostPattern = '^(cloud|distributor|devices-v4|bulkdata|docs|legacy|ipcloud|crm[\w-]*|srv[\w-]*)\.51degrees\.com$'

$sources = 'github|code|nuget|npm|maven|packagist'
$mediums = 'readme|docs|example|comment|package'
$slug = '[a-z0-9][a-z0-9._-]*'
$campaignEscaped = [regex]::Escape($Campaign)
$queryPattern = "^([^&#]+&)?utm_source=($sources)&utm_medium=($mediums)" +
    "&utm_campaign=$campaignEscaped&utm_content=$slug&utm_term=$slug$"

$xmlExtensions = @('.xml','.csproj','.resx','.nuspec','.props',
    '.targets','.config','.aspx','.cshtml','.vbproj','.pubxml')

# Backslash terminates a URL because string escape sequences such as
# \n in C, Java, and JavaScript literals follow the URL directly.
$urlRegex = [regex]'(?i)(https?:)?//([a-z0-9.-]*51degrees\.com)([^\s"''<>\)\]\},`\\]*)'

$violations = [System.Collections.Generic.List[string]]::new()

$files = git -C $RepoRoot ls-files
if ($LASTEXITCODE -ne 0) { throw "git ls-files failed in $RepoRoot" }

foreach ($file in $files) {
    $unixPath = $file -replace '\\', '/'
    if ($excludePatterns | Where-Object { $unixPath -imatch $_ }) { continue }
    $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
    if ($binaryExtensions -contains $ext) { continue }
    $full = Join-Path $RepoRoot $file
    if (-not (Test-Path $full -PathType Leaf)) { continue }

    $lineNo = 0
    foreach ($line in [IO.File]::ReadLines($full)) {
        $lineNo++
        if ($line -inotmatch '51degrees\.com') { continue }
        foreach ($m in $urlRegex.Matches($line)) {
            $rawUrl = $m.Value.TrimEnd('.', ',', ';', ':', '!', '?', "'", '"')
            if ($urlAllowlist | Where-Object { $rawUrl -imatch $_ }) { continue }

            # A URL split across concatenated string literals continues
            # on the next line, so this fragment cannot be validated
            # here. Example: "https://...__hash" + ".html?utm_...".
            $rest = $line.Substring($m.Index + $m.Length)
            if ($rest -match '^["'']\s*[+.&]\s*$') { continue }

            $where = "${file}:${lineNo}"
            if ($rawUrl -imatch 'logo\.ashx') {
                $violations.Add("$where retired Logo.ashx URL: $rawUrl")
                continue
            }

            # Documentation links must use the current version or the
            # un-versioned URL, never an older version.
            $docVer = [regex]::Match($rawUrl, '/documentation/(\d+\.\d+)/')
            if ($docVer.Success -and
                $docVer.Groups[1].Value -ne $CurrentDocVersion) {
                $violations.Add("$where stale documentation version $($docVer.Groups[1].Value), use the un-versioned URL or ${CurrentDocVersion}: $rawUrl")
            }

            $host51 = $m.Groups[2].Value.ToLowerInvariant()
            $hasUtm = $rawUrl -imatch 'utm_'

            if ($host51 -imatch $excludedHostPattern) {
                if ($hasUtm) {
                    $violations.Add("$where utm parameters on functional host ${host51}: $rawUrl")
                }
                continue
            }
            if ($host51 -notmatch '^(www\.)?51degrees\.com$' -and
                $host51 -ne 'configure.51degrees.com') {
                continue
            }

            if ($m.Groups[1].Value -ieq 'http:') {
                $violations.Add("$where http link, use https: $rawUrl")
            }
            if ($m.Groups[1].Value -eq '') {
                $violations.Add("$where protocol-relative link, use https: $rawUrl")
            }
            if ($host51.StartsWith('www.')) {
                $violations.Add("$where www host, use the bare domain: $rawUrl")
            }

            # Forbid mode: this repository's content is served from
            # 51degrees.com, so links to it are internal and must not be
            # UTM-tagged. The https/www/version checks above still apply.
            if ($mode -eq "forbid") {
                if ($hasUtm) {
                    $violations.Add("$where UTM parameters on an internal 51degrees.com link (this repository publishes to 51degrees.com, so its links are internal and must not be tagged): $rawUrl")
                }
                continue
            }

            if (-not $hasUtm) {
                if (-not ($allowUntagged | Where-Object { $unixPath -imatch $_ })) {
                    $violations.Add("$where untagged navigational link: $rawUrl")
                }
                continue
            }

            if (($xmlExtensions -contains $ext) -and
                ($rawUrl -match '(?<!&amp;|amp)&utm_')) {
                $violations.Add("$where raw & separator in XML context, use &amp;: $rawUrl")
            }

            $query = ($rawUrl -split '\?', 2)[1]
            if ($null -eq $query) {
                $violations.Add("$where utm fragment without query string: $rawUrl")
                continue
            }
            $query = ($query -split '#', 2)[0] -replace '&amp;', '&'

            $utmCount = ([regex]::Matches($query, 'utm_')).Count
            if ($utmCount -ne 5) {
                $violations.Add("$where expected exactly 5 utm parameters, found ${utmCount}: $rawUrl")
                continue
            }
            if ($query -notmatch $queryPattern) {
                $violations.Add("$where parameters do not match the convention (order, closed sets, campaign '$Campaign', slug alphabet): $rawUrl")
                continue
            }
            $term = [regex]::Match($query, 'utm_term=([^&#]*)').Groups[1].Value
            if ($term.Length -gt 60) {
                $violations.Add("$where utm_term longer than 60 characters: $rawUrl")
            }
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "UTM link lint: $($violations.Count) violation(s) for campaign '$Campaign'" -ForegroundColor Red
    $violations | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "UTM link lint: clean for campaign '$Campaign'" -ForegroundColor Green
exit 0
