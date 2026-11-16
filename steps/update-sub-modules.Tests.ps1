# Tests for steps/update-sub-modules.ps1.
#
# Each test makes real repositories in a temporary folder, clones the one that
# holds the submodules the way steps/clone-repo.ps1 does, which gives each
# submodule one commit of history, and runs the step on that clone. Nothing
# reaches GitHub.

BeforeAll {
    $script:Step = Join-Path $PSScriptRoot 'update-sub-modules.ps1'

    # Git clones a submodule from a folder only when it is told it may, and a
    # commit needs an author. Both are set for these tests alone.
    $script:Environment = @{
        GIT_CONFIG_COUNT    = '1'
        GIT_CONFIG_KEY_0    = 'protocol.file.allow'
        GIT_CONFIG_VALUE_0  = 'always'
        GIT_AUTHOR_NAME     = 'Test'
        GIT_AUTHOR_EMAIL    = 'test@example.com'
        GIT_COMMITTER_NAME  = 'Test'
        GIT_COMMITTER_EMAIL = 'test@example.com'
    }
    $script:Saved = @{}
    foreach ($name in $script:Environment.Keys) {
        $script:Saved[$name] = [Environment]::GetEnvironmentVariable($name)
        Set-Item -Path "Env:$name" -Value $script:Environment[$name]
    }

    # Runs git, returns what it printed, and stops the test when git fails.
    function Invoke-Git {
        $output = git @args
        if ($LASTEXITCODE -ne 0) { throw "git $args failed with $LASTEXITCODE" }
        return $output
    }

    # The file address of a folder, which starts with a drive letter on
    # Windows and with a slash elsewhere.
    function Get-Url ([string]$Folder) {
        $path = $Folder -replace '\\', '/'
        if (-not $path.StartsWith('/')) { $path = "/$path" }
        return "file://$path"
    }

    # Adds a commit to the branch checked out and returns its id.
    function Add-Commit ([string]$Folder, [string]$Name) {
        Set-Content -Path (Join-Path $Folder "$Name.txt") -Value $Name
        Invoke-Git -C $Folder add . | Out-Null
        Invoke-Git -C $Folder commit --quiet -m $Name | Out-Null
        return Invoke-Git -C $Folder rev-parse HEAD
    }

    # A repository a submodule can point at, with one commit on main. It
    # gives any commit asked for by id, as GitHub gives any commit a branch
    # holds, because a clone with one commit of history asks for the recorded
    # commit by its id.
    function New-Library ([string]$Name) {
        $folder = Join-Path $script:Root $Name
        Invoke-Git init --quiet --initial-branch main $folder | Out-Null
        Invoke-Git -C $folder config uploadpack.allowAnySHA1InWant true | Out-Null
        Add-Commit $folder 'first' | Out-Null
        return $folder
    }

    # Adds a commit on a branch named rc that main does not hold, leaves main
    # checked out, and returns the commit's id.
    function Add-CommitAhead ([string]$Folder) {
        Invoke-Git -C $Folder switch --quiet --create rc | Out-Null
        $ahead = Add-Commit $Folder 'ahead'
        Invoke-Git -C $Folder switch --quiet main | Out-Null
        return $ahead
    }

    # Makes a repository that records each library as a submodule at the
    # commit given, and clones it into the working folder as `demo`.
    function New-Clone ([hashtable]$Recorded) {
        $super = Join-Path $script:Root 'super'
        Invoke-Git init --quiet --initial-branch main $super | Out-Null
        foreach ($name in $Recorded.Keys) {
            $url = Get-Url (Join-Path $script:Root $name)
            Invoke-Git -C $super submodule --quiet add $url $name | Out-Null
            Invoke-Git -C (Join-Path $super $name) checkout --quiet $Recorded[$name] |
                Out-Null
            Invoke-Git -C $super add $name | Out-Null
        }
        Invoke-Git -C $super commit --quiet -m 'Add submodules' | Out-Null
        Invoke-Git clone --quiet --recurse-submodules --shallow-submodules `
            --branch main (Get-Url $super) (Join-Path $script:Work 'demo') | Out-Null
    }

    # Runs the step from the working folder, as the nightly does, and returns
    # what it printed.
    function Invoke-Step {
        Push-Location $script:Work
        try {
            return (& $script:Step -RepoName demo | Out-String)
        } finally {
            Pop-Location
        }
    }

    # The commit a submodule of the clone is at.
    function Get-Head ([string]$Name) {
        return Invoke-Git -C (Join-Path $script:Work "demo/$Name") rev-parse HEAD
    }

    # What the clone would commit after the step.
    function Get-Changes {
        return Invoke-Git -C (Join-Path $script:Work 'demo') status --porcelain
    }
}

AfterAll {
    # A name that was not set before is removed, so that no later test sees it.
    foreach ($name in $script:Saved.Keys) {
        if ($null -eq $script:Saved[$name]) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        } else {
            Set-Item -Path "Env:$name" -Value $script:Saved[$name]
        }
    }
}

Describe 'update-sub-modules.ps1' {
    BeforeEach {
        $script:Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N').Substring(0, 8))
        $script:Work = Join-Path $script:Root 'work'
        New-Item -ItemType Directory -Path $script:Work -Force | Out-Null
    }

    It 'moves a submodule forward to the head of its branch' {
        $library = New-Library lib
        $first = Invoke-Git -C $library rev-parse HEAD
        $second = Add-Commit $library 'second'
        New-Clone @{ lib = $first }

        Invoke-Step | Out-Null

        Get-Head lib | Should -Be $second
        Get-Changes | Should -Match 'lib'
    }

    It 'leaves a submodule at a commit its branch does not hold yet, and says why' {
        # The repository records the head of a release branch of the library.
        # The library's main is behind that commit, so moving to main would
        # take the submodule backwards.
        $library = New-Library lib
        $ahead = Add-CommitAhead $library
        New-Clone @{ lib = $ahead }

        $output = Invoke-Step

        Get-Head lib | Should -Be $ahead
        Get-Changes | Should -BeNullOrEmpty
        $output | Should -Match "lib stays at $ahead"
    }

    It 'leaves a submodule whose commit its branch has moved on without' {
        $library = New-Library lib
        $ahead = Add-CommitAhead $library
        Add-Commit $library 'other' | Out-Null
        New-Clone @{ lib = $ahead }

        $output = Invoke-Step

        Get-Head lib | Should -Be $ahead
        Get-Changes | Should -BeNullOrEmpty
        $output | Should -Match "lib stays at $ahead"
    }

    It 'moves a submodule forward once its branch holds the commit' {
        $library = New-Library lib
        $ahead = Add-CommitAhead $library
        Invoke-Git -C $library merge --quiet --no-ff -m 'Release' rc | Out-Null
        $release = Invoke-Git -C $library rev-parse HEAD
        New-Clone @{ lib = $ahead }

        Invoke-Step | Out-Null

        Get-Head lib | Should -Be $release
        Get-Changes | Should -Match 'lib'
    }

    It 'judges each submodule by itself' {
        $behind = New-Library behind
        $first = Invoke-Git -C $behind rev-parse HEAD
        $second = Add-Commit $behind 'second'
        $library = New-Library lib
        $ahead = Add-CommitAhead $library
        New-Clone @{ behind = $first; lib = $ahead }

        $output = Invoke-Step

        Get-Head behind | Should -Be $second
        Get-Head lib | Should -Be $ahead
        $output | Should -Match "lib stays at $ahead"
        $output | Should -Not -Match 'behind stays'
        $changes = Get-Changes | Out-String
        $changes | Should -Match 'behind'
        $changes | Should -Not -Match 'lib'
    }

    It 'changes nothing when every submodule is at the head of its branch' {
        $library = New-Library lib
        $first = Invoke-Git -C $library rev-parse HEAD
        New-Clone @{ lib = $first }

        $output = Invoke-Step

        Get-Head lib | Should -Be $first
        Get-Changes | Should -BeNullOrEmpty
        $output | Should -Not -Match 'stays'
    }
}
