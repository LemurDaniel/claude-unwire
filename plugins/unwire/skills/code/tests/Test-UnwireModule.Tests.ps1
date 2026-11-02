# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./tests

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
param ()

# ===========================================================================
# =======================   CHECK GENERATED MODULES   =======================
# ===========================================================================
#
#   reference_passes        The reference module passes, import included.
#   picked_missing          A picked operation without a function is an error.
#   not_picked              A function for an operation not picked is a warning.
#   picked_comma_list       A comma list in one string counts as single picks,
#                           also through pwsh -File.
#   wrong_path              A path or method other than the spec's is an error.
#   write_without_confirm   A write without ConfirmImpact High is an error.
#   unsure_without_warning  A low or medium operation without Write-Warning is an error.
#   security_mismatch       Security other than the spec's is an error.
#   request_outside         A request command outside the wrapper is an error.
#   storage                 Writing a file or an environment variable is an error.
#   redirect                A wrapper that follows redirects is an error.
#   manifest                Exports and dot-sources must list every function.
#   guide                   A missing GETTING_STARTED.md, or one without the
#                           import or the connect, is an error.
#   naming                  A function without an approved verb and the prefix is an error.
#   schemes                 A scheme other than the spec's is an error.
#   chapters                Sections outside a chapter, a chapter missing in the
#                           table of contents or a short banner is an error.
#   parse                   A syntax error is an error and skips the import.
#   import                  A module that fails to import is an error.
#

BeforeAll {
    $SCRIPT_PATH      = Join-Path -Path $PSScriptRoot -ChildPath '../scripts/Test-UnwireModule.ps1'
    $REFERENCE_MODULE = Join-Path -Path $PSScriptRoot -ChildPath '../references/ReferenceHard'
    $REFERENCE_SPEC   = Join-Path -Path $PSScriptRoot -ChildPath '../../analyze/references/reference.hard.openapi.json'
    $PICKED           = @('listAccounts', 'lockAccount', 'saveSettings', 'startJob', 'enterStandby')

    function Edit-TestFile {
        param (
            [System.String] $RelativePath,
            [System.String] $OldText,
            [System.String] $NewText
        )

        $file = Join-Path -Path $ModulePath -ChildPath $RelativePath
        $text = Get-Content -Path $file -Raw
        # A replacement that misses would let a test pass for the wrong reason.
        $text.Contains($OldText) | Should -BeTrue -Because "'$OldText' must be in $RelativePath"
        Set-Content -Path $file -Value $text.Replace($OldText, $NewText) -NoNewline
    }

    function Invoke-TestCheck {
        param (
            [System.String[]] $OperationId = $PICKED,
            [System.Management.Automation.SwitchParameter] $WithImport
        )

        return @(& $SCRIPT_PATH -Path $ModulePath -Spec $REFERENCE_SPEC -OperationId $OperationId -SkipImport:(-NOT $WithImport.IsPresent))
    }
}

