# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./tests

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The test helpers only write fixtures into TestDrive.')]
param ()

# ===========================================================================
# ===========================   CHECK COVERAGE   ============================
# ===========================================================================
#
#   by_source          Counts a candidate whose position an x-unwire-source names.
#   by_path            Counts a literal path that matches a spec path, templates included.
#   base_and_suffix    Matches a base string as start, 'base + "/x"' as end of a path.
#   unresolved_call    Reports a call on an unknown base without a citation as missing.
#   column_tolerance   Tells two calls on one minified line apart by their column.
#   by_note            Counts positions named in an open point, as list and as range.
#   external           Puts a target on another origin aside, not missing.
#   server_prefix      Applies the path of the first server before matching.
#   missing_file       Fails early on a missing candidates file.
#

BeforeAll {
    $SCRIPT_PATH = Join-Path -Path $PSScriptRoot -ChildPath '../scripts/Test-UnwireCoverage.ps1'

    # One candidate as Get-UnwireJsCandidate writes it.
    function New-TestCandidate {
        param ([System.String] $File = 'assets/app.js', [System.Int32] $Line = 1, [System.Int32] $Column = 1, [System.String] $Kind = 'fetch', [System.String] $Target, [System.Boolean] $IsLiteral = $true, [System.String] $Method = 'GET')
        return @{ File = $File; Line = $Line; Column = $Column; Kind = $Kind; Method = $Method; Target = $Target; IsLiteralTarget = $IsLiteral; Snippet = '' }
    }

    # Writes the spec and candidates into a fresh folder, returns both paths.
    function Set-TestInput {
        param ([System.Collections.IDictionary] $Paths = @{}, [System.Object[]] $Candidates = @(), [System.String[]] $RootOpen = @(), [System.String] $Server = '/')
        $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
        $null   = New-Item -ItemType Directory -Path $folder
        $spec   = @{ openapi = '3.1.0'; info = @{ title = 'T'; version = '1' }; servers = @(@{ url = $Server }); paths = $Paths; 'x-unwire-open' = $RootOpen }
        $spec | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $folder 'openapi.json')
        @{ candidates = $Candidates } | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $folder 'candidates.json')
        return @{ Path = Join-Path $folder 'openapi.json'; CandidateFile = Join-Path $folder 'candidates.json' }
    }

    function New-TestOperation {
        param ([System.String] $Source = 'assets/other.js:99')
        return @{ responses = @{}; 'x-unwire-source' = $Source }
    }
}

