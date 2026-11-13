# Tests for steps/environment-variables.ps1, which checks
# environment-variables.json and writes environment-variables.md from it.
#
# Each rule test changes one thing in a copy of the real list and expects the
# script to refuse it, naming the problem, so a rule that stopped being
# checked fails here.

# Pages are compared with Contains rather than -BeLike, because a backtick is
# the escape character in a PowerShell wildcard and the page quotes names in
# backticks.

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot 'environment-variables.ps1'
    $script:RealList = Join-Path $PSScriptRoot '..' 'environment-variables.json'
    $script:RealPage = Join-Path $PSScriptRoot '..' 'environment-variables.md'

    # A fresh copy of the real list, as objects to change.
    function Get-List {
        return Get-Content -Raw -LiteralPath $script:RealList | ConvertFrom-Json
    }

    # Writes the list to the test drive and runs the script on it, writing
    # the page to the test drive too.
    function Invoke-Script ($List, [switch]$Check, [string]$Page) {
        $listPath = Join-Path $TestDrive 'environment-variables.json'
        if (-not $Page) { $Page = Join-Path $TestDrive 'environment-variables.md' }
        $List | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $listPath
        & $script:Script -ListPath $listPath -PagePath $Page -Check:$Check
    }

    function New-Old ([string]$Name, [string[]]$Languages) {
        return [pscustomobject]@{
            name = $Name; languages = $Languages; stopsBeingReadIn = ''
        }
    }
}

Describe 'The list in this repository' {
    It 'follows the rules, and environment-variables.md is the page it makes' {
        { & $script:Script -Check } | Should -Not -Throw
    }

    It 'holds at least one current name, one deprecated name and one other name' {
        $list = Get-List
        @($list.variables).Count | Should -BeGreaterThan 0
        @($list.variables | ForEach-Object { $_.deprecated }).Count |
            Should -BeGreaterThan 0
        @($list.otherNames).Count | Should -BeGreaterThan 0
    }
}

