# Guards the names in this repository. Run with: Invoke-Pester ./steps/names.Tests.ps1
#
# A name that a customer uses, in the demos and the examples, starts with
# _51DEGREES_. A secret that only CI uses has no prefix, its name says what it
# does, and steps/ci-secrets.psd1 lists it. Every name that a script, a
# workflow, an action or a test reads or sets in the environment is one of
# these, or a name that GitHub, the operating system or a tool defines, which
# is used as that tool requires. This file is left out of its own checks.

BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $script:Ci = Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'ci-secrets.psd1')
    $script:CiNames = @($script:Ci.Every) + @($script:Ci.Publish) + @($script:Ci.Sign) + @($script:Ci.Data)
    $script:Self = [IO.Path]::GetRelativePath($script:Root, $PSCommandPath) -replace '\\', '/'

    # The tracked text files, as paths relative to the root.
    $tracked = @(git -C $script:Root ls-files)
    $binary = '\.(png|jpg|jpeg|gif|ico|snk|zip|gz)$'
    # These folders are used by other 51Degrees repositories.
    $shared = '^(docker|scripts/modules|scripts/azure)/'
    $script:Files = @($tracked | Where-Object { $_ -notmatch $binary -and $_ -notmatch $shared -and $_ -ne $script:Self })

    $script:Workflows = @($script:Files | Where-Object { $_ -like '.github/workflows/*.yml' })
    $script:Actions = @($script:Files | Where-Object { $_ -like '*/action.yml' })
    $script:Scripts = @($script:Files | Where-Object { $_ -like '*.ps1' })
    $script:Python = @($script:Files | Where-Object { $_ -like '*.py' })
    # Everything that is not a script or a document: the workflows, the
    # actions and the settings files.
    $script:Settings = @($script:Files | Where-Object { $_ -notlike '*.ps1' -and $_ -notlike '*.py' -and $_ -notlike '*.md' })

    # The names that GitHub, the operating system or a tool defines.
    $script:ToolNames = '^(' + (@(
        'GITHUB_\w+', 'RUNNER_\w+', 'CI'            # GitHub Actions
        'PATH', 'HOME'                              # the operating system
        'GH_TOKEN'                                  # the GitHub CLI
        'GIT_\w+'                                   # git
        'JAVA_HOME'                                 # Java
        'NODE_AUTH_TOKEN', 'JEST_JUNIT_OUTPUT_DIR'  # npm and jest-junit
        'TWINE_USERNAME', 'TWINE_PASSWORD'          # twine
        'Version'                                   # MSBuild
    ) -join '|') + ')$'

    function Test-Name ([string]$Name) {
        return $Name.StartsWith('_51DEGREES_', [StringComparison]::Ordinal) -or
            $Name -cin $script:CiNames -or $Name -cmatch $script:ToolNames
    }

    # Every name the pattern's first group finds in the files that is not a
    # _51DEGREES_ name, a listed CI secret or a tool's, as path:line: name.
    function Find-OtherNames {
        param([string[]]$Paths, [string]$Pattern)
        $hits = @()
        foreach ($path in $Paths) {
            $lines = @(Get-Content -LiteralPath (Join-Path $script:Root $path))
            for ($i = 0; $i -lt $lines.Count; $i++) {
                foreach ($match in [regex]::Matches($lines[$i], $Pattern)) {
                    $name = $match.Groups[1].Value
                    if (-not (Test-Name $name)) { $hits += "${path}:$($i + 1): $name" }
                }
            }
        }
        return $hits
    }

    # Every key of an 'env:' block in the files that is not a _51DEGREES_
    # name, a listed CI secret or a tool's, as path:line: name. A block's keys
    # are the lines indented further than its 'env:' line.
    function Find-OtherEnvKeys {
        param([string[]]$Paths)
        $hits = @()
        foreach ($path in $Paths) {
            $lines = @(Get-Content -LiteralPath (Join-Path $script:Root $path))
            $indent = -1
            for ($i = 0; $i -lt $lines.Count; $i++) {
                $line = $lines[$i]
                if ($line -match '^\s*(#.*)?$') { continue }
                $depth = $line.Length - $line.TrimStart().Length
                if ($indent -ge 0 -and $depth -le $indent) { $indent = -1 }
                if ($indent -ge 0) {
                    if ($line -match '^\s+([A-Za-z_][A-Za-z0-9_]*)\s*:' -and -not (Test-Name $Matches[1])) {
                        $hits += "${path}:$($i + 1): $($Matches[1])"
                    }
                    continue
                }
                if ($line -match '^\s*(- )?env:\s*$') { $indent = $depth }
            }
        }
        return $hits
    }
}