Describe 'Test-UnwireCoverage' {
    It 'by_source: counts a candidate whose position an x-unwire-source names' {
        $input_ = Set-TestInput -Paths @{ '/x' = @{ get = (New-TestOperation -Source 'assets/app.js:12') } } -Candidates @(
            New-TestCandidate -File 'app.js' -Line 12 -Column 5 -Target 'api.url' -IsLiteral $false
        )

        $result = & $SCRIPT_PATH @input_

        $result.Operation     | Should -Be 1
        $result.Missing.Count | Should -Be 0
    }

    It 'by_path: counts a literal path that matches a spec path, templates included' {
        $input_ = Set-TestInput -Paths @{ '/api/devices/{mac}/block' = @{ post = (New-TestOperation) }; '/api/status' = @{ get = (New-TestOperation) } } -Candidates @(
            New-TestCandidate -Target '/api/status?v=2' -Line 1
            New-TestCandidate -Target '/api/devices/${mac}/block' -Kind 'url-template' -Line 2
            New-TestCandidate -Target '/api/unknown' -Line 3
        )

        $result = & $SCRIPT_PATH @input_

        $result.Path              | Should -Be 2
        $result.Missing.Target    | Should -Be @('/api/unknown')
    }

    It 'base_and_suffix: matches a base string as start, base + "/x" as end of a path' {
        $input_ = Set-TestInput -Paths @{ '/api/Products/{id}' = @{ get = (New-TestOperation) }; '/rest/continue-code/apply/{continueCode}' = @{ put = (New-TestOperation) } } -Candidates @(
            New-TestCandidate -Target '/api/Products' -Kind 'url-string' -Line 1
            New-TestCandidate -Target 'this.hostServer+"/rest/continue-code/apply/"' -IsLiteral $false -Kind 'http-client' -Line 2
            New-TestCandidate -Target '${this.host}/${e}' -Kind 'http-client' -Line 3
        )

        $result = & $SCRIPT_PATH @input_

        $result.Path              | Should -Be 2
        # '${this.host}/${e}' has no fixed segment: it would match every path, so it needs a citation.
        $result.Missing.Line      | Should -Be @(3)
    }

    It 'unresolved_call: reports a call on an unknown base without a citation as missing' {
        $input_ = Set-TestInput -Paths @{ '/api/Products/{id}' = @{ get = (New-TestOperation -Source 'assets/main.js:1:400') } } -Candidates @(
            New-TestCandidate -File 'main.js' -Column 300 -Target 'this.host+"/"' -IsLiteral $false -Kind 'http-client'
            New-TestCandidate -File 'main.js' -Column 400 -Target '${this.host}/${e}' -Kind 'http-client'
        )

        $result = & $SCRIPT_PATH @input_

        $result.Operation         | Should -Be 1
        $result.Missing.Column    | Should -Be @(300)
    }

    It 'column_tolerance: tells two calls on one minified line apart by their column' {
        $input_ = Set-TestInput -Paths @{ '/a' = @{ get = (New-TestOperation -Source 'assets/main.js:1:1005') } } -Candidates @(
            New-TestCandidate -File 'main.js' -Column 1000 -Target 'x' -IsLiteral $false
            New-TestCandidate -File 'main.js' -Column 1100 -Target 'y' -IsLiteral $false
        )

        $result = & $SCRIPT_PATH @input_

        $result.Operation         | Should -Be 1
        $result.Missing.Target    | Should -Be @('y')
    }

    It 'by_note: counts positions named in an open point, as list and as range' {
        $notes  = @('Helpers left out: assets/app.js:13, 18 (api.get, api.post).', 'Wallet library: assets/98.js:1:189000-193500.')
        $input_ = Set-TestInput -RootOpen $notes -Candidates @(
            New-TestCandidate -File 'app.js' -Line 13 -Target 'api.url' -IsLiteral $false
            New-TestCandidate -File 'app.js' -Line 18 -Target 'api.url' -IsLiteral $false
            New-TestCandidate -File '98.js' -Line 1 -Column 190625 -Target 'proxy'
            New-TestCandidate -File '98.js' -Line 1 -Column 202524 -Target '/v3/' -Kind 'url-string'
        )

        $result = & $SCRIPT_PATH @input_

        $result.Note              | Should -Be 3
        $result.Missing.Column    | Should -Be @(202524)
    }

    It 'external: puts a target on another origin aside, not missing' {
        $input_ = Set-TestInput -Candidates @(New-TestCandidate -Target 'https://cdn.test/list.json')

        $result = & $SCRIPT_PATH @input_

        $result.External          | Should -Be 1
        $result.Missing.Count     | Should -Be 0
    }

    It 'server_prefix: applies the path of the first server before matching' {
        $input_ = Set-TestInput -Server 'http://router.test/api/v1' -Paths @{ '/devices' = @{ get = (New-TestOperation) } } -Candidates @(New-TestCandidate -Target '/api/v1/devices')

        $result = & $SCRIPT_PATH @input_

        $result.Path              | Should -Be 1
    }

    It 'missing_file: fails early on a missing candidates file' {
        $input_ = Set-TestInput
        Remove-Item -Path $input_.CandidateFile

        { & $SCRIPT_PATH @input_ } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*must be existing files*'
    }
}
