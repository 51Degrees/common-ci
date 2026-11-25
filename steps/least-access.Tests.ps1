# Checks that each job of the reusable workflows takes the secrets through one
# step alone. Run with: Invoke-Pester ./steps/least-access.Tests.ps1
#
# The secrets reach a job's scripts through steps/export-secrets.ps1, which
# exports them into the environment. A job receives only the secrets it uses,
# so the publishing names reach the job that publishes and the signing names
# the job that signs. These checks read each workflow job by
# job and look at where the secrets context appears.

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

    # The steps of a job or an action as a list of texts. A step starts at a
    # '- ' at the indentation of the first item under 'steps:', and the list
    # ends at the first line, other than a comment, indented less than that.
    function Get-Steps ([string]$JobText) {
        $steps = @()
        $current = $null
        $inSteps = $false
        $indent = $null
        foreach ($line in $JobText -split "`n") {
            if (-not $inSteps) {
                if ($line -cmatch '^\s*steps:\s*$') { $inSteps = $true; $indent = $null }
                continue
            }
            if ($line -match '^\s*(#.*)?$') {
                if ($null -ne $current) { $current += "$line`n" }
                continue
            }
            $width = $line.Length - $line.TrimStart().Length
            if ($null -eq $indent) {
                if ($line -cnotmatch '^\s*- ') { $inSteps = $false; continue }
                $indent = $width
            }
            if ($width -lt $indent) {
                if ($null -ne $current) { $steps += $current }
                $current = $null
                $inSteps = $false
                continue
            }
            if ($width -eq $indent -and $line -cmatch '^\s*- ') {
                if ($null -ne $current) { $steps += $current }
                $current = ''
            }
            if ($null -ne $current) { $current += "$line`n" }
        }
        if ($null -ne $current) { $steps += $current }
        return $steps
    }

    # A step's text without its comment lines, so that a comment does not
    # decide what the step runs.
    function Get-Code ([string]$Step) {
        return (($Step -split "`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    }

    # The jobs that run a caller's build, test or publish scripts, and so need
    # the secrets in the environment.
    $script:ExportingJobs = @('PreBuild', 'Build', 'Test', 'Package', 'BuildAndTest')

    # The data file license, which only the steps that download the data files
    # take.
    $script:Data = @((Import-PowerShellDataFile -Path (Join-Path $PSScriptRoot 'ci-secrets.psd1')).Data)
}

Describe 'Secrets in <_.Name>' -ForEach $Workflows {

    BeforeAll {
        $script:Jobs = Get-Jobs $_.FullName
    }

    It 'hands the secrets context only to the export step and the asset prefetch' {
        foreach ($name in $script:Jobs.Keys) {
            foreach ($step in Get-Steps $script:Jobs[$name]) {
                if ($step -cnotmatch 'toJSON\(secrets\)') { continue }
                ($step -cmatch 'export-secrets\.ps1' -or $step -cmatch 'prefetch_assets') |
                    Should -BeTrue -Because "a step of $name takes the secrets context without exporting it"
            }
        }
    }

    It 'exports the secrets in each job that runs a caller''s scripts' {
        foreach ($name in $script:Jobs.Keys) {
            if ($name -cnotin $script:ExportingJobs) { continue }
            $script:Jobs[$name] | Should -Match 'export-secrets\.ps1' -Because "$name runs scripts that read the secrets"
        }
    }

    # The Build job builds the packages and signs them. The Package job
    # publishes them. Every other job takes neither class.
    It 'exports the signing names in the Build job alone and the publishing names in the Package job alone' {
        foreach ($name in $script:Jobs.Keys) {
            foreach ($step in Get-Steps $script:Jobs[$name]) {
                if ($step -cnotmatch 'export-secrets\.ps1') { continue }
                ($step -cmatch ' -Sign\b') | Should -Be ($name -ceq 'Build') -Because "only the Build job signs, and this is $name"
                ($step -cmatch ' -Publish\b') | Should -Be ($name -ceq 'Package') -Because "only the Package job publishes, and this is $name"
            }
        }
    }

    # The calling repository's own list goes to the jobs that run its build
    # and test scripts, and never to a job that publishes or signs.
    It 'passes the calling repository''s list only to the jobs that run its build and test scripts' {
        $callerJobs = @('BuildAndTest', 'PreBuild', 'Test')
        foreach ($name in $script:Jobs.Keys) {
            foreach ($step in Get-Steps $script:Jobs[$name]) {
                if ($step -cnotmatch 'export-secrets\.ps1') { continue }
                ($step -cmatch ' -CallerList\b') | Should -Be ($name -cin $callerJobs) -Because "only the jobs that run the caller's build and test scripts take its list, and this is $name"
                if ($step -cmatch ' -CallerList\b') {
                    $step | Should -Not -Match ' -(Publish|Sign)\b' -Because 'a job that takes the list neither publishes nor signs'
                }
            }
        }
    }

    # The step that reads the list comes straight before the export step that
    # takes it. It reads at the branch the workflow was given, or the branch
    # the workflow runs on, and saves to the file the export step reads.
    It 'reads the calling repository''s list at the branch the workflow works on, straight before the step that takes it' {
        $refs = @(
            '${{ github.ref_name }}'
            '${{ inputs.branch != '''' && inputs.branch || github.ref_name }}'
        )
        foreach ($name in $script:Jobs.Keys) {
            $steps = @(Get-Steps $script:Jobs[$name])
            for ($i = 0; $i -lt $steps.Count; $i++) {
                if ($steps[$i] -cnotmatch 'export-secrets\.ps1' -or $steps[$i] -cnotmatch ' -CallerList\b') { continue }
                $steps[$i] | Should -Match ' -CallerList caller-ci-secrets\.psd1\b' -Because "the export step of $name reads the file the read step saves"
                $i | Should -BeGreaterThan 0 -Because "the export step of $name follows the step that reads the list"
                $read = $steps[$i - 1]
                $read | Should -Match 'get-caller-ci-secrets\.ps1' -Because "the step before the export step of $name reads the list"
                $read | Should -Match ' -Ref \$env:_51DEGREES_REF\b' -Because "the read step of $name takes the branch from _51DEGREES_REF"
                $read | Should -Match ' -Path caller-ci-secrets\.psd1\b' -Because "the read step of $name saves the file the export step reads"
                $ref = [regex]::Match($read, '(?m)^\s*_51DEGREES_REF:\s*(.+?)\s*$').Groups[1].Value
                $ref | Should -BeIn $refs -Because "the read step of $name reads at the branch the workflow works on"
            }
        }
    }

    # The automation token, CI_ACCESS_TOKEN, in a workflow that publishes
    # the publishing token, PUBLISH_ACCESS_TOKEN, and the data file license.
    It 'reads by name only the automation token, the publishing token where it publishes, and the data file license' {
        $text = Get-Content -Raw -LiteralPath $_.FullName
        $tokens = @('CI_ACCESS_TOKEN') + $script:Data
        if ($_.Name -clike 'nightly-publish*.yml') { $tokens += 'PUBLISH_ACCESS_TOKEN' }
        foreach ($match in [regex]::Matches($text, '(?<![\w-])secrets\.([A-Za-z0-9_.-]+)')) {
            $match.Groups[1].Value | Should -BeIn $tokens -Because "$($match.Value) is not a token $($_.Name) reads by name"
        }
    }
}

Describe 'The data file license in <_.Name>' -ForEach $Workflows {

    BeforeAll {
        $script:Jobs = Get-Jobs $_.FullName
    }

    # The asset prefetch takes it as its license-key input, and the step that
    # runs the build and test script or the test script sets it as
    # _51DEGREES_LICENSE_KEY in its own env, for the data file downloads and
    # the data file update example tests. No job takes it in its env, and no
    # export step takes it.
    It 'hands the data file license only to the steps that download the data files' {
        foreach ($name in $script:Jobs.Keys) {
            $inSteps = 0
            foreach ($step in Get-Steps $script:Jobs[$name]) {
                $count = 0
                foreach ($license in $script:Data) {
                    $count += [regex]::Matches($step, [regex]::Escape($license)).Count
                }
                if ($count -eq 0) { continue }
                $inSteps += $count
                $code = Get-Code $step
                $step | Should -Not -Match 'export-secrets\.ps1' -Because "an export step of $name takes no data file license"
                ($code -cmatch 'prefetch_assets' -or
                    $code -cmatch 'nightly-pull-request\.build-and-test\.ps1|nightly-publish\.test\.ps1') |
                    Should -BeTrue -Because "only the steps of $name that download the data files take the data file license"
                $step | Should -Not -Match 'GITHUB_ENV' -Because "a step of $name that takes the data file license keeps it to itself"
            }
            $inJob = 0
            foreach ($license in $script:Data) {
                $inJob += [regex]::Matches($script:Jobs[$name], [regex]::Escape($license)).Count
            }
            $inSteps | Should -Be $inJob -Because "$name takes the data file license in no env of its own"
        }
    }

    # The steps that download the data files and run the data file update
    # example tests each take it.
    It 'hands the data file license to each step that downloads the data files' {
        $names = ($script:Data | ForEach-Object { [regex]::Escape($_) }) -join '|'
        foreach ($name in $script:Jobs.Keys) {
            foreach ($step in Get-Steps $script:Jobs[$name]) {
                if ($step -cmatch 'prefetch_assets') {
                    $step | Should -Match "license-key: \$\{\{ secrets\.($names) \}\}" -Because "the asset prefetch of $name downloads the data files"
                }
                if ($step -cmatch 'nightly-pull-request\.build-and-test\.ps1|nightly-publish\.test\.ps1') {
                    $step | Should -Match "_51DEGREES_LICENSE_KEY: \$\{\{ secrets\.($names) \}\}" -Because "a step of $name downloads the data files and runs the data file update example tests"
                }
            }
        }
    }

    # A workflow level env would hand it to every job, the publishing and
    # signing jobs among them.
    It 'names the data file license nowhere outside its jobs' {
        $text = Get-Content -Raw -LiteralPath $_.FullName
        $head = ($text -split '(?m)^jobs:\s*$', 2)[0]
        foreach ($license in $script:Data) {
            $head | Should -Not -Match ([regex]::Escape($license)) -Because "$($_.Name) names $license outside its jobs"
        }
    }
}

Describe 'Secrets in the composite actions' {

    # An action that runs a caller's script with the secrets exports them
    # first, and passes none as a parameter.
    It '<_.Directory.Name> exports the secrets before running the caller''s script' -ForEach $ScriptRunningActions {
        $text = Get-Content -Raw -LiteralPath $_.FullName
        $text | Should -Match 'export-secrets\.ps1'
        $text | Should -Not -Match 'Parameters'
    }

    # The secrets context holds the publishing and signing values too, so the
    # caller's script runs in a step of its own after the export step. It
    # sees the names the export step wrote and nothing else.
    It '<_.Directory.Name> runs the caller''s script in a step without the secrets context' -ForEach $ScriptRunningActions {
        $steps = @(Get-Steps (Get-Content -Raw -LiteralPath $_.FullName) | Where-Object { $_ -cmatch '&\s*"[^"]*ci/fetch-assets\.ps1"' })
        $steps.Count | Should -BeGreaterThan 0 -Because 'the action runs the caller''s ci/fetch-assets.ps1'
        foreach ($step in $steps) {
            $step | Should -Not -Match 'inputs\.secrets|toJSON\(secrets\)|_51DEGREES_SECRETS|export-secrets\.ps1' -Because 'the step that runs the caller''s script takes no secrets context'
        }
    }

    # The step that runs the caller's fetch script sets the license from the
    # action's input.
    It '<_.Directory.Name> sets _51DEGREES_LICENSE_KEY from its license-key input for the caller''s script' -ForEach $ScriptRunningActions {
        $steps = @(Get-Steps (Get-Content -Raw -LiteralPath $_.FullName) | Where-Object { $_ -cmatch '&\s*"[^"]*ci/fetch-assets\.ps1"' })
        foreach ($step in $steps) {
            $step | Should -Match '_51DEGREES_LICENSE_KEY: \$\{\{ inputs\.license-key \}\}' -Because 'the caller''s fetch script downloads the data files with it'
        }
    }

    # The data file license reaches the step that runs the caller's script
    # and no other step of the action.
    It '<_.Directory.Name> hands its license-key input only to the step that runs the caller''s script' -ForEach $Actions {
        $text = Get-Content -Raw -LiteralPath $_.FullName
        foreach ($step in Get-Steps $text) {
            if ($step -cnotmatch 'inputs\s*(\.|\[\s*[''"])license-key') { continue }
            Get-Code $step | Should -Match '&\s*"[^"]*ci/fetch-assets\.ps1"' -Because 'only the step that runs the caller''s script takes the data file license'
            $step | Should -Not -Match 'GITHUB_ENV' -Because 'the step that runs the caller''s script keeps the data file license to itself'
        }
    }

    It '<_.Directory.Name> takes no publishing or signing name' -ForEach $Actions {
        (Get-Content -Raw -LiteralPath $_.FullName) | Should -Not -Match ' -(Publish|Sign)\b'
    }
}

Describe 'How these checks read the steps' {

    # A job level env written after the steps belongs to no step, so the
    # checks above count it as the job's own.
    It 'ends the steps at a job key that follows them' {
        $job = @(
            '    runs-on: ubuntu-latest'
            '    steps:'
            '      - name: First'
            '        run: ./first.ps1'
            ''
            '      # A comment between the steps.'
            '      - name: Last'
            '        uses: ./.github/actions/example'
            '    env:'
            '      _51DEGREES_EXAMPLE: ${{ secrets.EXAMPLE }}'
        ) -join "`n"
        $steps = @(Get-Steps $job)
        $steps.Count | Should -Be 2
        $steps[0] | Should -Match 'first\.ps1'
        $steps[1] | Should -Match 'actions/example'
        $steps | Should -Not -Match '_51DEGREES_EXAMPLE'
    }

    It 'reads the steps of an action at whatever indentation they have' {
        $action = @(
            'runs:'
            '  using: "composite"'
            '  steps:'
            '    - name: First'
            '      shell: pwsh'
            '      run: ./first.ps1'
            '    - uses: ./example'
            '      with:'
            '        list:'
            '          - one'
        ) -join "`n"
        $steps = @(Get-Steps $action)
        $steps.Count | Should -Be 2
        $steps[1] | Should -Match '- one'
    }

    It 'leaves the comments out of what a step runs' {
        $code = Get-Code "      - name: Build`n        # ./nightly-publish.test.ps1`n        run: ./build.ps1`n"
        $code | Should -Not -Match 'nightly-publish\.test\.ps1'
        $code | Should -Match 'build\.ps1'
    }
}
