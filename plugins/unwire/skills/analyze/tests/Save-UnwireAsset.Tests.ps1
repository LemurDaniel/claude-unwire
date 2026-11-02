# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./tests

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks and mocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The test helper only builds an in-memory object.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The Read-Host mocks return fake test cookies.')]
param ()

# ===========================================================================
# =======================   DOWNLOAD STATIC ASSETS   ========================
# ===========================================================================
#
#   page_and_scripts       Saves the page and same-origin scripts, skips other origins.
#   source_map_comment     Loads the map named in sourceMappingURL.
#   source_map_probe       Probes '<script>.map' without a comment, a 404 is no error.
#   missing_map            Reports a referenced but missing source map as not-found.
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
#   untrusted_certificate  Stops at the start page on an untrusted certificate.
#   webpack_chunk_map      Loads the lazy chunks of a webpack runtime by name and hash.
#   webpack_chunk_prefix   Builds CRA-style chunk names relative to the runtime's folder.
#   referer                Sends the loading page as Referer, the start page without one.
#   access_denied          Counts scripts that answer 401 or 403 and warns about a login.
#   no_cookie_by_default   Sends no Cookie header without UseSession.
#   session_missing        Fails early when the session variable is empty.
#   session_cookie         Sends the cookie from the session variable.
#   session_static_only    Requests only the start page and scripts, never pages or endpoints.
#   session_denylist       Never requests a denylisted path, also not a script.
#   session_no_redirect    Never follows a redirect and warns about an expired session.
#   session_secret         Never writes the cookie value into the manifest or the output.
#   session_page_unsaved   Reads the signed-in start page for scripts, never saves it.
#   prompt_session         Asks for the cookie masked and sends it, no variable needed.
#   prompt_header_line     Accepts a pasted 'Cookie: name=value' header line.
#   prompt_curl            Takes the cookie out of a pasted 'Copy as cURL' command.
#   prompt_multi_line      Reads a multi-line cURL paste completely, bash and cmd format.
#   prompt_devtools_row    Turns a pasted DevTools cookie table row into name=value.
#   prompt_bare_value      Fails early on a value without its name, shows only its shape.
#   prompt_guide           Shows the login guide with the URL before the prompt, in -Language.
#   prompt_guide_fallback  Falls back to the English guide for an unknown language.
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
            if ($null -EQ $response) { return New-TestResponse -StatusCode 404 }
            # Mirrors pwsh 7.4+: a 3xx under MaximumRedirection 0 also writes this error.
            if ($response.StatusCode -GE 300 -AND $response.StatusCode -LT 400) {
                Write-Error -Message 'The maximum redirection count has been exceeded.' -ErrorId 'MaximumRedirectExceeded'
            }
            $response
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

    It 'missing_map: reports a referenced but missing source map as not-found' {
        $Site['http://router.test/']       = New-TestResponse -Content '<script src="/app.js"></script>'
        $Site['http://router.test/app.js'] = New-TestResponse -Content "x()`n//# sourceMappingURL=app.js.map"

        $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory

        $summary.Failed   | Should -Be 0
        $summary.NotFound | Should -Be 1
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

    It 'untrusted_certificate: stops at the start page and names SkipCertificateCheck' {
        $inner = [System.Security.Authentication.AuthenticationException]::new('The remote certificate is invalid because of errors in the certificate chain: UntrustedRoot')
        Mock Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('The SSL connection could not be established, see inner exception.', $inner) }

        { & $SCRIPT_PATH -Uri 'https://router.test/' -OutputDirectory $OutputDirectory } | Should -Throw -ExceptionType ([System.Security.Authentication.AuthenticationException]) -ExpectedMessage "Uri 'https://router.test/' has a TLS certificate this machine does not trust (*UntrustedRoot)*-SkipCertificateCheck*"
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
    }

    It 'webpack_chunk_map: loads the lazy chunks of a webpack runtime by name and hash' {
        $Site['http://router.test/']                         = New-TestResponse -Content '<base href="/grafana/"><script src="public/build/runtime.js"></script>'
        $Site['http://router.test/grafana/public/build/runtime.js'] = New-TestResponse -Content 'b.u=e=>""+({123:"TeamList"}[e]||e)+"."+{123:"cbbdd876417c6516e99c",456:"0549a3fcb50e73c4b256"}[e]+".js",b.p="public/build/"'
        $Site['http://router.test/grafana/public/build/TeamList.cbbdd876417c6516e99c.js'] = New-TestResponse -Content 'teams()'
        $Site['http://router.test/grafana/public/build/456.0549a3fcb50e73c4b256.js']      = New-TestResponse -Content 'other()'

        $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -SkipSourceMapProbe

        $summary.Failed                                                                               | Should -Be 0
        Join-Path -Path $OutputDirectory -ChildPath 'grafana/public/build/TeamList.cbbdd876417c6516e99c.js' | Should -Exist
        Join-Path -Path $OutputDirectory -ChildPath 'grafana/public/build/456.0549a3fcb50e73c4b256.js'      | Should -Exist
    }

    It 'webpack_chunk_prefix: builds CRA-style chunk names relative to the runtime folder' {
        $Site['http://router.test/']                      = New-TestResponse -Content '<script src="/static/runtime.js"></script>'
        $Site['http://router.test/static/runtime.js']     = New-TestResponse -Content 'n.u=e=>"js/"+e+"."+{45:"0a1b2c3d"}[e]+".chunk.js"'
        $Site['http://router.test/static/js/45.0a1b2c3d.chunk.js'] = New-TestResponse -Content 'c()'

        $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -SkipSourceMapProbe

        Join-Path -Path $OutputDirectory -ChildPath 'static/js/45.0a1b2c3d.chunk.js' | Should -Exist
    }

    It 'referer: sends the loading page as Referer, the start page without one' {
        $Site['http://router.test/']              = New-TestResponse -Content '<script src="/js/runtime.js"></script><iframe src="/frame.htm"></iframe>'
        $Site['http://router.test/js/runtime.js'] = New-TestResponse -Content 'load("js/chunk.js")'
        $Site['http://router.test/js/chunk.js']   = New-TestResponse -Content 'c()'
        $Site['http://router.test/frame.htm']     = New-TestResponse -Content '<script src="/js/frame.js"></script>'
        $Site['http://router.test/js/frame.js']   = New-TestResponse -Content 'f()'

        $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -SkipSourceMapProbe

        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/' -AND $null -EQ $Headers }
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/js/runtime.js' -AND $Headers.Referer -EQ 'http://router.test/' }
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/js/chunk.js' -AND $Headers.Referer -EQ 'http://router.test/' }
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/js/frame.js' -AND $Headers.Referer -EQ 'http://router.test/frame.htm' }
    }

    It 'access_denied: counts scripts that answer 401 or 403 and warns about a login' {
        $Site['http://router.test/']       = New-TestResponse -Content '<script src="/a.js"></script><script src="/b.js"></script><script src="/c.js"></script>'
        $Site['http://router.test/a.js']   = New-TestResponse -StatusCode 403
        $Site['http://router.test/b.js']   = New-TestResponse -StatusCode 401
        $Site['http://router.test/c.js']   = New-TestResponse -StatusCode 500

        $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -SkipSourceMapProbe -WarningVariable warnings -WarningAction SilentlyContinue

        $summary.AccessDenied | Should -Be 2
        $summary.Failed       | Should -Be 3
        $warnings             | Should -BeLike '*2 scripts or maps answered 401/403*session mode*'
    }

    It 'no_cookie_by_default: sends no Cookie header without UseSession' {
        $Site['http://router.test/'] = New-TestResponse -Content '<html></html>'

        $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory

        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $null -NE $Headers }
    }

    Context 'session mode' {
        BeforeEach {
            $env:UNWIRE_TEST_COOKIE = 'sid=TOP-SECRET-VALUE'
            $SessionConfig = @{ UseSession = $true; SessionVariable = 'UNWIRE_TEST_COOKIE'; SkipSourceMapProbe = $true }
        }
        AfterEach {
            Remove-Item -Path Env:UNWIRE_TEST_COOKIE -ErrorAction SilentlyContinue
        }

        It 'session_missing: fails early when the session variable is empty' {
            Remove-Item -Path Env:UNWIRE_TEST_COOKIE

            { & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "Environment variable 'UNWIRE_TEST_COOKIE' must hold the session cookie*"
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 'session_cookie: sends the cookie from the session variable' {
            $Site['http://router.test/'] = New-TestResponse -Content '<html></html>'

            $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig

            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Headers.Cookie -EQ 'sid=TOP-SECRET-VALUE' }
        }

        It 'session_static_only: requests only the start page and scripts, never pages or endpoints' {
            $Site['http://router.test/']           = New-TestResponse -Content '<script src="/app.js"></script><iframe src="/panel"></iframe><script src="/data.lua?page=x"></script>'
            $Site['http://router.test/app.js']     = New-TestResponse -Content 'fetch("/api/status")'

            $summary  = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig
            $manifest = Get-Content -Path $summary.Manifest -Raw | ConvertFrom-Json

            $summary.Saved    | Should -Be 1
            $summary.ReadOnly | Should -Be 1
            Should -Invoke Invoke-WebRequest -Times 2 -Exactly
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Uri.AbsolutePath -IN @('/panel', '/data.lua', '/api/status') }
            ($manifest.assets | Where-Object -Property Uri -EQ -Value 'http://router.test/panel').Reason | Should -Be 'session mode: no static script or source map'
        }

        It 'session_denylist: never requests a denylisted path, also not a script' {
            $Site['http://router.test/'] = New-TestResponse -Content '<script src="/js/logout.js"></script><script src="/js/app.js"></script>'
            $Site['http://router.test/js/app.js'] = New-TestResponse -Content 'a()'

            $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig

            Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/js/logout.js' }
            Join-Path -Path $OutputDirectory -ChildPath 'js/app.js' | Should -Exist
        }

        It 'session_no_redirect: never follows a redirect and warns about an expired session' {
            $Site['http://router.test/'] = New-TestResponse -StatusCode 302 -Headers @{ Location = @('/login') }

            $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig -WarningVariable warnings -WarningAction SilentlyContinue

            $summary.Saved | Should -Be 0
            $warnings[0]   | Should -BeLike '*session cookie is probably expired*'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/login' }
        }

        It 'session_secret: never writes the cookie value into the manifest or the output' {
            $Site['http://router.test/']       = New-TestResponse -Content '<script src="/app.js"></script>'
            $Site['http://router.test/app.js'] = New-TestResponse -Content 'a()'

            $output  = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig -Verbose 4>&1 3>&1 | Out-String
            $summary = Get-ChildItem -Path $OutputDirectory -Recurse -File | Get-Content -Raw | Out-String

            $output  | Should -Not -Match 'TOP-SECRET-VALUE'
            $summary | Should -Not -Match 'TOP-SECRET-VALUE'
            (Get-Content -Path (Join-Path $OutputDirectory 'unwire-assets.json') -Raw | ConvertFrom-Json).session | Should -BeTrue
        }

        It 'session_page_unsaved: reads the signed-in start page for scripts, never saves it' {
            $Site['http://router.test/']       = New-TestResponse -Content '<html>Hello daniel<script src="/app.js"></script></html>'
            $Site['http://router.test/app.js'] = New-TestResponse -Content 'a()'

            $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig

            $summary.Saved    | Should -Be 1
            $summary.ReadOnly | Should -Be 1
            Join-Path -Path $OutputDirectory -ChildPath 'index.html' | Should -Not -Exist
            Join-Path -Path $OutputDirectory -ChildPath 'app.js'     | Should -Exist
        }
    }

    Context 'prompt session' {
        BeforeEach {
            $Site['http://router.test/']       = New-TestResponse -Content '<script src="/app.js"></script><iframe src="/panel"></iframe>'
            $Site['http://router.test/app.js'] = New-TestResponse -Content 'a()'
            # The guide goes to the host: hidden here, read by the prompt_guide tests.
            $PromptConfig = @{ PromptSession = $true; SkipSourceMapProbe = $true; InformationAction = 'Ignore' }
            $GuideConfig  = @{ PromptSession = $true; SkipSourceMapProbe = $true; InformationAction = 'Continue' }
        }

        It 'prompt_session: asks for the cookie masked and sends it, no variable needed' {
            Mock Read-Host { ConvertTo-SecureString -String 'i_like_gitea=PROMPT-SECRET' -AsPlainText -Force }

            $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @PromptConfig

            $summary.Saved | Should -Be 1
            Should -Invoke Read-Host -Times 1 -Exactly -ParameterFilter { $AsSecureString }
            Should -Invoke Invoke-WebRequest -Times 2 -Exactly -ParameterFilter { $Headers.Cookie -EQ 'i_like_gitea=PROMPT-SECRET' }
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/panel' }
            Get-Content -Path $summary.Manifest -Raw | Should -Not -Match 'PROMPT-SECRET'
        }

        It 'prompt_header_line: accepts a pasted Cookie header line' {
            Mock Read-Host { ConvertTo-SecureString -String '  Cookie: i_like_gitea=PROMPT-SECRET ' -AsPlainText -Force }

            $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @PromptConfig

            Should -Invoke Invoke-WebRequest -Times 2 -Exactly -ParameterFilter { $Headers.Cookie -EQ 'i_like_gitea=PROMPT-SECRET' }
        }

        It 'prompt_curl: takes the cookie out of a pasted Copy as cURL command' -ForEach @(
            @{ Pasted = "curl 'https://router.test/' -H 'accept: text/html' -b 'lang=de-DE; i_like_gitea=PROMPT-SECRET' --compressed" }
            @{ Pasted = "curl 'https://router.test/' -H 'cookie: lang=de-DE; i_like_gitea=PROMPT-SECRET' -H 'accept: */*'" }
        ) {
            Mock Read-Host { ConvertTo-SecureString -String $Pasted -AsPlainText -Force }

            $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @PromptConfig

            Should -Invoke Invoke-WebRequest -Times 2 -Exactly -ParameterFilter { $Headers.Cookie -EQ 'lang=de-DE; i_like_gitea=PROMPT-SECRET' }
        }

        It 'prompt_multi_line: reads a multi-line cURL paste completely, <Format> format' -ForEach @(
            @{
                Format = 'cmd'
                Lines  = @(
                    'curl ^"https://router.test/gitea/^" ^'
                    '  -H ^"Accept: text/html^" ^'
                    '  -b ^"lang=de-DE; i_like_gitea=PROMPT-SECRET^" ^'
                    '  -H ^"sec-ch-ua: ^\^"Opera^\^";v=^\^"137^\^"^" ^'
                    '  --insecure'
                )
            }
            @{
                Format = 'bash'
                Lines  = @(
                    "curl 'https://router.test/gitea/' \"
                    "  -H 'accept: text/html' \"
                    "  -b 'lang=de-DE; i_like_gitea=PROMPT-SECRET' \"
                    '  --compressed'
                )
            }
        ) {
            $pasted = [System.Collections.Generic.Queue[System.String]]::new([System.String[]] $Lines)
            Mock Read-Host { ConvertTo-SecureString -String $pasted.Dequeue() -AsPlainText -Force }

            $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @PromptConfig

            Should -Invoke Read-Host -Times $Lines.Count -Exactly
            $pasted.Count | Should -Be 0
            Should -Invoke Invoke-WebRequest -Times 2 -Exactly -ParameterFilter { $Headers.Cookie -EQ 'lang=de-DE; i_like_gitea=PROMPT-SECRET' }
        }

        It 'prompt_devtools_row: turns a pasted DevTools cookie table row into name=value' {
            Mock Read-Host { ConvertTo-SecureString -String "i_like_gitea`tPROMPT-SECRET`tnfs.fritz.box`t/gitea`tSession`t46`ttrue`ttrue`tLax" -AsPlainText -Force }

            $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @PromptConfig

            Should -Invoke Invoke-WebRequest -Times 2 -Exactly -ParameterFilter { $Headers.Cookie -EQ 'i_like_gitea=PROMPT-SECRET' }
        }

        It 'prompt_bare_value: fails early on a value without its name, shows only its shape' {
            Mock Read-Host { ConvertTo-SecureString -String 'PROMPT-SECRET' -AsPlainText -Force }

            $thrown = { & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @PromptConfig } | Should -Throw -ExceptionType ([System.ArgumentException]) -PassThru

            $thrown.Exception.Message | Should -BeLike "The session cookie must be 'name=value'*Got: 13 characters, no '='."
            $thrown.Exception.Message | Should -Not -Match 'PROMPT-SECRET'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 'prompt_guide: shows the login guide with the URL before the prompt, in <Language>' -ForEach @(
            @{ Language = 'de'; Title = 'Unwire: Login f?r http://router.test/'; Step = '2. Dr?ck F12*'; PromptLike = 'Session-Cookie (*'; Done = 'Fertig.*' }
            @{ Language = 'en'; Title = 'Unwire: login for http://router.test/'; Step = '2. Press F12*'; PromptLike = 'Session cookie (*'; Done = 'Done.*' }
        ) {
            Mock Read-Host { ConvertTo-SecureString -String 'i_like_gitea=PROMPT-SECRET' -AsPlainText -Force }

            $output = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @GuideConfig -Language $Language 6>&1
            $shown  = @($output | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { "$($_.MessageData)" })

            @($shown -LIKE $Title).Count                       | Should -Be 1
            @($shown -LIKE '1. * http://router.test/ *').Count | Should -Be 1
            @($shown -LIKE $Step).Count                        | Should -Be 1
            $shown[-1]                                         | Should -BeLike $Done
            Should -Invoke Read-Host -Times 1 -Exactly -ParameterFilter { $Prompt -LIKE $PromptLike }
        }

        It 'prompt_guide_fallback: falls back to the English guide for an unknown language' {
            Mock Read-Host { ConvertTo-SecureString -String 'i_like_gitea=PROMPT-SECRET' -AsPlainText -Force }

            $output = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @GuideConfig -Language 'fr' 6>&1
            $shown  = @($output | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { "$($_.MessageData)" })

            $shown | Should -Contain 'Unwire: login for http://router.test/'
        }
    }
}
