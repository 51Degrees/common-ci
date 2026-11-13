# Tests for the directive matching in steps/version-directive.ps1.
#
# The script calls gh for the pull request and the timeline, which a unit test
# cannot reach, so the pattern and the approver rule are tested directly. They
# are the two decisions the script makes; everything else is fetching.

BeforeAll {
    # The same pattern the script uses. Kept here deliberately rather than
    # dot-sourcing, because the script runs its body on load and would call gh.
    $script:DirectivePattern = '\+semver:\s*(minor|major)'

    function Test-Directive ([string]$Message) {
        $m = [regex]::Match($Message, $script:DirectivePattern, 'IgnoreCase')
        if ($m.Success) { return $m.Groups[1].Value.ToLowerInvariant() }
        return $null
    }

    # The approver rule: someone other than the author applied the label.
    function Get-Approver ([object[]]$Events, [string]$Author, [string]$Label) {
        foreach ($e in $Events) {
            if ($e.event -eq 'labeled' -and $e.label.name -eq $Label) {
                if ($e.actor.login -and $e.actor.login -ne $Author) { return $e.actor.login }
            }
        }
        return $null
    }

    function New-LabelEvent ([string]$Actor, [string]$Label) {
        [pscustomobject]@{ event = 'labeled'; actor = @{ login = $Actor }; label = @{ name = $Label } }
    }
}

Describe 'the directive pattern' {
    It 'finds a minor directive on its own line' {
        Test-Directive "BUILD: something`n`n+semver: minor" | Should -Be 'minor'
    }

    It 'finds a major directive' {
        Test-Directive "+semver: major" | Should -Be 'major'
    }

    It 'finds it whatever the spacing' {
        Test-Directive '+semver:minor'   | Should -Be 'minor'
        Test-Directive '+semver:   minor' | Should -Be 'minor'
    }

    It 'ignores case, because GitVersion does' {
        Test-Directive '+SemVer: Minor' | Should -Be 'minor'
    }

    It 'finds it in the body of a long message' {
        $message = @"
BUILD: Publish the rename as a minor version

Several paragraphs of reasoning that mention semver and versions and
minor changes in passing, none of which is the directive.

+semver: minor
"@
        Test-Directive $message | Should -Be 'minor'
    }

    It 'does not fire on a patch directive, which asks for what happens anyway' {
        Test-Directive '+semver: patch' | Should -BeNullOrEmpty
    }

    It 'does not fire on prose about a minor version' {
        Test-Directive 'This is published as a minor version rather than a patch.' |
            Should -BeNullOrEmpty
    }

    It 'does not fire on a message with no directive at all' {
        Test-Directive "FIX: an ordinary change`n`nWith a body." | Should -BeNullOrEmpty
    }
}

Describe 'the approver rule' {
    $label = 'version bump approved'

    It 'refuses the author labelling their own pull request' {
        $events = @((New-LabelEvent 'jwrosewell' $label))
        Get-Approver $events 'jwrosewell' $label | Should -BeNullOrEmpty
    }

    It 'accepts a second person' {
        $events = @((New-LabelEvent 'justadreamer' $label))
        Get-Approver $events 'jwrosewell' $label | Should -Be 'justadreamer'
    }

    It 'accepts a second person even when the author also labelled it' {
        $events = @(
            (New-LabelEvent 'jwrosewell' $label),
            (New-LabelEvent 'justadreamer' $label))
        Get-Approver $events 'jwrosewell' $label | Should -Be 'justadreamer'
    }

    It 'ignores a different label applied by someone else' {
        $events = @((New-LabelEvent 'justadreamer' 'ready for review'))
        Get-Approver $events 'jwrosewell' $label | Should -BeNullOrEmpty
    }

    It 'ignores an event that is not a labelling' {
        $events = @([pscustomobject]@{ event = 'commented'; actor = @{ login = 'justadreamer' }; label = @{ name = $label } })
        Get-Approver $events 'jwrosewell' $label | Should -BeNullOrEmpty
    }

    It 'finds nothing when nothing happened' {
        Get-Approver @() 'jwrosewell' $label | Should -BeNullOrEmpty
    }
}
