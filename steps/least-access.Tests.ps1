# Checks that each job of the reusable workflows takes the secrets through one
# step alone. Run with: Invoke-Pester ./steps/least-access.Tests.ps1
#
# The secrets reach a job's scripts through steps/set-resource-keys.ps1, which
# exports the _51DEGREES_ secrets into the environment. These checks read each
# workflow job by job and look at where the secrets context appears.

# The files are listed at discovery, because each one becomes its own set of
# tests.
BeforeDiscovery {
    $root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $Workflows = @(Get-ChildItem (Join-Path $root '.github/workflows') -Filter '*.yml')
    $Actions = @(Get-ChildItem (Join-Path $root '.github/actions'), (Join-Path $root 'actions') -Recurse -Filter 'action.yml')
    $ScriptRunningActions = @($Actions | Where-Object { (Get-Content -Raw $_.FullName) -cmatch 'ci/fetch-assets\.ps1' })
}

BeforeAll {
    # The jobs of a workflow as name -> text. A job starts at a two-space
    # indented key under 'jobs:'.
    function Get-Jobs ([string]$Path) {
        $jobs = [ordered]@{}
        $name = $null
        $inJobs = $false
        foreach ($line in Get-Content -LiteralPath $Path) {
            if ($line -cmatch '^jobs:\s*$') { $inJobs = $true; continue }
            if (-not $inJobs) { continue }
            if ($line -cmatch '^  ([A-Za-z0-9_-]+):\s*$') {
                $name = $Matches[1]
                $jobs[$name] = ''
                continue
            }
            if ($name) { $jobs[$name] += "$line`n" }
        }
        return $jobs
    }

    # The steps of a job as a list of texts. A step starts at '- name:' or
    # '- uses:' at the steps indentation.
    function Get-Steps ([string]$JobText) {
        $steps = @()
        $current = $null
        foreach ($line in $JobText -split "`n") {
            if ($line -cmatch '^      - (name|uses|id|if|run|env|with|shell):') {
                if ($null -ne $current) { $steps += $current }
                $current = ''
            }
            if ($null -ne $current) { $current += "$line`n" }
        }
        if ($null -ne $current) { $steps += $current }
        return $steps
    }

    # The jobs that run a caller's build, test or publish scripts, and so need
    # the _51DEGREES_ secrets in the environment.
    $script:ExportingJobs = @('PreBuild', 'Build', 'Test', 'Package', 'BuildAndTest')
}

Describe 'Secrets in <_.Name>' -ForEach $Workflows {

    BeforeAll {
        $script:Jobs = Get-Jobs $_.FullName
    }

    It 'hands the secrets context only to the export step and the asset prefetch' {
        foreach ($name in $script:Jobs.Keys) {
            foreach ($step in Get-Steps $script:Jobs[$name]) {
                if ($step -cnotmatch 'toJSON\(secrets\)') { continue }
                ($step -cmatch 'set-resource-keys\.ps1' -or $step -cmatch 'prefetch_assets') |
                    Should -BeTrue -Because "a step of $name takes the secrets context without exporting it"
            }
        }
    }

    It 'exports the secrets in each job that runs a caller''s scripts' {
        foreach ($name in $script:Jobs.Keys) {
            if ($name -cnotin $script:ExportingJobs) { continue }
            $script:Jobs[$name] | Should -Match 'set-resource-keys\.ps1' -Because "$name runs scripts that read the _51DEGREES_ secrets"
        }
    }

    It 'reads by name only the automation token, as _51DEGREES_ACCESS_TOKEN' {
        $text = Get-Content -Raw -LiteralPath $_.FullName
        foreach ($match in [regex]::Matches($text, '(?<![\w-])secrets\.([A-Za-z0-9_.-]+)')) {
            (@('_51DEGREES_ACCESS_TOKEN', '_51DEGREES_LABEL_SYNC_TOKEN') -ccontains $match.Groups[1].Value) | Should -BeTrue -Because "$($match.Value) is not a _51DEGREES_ token"
        }
    }
}

Describe 'Secrets in the composite actions' {

    # An action that runs a caller's script with the secrets exports them
    # first, and passes none as a parameter.
    It '<_.Directory.Name> exports the secrets before running the caller''s script' -ForEach $ScriptRunningActions {
        $text = Get-Content -Raw -LiteralPath $_.FullName
        $text | Should -Match 'set-resource-keys\.ps1'
        $text | Should -Not -Match 'Parameters'
    }
}