Describe 'Every name in the environment is a _51DEGREES_ name, a listed CI secret or one a tool defines' {

    It 'reads and sets only such names in the scripts and the tests' {
        # $env:NAME, ${env:NAME} and the Env:NAME drive path.
        Find-OtherNames $script:Scripts '(?i)\benv:\\?([A-Za-z_][A-Za-z0-9_]*)' | Should -BeNullOrEmpty
        Find-OtherNames $script:Scripts '(?i)[GS]etEnvironmentVariable\(\s*[''"]([A-Za-z_][A-Za-z0-9_]*)' | Should -BeNullOrEmpty
        Find-OtherNames $script:Python 'os\.(?:environ(?:\.get)?|getenv)[\[(]\s*[''"]([A-Za-z_][A-Za-z0-9_]*)' | Should -BeNullOrEmpty
    }

    It 'sets only such names in the env blocks of the workflows and the actions' {
        Find-OtherEnvKeys ($script:Workflows + $script:Actions) | Should -BeNullOrEmpty
    }

    It 'reads only such names in the shell steps of the workflows and the actions' {
        # $NAME and ${NAME}, where the name is in capitals.
        Find-OtherNames ($script:Workflows + $script:Actions) '(?<![\w$`])\$\{?(_*[A-Z][A-Z0-9_]*)(?![A-Za-z0-9_])' |
            Should -BeNullOrEmpty
    }

    It 'reads a secret, a variable or an environment value by such a name in every expression and placeholder' {
        # secrets.NAME, vars.NAME and env.NAME, in a workflow expression or a
        # settings file placeholder.
        Find-OtherNames $script:Settings '(?<![\w.-])(?:secrets|vars|env)\.([A-Za-z_][A-Za-z0-9_-]*)' | Should -BeNullOrEmpty
    }
}

Describe 'Workflows take their secrets from the caller' {

    It 'declares no secret of its own, so a caller passes secrets: inherit' {
        # A reusable workflow's own declaration sits at on.workflow_call.secrets,
        # four spaces in. A job's 'secrets: inherit' is not a declaration.
        foreach ($path in $script:Workflows) {
            (Get-Content -LiteralPath (Join-Path $script:Root $path)) -cmatch '^    secrets:\s*$' |
                Should -BeNullOrEmpty -Because "$path declares no secret"
        }
    }
}

Describe 'A secret that only CI uses has no prefix' {

    It 'lists each CI secret once, without the _51DEGREES_ prefix' {
        $script:CiNames.Count | Should -BeGreaterThan 0
        $script:CiNames | Where-Object { $_.StartsWith('_51DEGREES_', [StringComparison]::Ordinal) } | Should -BeNullOrEmpty
        $script:CiNames | Group-Object | Where-Object Count -gt 1 | ForEach-Object Name | Should -BeNullOrEmpty
    }

    # A listed name with the prefix, a publishing or signing class under the
    # prefix, or the automation token under the prefix.
    It 'never reads a CI secret under the _51DEGREES_ prefix' {
        $prefixed = '\b_51DEGREES_(PUBLISH_\w+|SIGN_\w+|ACCESS_TOKEN|' + (($script:CiNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'
        $hits = @()
        foreach ($path in $script:Files) {
            $lines = @(Get-Content -LiteralPath (Join-Path $script:Root $path))
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -cmatch $prefixed) { $hits += "${path}:$($i + 1): $($Matches[0])" }
            }
        }
        $hits | Should -BeNullOrEmpty
    }
}

Describe 'A script reads a publishing or signing secret only where it publishes or signs' {

    BeforeAll {
        # The _51DEGREES_ names and the CI secrets each script mentions.
        $named = '\b(_51DEGREES_[A-Z0-9_]*[A-Z0-9]|' + (($script:CiNames | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'
        $script:Reads = @{}
        foreach ($path in $script:Scripts | Where-Object { $_ -notlike '*.Tests.ps1' }) {
            [string]$text = Get-Content -Raw -LiteralPath (Join-Path $script:Root $path)
            $script:Reads[$path] = @([regex]::Matches($text, $named) | ForEach-Object Value | Sort-Object -Unique)
        }
        function Get-Readers ([string[]]$Names) {
            return @($script:Reads.Keys | Where-Object { @($script:Reads[$_] | Where-Object { $_ -cin $Names }).Count -gt 0 } | Sort-Object)
        }
    }

    It 'reads a publishing name only in a script that publishes a package' {
        Get-Readers $script:Ci.Publish | Where-Object { $_ -notlike '*/publish-package*.ps1' } | Should -BeNullOrEmpty
    }

    It 'reads a signing name only in a script that builds a package' {
        Get-Readers $script:Ci.Sign | Where-Object { $_ -notlike '*/build-package*.ps1' } | Should -BeNullOrEmpty
    }

    It 'publishes a package with publishing secrets alone' {
        $publishers = @($script:Reads.Keys | Where-Object { $_ -like '*/publish-package*.ps1' -and $script:Reads[$_].Count -gt 0 })
        $publishers.Count | Should -BeGreaterThan 0
        foreach ($path in $publishers) {
            $script:Reads[$path] | Where-Object { $_ -cnotin $script:Ci.Publish } |
                Should -BeNullOrEmpty -Because "$path publishes"
        }
    }

    It 'signs a package with signing secrets alone' {
        $signers = @($script:Reads.Keys | Where-Object { $_ -like '*/build-package*.ps1' -and $script:Reads[$_].Count -gt 0 })
        $signers.Count | Should -BeGreaterThan 0
        foreach ($path in $signers) {
            $script:Reads[$path] | Where-Object { $_ -cnotin $script:Ci.Sign } |
                Should -BeNullOrEmpty -Because "$path signs what it builds"
        }
    }
}
