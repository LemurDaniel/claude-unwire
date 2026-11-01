# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./tests

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks and mocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The test helper only builds an in-memory object.')]
param ()

# ===========================================================================
# =======================   DOWNLOAD STATIC ASSETS   ========================
# ===========================================================================
#
#   page_and_scripts       Saves the page and same-origin scripts, skips other origins.
#   source_map_comment     Loads the map named in sourceMappingURL.
#   source_map_probe       Probes '<script>.map' without a comment, a 404 is no error.
#   inline_map             Saves an inline data: source map next to its script.
#   spa_fallback           Skips a script that returns HTML.
#   chunks_and_depth       Follows chunk paths, but not beyond MaxDepth.
#   frames                 Follows frames as pages.
#   base_href              Resolves scripts and chunks against the base tag of the page.
#   guess_limit            Reports guessed paths as not-found and stops guessing at the limit.
#   duplicate_content      Saves pages with the same content only once.
#   redirect_same_origin   Follows a redirect within the origin.
#   redirect_cross_origin  Never follows a redirect to another origin.
#   max_assets             Stops saving at MaxAssets.
#   get_only               Never sends anything but GET, never lets the client redirect.
#   manifest               Writes unwire-assets.json with every asset.
#   unreachable            Fails with a clear error when the start page is unreachable.
#

BeforeAll {
    $SCRIPT_PATH = Join-Path -Path $PSScriptRoot -ChildPath '../scripts/Save-UnwireAsset.ps1'
    $START_URI   = 'http://router.test/'

    function New-TestResponse {
        param ([System.Int32] $StatusCode = 200, [System.String] $Content = '', [System.Collections.Hashtable] $Headers = @{})
        return [PSCustomObject]@{ StatusCode = $StatusCode; Content = $Content; Headers = $Headers }
    }
}