Describe 'The rules' {
    It 'accepts the real list' {
        { Invoke-Script (Get-List) } | Should -Not -Throw
    }

    It 'refuses a language with no name or no repository' {
        $list = Get-List
        $list.languages.go.repository = ''
        { Invoke-Script $list } |
            Should -Throw "*language 'go' needs a name and a repository*"
    }

    It 'refuses an empty current name' {
        $list = Get-List
        $list.variables[0].name = ''
        { Invoke-Script $list } | Should -Throw '*A current name is empty*'
    }

    It 'refuses an empty other name' {
        $list = Get-List
        $list.otherNames[0].name = ' '
        { Invoke-Script $list } | Should -Throw '*One of the other names is empty*'
    }

    It 'refuses an empty old name' {
        $list = Get-List
        $list.variables[0].deprecated = @(New-Old '' @('go'))
        { Invoke-Script $list } |
            Should -Throw "*An old name of '$($list.variables[0].name)' is empty*"
    }

    It 'refuses a current name that does not start _51DEGREES_' {
        $list = Get-List
        $list.variables[0].name = 'FIFTYONE_RESOURCE_KEY'
        { Invoke-Script $list } |
            Should -Throw "*current name 'FIFTYONE_RESOURCE_KEY' does not start _51DEGREES_*"
    }

    It 'refuses a current name that only differs from _51DEGREES_ in letter case' {
        $list = Get-List
        $list.variables[0].name = '_51degrees_RESOURCE_KEY'
        { Invoke-Script $list } |
            Should -Throw "*'_51degrees_RESOURCE_KEY' does not start _51DEGREES_*"
    }

    It 'refuses a current name that appears twice' {
        $list = Get-List
        $list.variables[1].name = $list.variables[0].name
        { Invoke-Script $list } |
            Should -Throw "*'$($list.variables[0].name)' appears twice*"
    }

    It 'refuses a name that is both a current name and another name' {
        $list = Get-List
        $list.otherNames[0].name = $list.variables[0].name
        { Invoke-Script $list } |
            Should -Throw "*'$($list.variables[0].name)' appears twice*"
    }

    It 'refuses another name that appears twice' {
        $list = Get-List
        $list.otherNames[1].name = $list.otherNames[0].name
        { Invoke-Script $list } |
            Should -Throw "*'$($list.otherNames[0].name)' appears twice*"
    }

    It 'refuses an old name listed twice under one current name' {
        $list = Get-List
        $list.variables[0].deprecated = @(
            (New-Old 'OLD_NAME' @('go')), (New-Old 'OLD_NAME' @('rust')))
        { Invoke-Script $list } |
            Should -Throw "*old name 'OLD_NAME' of '$($list.variables[0].name)' appears twice*"
    }

    It 'accepts old names that differ only in letter case, as Linux does' {
        $list = Get-List
        $list.variables[0].deprecated = @(
            (New-Old 'OLD_NAME' @('go')), (New-Old 'old_name' @('rust')))
        { Invoke-Script $list } | Should -Not -Throw
    }

    It 'refuses an old name that is also a current name' {
        $list = Get-List
        $list.variables[0].deprecated = @(
            New-Old $list.variables[1].name @('go'))
        { Invoke-Script $list } |
            Should -Throw "*old name '$($list.variables[1].name)' is also a current name*"
    }

    It 'refuses an old name that is also another name in the same language' {
        $list = Get-List
        $other = $list.otherNames[0]
        $list.variables[0].deprecated = @(
            New-Old $other.name @($other.languages[0]))
        { Invoke-Script $list } |
            Should -Throw "*old name '$($other.name)' is also one of the other names in '$($other.languages[0])'*"
    }

    It 'accepts an old name that is another name only in other languages' {
        $list = Get-List
        $list.otherNames[0].languages = @('rust')
        $list.variables[0].deprecated = @(New-Old $list.otherNames[0].name @('go'))
        { Invoke-Script $list } | Should -Not -Throw
    }

    It 'refuses a language the list does not name' {
        $list = Get-List
        $list.variables[0].languages = @('cobol')
        { Invoke-Script $list } |
            Should -Throw "*the language 'cobol', which is not in the list's languages*"
    }

    It 'refuses another name with a language the list does not name' {
        $list = Get-List
        $list.otherNames[0].languages = @('cobol')
        { Invoke-Script $list } |
            Should -Throw "*other name '$($list.otherNames[0].name)' names the language 'cobol'*"
    }

    It 'refuses an old name with no languages' {
        $list = Get-List
        $list.variables[0].deprecated = @(New-Old 'OLD_NAME' @())
        { Invoke-Script $list } |
            Should -Throw "*old name 'OLD_NAME' of '$($list.variables[0].name)' names no languages*"
    }

    It 'refuses a current name with no languages' {
        $list = Get-List
        $list.variables[0].languages = @()
        { Invoke-Script $list } |
            Should -Throw "*'$($list.variables[0].name)' names no languages*"
    }

    It 'refuses a current name that does not say what it holds' {
        $list = Get-List
        $list.variables[0].holds = ' '
        { Invoke-Script $list } |
            Should -Throw "*'$($list.variables[0].name)' does not say what it holds*"
    }

    It 'refuses readByPackages that is not true or false' {
        $list = Get-List
        $list.variables[0].readByPackages = 'yes'
        { Invoke-Script $list } |
            Should -Throw "*'$($list.variables[0].name)' needs readByPackages as true or false*"
    }

    It 'refuses a current name with no list of deprecated names' {
        $list = Get-List
        $list.variables[0].PSObject.Properties.Remove('deprecated')
        { Invoke-Script $list } |
            Should -Throw "*'$($list.variables[0].name)' needs a list of deprecated names*"
    }

    It 'refuses an old name whose release is not text' {
        $list = Get-List
        $old = New-Old 'OLD_NAME' @('go')
        $old.stopsBeingReadIn = $null
        $list.variables[0].deprecated = @($old)
        { Invoke-Script $list } |
            Should -Throw "*'OLD_NAME' of '$($list.variables[0].name)' needs stopsBeingReadIn as text*"
    }

    It 'refuses another name with nothing to say what sets it' {
        $list = Get-List
        $list.otherNames[0].setBy = ''
        { Invoke-Script $list } |
            Should -Throw "*other name '$($list.otherNames[0].name)' needs what it holds and what sets it*"
    }

    It 'writes no page when the list breaks a rule' {
        $list = Get-List
        $list.variables[0].name = 'NO_PREFIX'
        $page = Join-Path $TestDrive 'refused.md'
        { Invoke-Script $list -Page $page } | Should -Throw
        Test-Path -LiteralPath $page | Should -BeFalse
    }
}

