# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./tests

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The test helper only writes fixtures into TestDrive.')]
param ()

# ===========================================================================
# ======================   FIND ENDPOINT CANDIDATES   =======================
# ===========================================================================
#
#   fetch_literal       Finds fetch with a literal path, method unknown.
#   fetch_options       Takes the method from the fetch options.
#   axios_no_dupe       Finds axios.post once, not again as http-client.
#   xhr_open            Finds XMLHttpRequest.open with method and path.
#   jquery_getjson      Maps $.getJSON to GET.
#   url_strings         Finds API paths and script endpoints as plain strings.
#   url_templates       Finds template URLs on a base variable, not pure variable paths.
#   dynamic_target      Marks a variable target as not literal.
#   line_column         Reports line and column of a hit in a multi-line file.
#   source_map          Prefers the map over its bundle, skips vendor sources.
#   include_vendor      Scans vendor sources with IncludeVendor.
#   output_file         Writes candidates.json and returns a summary.
#   missing_path        Fails early on a missing path.
#

BeforeAll {
    $SCRIPT_PATH = Join-Path -Path $PSScriptRoot -ChildPath '../scripts/Get-UnwireJsCandidate.ps1'

    # Writes one fixture file into a fresh folder and returns the folder.
    function Set-TestAsset {
        param ([System.String] $Name, [System.String] $Content)
        $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
        $null   = New-Item -ItemType Directory -Path $folder
        Set-Content -Path (Join-Path -Path $folder -ChildPath $Name) -Value $Content -NoNewline
        return $folder
    }
}

