# Tests for steps/update-tag.ps1.
#
# Each test runs the step in a throwaway folder holding a git repository with a
# bare origin to push to, and a package folder like the one the publish
# downloads. gh is replaced by a function that records each call.

BeforeAll {
    $script:Step = Join-Path $PSScriptRoot 'update-tag.ps1'

    # Stands in for gh, recording each call as its list of arguments.
    function global:gh {
        $global:GhCalls += , @($args | Where-Object { $null -ne $_ })
    }

    # A folder holding 'repo', a git repository whose origin is a bare
    # repository, and 'package', holding the files named.
    function New-Workspace ([string[]]$Files, [string[]]$Folders) {
        $path = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $path | Out-Null
        git init --quiet --bare (Join-Path $path 'origin.git')
        git init --quiet (Join-Path $path 'repo')
        git -C (Join-Path $path 'repo') -c user.name=test `
            -c user.email=test@example.com commit --quiet --allow-empty -m first
        git -C (Join-Path $path 'repo') remote add origin (Join-Path $path 'origin.git')
        $package = New-Item -ItemType Directory -Path (Join-Path $path 'package')
        foreach ($file in $Files) {
            Set-Content -Path (Join-Path $package $file) -Value $file
        }
        foreach ($folder in $Folders) {
            $made = New-Item -ItemType Directory -Path (Join-Path $package $folder)
            Set-Content -Path (Join-Path $made 'inside.txt') -Value $folder
        }
        return $path
    }

    # Runs the step from the workspace, as the publish runs it from common-ci's
    # checkout, and returns the gh calls it made.
    function Invoke-Step ([string]$Workspace, [string]$Tag = '4.5.10',
        [bool]$DryRun = $false) {
        $global:GhCalls = @()
        Push-Location $Workspace
        try {
            & $script:Step -RepoName repo -OrgName org -Tag $Tag -DryRun $DryRun |
                Out-Null
        } finally {
            Pop-Location
        }
        return , $global:GhCalls
    }

    # The release create call, which must be the only gh call.
    function Get-CreateCall ($Calls) {
        $Calls.Count | Should -Be 1
        $call = $Calls[0]
        ($call -join ' ') | Should -BeLike '-R org/repo release create *'
        return $call
    }
}

AfterAll {
    Remove-Item function:global:gh -ErrorAction SilentlyContinue
    Remove-Variable -Name GhCalls -Scope Global -ErrorAction SilentlyContinue
}

Describe 'update-tag.ps1' {

    AfterEach {
        if ($script:Workspace) {
            Remove-Item -Recurse -Force $script:Workspace -ErrorAction SilentlyContinue
            $script:Workspace = $null
        }
    }

    It 'creates the release with every package file in the same call' {
        $script:Workspace = New-Workspace -Files 'first.bin', 'second.bin'
        $call = Get-CreateCall (Invoke-Step $script:Workspace)
        $call | Should -Contain '4.5.10'
        ($call | Where-Object { $_ -like '*first.bin' }).Count | Should -Be 1
        ($call | Where-Object { $_ -like '*second.bin' }).Count | Should -Be 1
    }

    It 'zips a folder in the package and attaches the zip' {
        $script:Workspace = New-Workspace -Folders 'build'
        $call = Get-CreateCall (Invoke-Step $script:Workspace)
        ($call | Where-Object { $_ -like '*build.zip' }).Count | Should -Be 1
        Join-Path $script:Workspace 'package/build.zip' | Should -Exist
    }

    It 'creates the release with no files when the package holds only dummy.txt' {
        $script:Workspace = New-Workspace -Files 'dummy.txt'
        $call = Get-CreateCall (Invoke-Step $script:Workspace)
        ($call | Where-Object { $_ -like '*dummy.txt' }).Count | Should -Be 0
        $call[-1] | Should -Be '4.5.10'
    }

    It 'creates the release with no files when there is no package folder' {
        $script:Workspace = New-Workspace
        Remove-Item (Join-Path $script:Workspace 'package')
        $call = Get-CreateCall (Invoke-Step $script:Workspace)
        $call[-1] | Should -Be '4.5.10'
    }

    It 'marks an alpha version as a prerelease' {
        $script:Workspace = New-Workspace -Files 'first.bin'
        $call = Get-CreateCall (Invoke-Step $script:Workspace -Tag '4.5.10-alpha.3')
        $call | Should -Contain '--prerelease'
    }

    It 'pushes the tag before creating the release' {
        $script:Workspace = New-Workspace -Files 'first.bin'
        Invoke-Step $script:Workspace | Out-Null
        git -C (Join-Path $script:Workspace 'origin.git') tag --list |
            Should -Be '4.5.10'
    }

    It 'creates no release and pushes no tag on a dry run' {
        $script:Workspace = New-Workspace -Files 'first.bin'
        (Invoke-Step $script:Workspace -DryRun $true).Count | Should -Be 0
        git -C (Join-Path $script:Workspace 'origin.git') tag --list |
            Should -BeNullOrEmpty
    }
}
