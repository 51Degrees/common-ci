<#
.SYNOPSIS
Checks environment-variables.json and writes environment-variables.md from it.

.DESCRIPTION
environment-variables.json, at the root of this repository, is the one list
of the environment variable names that 51Degrees packages, tests, examples
and CI scripts read, in every language. environment-variables.md is the page
people read, and this script makes it from the list, so the page is never
edited by hand.

The list is refused, and nothing is written, when it breaks one of these
rules.

- Every current name starts _51DEGREES_.
- No name appears twice among the current names and the other names, and no
  old name appears twice under one current name.
- No old name is also a current name.
- An old name that is also one of the other names is never both in the same
  language, so each name means one thing in each language.
- Every entry has its fields, and every language it names is in the list's
  languages.

.PARAMETER ListPath
The list to read. The default is environment-variables.json at the root of
this repository.

.PARAMETER PagePath
The page to write, or to compare with -Check. The default is
environment-variables.md at the root of this repository.

.PARAMETER Check
Write nothing, and fail when the page differs from the one the list makes.
#>
param(
    [string]$ListPath = (Join-Path $PSScriptRoot '..' 'environment-variables.json'),
    [string]$PagePath = (Join-Path $PSScriptRoot '..' 'environment-variables.md'),
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

$CurrentPrefix = '_51DEGREES_'

# Environment variable names are case sensitive on Linux and macOS, so names
# are compared with case, unlike a PowerShell hashtable or -contains.
function New-NameSet {
    $set = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal)
    # The comma stops PowerShell unrolling the empty set into nothing.
    return , $set
}

function Test-Text ($Value) {
    return $Value -is [string] -and $Value.Trim().Length -gt 0
}

# Returns a problem for each language that is missing, empty or unknown.
function Get-LanguageProblems ([string]$Where, $Entry, [string[]]$Known) {
    if (-not $Entry.PSObject.Properties['languages'] -or
        @($Entry.languages).Count -eq 0) {
        return "$Where names no languages."
    }
    foreach ($language in @($Entry.languages)) {
        if ($Known -cnotcontains $language) {
            "$Where names the language '$language', which is not in the list's languages."
        }
    }
}

# Returns every way the list breaks the rules, or nothing.
function Get-ListProblems ($List) {
    $known = @($List.languages.PSObject.Properties.Name)
    foreach ($id in $known) {
        $language = $List.languages.$id
        if (-not (Test-Text $language.name) -or
            -not (Test-Text $language.repository)) {
            "The language '$id' needs a name and a repository."
        }
    }

    $seen = New-NameSet
    $current = New-NameSet
    $otherLanguages = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal)
    foreach ($variable in @($List.variables)) {
        $name = $variable.name
        if (-not (Test-Text $name)) {
            'A current name is empty.'
            continue
        }
        if (-not $name.StartsWith($CurrentPrefix, [StringComparison]::Ordinal)) {
            "The current name '$name' does not start $CurrentPrefix."
        }
        if (-not $seen.Add($name)) {
            "The name '$name' appears twice."
        }
        [void]$current.Add($name)
        if (-not (Test-Text $variable.holds)) {
            "The current name '$name' does not say what it holds."
        }
        if ($variable.readByPackages -isnot [bool]) {
            "The current name '$name' needs readByPackages as true or false."
        }
        Get-LanguageProblems "The current name '$name'" $variable $known
    }
    foreach ($other in @($List.otherNames)) {
        $name = $other.name
        if (-not (Test-Text $name)) {
            'One of the other names is empty.'
            continue
        }
        if (-not $seen.Add($name)) {
            "The name '$name' appears twice."
        }
        $otherLanguages[$name] = @($other.languages)
        if (-not (Test-Text $other.holds) -or -not (Test-Text $other.setBy)) {
            "The other name '$name' needs what it holds and what sets it."
        }
        Get-LanguageProblems "The other name '$name'" $other $known
    }

    foreach ($variable in @($List.variables)) {
        if (-not $variable.PSObject.Properties['deprecated']) {
            "The current name '$($variable.name)' needs a list of deprecated names, empty when it has none."
            continue
        }
        $oldSeen = New-NameSet
        foreach ($old in @($variable.deprecated)) {
            $name = $old.name
            $where = "The old name '$name' of '$($variable.name)'"
            if (-not (Test-Text $name)) {
                "An old name of '$($variable.name)' is empty."
                continue
            }
            if (-not $oldSeen.Add($name)) {
                "$where appears twice."
            }
            if ($current.Contains($name)) {
                "The old name '$name' is also a current name."
            }
            if ($otherLanguages.ContainsKey($name)) {
                foreach ($language in @($old.languages)) {
                    if ($otherLanguages[$name] -ccontains $language) {
                        "The old name '$name' is also one of the other names in '$language'."
                    }
                }
            }
            if ($old.stopsBeingReadIn -isnot [string]) {
                "$where needs stopsBeingReadIn as text, empty until a release is decided."
            }
            Get-LanguageProblems $where $old $known
        }
    }
}

function Format-Cell ([string]$Text) {
    return $Text.Replace('|', '\|')
}

