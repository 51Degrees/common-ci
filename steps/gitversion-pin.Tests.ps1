# Tests that every place this repository installs or runs GitVersion uses the
# one exact version that steps/install-gitversion.ps1 pins. A version such as
# '6.1', or a check that only asks whether dotnet-gitversion is present, lets
# a runner that already has another GitVersion use that one.

BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:InstallScript = Join-Path $PSScriptRoot 'install-gitversion.ps1'

    # Every workflow, action and script. Documents and tests only talk about
    # GitVersion, they do not run it.
    $script:Files = Get-ChildItem -Path $script:Root -Recurse -File |
        Where-Object {
            $_.FullName.Replace([char]92, '/') -notmatch '/\.git/' -and
            $_.Extension -in '.yml', '.yaml', '.ps1', '.psm1', '.sh' -and
            $_.Name -notlike '*.Tests.ps1'
        }

    function Get-Relative($File) {
        return $File.FullName.Substring($script:Root.Length + 1).Replace([char]92, '/')
    }

    $script:Pinned = $null
    if (Test-Path $script:InstallScript) {
        $match = [regex]::Match((Get-Content $script:InstallScript -Raw),
            '\[string\]\$Version\s*=\s*''(?<v>[^'']*)''')
        if ($match.Success) { $script:Pinned = $match.Groups['v'].Value }
    }

    $installLine = 'dotnet\s+tool\s+(?:install|update)\b[^\r\n]*GitVersion\.Tool[^\r\n]*'
    $script:Installs = foreach ($file in $script:Files) {
        $n = 0
        foreach ($line in Get-Content $file.FullName) {
            $n++
            if ($line -match $installLine) {
                $v = [regex]::Match($line, '(?:--version|-v)[\s=]+[''"]?(?<v>[^\s''"]+)')
                [pscustomobject]@{
                    Where   = "$(Get-Relative $file):$n"
                    File    = Get-Relative $file
                    Version = if ($v.Success) { $v.Groups['v'].Value } else { $null }
                }
            }
        }
    }

    $script:Users = $script:Files | Where-Object {
        (Get-Content $_.FullName -Raw) -match 'dotnet-gitversion'
    }
}

Describe 'the pinned GitVersion version' {
    It 'is one exact major.minor.patch in steps/install-gitversion.ps1' {
        $script:Pinned | Should -Match '^\d+\.\d+\.\d+$'
    }
}

Describe 'every GitVersion install' {
    It 'is found at least once' {
        @($script:Installs).Count | Should -BeGreaterThan 0
    }

    It 'names an exact version' {
        $bad = $script:Installs | Where-Object {
            -not ($_.Version -match '^\d+\.\d+\.\d+$' -or
                ($_.File -eq 'steps/install-gitversion.ps1' -and
                $_.Version -match '^\$\(?Version\)?$'))
        } | ForEach-Object { "$($_.Where) has '$($_.Version)'" }
        $bad | Should -BeNullOrEmpty
    }

    It 'names the pinned version and no other' {
        $bad = $script:Installs | Where-Object {
            $_.Version -match '^\d+\.\d+\.\d+$' -and $_.Version -ne $script:Pinned
        } | ForEach-Object { "$($_.Where) has '$($_.Version)', not '$script:Pinned'" }
        $bad | Should -BeNullOrEmpty
    }
}

Describe 'every file that runs dotnet-gitversion' {
    It 'gets it from install-gitversion.ps1 and not from a presence check' {
        $bad = $script:Users | Where-Object {
            (Get-Relative $_) -ne 'steps/install-gitversion.ps1' -and
            (Get-Content $_.FullName -Raw) -notmatch 'install-gitversion\.ps1'
        } | ForEach-Object { Get-Relative $_ }
        $bad | Should -BeNullOrEmpty
    }

    It 'has no presence-only check of its own' {
        $bad = $script:Users | Where-Object {
            (Get-Relative $_) -ne 'steps/install-gitversion.ps1' -and
            (Get-Content $_.FullName -Raw) -match
                '(?:Get-Command|command\s+-v|which|Test-Path)[^\r\n]*dotnet-gitversion'
        } | ForEach-Object { Get-Relative $_ }
        $bad | Should -BeNullOrEmpty
    }
}

Describe 'steps/install-gitversion.ps1' {
    It 'checks the installed version' {
        (Get-Content $script:InstallScript -Raw) | Should -Match 'dotnet-gitversion\s+/version'
    }
}
