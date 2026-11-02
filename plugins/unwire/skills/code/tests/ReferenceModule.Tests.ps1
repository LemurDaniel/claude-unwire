# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./tests

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The tests connect with fake test tokens.')]
param ()

# ===========================================================================
# ==========================   REFERENCE MODULE   ===========================
# ===========================================================================
#
#   no_vendor          No product or vendor name in the reference module.
#   named_in_skill     SKILL.md names the reference module and its spec.
#   meta_operations    meta.json lists the operations the module covers.
#   no_request         Importing and connecting send nothing.
#   request_shape      The wrapper sends method, url, header and body of the spec.
#   path_token         A path token goes after its prefix, never into a log.
#   write_whatif       -WhatIf on a write sends nothing.
#   no_session         Without Connect the wrapper fails before sending.
#

BeforeAll {
    $REFERENCE_ROOT = Join-Path -Path $PSScriptRoot -ChildPath '../references'
    $MODULE_FILE    = Join-Path -Path $REFERENCE_ROOT -ChildPath 'ReferenceHard/ReferenceHard.psd1'
    $SKILL_FILE     = Join-Path -Path $PSScriptRoot -ChildPath '../SKILL.md'
    # Names the plugin must not ship: products seen in the testbed or in real runs.
    $VENDOR_NAMES   = '(?i)juice|gitea|grafana|kuma|fritz|tp-?link|synology|qnap|netgear|asus|ubiquiti|openwrt|home ?assistant|pi-?hole|owasp'
    $TEST_TOKEN     = ConvertTo-SecureString -String 'test-token-123' -AsPlainText -Force

    Import-Module -Name $MODULE_FILE -Force
}

AfterAll {
    Remove-Module -Name ReferenceHard -Force -ErrorAction SilentlyContinue
}

Describe 'Reference module' {
    It 'no_vendor: no file of the reference names a product or vendor' {
        $files = Get-ChildItem -Path $REFERENCE_ROOT -Recurse -File
        $files.Count | Should -BeGreaterThan 0
        foreach ($file in $files) {
            Get-Content -Path $file.FullName -Raw | Should -Not -Match $VENDOR_NAMES -Because $file.Name
        }
    }

    It 'named_in_skill: SKILL.md names the reference module and its spec' {
        $skill = Get-Content -Path $SKILL_FILE -Raw
        $skill | Should -Match 'references/ReferenceHard'
        $skill | Should -Match 'reference\.hard\.openapi\.json'
    }

    It 'meta_operations: meta.json lists the operations of the module' {
        $meta  = Get-Content -Path (Join-Path -Path $REFERENCE_ROOT -ChildPath 'ReferenceHard/meta.json') -Raw | ConvertFrom-Json
        $notes = Get-ChildItem -Path (Join-Path -Path $REFERENCE_ROOT -ChildPath 'ReferenceHard/functions') -Recurse -Filter '*.ps1'
        | Select-String -Pattern 'Operation:\s+\w+\s+\S+\s+\((?<id>[^)]+)\)'
        | ForEach-Object { $_.Matches[0].Groups['id'].Value }

        $meta.unwire.operations | Sort-Object | Should -Be ($notes | Sort-Object)
    }
}

Describe 'Reference module requests' {
    BeforeEach {
        Mock -ModuleName ReferenceHard Invoke-WebRequest {
            [PSCustomObject]@{
                StatusCode = 200
                Headers    = @{ 'Content-Type' = @('application/json') }
                Content    = '{"accounts":[{"login":"admin","isAdmin":true}]}'
            }
        }
        Disconnect-ReferenceHard
    }

    It 'no_request: importing and connecting send nothing' {
        Connect-ReferenceHard -BaseUrl 'https://nas.example.test:5443/' -TokenAuth $TEST_TOKEN

        Should -Invoke -ModuleName ReferenceHard Invoke-WebRequest -Times 0 -Exactly
    }

    It 'request_shape: GET with the token header, no redirects, the parsed answer' {
        Connect-ReferenceHard -BaseUrl 'https://nas.example.test:5443/' -TokenAuth $TEST_TOKEN

        $accounts = Get-ReferenceHardAccount

        $accounts.login | Should -Be 'admin'
        Should -Invoke -ModuleName ReferenceHard Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Method -EQ 'Get' -AND $Uri -EQ 'https://nas.example.test:5443/api/v1/accounts' -AND $Headers['X-Auth-Token'] -EQ 'test-token-123' -AND $MaximumRedirection -EQ 0
        }
    }

    It 'request_shape: POST escapes the path value and sends only the given body fields' {
        Connect-ReferenceHard -BaseUrl 'https://nas.example.test:5443' -TokenAuth $TEST_TOKEN

        Lock-ReferenceHardAccount -AccountId 'u 17' -Confirm:$false -WarningAction SilentlyContinue

        Should -Invoke -ModuleName ReferenceHard Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Method -EQ 'Post' -AND $Uri -EQ 'https://nas.example.test:5443/api/v1/accounts/u%2017/lock' -AND $Body -EQ '{}' -AND $ContentType -EQ 'application/json'
        }
    }

    It 'path_token: a path token goes after its prefix and stays out of the verbose log' {
        Connect-ReferenceHard -BaseUrl 'http://router.test/' -TokenAuth $TEST_TOKEN
        InModuleScope ReferenceHard {
            $script:SECURITY_SCHEMES['pathToken'] = @{ type = 'apiKey'; in = 'query'; name = 'tok'; 'x-unwire-in' = 'path'; 'x-unwire-path-prefix' = '/ui/' }
            $script:ReferenceHardSession.Secrets['pathToken'] = ConvertTo-SecureString -String 'path-secret-456' -AsPlainText -Force
        }

        $log = Invoke-ReferenceHardRest -Method GET -Path '/ui/status' -Security pathToken -Verbose 4>&1

        Should -Invoke -ModuleName ReferenceHard Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -EQ 'http://router.test/ui/;tok=path-secret-456/status' }
        ($log | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }).Message | Should -Not -Match 'path-secret-456'
        InModuleScope ReferenceHard { $null = $script:SECURITY_SCHEMES.Remove('pathToken') }
    }

    It 'write_whatif: -WhatIf on a write sends nothing' {
        Connect-ReferenceHard -BaseUrl 'https://nas.example.test:5443/' -TokenAuth $TEST_TOKEN

        Suspend-ReferenceHardDevice -WhatIf

        Should -Invoke -ModuleName ReferenceHard Invoke-WebRequest -Times 0 -Exactly
    }

    It 'no_session: without Connect the wrapper fails before sending' {
        { Get-ReferenceHardAccount } | Should -Throw '*Connect-ReferenceHard must run first*'

        Should -Invoke -ModuleName ReferenceHard Invoke-WebRequest -Times 0 -Exactly
    }
}