function Format-Languages ($List, $Languages) {
    return (@($Languages) | ForEach-Object { $List.languages.$_.name }) -join ', '
}

# Returns the page as text with LF line endings.
function ConvertTo-Page ($List) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $add = { param($line) $lines.Add($line) }

    & $add '# Environment variable names'
    & $add ''
    & $add 'This page is made from [`environment-variables.json`](environment-variables.json) by [`steps/environment-variables.ps1`](steps/environment-variables.ps1). Change the JSON file and run the script, never this page. The JSON file decides, and a test fails when this page differs from it.'
    & $add ''
    & $add 'These are the environment variable names that 51Degrees packages, tests, examples and CI scripts read, in every language. Each is a public name. A patch release never removes or renames one. When a name changes, the old name is still read for at least one release, only when the new name is unset or empty, with a message naming the new one.'
    & $add ''
    & $add 'Names that the operating system, GitHub Actions or a build tool defines, such as `CI`, `PATH`, `HOME` and the `GITHUB_`, `RUNNER_` and `CARGO_` names, are not 51Degrees names and are not listed.'
    & $add ''
    & $add '## Current names'
    & $add ''
    & $add 'Every current name starts `_51DEGREES_`. "Packages" means a published package reads the name. "Tests, examples and CI" means only those do.'
    & $add ''
    & $add '| Name | What it holds | Read by | Languages | Deprecated names |'
    & $add '| --- | --- | --- | --- | --- |'
    $deprecatedNames = New-NameSet
    $decidedNames = New-NameSet
    foreach ($variable in @($List.variables)) {
        $readBy = if ($variable.readByPackages) { 'Packages' } else { 'Tests, examples and CI' }
        $olds = foreach ($old in @($variable.deprecated)) {
            [void]$deprecatedNames.Add($old.name)
            $text = '`' + $old.name + '` (' + (Format-Languages $List $old.languages)
            if ($old.stopsBeingReadIn) {
                [void]$decidedNames.Add($old.name)
                $text += ', read until ' + $old.stopsBeingReadIn
            }
            $text + ')'
        }
        & $add ('| `' + $variable.name + '` | ' + (Format-Cell $variable.holds) +
            ' | ' + $readBy + ' | ' + (Format-Languages $List $variable.languages) +
            ' | ' + (Format-Cell ((@($olds)) -join ', ')) + ' |')
    }
    & $add ''
    & $add '## Deprecated names'
    & $add ''
    & $add 'Each deprecated name is shown with the languages that read it in place of the current name. A release is shown where it has been decided which release stops reading the name.'
    & $add ''
    if ($decidedNames.Count -eq 0) {
        & $add "The list holds $($deprecatedNames.Count) deprecated names, and no release has been decided yet for any of them to stop being read."
    }
    else {
        & $add "The list holds $($deprecatedNames.Count) deprecated names, and a release has been decided for $($decidedNames.Count) of them."
    }
    & $add ''
    & $add '## Other names'
    & $add ''
    & $add 'These names do not start `_51DEGREES_`, and 51Degrees files read them. Each is a public name all the same.'
    & $add ''
    & $add '| Name | What it holds | Set by | Languages |'
    & $add '| --- | --- | --- | --- |'
    foreach ($other in @($List.otherNames)) {
        & $add ('| `' + $other.name + '` | ' + (Format-Cell $other.holds) + ' | ' +
            (Format-Cell $other.setBy) + ' | ' + (Format-Languages $List $other.languages) + ' |')
    }
    & $add ''
    & $add '## Languages'
    & $add ''
    & $add '| Language | Repository |'
    & $add '| --- | --- |'
    foreach ($id in $List.languages.PSObject.Properties.Name) {
        $language = $List.languages.$id
        & $add ('| ' + $language.name + ' | [' + $language.repository + '](https://github.com/' + $language.repository + ') |')
    }
    & $add ''
    & $add '## Changing the list'
    & $add ''
    & $add '1. Change `environment-variables.json`.'
    & $add '2. Run `pwsh steps/environment-variables.ps1`, which checks the list and writes this page.'
    & $add '3. Commit both files together.'
    & $add ''
    & $add 'The tests in `steps/environment-variables.Tests.ps1` fail when the list breaks a rule or this page differs from it.'
    return ($lines -join "`n") + "`n"
}

$list = Get-Content -Raw -LiteralPath $ListPath | ConvertFrom-Json
$problems = @(Get-ListProblems $list)
if ($problems.Count -gt 0) {
    throw ("$ListPath breaks the list's rules.`n" + ($problems -join "`n"))
}
$page = ConvertTo-Page $list

if ($Check) {
    $written = ''
    if (Test-Path -LiteralPath $PagePath) {
        $written = (Get-Content -Raw -LiteralPath $PagePath) -replace "`r`n", "`n"
    }
    if ($written -ne $page) {
        throw ("$PagePath differs from the page $ListPath makes. " +
            'Run steps/environment-variables.ps1 and commit the page it writes.')
    }
    Write-Host "$PagePath matches $ListPath."
}
else {
    [System.IO.File]::WriteAllText($PagePath, $page,
        [System.Text.UTF8Encoding]::new($false))
    Write-Host "Wrote $PagePath from $ListPath."
}
