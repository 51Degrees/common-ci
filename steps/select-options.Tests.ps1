# Tests for steps/select-options.ps1.
#
# Each test builds a throwaway repository whose origin/rc is its first commit,
# gives it a ci/select-options.ps1, commits the change under test and runs the
# step against it. The repository's script records the files it was given in
# changed.txt, beside itself, so a test can see what it was asked.

BeforeAll {
    $script:Step = Join-Path $PSScriptRoot 'select-options.ps1'
    $script:Options = '[{"Name":"Linux","Image":"ubuntu-latest"},' +
        '{"Name":"Mac","Image":"macos-latest"}]'

    # Writes each file with new text and commits them all.
    function Add-Commit ([string]$Path, [string[]]$Files, [string]$Message) {
        foreach ($file in $Files) {
            $full = Join-Path $Path $file
            New-Item -ItemType Directory -Force (Split-Path $full) | Out-Null
            Set-Content -Path $full -Value ([Guid]::NewGuid().ToString())
        }
        git -C $Path add --all
        git -C $Path -c user.name=test -c user.email=test@example.com `
            commit --quiet -m $Message
    }

    # A repository with the given ci/select-options.ps1 and base files, with
    # origin/rc at that commit, then one commit of the changed files. With
    # Comments, the script also takes CommentOnlyFiles and records them in
    # comments.txt.
    function New-Repo ([string]$Select, [string[]]$Changed,
        [string[]]$Base = @('engine.c'), [switch]$Comments) {
        $path = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        git init --quiet $path
        New-Item -ItemType Directory (Join-Path $path 'ci') | Out-Null
        $header = $Comments ?
            ("param([object[]]`$Options, [string[]]`$ChangedFiles, " +
                "[string[]]`$CommentOnlyFiles)`n" +
                "Set-Content (Join-Path `$PSScriptRoot 'comments.txt') " +
                "`$CommentOnlyFiles`n") :
            "param([object[]]`$Options, [string[]]`$ChangedFiles)`n"
        Set-Content -Path (Join-Path $path 'ci/select-options.ps1') -Value (
            $header +
            "Set-Content (Join-Path `$PSScriptRoot 'changed.txt') `$ChangedFiles`n" +
            $Select)
        Add-Commit $path $Base 'Base'
        git -C $path update-ref refs/remotes/origin/rc HEAD
        if ($Changed) {
            Add-Commit $path $Changed 'Change'
        }
        return $path
    }

    # Runs the step and returns the JSON it chose.
    function Invoke-Select ([string]$Repo) {
        & $script:Step -RepoName $Repo -Branch rc -Options $script:Options `
            -SetVariable Selected | Out-Null
        return $Selected
    }

    # The files the repository's script was given, or null if it never ran.
    function Get-Given ([string]$Repo) {
        $file = Join-Path $Repo 'ci/changed.txt'
        if (Test-Path $file) { return @(Get-Content $file) }
        return $null
    }

    $script:KeepLinux = '$Options | Where-Object Name -eq Linux'
}

Describe 'select-options.ps1' {

    AfterEach {
        if ($script:Repo -and (Test-Path $script:Repo)) {
            Remove-Item -Recurse -Force $script:Repo
        }
        $script:Repo = $null
    }

    It 'builds nothing, without asking the repository, for documentation alone' {
        $script:Repo = New-Repo $script:KeepLinux @('README.md', 'docs/Doxyfile',
            'src/docs/guide.txt')
        Invoke-Select $script:Repo | Should -Be '[]'
        Get-Given $script:Repo | Should -BeNullOrEmpty
    }

    It 'treats a Markdown file of any case as documentation' {
        $script:Repo = New-Repo $script:KeepLinux @('CHANGES.MD')
        Invoke-Select $script:Repo | Should -Be '[]'
    }

    It 'gives the repository the changed files that are not documentation' {
        $script:Repo = New-Repo $script:KeepLinux @('README.md', 'src/engine.c')
        $selected = Invoke-Select $script:Repo | ConvertFrom-Json
        @($selected).Name | Should -Be @('Linux')
        Get-Given $script:Repo | Should -Be @('src/engine.c')
    }

    It 'asks the repository about a workflow change' {
        $script:Repo = New-Repo $script:KeepLinux @('.github/workflows/build.yml')
        @(Invoke-Select $script:Repo | ConvertFrom-Json).Name |
            Should -Be @('Linux')
        Get-Given $script:Repo | Should -Be @('.github/workflows/build.yml')
    }

    It 'gives the repository both sides of a move' {
        $script:Repo = New-Repo $script:KeepLinux @() -Base @('src/dd/a.c')
        git -C $script:Repo mv src/dd/a.c src/ipi/a.c
        git -C $script:Repo -c user.name=test -c user.email=test@example.com `
            commit --quiet -m 'Move'
        Invoke-Select $script:Repo | Out-Null
        Get-Given $script:Repo | Sort-Object | Should -Be @('src/dd/a.c', 'src/ipi/a.c')
    }

    It 'tells a repository that asks which files changed only in comments' {
        $script:Repo = New-Repo $script:KeepLinux @() -Comments
        $commit = { param($Message)
            git -C $script:Repo add --all
            git -C $script:Repo -c user.name=test -c user.email=test@example.com `
                commit --quiet -m $Message }
        New-Item -ItemType Directory (Join-Path $script:Repo 'src') | Out-Null
        Set-Content (Join-Path $script:Repo 'src/a.c') '// A comment'
        Set-Content (Join-Path $script:Repo 'src/b.c') 'int b = 1;'
        & $commit 'Base'
        git -C $script:Repo update-ref refs/remotes/origin/rc HEAD
        Set-Content (Join-Path $script:Repo 'src/a.c') '// Another comment'
        Set-Content (Join-Path $script:Repo 'src/b.c') 'int b = 2;'
        & $commit 'Comment and code'
        Invoke-Select $script:Repo | Out-Null
        Get-Given $script:Repo | Should -Be @('src/a.c', 'src/b.c')
        @(Get-Content (Join-Path $script:Repo 'ci/comments.txt')) |
            Should -Be @('src/a.c')
    }

    It 'keeps the changes the repository makes to an entry' {
        $script:Repo = New-Repo ('$Options | ForEach-Object { ' +
            '$_.Depth = "standard"; $_ }') @('src/engine.c')
        $selected = @(Invoke-Select $script:Repo | ConvertFrom-Json)
        $selected.Name | Should -Be @('Linux', 'Mac')
        $selected.Depth | Should -Be @('standard', 'standard')
    }

    It 'writes a single entry as an array' {
        $script:Repo = New-Repo $script:KeepLinux @('src/engine.c')
        Invoke-Select $script:Repo | Should -BeLike '`[{*}`]'
    }

    It 'builds nothing when the repository chooses nothing' {
        $script:Repo = New-Repo '' @('src/engine.c')
        Invoke-Select $script:Repo | Should -Be '[]'
    }

    It 'fails when the repository writes something that is not an entry' {
        $script:Repo = New-Repo ("Write-Output 'Keeping Linux'`n" +
            $script:KeepLinux) @('src/engine.c')
        { Invoke-Select $script:Repo } | Should -Throw '*Keeping Linux*'
    }

    It 'fails when the repository script exits with an error' {
        $script:Repo = New-Repo ($script:KeepLinux + "`nexit 3") @('src/engine.c')
        { Invoke-Select $script:Repo } | Should -Throw '*code 3*'
    }

    It 'fails when the repository returns an entry not in options.json' {
        $script:Repo = New-Repo '@{ Name = "Windows" }' @('src/engine.c')
        { Invoke-Select $script:Repo } | Should -Throw '*Windows*'
    }

    It 'fails when the repository returns an entry twice' {
        $script:Repo = New-Repo ($script:KeepLinux + "`n" + $script:KeepLinux) `
            @('src/engine.c')
        { Invoke-Select $script:Repo } | Should -Throw '*Linux*'
    }
}
