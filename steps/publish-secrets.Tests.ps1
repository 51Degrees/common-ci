# Tests for the secrets that the two publish workflows,
# .github/workflows/nightly-publish.yml and nightly-publish-main.yml, take
# from their callers. Each secret reaches the caller's own scripts through
# toJSON(secrets) and steps/run-script.ps1, which hands a script only the
# keys whose names match its parameters, so a name here is also the name of
# a parameter in a caller's script.

BeforeAll {
    $script:Workflows = Join-Path $PSScriptRoot '..' '.github' 'workflows'
    $script:Files = @('nightly-publish.yml', 'nightly-publish-main.yml')

    # The names under on.workflow_call.secrets, read by indentation so that
    # no YAML module is needed.
    function Get-DeclaredSecrets([string]$Path) {
        $names = @()
        $inCall = $false
        $inSecrets = $false
        foreach ($line in Get-Content $Path) {
            if ($line -match '^\s*(#.*)?$') { continue }
            $indent = $line.Length - $line.TrimStart().Length
            if ($indent -le 2) { $inCall = $line -match '^  workflow_call:\s*$'; $inSecrets = $false; continue }
            if (-not $inCall) { continue }
            if ($indent -le 4) { $inSecrets = $line -match '^    secrets:\s*$'; continue }
            if ($inSecrets -and $line -match '^      ([A-Za-z0-9_-]+):') { $names += $Matches[1] }
        }
        return $names
    }

    # The names of every secrets.<name> the workflow refers to.
    function Get-SecretReferences([string]$Path) {
        $text = Get-Content -Raw $Path
        return @([regex]::Matches($text, 'secrets\.([A-Za-z0-9_-]+)') |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    }
}

Describe 'The secrets of the publish workflows' {

    It 'declares ReportingToken, the token for reporting a published package' {
        foreach ($file in $script:Files) {
            Get-DeclaredSecrets (Join-Path $script:Workflows $file) |
                Should -Contain 'ReportingToken' -Because $file
        }
    }

    It 'declares the same secrets in both workflows' {
        $first = Get-DeclaredSecrets (Join-Path $script:Workflows $script:Files[0])
        $second = Get-DeclaredSecrets (Join-Path $script:Workflows $script:Files[1])
        $first | Should -Not -BeNullOrEmpty
        ($first | Sort-Object) -join ',' | Should -Be (($second | Sort-Object) -join ',')
    }

    It 'refers only to secrets it declares' {
        foreach ($file in $script:Files) {
            $path = Join-Path $script:Workflows $file
            $declared = Get-DeclaredSecrets $path
            foreach ($name in Get-SecretReferences $path) {
                $declared | Should -Contain $name -Because "$file refers to secrets.$name"
            }
        }
    }
}
