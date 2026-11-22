# Tests that the copyright update is named for what it does and how often it
# runs: once a year, on 1 January. Run with:
# Invoke-Pester ./steps/yearly-copyright-update.Tests.ps1

BeforeAll {
    $script:Root = Split-Path $PSScriptRoot -Parent
    $script:Workflow = Join-Path $script:Root '.github/workflows/yearly-copyright-update.yml'
    $script:Script = Join-Path $script:Root 'yearly-copyright-update.ps1'
}

Describe 'Yearly copyright update' {
    It 'has a reusable workflow named for running yearly' {
        $script:Workflow | Should -Exist
        Get-Content $script:Workflow -TotalCount 1 | Should -Be 'name: Yearly Copyright Update'
    }

    It 'runs the yearly script, which exists' {
        $script:Script | Should -Exist
        Get-Content -Raw $script:Workflow | Should -Match '/yearly-copyright-update\.ps1'
    }

    It 'is described nowhere else in this repository by another frequency' {
        # -Force, because on Linux and macOS .github counts as hidden.
        $Hits = Get-ChildItem $script:Root -Recurse -File -Force -Exclude '*.Tests.ps1' |
            Where-Object FullName -NotMatch '[\\/]\.git[\\/]' |
            Select-String -Pattern 'monthly' -SimpleMatch
        $Hits | Should -BeNullOrEmpty
    }
}
