# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./tests

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The test helper only writes fixtures into TestDrive.')]
param ()

# ===========================================================================
# ======================   RENDER API DOCUMENTATION   =======================
# ===========================================================================
#
#   example_spec           Renders the example spec with title and operation count.
#   default_output         Writes API.html next to the spec by default.
#   title_escaped          HTML-encodes the title.
#   script_breakout        Keeps a closing script tag in spec strings from ending the block.
#   placeholder_in_title   Never replaces a placeholder inside the title again.
#   invalid_json           Fails early on invalid JSON.
#   missing_file           Fails early on a missing file.
#

BeforeAll {
    $SCRIPT_PATH  = Join-Path -Path $PSScriptRoot -ChildPath '../scripts/ConvertTo-UnwireHtml.ps1'
    $EXAMPLE_SPEC = Join-Path -Path $PSScriptRoot -ChildPath '../../../../../examples/grafana/openapi.json'
    # The embedded spec between the JSON script tags of the page
    $SPEC_BLOCK   = '(?s)<script type="application/json" id="unwire-spec">(?<json>.*?)</script>'

    # Writes a spec into its own TestDrive folder and returns its path.
    function Set-TestSpec {
        param ([System.String] $Title, [System.String] $Description = '')
        $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
        $null   = New-Item -ItemType Directory -Path $folder
        $file   = Join-Path -Path $folder -ChildPath 'openapi.json'
        @{ openapi = '3.1.0'; info = @{ title = $Title; version = '1'; description = $Description }; paths = @{} } | ConvertTo-Json -Depth 5 | Set-Content -Path $file
        return $file
    }
}

Describe 'ConvertTo-UnwireHtml' {
    It 'example_spec: renders the example spec with title and operation count' {
        $outputFile = Join-Path -Path $TestDrive -ChildPath 'example.html'

        $result = & $SCRIPT_PATH -Path $EXAMPLE_SPEC -OutputFile $outputFile
        $html   = Get-Content -Path $outputFile -Raw

        $result.Title      | Should -Be 'Grafana (NAS dashboard)'
        $result.Operations | Should -Be 6
        $html              | Should -Match '<title>Grafana \(NAS dashboard\)</title>'
        $html              | Should -Not -Match '__UNWIRE_'
    }

    It 'default_output: writes API.html next to the spec by default' {
        $specFile = Set-TestSpec -Title 'Router'

        $result = & $SCRIPT_PATH -Path $specFile

        $result.OutputFile | Should -Be (Join-Path -Path (Split-Path -Path $specFile -Parent) -ChildPath 'API.html')
        $result.OutputFile | Should -Exist
    }

    It 'title_escaped: HTML-encodes the title' {
        $specFile = Set-TestSpec -Title '<b>Router</b> & NAS'

        $result = & $SCRIPT_PATH -Path $specFile

        Get-Content -Path $result.OutputFile -Raw | Should -Match ([System.Text.RegularExpressions.Regex]::Escape('<title>&lt;b&gt;Router&lt;/b&gt; &amp; NAS</title>'))
    }

    It 'script_breakout: keeps a closing script tag in spec strings from ending the script block' {
        $description = '</script><script>alert(1)</script><!-- x'
        $specFile    = Set-TestSpec -Title 'Router' -Description $description

        $result = & $SCRIPT_PATH -Path $specFile
        $html   = Get-Content -Path $result.OutputFile -Raw
        $block  = [System.Text.RegularExpressions.Regex]::Match($html, $SPEC_BLOCK).Groups['json'].Value

        $html                                     | Should -Not -Match ([System.Text.RegularExpressions.Regex]::Escape('<script>alert(1)'))
        ($block | ConvertFrom-Json).info.description | Should -Be $description
    }

    It 'placeholder_in_title: never replaces a placeholder inside the title again' {
        $specFile = Set-TestSpec -Title '__UNWIRE_SPEC_JSON__'

        $result = & $SCRIPT_PATH -Path $specFile

        Get-Content -Path $result.OutputFile -Raw | Should -Match '<title>__UNWIRE_SPEC_JSON__</title>'
    }

    It 'invalid_json: fails early on invalid JSON' {
        $file = Join-Path -Path $TestDrive -ChildPath 'broken.json'
        Set-Content -Path $file -Value '{ "openapi": '

        { & $SCRIPT_PATH -Path $file } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*must contain valid JSON*'
    }

    It 'missing_file: fails early on a missing file' {
        { & $SCRIPT_PATH -Path (Join-Path -Path $TestDrive -ChildPath 'nope.json') } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*must be an existing openapi.json file*'
    }
}