Describe 'Save-UnwireAsset' {
    BeforeEach {
        # The fake web server: absolute URI => response, everything else answers 404.
        $Site = @{}
        Mock Invoke-WebRequest {
            $response = $Site[$Uri.AbsoluteUri]
            if ($null -EQ $response) { New-TestResponse -StatusCode 404 } else { $response }
        }
        $OutputDirectory = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
    }

    It 'page_and_scripts: saves the page and same-origin scripts, skips other origins' {
        $Site['http://router.test/']              = New-TestResponse -Content '<script src="/js/app.js"></script><script src="https://cdn.test/lib.js"></script>'
        $Site['http://router.test/js/app.js']     = New-TestResponse -Content 'console.log(1)'

        $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -SkipSourceMapProbe

        $summary.Saved                                                     | Should -Be 2
        Join-Path -Path $OutputDirectory -ChildPath 'index.html'           | Should -Exist
        Get-Content -Path (Join-Path $OutputDirectory 'js/app.js') -Raw    | Should -Be 'console.log(1)'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Uri.Host -EQ 'cdn.test' }
    }

    It 'source_map_comment: loads the map named in sourceMappingURL' {
        $Site['http://router.test/']               = New-TestResponse -Content '<script src="/js/app.js"></script>'
        $Site['http://router.test/js/app.js']      = New-TestResponse -Content "x()`n//# sourceMappingURL=maps/app.js.map"
        $Site['http://router.test/js/maps/app.js.map'] = New-TestResponse -Content '{"version":3,"sources":["src/a.ts"],"mappings":""}'

        $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory

        Join-Path -Path $OutputDirectory -ChildPath 'js/maps/app.js.map' | Should -Exist
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/js/app.js.map' }
    }

    It 'source_map_probe: probes <script>.map without a comment, a 404 is no error' {
        $Site['http://router.test/']          = New-TestResponse -Content '<script src="/js/app.js"></script>'
        $Site['http://router.test/js/app.js'] = New-TestResponse -Content 'x()'

        $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory

        $summary.Saved    | Should -Be 2
        $summary.Failed   | Should -Be 0
        $summary.NotFound | Should -Be 1
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/js/app.js.map' }
    }

    It 'inline_map: saves an inline data: source map next to its script' {
        $map    = '{"version":3,"sources":["src/a.ts"],"mappings":""}'
        $base64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($map))
        $Site['http://router.test/']          = New-TestResponse -Content '<script src="/app.js"></script>'
        $Site['http://router.test/app.js']    = New-TestResponse -Content "x()`n//# sourceMappingURL=data:application/json;base64,$base64"

        $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory

        Get-Content -Path (Join-Path $OutputDirectory 'app.js.map') -Raw | Should -Be $map
    }

    It 'spa_fallback: skips a script that returns HTML' {
        $Site['http://router.test/']          = New-TestResponse -Content '<script src="/js/missing.js"></script>'
        $Site['http://router.test/js/missing.js'] = New-TestResponse -Content '<!doctype html><html></html>'

        $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory

        $summary.Saved                                                | Should -Be 1
        Join-Path -Path $OutputDirectory -ChildPath 'js/missing.js'   | Should -Not -Exist
    }

    It 'chunks_and_depth: follows chunk paths, but not beyond MaxDepth' {
        $Site['http://router.test/']                 = New-TestResponse -Content '<script src="/js/app.js"></script>'
        $Site['http://router.test/js/app.js']        = New-TestResponse -Content 'load("js/chunk.1.js"); load("./deep.js")'
        $Site['http://router.test/js/chunk.1.js']    = New-TestResponse -Content 'load("./chunk.2.js")'
        $Site['http://router.test/js/deep.js']       = New-TestResponse -Content 'y()'
        $Site['http://router.test/js/chunk.2.js']    = New-TestResponse -Content 'z()'

        $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -MaxDepth 2 -SkipSourceMapProbe

        Join-Path -Path $OutputDirectory -ChildPath 'js/chunk.1.js' | Should -Exist
        Join-Path -Path $OutputDirectory -ChildPath 'js/deep.js'    | Should -Exist
        Join-Path -Path $OutputDirectory -ChildPath 'js/chunk.2.js' | Should -Not -Exist
    }

    It 'frames: follows frames as pages' {
        $Site['http://router.test/']          = New-TestResponse -Content '<frameset><frame src="menu"></frameset>'
        $Site['http://router.test/menu']      = New-TestResponse -Content '<script src="/menu.js"></script>'
        $Site['http://router.test/menu.js']   = New-TestResponse -Content 'm()'

        $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -SkipSourceMapProbe

        Join-Path -Path $OutputDirectory -ChildPath 'menu.html' | Should -Exist
        Join-Path -Path $OutputDirectory -ChildPath 'menu.js'   | Should -Exist
    }

    It 'base_href: resolves scripts and chunks against the base tag of the page' {
        $Site['http://router.test/']                              = New-TestResponse -Content '<iframe src="/grafana/d/abc/system"></iframe>'
        $Site['http://router.test/grafana/d/abc/system']          = New-TestResponse -Content '<base href="/grafana/" /><script src="public/build/app.js"></script>'
        $Site['http://router.test/grafana/public/build/app.js']   = New-TestResponse -Content 'load("public/build/chunk.1.js")'
        $Site['http://router.test/grafana/public/build/chunk.1.js'] = New-TestResponse -Content 'c()'

        $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -SkipSourceMapProbe

        $summary.Failed                                                              | Should -Be 0
        Join-Path -Path $OutputDirectory -ChildPath 'grafana/public/build/app.js'     | Should -Exist
        Join-Path -Path $OutputDirectory -ChildPath 'grafana/public/build/chunk.1.js' | Should -Exist
    }

    It 'guess_limit: reports guessed paths as not-found and stops guessing at the limit' {
        $Site['http://router.test/']       = New-TestResponse -Content '<script src="/app.js"></script>'
        $Site['http://router.test/app.js'] = New-TestResponse -Content 'l("a.js"); l("b.js"); l("c.js")'

        $summary  = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -SkipSourceMapProbe -MaxGuessMisses 2
        $manifest = Get-Content -Path $summary.Manifest -Raw | ConvertFrom-Json

        $summary.Failed                    | Should -Be 0
        $summary.NotFound                  | Should -Be 2
        $manifest.assets[-1].Reason        | Should -Be 'MaxGuessMisses 2 reached'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/c.js' }
    }

    It 'duplicate_content: saves pages with the same content only once' {
        $Site['http://router.test/']              = New-TestResponse -Content '<iframe src="/panel?id=1"></iframe><iframe src="/panel?id=2"></iframe>'
        $Site['http://router.test/panel?id=1']    = New-TestResponse -Content '<html>panel</html>'
        $Site['http://router.test/panel?id=2']    = New-TestResponse -Content '<html>panel</html>'

        $summary  = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory
        $manifest = Get-Content -Path $summary.Manifest -Raw | ConvertFrom-Json

        $summary.Saved             | Should -Be 2
        $manifest.assets[2].Reason | Should -Be "same content as 'panel.html'"
    }

    It 'redirect_same_origin: follows a redirect within the origin' {
        $Site['http://router.test/']           = New-TestResponse -StatusCode 302 -Headers @{ Location = @('/login.lua') }
        $Site['http://router.test/login.lua']  = New-TestResponse -Content '<html>login</html>'

        $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory

        $summary.Saved                                               | Should -Be 1
        Join-Path -Path $OutputDirectory -ChildPath 'login.lua'      | Should -Exist
    }

    It 'redirect_cross_origin: never follows a redirect to another origin' {
        $Site['http://router.test/'] = New-TestResponse -StatusCode 302 -Headers @{ Location = @('https://evil.test/') }

        $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -WarningAction SilentlyContinue

        $summary.Saved | Should -Be 0
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Uri.Host -EQ 'evil.test' }
    }

    It 'max_assets: stops saving at MaxAssets' {
        $Site['http://router.test/']       = New-TestResponse -Content '<script src="/a.js"></script><script src="/b.js"></script>'
        $Site['http://router.test/a.js']   = New-TestResponse -Content 'a()'
        $Site['http://router.test/b.js']   = New-TestResponse -Content 'b()'

        $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -MaxAssets 2 -SkipSourceMapProbe

        $summary.Saved   | Should -Be 2
        $summary.Skipped | Should -Be 1
    }

    It 'get_only: never sends anything but GET, never lets the client redirect' {
        $Site['http://router.test/']       = New-TestResponse -Content '<script src="/a.js"></script>'
        $Site['http://router.test/a.js']   = New-TestResponse -Content 'a()'

        $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory

        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Method -NE 'Get' -OR $MaximumRedirection -NE 0 }
    }

    It 'manifest: writes unwire-assets.json with every asset' {
        $Site['http://router.test/']       = New-TestResponse -Content '<script src="/a.js"></script><script src="https://cdn.test/x.js"></script>'
        $Site['http://router.test/a.js']   = New-TestResponse -Content 'a()'

        $summary  = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -SkipSourceMapProbe
        $manifest = Get-Content -Path $summary.Manifest -Raw | ConvertFrom-Json

        $manifest.startUri          | Should -Be 'http://router.test/'
        $manifest.assets.Uri        | Should -Be @('http://router.test/', 'http://router.test/a.js', 'https://cdn.test/x.js')
        $manifest.assets.Status     | Should -Be @('saved', 'saved', 'skipped')
        $manifest.assets[1].File    | Should -Be 'a.js'
        $manifest.assets[2].Reason  | Should -Be 'cross-origin'
    }

    It 'unreachable: fails with a clear error when the start page is unreachable' {
        Mock Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('No such host is known.') }

        { & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory } | Should -Throw -ExceptionType ([System.InvalidOperationException]) -ExpectedMessage "Uri 'http://router.test/' must be reachable*"
    }
}
