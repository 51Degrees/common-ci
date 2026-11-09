# Dot-sourced by the scripts that read a repository's releases from its tags,
# so that they all agree on which tags are releases.
#
# A release tag is a version, after a package's prefix and a '/' where the
# repository tags each package on its own, and after a 'v' where it wants
# one, as Go does:
#   4.5.103   v4.5.29   pipeline/4.5.129   pipeline/v4.5.171
# The version is major.minor.patch. A fourth number, as in 4.4.3.0, or build
# metadata, as in 4.3.5+2, may follow and is ignored, as Semantic Versioning
# ignores build metadata. A pre-release, such as 4.5.8-49 or v4.5.0-alpha.1,
# is not a release, and nor is any other tag.
$VersionTagPattern = '^(?:(?<prefix>.+)/)?v?(?<version>[0-9]+\.[0-9]+\.[0-9]+)' +
    '(?:\.[0-9]+)?(?:\+[0-9A-Za-z.-]+)?$'

# The parts of a version such as 4.5.38, or $null for anything else.
function ConvertTo-VersionParts([string]$Text) {
    $match = [regex]::Match($Text, '^(\d+)\.(\d+)\.(\d+)$')
    if ($match.Success -eq $false) {
        return $null
    }
    return [version]::new([int]$match.Groups[1].Value,
        [int]$match.Groups[2].Value, [int]$match.Groups[3].Value)
}

# The version a release tag names, or $null for a tag that is not a release
# or is not one of those asked for. With -Prefix only the package's own tags,
# '<Prefix>/<version>', count. Otherwise, with -AnyPrefix every release tag
# counts, whatever its package, and without it only tags with no prefix.
function ConvertFrom-VersionTag([string]$Tag, [string]$Prefix,
        [switch]$AnyPrefix) {
    $match = [regex]::Match($Tag, $VersionTagPattern)
    if ($match.Success -eq $false) {
        return $null
    }
    $tagPrefix = $match.Groups['prefix']
    if ($Prefix) {
        if ($tagPrefix.Success -eq $false -or $tagPrefix.Value -cne $Prefix) {
            return $null
        }
    } elseif ($tagPrefix.Success -eq $true -and $AnyPrefix -eq $false) {
        return $null
    }
    return ConvertTo-VersionParts $match.Groups['version'].Value
}

# The release tags of a checkout, as Tag and Version, highest version last.
# -Prefix and -AnyPrefix choose the tags as ConvertFrom-VersionTag does.
# -AtHead keeps the tags on HEAD and -Merged those on HEAD or before it. Of
# two tags of one version the one with no 'v' comes last.
function Get-VersionTags([string]$RepoPath, [string]$Prefix,
        [switch]$AnyPrefix, [switch]$AtHead, [switch]$Merged) {
    # Tags are found by prefix, not with a 'name/*' pattern, because PowerShell
    # on Linux and macOS expands a '*' in an argument to a native command into
    # matching files, and would give git file names.
    $arguments = @('-C', $RepoPath, 'for-each-ref',
        '--format=%(refname:strip=2)')
    if ($AtHead -eq $true) {
        $arguments += @('--points-at', 'HEAD')
    }
    if ($Merged -eq $true) {
        $arguments += '--merged=HEAD'
    }
    $arguments += $Prefix ? "refs/tags/$Prefix/" : 'refs/tags/'
    $tags = foreach ($tag in (& git @arguments)) {
        $version = ConvertFrom-VersionTag $tag -Prefix $Prefix `
            -AnyPrefix:$AnyPrefix
        if ($null -ne $version) {
            [pscustomobject]@{ Tag = $tag; Version = $version }
        }
    }
    return @($tags | Sort-Object Version,
        @{ Expression = { $_.Tag -notmatch '(^|/)v[0-9]' } }, Tag)
}
