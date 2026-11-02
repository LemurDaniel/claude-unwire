# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./plugins/unwire

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
param ()

# ===========================================================================
# =======================   CHECK PWSH INSTALL DATA   =======================
# ===========================================================================
#
#   minimum_version     The check asks for PowerShell 7 or newer.
#   platform_commands   Windows and macOS have a command, Linux only a link.
#   language_keys       Every language has the same texts and placeholders.
#   question_limits     Header and labels fit the AskUserQuestion limits.
#

BeforeAll {
    $DATA_PATH = Join-Path -Path $PSScriptRoot -ChildPath '../data/pwsh-install.json'
    $Data      = Get-Content -Path $DATA_PATH -Raw | ConvertFrom-Json -AsHashtable
}

Describe 'pwsh-install.json' {
    It 'minimum_version: the check asks for PowerShell 7 or newer' {
        $Data.minimumMajor | Should -Be 7
        $Data.check        | Should -BeLike 'pwsh -NoProfile *PSVersion.Major*'
    }

    It 'platform_commands: <Platform> has the expected command' -ForEach @(
        @{ Platform = 'windows'; Command = 'winget install --id Microsoft.PowerShell --exact --source winget' }
        @{ Platform = 'macos';   Command = 'brew install --cask powershell' }
        @{ Platform = 'linux';   Command = $null }
    ) {
        $Data.platforms[$Platform].command | Should -Be $Command
        $Data.platforms[$Platform].docs    | Should -BeLike 'https://learn.microsoft.com/powershell/*'
    }

    It 'language_keys: <Language> has the texts and placeholders of en' -ForEach @(
        @{ Language = 'de' }
    ) {
        $text = $Data[$Language]

        @($text.Keys | Sort-Object)       | Should -Be @($Data.en.Keys | Sort-Object)
        @($text.found.Keys | Sort-Object) | Should -Be @($Data.en.found.Keys | Sort-Object)
        foreach ($placeholder in '{FOUND}', '{COMMAND}', '{DOCS}') {
            $text.question | Should -BeLike "*$placeholder*"
        }
        $text.found.outdated | Should -BeLike '*{VERSION}*'
    }

    It 'question_limits: <Language> fits the AskUserQuestion limits' -ForEach @(
        @{ Language = 'en' }
        @{ Language = 'de' }
    ) {
        $text = $Data[$Language]

        # Header chip: at most 12 characters, labels: 1 to 5 words
        $text.header.Length | Should -BeLessOrEqual 12
        foreach ($option in 'self', 'claude', 'cancel') {
            ($text[$option].label -split ' ').Count | Should -BeLessOrEqual 5
            $text[$option].description              | Should -Not -BeNullOrEmpty
        }
    }
}
