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
#   title_and_count        Renders a spec with its title and operation count.
#   default_output         Writes API.html next to the spec by default.
#   file_uri               Returns a file URI to open the page in the browser.
#   confidence_legend      Explains every confidence level on the page.
#   example_current        examples/juiceshop/API.html matches the current template.
#   title_escaped          HTML-encodes the title.
#   script_breakout        Keeps a closing script tag in spec strings from ending the block.
#   favicon                Embeds the plugin icon as base64 SVG favicon.
#   no_network             The page never sends a request itself, it only builds commands.
#   try_it                 Builds PowerShell and cURL commands, session values never stored,
#                          cookie names editable.
#   placeholder_in_title   Never replaces a placeholder inside the title again.
#   invalid_json           Fails early on invalid JSON.
#   missing_file           Fails early on a missing file.
#

BeforeAll {
    $SCRIPT_PATH = Join-Path -Path $PSScriptRoot -ChildPath '../scripts/ConvertTo-UnwireHtml.ps1'
    # The embedded spec between the JSON script tags of the page
    $SPEC_BLOCK  = '(?s)<script type="application/json" id="unwire-spec">(?<json>.*?)</script>'

    # Writes a spec into its own TestDrive folder and returns its path.
    function Set-TestSpec {
        param ([System.String] $Title, [System.String] $Description = '', [System.Collections.IDictionary] $Paths = @{})
        $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
        $null   = New-Item -ItemType Directory -Path $folder
        $file   = Join-Path -Path $folder -ChildPath 'openapi.json'
        @{ openapi = '3.1.0'; info = @{ title = $Title; version = '1'; description = $Description }; paths = $Paths } | ConvertTo-Json -Depth 10 | Set-Content -Path $file
        return $file
    }
}

Describe 'ConvertTo-UnwireHtml' {
    It 'title_and_count: renders a spec with its title and operation count' {
        $paths = @{
            '/api/devices'      = @{ get = @{ responses = @{} }; post = @{ responses = @{} } }
            '/api/devices/{id}' = @{ get = @{ responses = @{} }; parameters = @() }
        }
        $outputFile = Join-Path -Path $TestDrive -ChildPath 'router.html'

        $result = & $SCRIPT_PATH -Path (Set-TestSpec -Title 'Router (home)' -Paths $paths) -OutputFile $outputFile
        $html   = Get-Content -Path $outputFile -Raw

        $result.Title      | Should -Be 'Router (home)'
        $result.Operations | Should -Be 3
        $html              | Should -Match '<title>Router \(home\)</title>'
        $html              | Should -Not -Match '__UNWIRE_'
    }

    It 'default_output: writes API.html next to the spec by default' {
        $specFile = Set-TestSpec -Title 'Router'

        $result = & $SCRIPT_PATH -Path $specFile

        $result.OutputFile | Should -Be (Join-Path -Path (Split-Path -Path $specFile -Parent) -ChildPath 'API.html')
        $result.OutputFile | Should -Exist
    }

    It 'file_uri: returns a file URI to open the page in the browser' {
        $outputFile = Join-Path -Path $TestDrive -ChildPath 'with space/API.html'

        $result = & $SCRIPT_PATH -Path (Set-TestSpec -Title 'Router') -OutputFile $outputFile

        $result.FileUri                          | Should -BeLike 'file:///*/with%20space/API.html'
        ([System.Uri] $result.FileUri).LocalPath | Should -Be ([System.IO.Path]::GetFullPath($outputFile))
    }

    It 'confidence_legend: explains every confidence level on the page' {
        $result = & $SCRIPT_PATH -Path (Set-TestSpec -Title 'Router')
        $html   = Get-Content -Path $result.OutputFile -Raw

        $html | Should -Match "high:\s+'path and body appear literally in the code'"
        $html | Should -Match "medium:\s+'assembled from parts of the code'"
        $html | Should -Match "low:\s+'guessed from hints in the code'"
        $html | Should -Match 'None of them is verified\.'
    }

    It 'example_current: examples/juiceshop/API.html matches the current template' {
        $exampleFolder = Join-Path -Path $PSScriptRoot -ChildPath '../../../../../examples/juiceshop'
        $outputFile    = Join-Path -Path $TestDrive -ChildPath 'juiceshop.html'

        $null = & $SCRIPT_PATH -Path (Join-Path -Path $exampleFolder -ChildPath 'openapi.json') -OutputFile $outputFile

        # A template change without re-rendering the example fails here.
        Get-Content -Path $outputFile -Raw | Should -BeExactly (Get-Content -Path (Join-Path -Path $exampleFolder -ChildPath 'API.html') -Raw) -Because 'the example is re-rendered after every template change'
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

    It 'favicon: embeds the plugin icon as base64 SVG' {
        $specFile = Set-TestSpec -Title 'Router'
        $iconFile = Join-Path -Path $PSScriptRoot -ChildPath '../../../assets/icon.svg'

        $result = & $SCRIPT_PATH -Path $specFile
        $html   = Get-Content -Path $result.OutputFile -Raw
        $match  = [System.Text.RegularExpressions.Regex]::Match($html, '<link rel="icon" type="image/svg\+xml" href="data:image/svg\+xml;base64,(?<data>[A-Za-z0-9+/=]+)">')

        $match.Success                                                    | Should -BeTrue
        [System.Convert]::FromBase64String($match.Groups['data'].Value) | Should -Be ([System.IO.File]::ReadAllBytes($iconFile))
    }

    It 'no_network: the page never sends a request itself, it only builds commands' {
        $template = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath '../templates/tmpl.api.html') -Raw

        # A file:// page cannot read answers of other origins, but a form POST would still fire.
        $template | Should -Not -Match '\bfetch\s*\(|XMLHttpRequest|sendBeacon|new\s+WebSocket|EventSource|\.submit\s*\(|<form\b'
    }

    It 'try_it: builds PowerShell and cURL commands, session values never stored' {
        $template = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath '../templates/tmpl.api.html') -Raw
        $script   = [System.Text.RegularExpressions.Regex]::Match($template, '(?s)// =+\s+BUILD COMMANDS\s+=+.*?// =+\s+RENDER OPERATIONS').Value

        $script | Should -Match 'Invoke-WebRequest @request'
        $script | Should -Match 'curl -i -X'
        $script | Should -Match "type: 'password'"
        $script | Should -Match "\['x-unwire-value-prefix'\]"
        $script | Should -Match "return 'Bearer '"
        $script | Should -Match "return 'Basic '"
        # The filled-in alternative wins over the first one of the spec.
        $script | Should -Match 'every\(name => trySettings\.secrets\[name\]\)'
        # The cookie name is editable, the spec may only guess it.
        $script | Should -Match "className: 'cookie-name'"
        $script | Should -Match 'trySettings\.cookieNames\[name\] = cookieName\.value'
        $script | Should -Match '\$\{cookieNameOf\(name, scheme\)\}=\$\{value\}'
        # Basic takes user and password, the page encodes them UTF-8 safe.
        $script | Should -Match "className: 'basic-user'"
        $script | Should -Match 'toBase64\(`\$\{user\.value\}:\$\{input\.value\}`\)'
        $script | Should -Match 'btoa\(Array\.from\(new TextEncoder\(\)\.encode\(text\)'
        $script | Should -Not -Match 'localStorage|sessionStorage|indexedDB|document\.cookie'
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