Describe 'Test-UnwireModule' {
    BeforeEach {
        $ModulePath = Join-Path -Path $TestDrive -ChildPath 'ReferenceHard'
        if (Test-Path -Path $ModulePath) {
            Remove-Item -Path $ModulePath -Recurse -Force
        }
        Copy-Item -Path $REFERENCE_MODULE -Destination $ModulePath -Recurse
    }

    It 'reference_passes: the reference module has no finding, import included' {
        Invoke-TestCheck -WithImport | Should -HaveCount 0
    }

    It 'picked_missing: a picked operation without a function is an error' {
        $findings = Invoke-TestCheck -OperationId ($PICKED + 'createSession')

        $findings                  | Should -HaveCount 1
        $findings[0].Severity      | Should -Be 'Error'
        $findings[0].Rule          | Should -Be 'selection'
        $findings[0].Message       | Should -BeLike "*'createSession' (POST /api/v1/auth/session)*"
    }

    It 'not_picked: a function for an operation not picked is a warning' {
        $findings = Invoke-TestCheck -OperationId 'listAccounts'

        $findings                              | Should -HaveCount 4
        $findings.Severity | Sort-Object -Unique | Should -Be 'Warning'
        $findings.Rule | Sort-Object -Unique   | Should -Be 'selection'
    }

    It 'picked_comma_list: a comma list in one string counts as single picks' {
        Invoke-TestCheck -OperationId ($PICKED -join ', ') | Should -HaveCount 0
    }

    It 'picked_comma_list: pwsh -File passes the comma list as one string, it still counts' {
        $output = & pwsh -NoProfile -File $SCRIPT_PATH -Path $ModulePath -Spec $REFERENCE_SPEC -OperationId ($PICKED -join ',') -SkipImport

        $LASTEXITCODE | Should -Be 0
        $output       | Should -BeNullOrEmpty
    }

    It 'wrong_path: a path other than the spec is an error in the note and the request' {
        Edit-TestFile -RelativePath 'functions/accounts/_data.sources/Get-ReferenceHardAccount.ps1' -OldText '/api/v1/accounts' -NewText '/api/v1/account'

        $findings = Invoke-TestCheck
        $findings.Rule     | Should -Be @('operation', 'operation')
        $findings.Location | Should -Be @('functions/accounts/_data.sources/Get-ReferenceHardAccount.ps1', 'functions/accounts/_data.sources/Get-ReferenceHardAccount.ps1')
    }

    It 'write_without_confirm: a write without ConfirmImpact High is an error' {
        Edit-TestFile -RelativePath 'functions/power/Suspend-ReferenceHardDevice.ps1' -OldText "SupportsShouldProcess = `$true,`n        ConfirmImpact = 'High'" -NewText 'SupportsShouldProcess = $true'

        $findings = Invoke-TestCheck
        $findings          | Should -HaveCount 1
        $findings[0].Rule  | Should -Be 'write'
        $findings[0].Message | Should -BeLike "*'enterStandby'*"
    }

    It 'unsure_without_warning: a low operation without Write-Warning is an error' {
        Edit-TestFile -RelativePath 'functions/jobs/Start-ReferenceHardJob.ps1' -OldText "Write-Warning '[Start-ReferenceHardJob]" -NewText "Write-Verbose '[Start-ReferenceHardJob]"

        $findings = Invoke-TestCheck
        $findings            | Should -HaveCount 1
        $findings[0].Rule    | Should -Be 'warning'
        $findings[0].Message | Should -BeLike "*'startJob' has confidence low*"
    }

    It 'security_mismatch: an operation without the scheme of the spec is an error' {
        Edit-TestFile -RelativePath 'functions/accounts/_data.sources/Get-ReferenceHardAccount.ps1' -OldText "Security = @('tokenAuth')" -NewText 'Security = @()'

        $findings = Invoke-TestCheck
        $findings            | Should -HaveCount 1
        $findings[0].Rule    | Should -Be 'security'
        $findings[0].Message | Should -BeLike "*Security = @('tokenAuth')*got @()*"
    }

    It 'request_outside: <Command> outside the wrapper is an error' -ForEach @(
        @{ Command = 'Invoke-RestMethod'; Line = "Invoke-RestMethod -Uri 'http://nas.example.test/'" }
        @{ Command = 'HttpClient'; Line = '$client = [System.Net.Http.HttpClient]::new()' }
    ) {
        Edit-TestFile -RelativePath 'functions/session/Disconnect-ReferenceHard.ps1' -OldText '    $script:ReferenceHardSession = $null' -NewText "    $Line`n    `$script:ReferenceHardSession = `$null"

        $findings = Invoke-TestCheck
        $findings            | Should -HaveCount 1
        $findings[0].Rule    | Should -Be 'request'
        $findings[0].Message | Should -BeLike "*$Command*"
    }

    It 'storage: <Case> is an error' -ForEach @(
        @{ Case = 'Export-Clixml'; Line = '$Secrets | Export-Clixml -Path ./session.xml' }
        @{ Case = 'an environment variable'; Line = '$env:NAS_TOKEN = ''x''' }
        @{ Case = 'a global variable'; Line = '$global:NasSecrets = $Secrets' }
    ) {
        Edit-TestFile -RelativePath 'functions/session/Connect-ReferenceHard.ps1' -OldText '    $script:ReferenceHardSession = [PSCustomObject]@{' -NewText "    $Line`n    `$script:ReferenceHardSession = [PSCustomObject]@{"

        $findings = Invoke-TestCheck
        $findings          | Should -HaveCount 1
        $findings[0].Rule  | Should -Be 'storage'
    }

    It 'redirect: a wrapper without MaximumRedirection 0 is an error' {
        Edit-TestFile -RelativePath 'functions/Invoke-ReferenceHardRest.ps1' -OldText 'MaximumRedirection   = 0' -NewText 'MaximumRedirection   = 5'

        $findings = Invoke-TestCheck
        $findings            | Should -HaveCount 1
        $findings[0].Rule    | Should -Be 'request'
        $findings[0].Message | Should -BeLike '*MaximumRedirection = 0*'
    }

    It 'manifest: a function missing in <List> is an error' -ForEach @(
        @{ List = 'FunctionsToExport'; File = 'ReferenceHard.psd1'; OldText = "'Suspend-ReferenceHardDevice', "; NewText = '' }
        @{ List = 'the dot-sources'; File = 'ReferenceHard.psm1'; OldText = ". `"`$PSScriptRoot/functions/power/Suspend-ReferenceHardDevice.ps1`"`n"; NewText = '' }
    ) {
        Edit-TestFile -RelativePath $File -OldText $OldText -NewText $NewText

        $findings = Invoke-TestCheck
        $findings            | Should -HaveCount 1
        $findings[0].Rule    | Should -Be 'manifest'
        $findings[0].Message | Should -BeLike '*Suspend-ReferenceHardDevice*'
    }

    It 'guide: a module without GETTING_STARTED.md is an error' {
        Remove-Item -Path (Join-Path -Path $ModulePath -ChildPath 'GETTING_STARTED.md')
        $findings = Invoke-TestCheck

        $findings             | Should -HaveCount 1
        $findings[0].Rule     | Should -Be 'layout'
        $findings[0].Location | Should -Be 'GETTING_STARTED.md'
    }

    It 'guide: a GETTING_STARTED.md without <Missing> is an error' -ForEach @(
        @{ Missing = 'the import';  OldText = 'Import-Module ./ReferenceHard/ReferenceHard.psd1'; NewText = 'Import-Module ./Other.psd1' }
        @{ Missing = 'the connect'; OldText = 'Connect-ReferenceHard';                            NewText = 'Connect-Other' }
    ) {
        Edit-TestFile -RelativePath 'GETTING_STARTED.md' -OldText $OldText -NewText $NewText
        $findings = Invoke-TestCheck

        $findings            | Should -HaveCount 1
        $findings[0].Rule    | Should -Be 'layout'
        $findings[0].Message | Should -BeLike "*must show '$OldText'*"
    }

    It 'naming: a function without an approved verb and the prefix is an error' {
        $helper = Join-Path -Path $ModulePath -ChildPath 'functions/_helper/Do-Thing.ps1'
        $null   = New-Item -Path $helper -ItemType File -Force -Value "function Do-Thing {`n    return 1`n}`n"
        Edit-TestFile -RelativePath 'ReferenceHard.psd1' -OldText "'Set-ReferenceHardSetting'" -NewText "'Set-ReferenceHardSetting', 'Do-Thing'"
        Edit-TestFile -RelativePath 'ReferenceHard.psm1' -OldText '. "$PSScriptRoot/functions/settings/' -NewText ". `"`$PSScriptRoot/functions/_helper/Do-Thing.ps1`"`n. `"`$PSScriptRoot/functions/settings/"

        $findings = Invoke-TestCheck
        $findings            | Should -HaveCount 1
        $findings[0].Rule    | Should -Be 'naming'
        $findings[0].Message | Should -BeLike "'Do-Thing' must be*-ReferenceHard<Noun>*"
    }

    It 'schemes: a header name other than the spec is an error' {
        Edit-TestFile -RelativePath 'data/security.schemes.json' -OldText '"X-Auth-Token"' -NewText '"X-Token"'

        $findings = Invoke-TestCheck
        $findings            | Should -HaveCount 1
        $findings[0].Rule    | Should -Be 'schemes'
        $findings[0].Message | Should -BeLike "*name 'X-Auth-Token'*got 'X-Token'*"
    }

    It 'chapters: <Case> is an error' -ForEach @(
        @{ Case = 'a section outside a chapter'; OldText = "    # ============================   BUILD REQUEST   ============================`n"; NewText = '';                                                                           Expected = '*must stand inside a chapter*' }
        @{ Case = 'a chapter missing in the table of contents'; OldText = "#     SEND REQUEST    Asks before a write, sends and parses the answer.`n"; NewText = '';                                                         Expected = "*Chapter 'SEND REQUEST' must be in the 'Chapters:'*" }
        @{ Case = 'a banner of another width'; OldText = '    # Validations'; NewText = "    # Validations`n    # ----------";                                                                                             Expected = '*must be 75 characters*' }
    ) {
        Edit-TestFile -RelativePath 'functions/Invoke-ReferenceHardRest.ps1' -OldText $OldText -NewText $NewText

        $findings = Invoke-TestCheck
        $findings.Rule    | Should -Contain 'chapters'
        ($findings | Where-Object Rule -EQ 'chapters').Message | Should -BeLike $Expected
    }

    It 'parse: a syntax error is an error and skips the import' {
        Edit-TestFile -RelativePath 'functions/power/Suspend-ReferenceHardDevice.ps1' -OldText 'param ()' -NewText 'param ('

        $findings = Invoke-TestCheck -WithImport
        $findings.Rule | Should -Contain 'parse'
        $findings.Rule | Should -Not -Contain 'import'
    }

    It 'import: a module that throws on import is an error' {
        Edit-TestFile -RelativePath 'ReferenceHard.psm1' -OldText '$script:ReferenceHardSession = $null' -NewText "throw 'broken on import'"

        $findings = Invoke-TestCheck -WithImport
        $findings            | Should -HaveCount 1
        $findings[0].Rule    | Should -Be 'import'
        $findings[0].Message | Should -BeLike '*broken on import*'
    }
}
