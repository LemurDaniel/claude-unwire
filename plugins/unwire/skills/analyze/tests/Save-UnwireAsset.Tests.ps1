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
#   inline_imports         Follows the imports of inline module scripts.
#   extra_scripts          Loads the scripts of -Script and follows their imports.
#   extra_script_rules     Rejects a script that is no same-origin *.js before any request.
#   login_form             Reports a start page with a password field or login script as LoginForm.
#   login_guide_options    Every language offers login, without login and cancel.
#   no_cookie_by_default   Sends no Cookie header without UseSession.
#   session_missing        Fails early when the session variable is empty.
#   session_cookie         Sends the cookie from the session variable.
#   session_static_only    Requests only the start page, scripts and .htm pages, never endpoints.
#   session_pages          Reads .htm frames, keeps only their inline scripts, values redacted.
#   session_extra_pages    Reads the pages of -Page, also as one comma list.
#   session_page_rules     Rejects a page that is no same-origin *.htm before any request.
#   session_page_denylist  Never requests a denylisted extra page.
#   session_denylist       Never requests a denylisted path, also not a script.
#   session_no_redirect    Never follows a redirect and warns about an expired session.
#   session_secret         Never writes the cookie value into the manifest or the output.
#   session_page_unsaved   Reads the signed-in start page for scripts, never saves it.
#   session_still_login    Warns when the start page is still a login page in session mode.
#   session_inline_object  Redacts object values of inline scripts, keeps plain paths.
#   session_value_scrub    Scrubs the session value from every saved file, wherever it is.
#   session_parameter      Sends the session as URL parameter, never as cookie, never in a record.
#   session_parameter_only Rejects SessionParameter without session mode before any request.
#   prompt_curl_header     Sends the Authorization or auth header of a cURL, drops the others.
#   prompt_curl_digest     Rejects HTTP Digest before any request.
#   prompt_curl_path_token Sends a path token only on the wire, as segment or appended.
#   prompt_curl_no_session Fails early on a cURL without any session.
#   prompt_curl_parameter  Takes the session parameter out of the URL or data of a pasted cURL.
#   prompt_curl_no_param   Fails early on a cURL without the parameter, shows only its shape.
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

    It 'inline_imports: follows the imports of inline module scripts' {
        $Site['http://router.test/']              = New-TestResponse -Content '<script type="module">import { setConfig } from "/js/config.js"; import login from "./js/start.js"; import("/js/lazy.mjs");</script>'
        $Site['http://router.test/js/config.js']  = New-TestResponse -Content 'c()'
        $Site['http://router.test/js/start.js']   = New-TestResponse -Content 's()'
        $Site['http://router.test/js/lazy.mjs']   = New-TestResponse -Content 'l()'

        $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -SkipSourceMapProbe

        $summary.Saved                                               | Should -Be 4
        Join-Path -Path $OutputDirectory -ChildPath 'js/config.js'   | Should -Exist
        Join-Path -Path $OutputDirectory -ChildPath 'js/start.js'    | Should -Exist
        Join-Path -Path $OutputDirectory -ChildPath 'js/lazy.mjs'    | Should -Exist
    }

    It 'extra_scripts: loads the scripts of -Script and follows their imports' {
        $Site['http://router.test/']                   = New-TestResponse -Content '<html></html>'
        $Site['http://router.test/js/views/status.js'] = New-TestResponse -Content 'import x from "./parts/table.js"'
        $Site['http://router.test/js/views/parts/table.js'] = New-TestResponse -Content 't()'
        $Site['http://router.test/js/views/wlan.mjs']  = New-TestResponse -Content 'w()'

        $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -SkipSourceMapProbe -Script '/js/views/status.js, js/views/wlan.mjs'

        $summary.Saved                                                         | Should -Be 4
        Join-Path -Path $OutputDirectory -ChildPath 'js/views/parts/table.js'  | Should -Exist
        Join-Path -Path $OutputDirectory -ChildPath 'js/views/wlan.mjs'        | Should -Exist
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/js/views/status.js' -AND $Headers.Referer -EQ 'http://router.test/' }
    }

    It 'extra_script_rules: rejects a script that is no same-origin *.js before any request, <Case>' -ForEach @(
        @{ Case = 'endpoint';     Script = '/data.lua' }
        @{ Case = 'other origin'; Script = 'http://cdn.test/a.js' }
    ) {
        { & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -Script $Script } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage 'Script must be a same-origin *.js or *.mjs path*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'login_form: reports a start page with a password field or login script as LoginForm, <Case>' -ForEach @(
        @{ Case = 'password field'; Page = '<form><input id="pw" type="password"></form><script src="/a.js"></script>'; Expected = $true }
        @{ Case = 'login script';   Page = '<script src="/js/box-login.js"></script><script src="/a.js"></script>';      Expected = $true }
        @{ Case = 'login import';   Page = '<script type="module">import login from "/js/login.js";</script>';            Expected = $true }
        @{ Case = 'other page';     Page = '<form><input type="text"></form><script src="/js/catalog.js"></script>';      Expected = $false }
    ) {
        $Site['http://router.test/']     = New-TestResponse -Content $Page
        $Site['http://router.test/a.js'] = New-TestResponse -Content 'a()'

        $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -SkipSourceMapProbe -WarningVariable warnings -WarningAction SilentlyContinue

        $summary.LoginForm                                     | Should -Be $Expected
        @($warnings -LIKE '*start page is a login form*').Count | Should -Be ([System.Int32] $Expected)
    }

    It 'login_guide_options: every language offers login, without login and cancel' {
        $guide = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath '../data/login-guide.json') -Raw | ConvertFrom-Json -AsHashtable

        foreach ($language in $guide.Keys) {
            foreach ($option in 'open', 'skip', 'cancel') {
                ($guide[$language][$option].label -split ' ').Count | Should -BeLessOrEqual 5 -Because "$language.$option.label must fit AskUserQuestion"
                $guide[$language][$option].description             | Should -Not -BeNullOrEmpty
            }
        }
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

        It 'session_static_only: requests only the start page, scripts and .htm pages, never endpoints' {
            $Site['http://router.test/']           = New-TestResponse -Content '<script src="/app.js"></script><iframe src="/panel"></iframe><script src="/data.lua?page=x"></script>'
            $Site['http://router.test/app.js']     = New-TestResponse -Content 'fetch("/api/status")'

            $summary  = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig
            $manifest = Get-Content -Path $summary.Manifest -Raw | ConvertFrom-Json

            $summary.Saved    | Should -Be 1
            $summary.ReadOnly | Should -Be 1
            Should -Invoke Invoke-WebRequest -Times 2 -Exactly
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Uri.AbsolutePath -IN @('/panel', '/data.lua', '/api/status') }
            ($manifest.assets | Where-Object -Property Uri -EQ -Value 'http://router.test/panel').Reason | Should -Be 'session mode: no static script, source map or .htm page'
        }

        It 'session_pages: reads .htm frames, keeps only their inline scripts with values redacted' {
            $Site['http://router.test/']                = New-TestResponse -Content '<frameset><frame src="/main/status.htm"></frameset>'
            $Site['http://router.test/main/status.htm'] = New-TestResponse -Content '<p>WAN 203.0.113.7</p><script>var wlanKey = "TOP-SECRET-KEY"; $.act(ACT_GET, WAN_IP_CONN, null, null, ["externalIPAddress"]);</script><script src="/js/status.js"></script>'
            $Site['http://router.test/js/status.js']    = New-TestResponse -Content 's()'

            $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig
            $inline  = Get-Content -Path (Join-Path $OutputDirectory 'main/status.htm.inline.js') -Raw
            $saved   = Get-ChildItem -Path $OutputDirectory -Recurse -File | Get-Content -Raw

            $summary.ReadOnly                                         | Should -Be 2
            $inline                                                   | Should -BeLike '*$.act(ACT_GET, WAN_IP_CONN*'
            $inline                                                   | Should -BeLike '*var wlanKey = "<redacted>"*'
            Join-Path -Path $OutputDirectory -ChildPath 'main/status.htm' | Should -Not -Exist
            Join-Path -Path $OutputDirectory -ChildPath 'js/status.js'    | Should -Exist
            ($saved -join "`n")                                       | Should -Not -Match 'TOP-SECRET-KEY|203\.0\.113\.7'
        }

        It 'session_extra_pages: reads the pages of -Page, also as one comma list, with the start page as Referer' {
            $Site['http://router.test/']                = New-TestResponse -Content '<script src="/js/lib.js"></script>'
            $Site['http://router.test/js/lib.js']       = New-TestResponse -Content 'l()'
            $Site['http://router.test/main/status.htm'] = New-TestResponse -Content '<script>$.act(ACT_GET, WAN_IP_CONN);</script>'
            $Site['http://router.test/frame/menu.htm']  = New-TestResponse -Content '<script>var pages = ["status.htm"];</script>'

            $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig -Page '/main/status.htm, frame/menu.htm'

            $summary.ReadOnly                                                       | Should -Be 3
            Join-Path -Path $OutputDirectory -ChildPath 'main/status.htm.inline.js' | Should -Exist
            Join-Path -Path $OutputDirectory -ChildPath 'frame/menu.htm.inline.js'  | Should -Exist
            Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/main/status.htm' -AND $Headers.Referer -EQ 'http://router.test/' }
        }

        It 'session_page_rules: rejects a page that is no same-origin *.htm before any request, <Case>' -ForEach @(
            @{ Case = 'endpoint';     Page = '/cgi/info' }
            @{ Case = 'other origin'; Page = 'http://cdn.test/a.htm' }
        ) {
            { & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig -Page $Page } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage 'Page must be a same-origin *.htm or *.html path*'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 'session_page_denylist: never requests a denylisted extra page' {
            $Site['http://router.test/'] = New-TestResponse -Content '<html></html>'

            $null = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig -Page '/main/reboot.htm'

            Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/main/reboot.htm' }
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

        It 'session_still_login: warns when the start page is still a login page in session mode' {
            $Site['http://router.test/'] = New-TestResponse -Content '<script src="/js/login.js"></script>'

            $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig -WarningVariable warnings -WarningAction SilentlyContinue

            $summary.LoginForm | Should -BeTrue
            $warnings          | Should -BeLike '*still is a login form in session mode*-SessionParameter*'
        }

        It 'session_inline_object: redacts object values of inline scripts, keeps plain paths' {
            $Site['http://router.test/'] = New-TestResponse -Content '<script type="module">const data = {"sid":"TOP-SECRET-SID","user":"TOP-SECRET-USER","firstTenMin":false}; ajax({url: "/data.lua", page: ''TOP-SECRET-PAGE''}); login.init(data);</script>'

            $null   = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig
            $inline = Get-Content -Path (Join-Path $OutputDirectory 'index.html.inline.js') -Raw

            $inline | Should -Not -Match 'TOP-SECRET'
            $inline | Should -BeLike '*{"sid":"<redacted>","user":"<redacted>","firstTenMin":false}*'
            $inline | Should -BeLike '*url: "/data.lua", page: "<redacted>"*'
        }

        It 'session_value_scrub: scrubs the session value from every saved file, wherever it is' {
            $Site['http://router.test/']       = New-TestResponse -Content '<script src="/app.js"></script><script>init(["TOP-SECRET-VALUE"]);</script>'
            $Site['http://router.test/app.js'] = New-TestResponse -Content 'call("/x?sid=TOP-SECRET-VALUE")'

            $null  = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig
            $saved = Get-ChildItem -Path $OutputDirectory -Recurse -File | Get-Content -Raw | Out-String

            $saved                                                              | Should -Not -Match 'TOP-SECRET-VALUE'
            Get-Content -Path (Join-Path $OutputDirectory 'app.js') -Raw       | Should -Be 'call("/x?sid=<redacted>")'
            Get-Content -Path (Join-Path $OutputDirectory 'index.html.inline.js') -Raw | Should -Be 'init(["<redacted>"]);'
        }

        It 'session_parameter: sends the session as URL parameter, never as cookie, never in a record' {
            $env:UNWIRE_TEST_COOKIE = 'TOP-SECRET-VALUE'
            $Site['http://router.test/?sid=TOP-SECRET-VALUE']          = New-TestResponse -Content '<script src="/js/app.js?v=2"></script><iframe src="/main.htm"></iframe>'
            $Site['http://router.test/js/app.js?v=2&sid=TOP-SECRET-VALUE'] = New-TestResponse -Content 'a()'
            $Site['http://router.test/main.htm?sid=TOP-SECRET-VALUE']  = New-TestResponse -Content '<script>var user = "TOP-SECRET-USER";</script>'

            $output   = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @SessionConfig -SessionParameter 'sid' -Verbose 4>&1 3>&1 | Out-String
            $saved    = Get-ChildItem -Path $OutputDirectory -Recurse -File | Get-Content -Raw | Out-String
            $manifest = Get-Content -Path (Join-Path $OutputDirectory 'unwire-assets.json') -Raw | ConvertFrom-Json

            Join-Path -Path $OutputDirectory -ChildPath 'js/app.js'           | Should -Exist
            Join-Path -Path $OutputDirectory -ChildPath 'main.htm.inline.js'  | Should -Exist
            $manifest.assets.Uri                                              | Should -Contain 'http://router.test/js/app.js?v=2'
            $manifest.sessionParameter                                        | Should -Be 'sid'
            $output                                                           | Should -Not -Match 'TOP-SECRET'
            $saved                                                            | Should -Not -Match 'TOP-SECRET'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $null -NE $Headers.Cookie -OR "$($Headers.Referer)" -MATCH 'TOP-SECRET' }
            Should -Invoke Invoke-WebRequest -Times 3 -Exactly -ParameterFilter { $Uri.Query -LIKE '*sid=TOP-SECRET-VALUE' -AND $Method -EQ 'Get' }
        }

        It 'session_parameter_only: rejects SessionParameter without session mode before any request' {
            { & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory -SessionParameter 'sid' } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "SessionParameter 'sid' must be used with PromptSession or UseSession."
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
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

        It 'prompt_curl_header: sends the <Header> header of a cURL, drops the others' -ForEach @(
            @{ Header = 'Authorization'; Value = 'Basic UFJPTVBULVNFQ1JFVA==' }
            @{ Header = 'Authorization'; Value = 'Bearer PROMPT-SECRET' }
            @{ Header = 'X-Auth-Token';  Value = 'PROMPT-SECRET' }
        ) {
            $pasted = "curl 'http://router.test/' -H 'accept: text/html' -H '$($Header): $Value' -H 'user-agent: test'"
            Mock Read-Host { ConvertTo-SecureString -String $pasted -AsPlainText -Force }

            $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @PromptConfig

            $summary.Saved | Should -Be 1
            Should -Invoke Invoke-WebRequest -Times 2 -Exactly -ParameterFilter { $Headers[$Header] -EQ $Value -AND -NOT $Headers.ContainsKey('accept') -AND -NOT $Headers.ContainsKey('Cookie') }
            $manifest = Get-Content -Path $summary.Manifest -Raw
            $manifest | Should -Not -Match 'PROMPT-SECRET|UFJPTVBULVNFQ1JFVA'
            ($manifest | ConvertFrom-Json).sessionKinds | Should -Be "header:$Header"
        }

        It 'prompt_curl_digest: rejects HTTP Digest before any request' {
            Mock Read-Host { ConvertTo-SecureString -String "curl 'http://router.test/' -H 'Authorization: Digest username=`"admin`", response=`"PROMPT-SECRET`"'" -AsPlainText -Force }

            $thrown = { & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @PromptConfig } | Should -Throw -ExceptionType ([System.ArgumentException]) -PassThru

            $thrown.Exception.Message | Should -BeLike 'The session must not be HTTP Digest*Save page as*'
            $thrown.Exception.Message | Should -Not -Match 'PROMPT-SECRET'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 'prompt_curl_path_token: sends a path token only on the wire, as <Case>' -ForEach @(
            @{
                Case     = 'segment'
                Start    = 'http://router.test/cgi-bin/ui/'
                Pasted   = "curl 'http://router.test/cgi-bin/ui/;stok=PROMPTSECRET1/admin/status' -H 'accept: */*'"
                Page     = '<script src="/static/app.js"></script><iframe src="/cgi-bin/ui/;stok=PROMPTSECRET1/admin/menu.htm"></iframe>'
                Wire     = @('http://router.test/cgi-bin/ui/;stok=PROMPTSECRET1/', 'http://router.test/static/app.js', 'http://router.test/cgi-bin/ui/;stok=PROMPTSECRET1/admin/menu.htm')
                Recorded = 'http://router.test/cgi-bin/ui/admin/menu.htm'
            }
            @{
                Case     = 'appended'
                Start    = 'http://router.test/app/home.jsp'
                Pasted   = "curl 'http://router.test/app/home.jsp;jsessionid=PROMPTSECRET2'"
                Page     = '<script src="/app/main.js"></script>'
                Wire     = @('http://router.test/app/home.jsp;jsessionid=PROMPTSECRET2', 'http://router.test/app/main.js;jsessionid=PROMPTSECRET2')
                Recorded = 'http://router.test/app/main.js'
            }
        ) {
            $Site[$Wire[0]] = New-TestResponse -Content $Page
            foreach ($wireUri in $Wire | Select-Object -Skip 1) { $Site[$wireUri] = New-TestResponse -Content '<script>x()</script>' }
            Mock Read-Host { ConvertTo-SecureString -String $Pasted -AsPlainText -Force }

            $output   = & $SCRIPT_PATH -Uri $Start -OutputDirectory $OutputDirectory @PromptConfig -Verbose 4>&1 3>&1 | Out-String
            $manifest = Get-Content -Path (Join-Path $OutputDirectory 'unwire-assets.json') -Raw

            foreach ($wireUri in $Wire) {
                Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri.AbsoluteUri -EQ $wireUri }
            }
            ($manifest | ConvertFrom-Json).assets.Uri | Should -Contain $Recorded
            $manifest                                 | Should -Not -Match 'PROMPTSECRET'
            $output                                   | Should -Not -Match 'PROMPTSECRET'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { "$($Headers.Referer)" -MATCH 'PROMPTSECRET' }
        }

        It 'prompt_curl_no_session: fails early on a cURL without any session' {
            Mock Read-Host { ConvertTo-SecureString -String "curl 'http://router.test/' -H 'accept: text/html' -H 'user-agent: PROMPT-SECRET'" -AsPlainText -Force }

            $thrown = { & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @PromptConfig } | Should -Throw -ExceptionType ([System.ArgumentException]) -PassThru

            $thrown.Exception.Message | Should -BeLike "The cURL must carry a session*first POST of type 'document'*Got: *starts with 'curl'."
            $thrown.Exception.Message | Should -Not -Match 'PROMPT-SECRET'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 'prompt_curl_parameter: takes the session parameter out of the <Case> of a pasted cURL' -ForEach @(
            @{ Case = 'data';     Lines = @("curl 'https://router.test/' \", "  -H 'accept: text/html' \", "  --data-raw 'reload=true&sid=PROMPT-SECRET&forward='") }
            @{ Case = 'URL';      Lines = @('curl ^"https://router.test/data.lua?lang=de^&sid=PROMPT-SECRET^" ^', '  -H ^"accept: */*^"') }
            @{ Case = 'pair';     Lines = @('sid=PROMPT-SECRET') }
            @{ Case = 'bare';     Lines = @('PROMPT-SECRET') }
        ) {
            $Site['http://router.test/?sid=PROMPT-SECRET']       = New-TestResponse -Content '<script src="/app.js"></script>'
            $Site['http://router.test/app.js?sid=PROMPT-SECRET'] = New-TestResponse -Content 'a()'
            $pasted = [System.Collections.Generic.Queue[System.String]]::new([System.String[]] $Lines)
            Mock Read-Host { ConvertTo-SecureString -String $pasted.Dequeue() -AsPlainText -Force }

            $summary = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @PromptConfig -SessionParameter 'sid'

            $summary.Saved | Should -Be 1
            Should -Invoke Invoke-WebRequest -Times 2 -Exactly -ParameterFilter { $Uri.Query -EQ '?sid=PROMPT-SECRET' }
        }

        It 'prompt_curl_no_param: fails early on a cURL without the parameter, shows only its shape' {
            Mock Read-Host { ConvertTo-SecureString -String "curl 'https://router.test/' --data-raw 'user=PROMPT-SECRET'" -AsPlainText -Force }

            $thrown = { & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @PromptConfig -SessionParameter 'sid' } | Should -Throw -ExceptionType ([System.ArgumentException]) -PassThru

            $thrown.Exception.Message | Should -BeLike "The session must be a 'Copy as cURL' with 'sid=' *Got: *starts with 'curl'."
            $thrown.Exception.Message | Should -Not -Match 'PROMPT-SECRET'
            Should -Invoke Invoke-WebRequest -Times 0 -Exactly
        }

        It 'prompt_guide: shows the login guide with the URL before the prompt, in <Language>' -ForEach @(
            @{ Language = 'de'; Title = 'Unwire: Login f?r http://router.test/'; Step = '1. *leeren Browser-Tab*F12*'; Blocked = '*Entwicklertools. Zuerst ge?ffnet, kann keine Seite sie sperren.'; PromptLike = 'Session ("Als cURL kopieren")'; Done = 'Fertig.*' }
            @{ Language = 'en'; Title = 'Unwire: login for http://router.test/'; Step = '1. *empty browser tab*F12*'; Blocked = '*Developer tools. Opened first, no page can block it.'; PromptLike = 'Session ("Copy as cURL")'; Done = 'Done.*' }
        ) {
            Mock Read-Host { ConvertTo-SecureString -String 'i_like_gitea=PROMPT-SECRET' -AsPlainText -Force }

            $output = & $SCRIPT_PATH -Uri $START_URI -OutputDirectory $OutputDirectory @GuideConfig -Language $Language 6>&1
            $shown  = @($output | Where-Object { $_ -is [System.Management.Automation.InformationRecord] } | ForEach-Object { "$($_.MessageData)" })

            @($shown -LIKE $Title).Count                       | Should -Be 1
            @($shown -LIKE '3. * http://router.test/ *').Count | Should -Be 1
            @($shown -LIKE $Step).Count                        | Should -Be 1
            @($shown -LIKE $Blocked).Count                     | Should -Be 1
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
