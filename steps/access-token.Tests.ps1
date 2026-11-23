# Checks how the automation token reaches the scripts. Run with:
# Invoke-Pester ./steps/access-token.Tests.ps1
#
# A script that needs the automation token reads CI_ACCESS_TOKEN from the
# environment itself. No script takes a token as a parameter and no
# workflow passes one. A step that runs such a script has the name in its
# environment, from the export step of its job or from its own env block.

BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $Workflows = @(Get-ChildItem (Join-Path $root '.github/workflows') -Filter '*.yml')
}

BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Name = 'CI_ACCESS_TOKEN'

    # The scripts of this repository, as paths relative to the root, without
    # the tests.
    $tracked = @(git -C $script:Root ls-files '*.ps1')
    $script:Scripts = @($tracked | Where-Object { $_ -notlike '*.Tests.ps1' })

    # The scripts that the workflows run: those at the root and in steps.
    $script:Text = @{}
    foreach ($path in $script:Scripts | Where-Object { $_ -match '^(steps/)?[^/]+$' }) {
        $script:Text[$path] = "$(Get-Content -Raw -LiteralPath (Join-Path $script:Root $path))"
    }

    # The root and steps scripts a text runs, by the ./name.ps1 and
    # ./steps/name.ps1 forms.
    function Get-Called ([string]$Text) {
        return @([regex]::Matches($Text, '(?<=[./])((?:steps/)?[A-Za-z0-9.-]+\.ps1)') |
            ForEach-Object { $_.Groups[1].Value } |
            Where-Object { $script:Text.ContainsKey($_) } | Sort-Object -Unique)
    }

    # The scripts that read the token, themselves or through a script they
    # run.
    $script:Readers = @($script:Text.Keys | Where-Object { $script:Text[$_].Contains("`$env:$($script:Name)") })
    do {
        $more = @($script:Text.Keys | Where-Object {
            $_ -cnotin $script:Readers -and @(Get-Called $script:Text[$_] | Where-Object { $_ -cin $script:Readers }).Count -gt 0
        })
        $script:Readers += $more
    } while ($more.Count -gt 0)

    # The jobs of a workflow as name -> list of step texts.
    function Get-JobSteps ([string]$Path) {
        $jobs = [ordered]@{}
        $name = $null
        $inJobs = $false
        foreach ($line in Get-Content -LiteralPath $Path) {
            if ($line -cmatch '^jobs:\s*$') { $inJobs = $true; continue }
            if (-not $inJobs) { continue }
            if ($line -cmatch '^  ([A-Za-z0-9_-]+):\s*$') {
                $name = $Matches[1]
                $jobs[$name] = [System.Collections.Generic.List[string]]::new()
                continue
            }
            if (-not $name) { continue }
            if ($line -cmatch '^      - ') { $jobs[$name].Add('') }
            if ($jobs[$name].Count -gt 0) { $jobs[$name][$jobs[$name].Count - 1] += "$line`n" }
        }
        return $jobs
    }
}

Describe 'The automation token in the scripts' {

    It 'is taken by no script as a parameter' {
        foreach ($path in $script:Scripts) {
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $path), [ref]$null, [ref]$errors)
            $parameters = @(if ($ast.ParamBlock) { $ast.ParamBlock.Parameters.Name.VariablePath.UserPath })
            $parameters -match 'Token$' | Should -BeNullOrEmpty -Because "$path reads the token from the environment"
        }
    }

    It 'is read from the environment by the script that sets up git' {
        $script:Readers | Should -Contain 'steps/configure-git.ps1'
    }

    It 'is read by every script that sets a token name a tool defines' {
        foreach ($path in $script:Text.Keys) {
            if ($script:Text[$path] -cnotmatch '\$env:(GITHUB_TOKEN|GH_TOKEN)\s*=') { continue }
            $script:Text[$path] | Should -Match ('\$env:(GITHUB_TOKEN|GH_TOKEN)\s*=\s*\$env:' + $script:Name + '\b') -Because "$path sets the tool's name straight from $($script:Name)"
        }
    }
}

Describe 'The automation token in <_.Name>' -ForEach $Workflows {

    BeforeAll {
        $script:Jobs = Get-JobSteps $_.FullName
    }

    It 'passes no token to a script as a parameter' {
        (Get-Content -Raw -LiteralPath $_.FullName) | Should -Not -Match ' -[A-Za-z]*Token\b'
    }

    It 'has the token in the environment of every step that runs a script that reads it' {
        foreach ($job in $script:Jobs.Keys) {
            $exported = $false
            foreach ($step in $script:Jobs[$job]) {
                if ($step -cmatch 'export-secrets\.ps1') { $exported = $true; continue }
                $readers = @(Get-Called $step | Where-Object { $_ -cin $script:Readers })
                if ($readers.Count -eq 0) { continue }
                ($exported -or $step -cmatch "(?m)^\s+$($script:Name): ") |
                    Should -BeTrue -Because "a step of $job runs $($readers -join ', '), which reads $($script:Name)"
            }
        }
    }
}