Describe 'The page' {
    BeforeEach {
        $script:Page = Join-Path $TestDrive 'page.md'
        if (Test-Path -LiteralPath $script:Page) { Remove-Item -LiteralPath $script:Page }
    }

    It 'passes the check straight after the script writes it' {
        Invoke-Script (Get-List) -Page $script:Page
        { Invoke-Script (Get-List) -Page $script:Page -Check } | Should -Not -Throw
    }

    It 'fails the check when it has been edited by hand' {
        Invoke-Script (Get-List) -Page $script:Page
        Add-Content -LiteralPath $script:Page -Value 'An edit by hand.'
        { Invoke-Script (Get-List) -Page $script:Page -Check } |
            Should -Throw '*differs from the page*'
    }

    It 'fails the check when only the letter case of a name on the page differs' {
        $list = Get-List
        Invoke-Script $list -Page $script:Page
        $name = $list.variables[0].name
        $text = (Get-Content -Raw -LiteralPath $script:Page).Replace(
            '`' + $name + '`', '`' + $name.ToLowerInvariant() + '`')
        [System.IO.File]::WriteAllText($script:Page, $text)
        { Invoke-Script $list -Page $script:Page -Check } |
            Should -Throw '*differs from the page*'
    }

    It 'fails the check when the list has changed and the page has not' {
        Invoke-Script (Get-List) -Page $script:Page
        $list = Get-List
        $list.variables[0].holds = 'Something else.'
        { Invoke-Script $list -Page $script:Page -Check } |
            Should -Throw '*differs from the page*'
    }

    It 'fails the check when there is no page' {
        { Invoke-Script (Get-List) -Page $script:Page -Check } |
            Should -Throw '*differs from the page*'
    }

    It 'passes the check on a page with Windows line endings' {
        Invoke-Script (Get-List) -Page $script:Page
        $text = (Get-Content -Raw -LiteralPath $script:Page) -replace "`n", "`r`n"
        [System.IO.File]::WriteAllText($script:Page, $text)
        { Invoke-Script (Get-List) -Page $script:Page -Check } | Should -Not -Throw
    }

    It 'shows every current name, deprecated name and other name' {
        $list = Get-List
        Invoke-Script $list -Page $script:Page
        $text = Get-Content -Raw -LiteralPath $script:Page
        foreach ($variable in $list.variables) {
            $text.Contains('`' + $variable.name + '`') | Should -BeTrue
            foreach ($old in @($variable.deprecated)) {
                $text.Contains('`' + $old.name + '`') | Should -BeTrue
            }
        }
        foreach ($other in $list.otherNames) {
            $text.Contains('`' + $other.name + '`') | Should -BeTrue
        }
    }

    It 'shows the release a deprecated name stops being read in once it is decided' {
        $list = Get-List
        $list.variables[0].deprecated = @(New-Old 'OLD_NAME' @('go'))
        $list.variables[0].deprecated[0].stopsBeingReadIn = '4.5.999'
        Invoke-Script $list -Page $script:Page
        $text = Get-Content -Raw -LiteralPath $script:Page
        $text.Contains('`OLD_NAME` (Go, read until 4.5.999)') | Should -BeTrue
    }
}