Describe 'Get-UnwireJsCandidate' {
    It 'fetch_literal: finds fetch with a literal path, method unknown' {
        $folder = Set-TestAsset -Name 'app.js' -Content "const r = fetch('/api/devices');"

        $hits = @(& $SCRIPT_PATH -Path $folder)

        $hits.Count              | Should -Be 1
        $hits[0].File            | Should -Be 'app.js'
        $hits[0].Kind            | Should -Be 'fetch'
        $hits[0].Target          | Should -Be '/api/devices'
        $hits[0].IsLiteralTarget | Should -BeTrue
        $hits[0].Method          | Should -BeNullOrEmpty
    }

    It 'fetch_options: takes the method from the fetch options' {
        $folder = Set-TestAsset -Name 'app.js' -Content "fetch('/api/wlan', {`n  method: 'POST',`n  body: JSON.stringify(cfg)`n})"

        $hits = @(& $SCRIPT_PATH -Path $folder)

        $hits[0].Method | Should -Be 'POST'
    }

    It 'axios_no_dupe: finds axios.post once, not again as http-client' {
        $folder = Set-TestAsset -Name 'app.js' -Content "axios.post('/api/wlan', body)"

        $hits = @(& $SCRIPT_PATH -Path $folder)

        $hits.Count     | Should -Be 1
        $hits[0].Kind   | Should -Be 'axios'
        $hits[0].Method | Should -Be 'POST'
        $hits[0].Target | Should -Be '/api/wlan'
    }

    It 'xhr_open: finds XMLHttpRequest.open with method and path' {
        $folder = Set-TestAsset -Name 'app.js' -Content 'xhr.open("GET", "/cgi-bin/status.cgi")'

        $hits = @(& $SCRIPT_PATH -Path $folder)

        $hits.Count     | Should -Be 1
        $hits[0].Kind   | Should -Be 'xhr'
        $hits[0].Method | Should -Be 'GET'
        $hits[0].Target | Should -Be '/cgi-bin/status.cgi'
    }

    It 'jquery_getjson: maps $.getJSON to GET' {
        $folder = Set-TestAsset -Name 'index.html' -Content "<script>`$.getJSON('/data.lua?page=overview', render)</script>"

        $hits = @(& $SCRIPT_PATH -Path $folder)

        $hits.Count     | Should -Be 1
        $hits[0].Kind   | Should -Be 'jquery'
        $hits[0].Method | Should -Be 'GET'
        $hits[0].Target | Should -Be '/data.lua?page=overview'
    }

    It 'url_strings: finds API paths and script endpoints as plain strings' {
        $folder = Set-TestAsset -Name 'app.js' -Content "const USERS = '/api/v1/users'; const DATA = `"data.lua`"; const LOGO = '/img/logo.png';"

        $hits = @(& $SCRIPT_PATH -Path $folder)

        $hits.Kind   | Should -Be @('url-string', 'url-string')
        $hits.Target | Should -Be @('/api/v1/users', 'data.lua')
    }

    It 'url_templates: finds template URLs on a base variable, not pure variable paths' {
        $folder = Set-TestAsset -Name 'app.js' -Content 'async function Kl(){let e=await X(`${Vl}/user/stopwatches`);let f=`${d}/${u}`;let g=`${e.repoLink}/issues/${n}`}'

        $hits = @(& $SCRIPT_PATH -Path $folder)

        $hits.Kind   | Should -Be @('url-template', 'url-template')
        $hits.Target | Should -Be @('${Vl}/user/stopwatches', '${e.repoLink}/issues/${n}')
    }

    It 'dynamic_target: marks a variable target as not literal' {
        $folder = Set-TestAsset -Name 'app.js' -Content 'fetch(this.baseUrl + path)'

        $hits = @(& $SCRIPT_PATH -Path $folder)

        $hits[0].Target          | Should -Be 'this.baseUrl'
        $hits[0].IsLiteralTarget | Should -BeFalse
    }

    It 'line_column: reports line and column of a hit in a multi-line file' {
        $folder = Set-TestAsset -Name 'app.js' -Content "// header`nconst a = 1;`n    fetch('/api/status')"

        $hits = @(& $SCRIPT_PATH -Path $folder)

        $hits[0].Line   | Should -Be 3
        $hits[0].Column | Should -Be 5
    }

    It 'source_map: prefers the map over its bundle, skips vendor sources' {
        $map = @{
            version        = 3
            sources        = @('webpack:///./src/api.ts', 'webpack:///node_modules/axios/lib/core.js')
            sourcesContent = @("export const getDevices = () => fetch('/api/devices')", "fetch('/vendor/internal')")
        } | ConvertTo-Json
        $folder = Set-TestAsset -Name 'bundle.js' -Content "fetch('/api/devices')"
        Set-Content -Path (Join-Path -Path $folder -ChildPath 'bundle.js.map') -Value $map

        $hits = @(& $SCRIPT_PATH -Path $folder)

        $hits.Count   | Should -Be 1
        $hits[0].File | Should -Be 'bundle.js.map::src/api.ts'
    }

    It 'include_vendor: scans vendor sources with IncludeVendor' {
        $map = @{
            version        = 3
            sources        = @('webpack:///./src/api.ts', 'webpack:///node_modules/axios/lib/core.js')
            sourcesContent = @("fetch('/api/devices')", "fetch('/vendor/internal')")
        } | ConvertTo-Json
        $folder = Set-TestAsset -Name 'bundle.js.map' -Content $map

        $hits = @(& $SCRIPT_PATH -Path $folder -IncludeVendor)

        $hits.Target | Should -Be @('/api/devices', '/vendor/internal')
    }

    It 'output_file: writes candidates.json and returns a summary' {
        $folder     = Set-TestAsset -Name 'app.js' -Content "fetch('/api/a'); axios.get('/api/b'); const C = '/api/c';"
        $outputFile = Join-Path -Path $TestDrive -ChildPath 'out/candidates.json'

        $summary = & $SCRIPT_PATH -Path $folder -OutputFile $outputFile
        $written = Get-Content -Path $outputFile -Raw | ConvertFrom-Json

        $summary.CandidateCount     | Should -Be 3
        $summary.ByKind['fetch']    | Should -Be 1
        $summary.ByKind['axios']    | Should -Be 1
        $summary.ByKind['url-string'] | Should -Be 1
        $written.sources            | Should -Be @('app.js')
        $written.candidates.Target  | Should -Be @('/api/a', '/api/b', '/api/c')
    }

    It 'missing_path: fails early on a missing path' {
        { & $SCRIPT_PATH -Path (Join-Path -Path $TestDrive -ChildPath 'nope') } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*must be an existing folder or file*'
    }
}
