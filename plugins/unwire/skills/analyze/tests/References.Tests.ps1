# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./tests

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
param ()

# ===========================================================================
# ===========================   REFERENCE SPECS   ===========================
# ===========================================================================
#
#   references exist   At least two references, a simple and a hard one.
#   valid_spec         Every reference passes Test-UnwireSpec without a finding.
#   marked             Every reference carries x-unwire-reference and a target.
#   no_vendor          No product or vendor name in a reference.
#   named_in_skill     SKILL.md names every reference file.
#   hard_case          The hard reference shows a session, a guess and a write.
#

BeforeDiscovery {
    $REFERENCE_FOLDER = Join-Path -Path $PSScriptRoot -ChildPath '../references'
    $References = Get-ChildItem -Path $REFERENCE_FOLDER -Filter '*.openapi.json' | ForEach-Object { @{ Name = $_.Name; File = $_.FullName } }
}

BeforeAll {
    $SPEC_CHECK = Join-Path -Path $PSScriptRoot -ChildPath '../../../shared/Test-UnwireSpec.ps1'
    $SKILL_FILE = Join-Path -Path $PSScriptRoot -ChildPath '../SKILL.md'
    # Names the plugin must not ship: products seen in the testbed or in real runs.
    $VENDOR_NAMES = '(?i)juice|gitea|grafana|kuma|fritz|tp-?link|synology|qnap|netgear|asus|ubiquiti|openwrt|home ?assistant|pi-?hole|owasp'
}

Describe 'Reference specs' {
    It 'references exist: two or more' {
        @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '../references') -Filter '*.openapi.json').Count | Should -BeGreaterOrEqual 2
    }

    It 'valid_spec: <Name> passes Test-UnwireSpec without a finding' -ForEach $References {
        @(& $SPEC_CHECK -Path $File) | Should -HaveCount 0
    }

    It 'marked: <Name> carries x-unwire-reference and an http(s) target' -ForEach $References {
        $spec = Get-Content -Path $File -Raw | ConvertFrom-Json -AsHashtable

        $spec['x-unwire-reference'] | Should -BeTrue
        $spec['x-unwire-target']    | Should -Match '^https?://'
    }

    It 'no_vendor: <Name> names no product or vendor' -ForEach $References {
        Get-Content -Path $File -Raw | Should -Not -Match $VENDOR_NAMES
    }

    It 'named_in_skill: SKILL.md names <Name>' -ForEach $References {
        Get-Content -Path $SKILL_FILE -Raw | Should -Match ([System.Text.RegularExpressions.Regex]::Escape($Name))
    }

    It 'hard_case: the hard reference shows a session, a guess with reasons and a write' {
        $spec       = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath '../references/reference.hard.openapi.json') -Raw | ConvertFrom-Json -AsHashtable
        $operations = @($spec['paths'].Values | ForEach-Object { $_.Values })

        $spec['components']['securitySchemes'].Count                                          | Should -BeGreaterThan 0
        @($operations | Where-Object { $_['x-unwire-confidence'] -EQ 'low' -AND $_['x-unwire-open'].Count -GT 0 }).Count | Should -BeGreaterThan 0
        @($operations | Where-Object { $_['x-unwire-impact'] -EQ 'write' }).Count             | Should -BeGreaterThan 0
        @($operations | Where-Object { $_['security'].Count -EQ 0 }).Count                    | Should -BeGreaterThan 0
    }
}
