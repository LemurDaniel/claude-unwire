# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./tests

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'The test helper only builds an in-memory object.')]
param ()

# ===========================================================================
# =====================   DETECT PUBLISHED DOCUMENTATION   ==================
# ===========================================================================
#
#   openapi_json            Detects an OpenAPI JSON spec with version and title.
#   swagger_yaml            Detects a Swagger YAML spec.
#   swagger_ui              Reports a Swagger UI page as documentation.
#   redirect_ignored        Ignores redirects, they usually lead to a login page.
#   redirect_error_skipped  Skips a redirect pwsh reports as an error.
#   slash_redirect          Follows a redirect that only adds a trailing slash.
#   other_redirect          Never follows a redirect to another path.
#   embedded_spec           Reads and saves a spec a Swagger UI script embeds as swaggerDoc.
#   swagger_ui_url          Probes a spec URL of the same origin, never another origin.
#   no_hits                 Returns nothing and warns when no path has docs.
#   saves_specs             Saves found specs into OutputDirectory.
#   get_only                Never sends anything but GET.
#   unreachable             Fails with a clear error on an unreachable host.
#   untrusted_certificate   Stops after the first request on an untrusted certificate.
#   invalid_uri             Fails early on a URI that is not http(s).
#

BeforeAll {
    $SCRIPT_PATH = Join-Path -Path $PSScriptRoot -ChildPath '../scripts/Find-UnwireSpec.ps1'
    $BASE_URI    = 'http://router.test'

    function New-TestResponse {
        param ([System.Int32] $StatusCode, [System.String] $Content = '', [System.Collections.Hashtable] $Headers = @{})
        return [PSCustomObject]@{ StatusCode = $StatusCode; Content = $Content; Headers = $Headers }
    }

    # A Swagger UI page under /api-docs/ that loads its configuration script.
    $SWAGGER_PAGE = '<div id="swagger-ui"></div><script src="./swagger-ui-bundle.js"></script><script src="./swagger-ui-init.js"></script>'
}

Describe 'Find-UnwireSpec' {
    BeforeEach {
        # Every path without its own mock answers 404.
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 404 }
    }

    It 'openapi_json: detects an OpenAPI JSON spec with version and title' {
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 200 -Content '{"openapi":"3.0.1","info":{"title":"Router API"}}' } -ParameterFilter { $Uri.AbsolutePath -EQ '/openapi.json' }

        $hits = @(& $SCRIPT_PATH -Uri $BASE_URI -WarningAction SilentlyContinue)

        $hits.Count      | Should -Be 1
        $hits[0].Uri     | Should -Be 'http://router.test/openapi.json'
        $hits[0].Kind    | Should -Be 'OpenApi'
        $hits[0].Version | Should -Be '3.0.1'
        $hits[0].Title   | Should -Be 'Router API'
    }

    It 'swagger_yaml: detects a Swagger YAML spec' {
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 200 -Content "swagger: '2.0'`ninfo:`n  title: NAS API`n" } -ParameterFilter { $Uri.AbsolutePath -EQ '/swagger.yaml' }

        $hits = @(& $SCRIPT_PATH -Uri $BASE_URI)

        $hits.Count      | Should -Be 1
        $hits[0].Kind    | Should -Be 'OpenApiYaml'
        $hits[0].Version | Should -Be '2.0'
        $hits[0].Title   | Should -Be 'NAS API'
    }

    It 'swagger_ui: reports a Swagger UI page as documentation' {
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 200 -Content '<div id="swagger-ui"></div>' } -ParameterFilter { $Uri.AbsolutePath -EQ '/swagger-ui/' }

        $hits = @(& $SCRIPT_PATH -Uri $BASE_URI)

        $hits.Count   | Should -Be 1
        $hits[0].Kind | Should -Be 'SwaggerUi'
    }

    It 'redirect_ignored: ignores redirects, they usually lead to a login page' {
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 302 -Content '{"openapi":"3.0.1"}' } -ParameterFilter { $Uri.AbsolutePath -EQ '/openapi.json' }

        $hits = @(& $SCRIPT_PATH -Uri $BASE_URI -WarningAction SilentlyContinue)

        $hits.Count | Should -Be 0
    }

    It 'redirect_error_skipped: skips a redirect pwsh reports as an error' {
        # pwsh 7.4+ reports a 3xx under MaximumRedirection 0 as MaximumRedirectExceeded.
        Mock Invoke-WebRequest {
            Write-Error -Message 'The maximum redirection count has been exceeded.' -ErrorId 'MaximumRedirectExceeded'
            New-TestResponse -StatusCode 301
        } -ParameterFilter { $Uri.AbsolutePath -EQ '/api-docs' }
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 200 -Content '{"openapi":"3.0.1","info":{"title":"Router API"}}' } -ParameterFilter { $Uri.AbsolutePath -EQ '/v3/api-docs' }

        $hits = @(& $SCRIPT_PATH -Uri $BASE_URI)

        $hits.Count   | Should -Be 1
        $hits[0].Path | Should -Be 'v3/api-docs'
    }

    It 'slash_redirect: follows a redirect that only adds a trailing slash' {
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 301 -Headers @{ Location = @('/api-docs/') } } -ParameterFilter { $Uri.AbsolutePath -EQ '/api-docs' }
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 200 -Content $SWAGGER_PAGE } -ParameterFilter { $Uri.AbsolutePath -EQ '/api-docs/' }

        $hits = @(& $SCRIPT_PATH -Uri $BASE_URI -Path 'api-docs')

        $hits.Count   | Should -Be 1
        $hits[0].Kind | Should -Be 'SwaggerUi'
        $hits[0].Uri  | Should -Be 'http://router.test/api-docs/'
    }

    It 'other_redirect: never follows a redirect to another path' {
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 302 -Headers @{ Location = @('/login?next=/api-docs/') } } -ParameterFilter { $Uri.AbsolutePath -EQ '/api-docs' }

        $hits = @(& $SCRIPT_PATH -Uri $BASE_URI -Path 'api-docs' -WarningAction SilentlyContinue)

        $hits.Count | Should -Be 0
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/login' }
    }

    It 'embedded_spec: reads the spec a Swagger UI script embeds as swaggerDoc and saves it' {
        $init = 'window.onload = function() { var options = { "swaggerDoc": { "openapi": "3.0.0", "info": { "title": "B2B API", "description": "braces } in a string {" }, "paths": {} }, "customOptions": {} }; }'
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 200 -Content $SWAGGER_PAGE } -ParameterFilter { $Uri.AbsolutePath -EQ '/api-docs/' }
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 200 -Content $init } -ParameterFilter { $Uri.AbsolutePath -EQ '/api-docs/swagger-ui-init.js' }
        $outputDirectory = Join-Path -Path $TestDrive -ChildPath 'embedded'

        $hits = @(& $SCRIPT_PATH -Uri $BASE_URI -Path 'api-docs/' -OutputDirectory $outputDirectory)
        $spec = Get-Content -Path $hits[1].SavedFile -Raw | ConvertFrom-Json

        $hits.Kind         | Should -Be @('SwaggerUi', 'OpenApi')
        $hits[1].Path      | Should -Be 'api-docs/swagger-ui-init.js#swaggerDoc'
        $hits[1].Title     | Should -Be 'B2B API'
        $spec.info.description | Should -Be 'braces } in a string {'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Uri.AbsolutePath -EQ '/api-docs/swagger-ui-bundle.js' }
    }

    It 'swagger_ui_url: probes a spec URL of the same origin, never one of another origin' {
        $init = 'window.ui = SwaggerUIBundle({ urls: [{ url: "/v1/openapi.json", name: "v1" }, { url: "https://petstore.swagger.io/v2/swagger.json", name: "demo" }] })'
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 200 -Content $SWAGGER_PAGE } -ParameterFilter { $Uri.AbsolutePath -EQ '/api-docs/' }
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 200 -Content $init } -ParameterFilter { $Uri.AbsolutePath -EQ '/api-docs/swagger-ui-init.js' }
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 200 -Content '{"openapi":"3.1.0","info":{"title":"V1"}}' } -ParameterFilter { $Uri.AbsolutePath -EQ '/v1/openapi.json' }

        $hits = @(& $SCRIPT_PATH -Uri $BASE_URI -Path 'api-docs/')

        $hits.Kind    | Should -Be @('SwaggerUi', 'OpenApi')
        $hits[1].Path | Should -Be 'v1/openapi.json'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Uri.Host -EQ 'petstore.swagger.io' }
    }

    It 'no_hits: returns nothing and warns when no path has docs' {
        $hits = @(& $SCRIPT_PATH -Uri $BASE_URI -WarningVariable warnings -WarningAction SilentlyContinue)

        $hits.Count    | Should -Be 0
        $warnings[0]   | Should -BeLike '*No published documentation found*'
    }

    It 'saves_specs: saves found specs into OutputDirectory' {
        $content = '{"openapi":"3.1.0","info":{"title":"Router API"}}'
        Mock Invoke-WebRequest { New-TestResponse -StatusCode 200 -Content $content } -ParameterFilter { $Uri.AbsolutePath -EQ '/swagger/v1/swagger.json' }
        $outputDirectory = Join-Path -Path $TestDrive -ChildPath 'discover'

        $hits = @(& $SCRIPT_PATH -Uri $BASE_URI -OutputDirectory $outputDirectory)

        $hits[0].SavedFile                     | Should -Be (Join-Path -Path $outputDirectory -ChildPath 'swagger-v1-swagger.json')
        Get-Content -Path $hits[0].SavedFile -Raw | Should -Be $content
    }

    It 'get_only: never sends anything but GET' {
        $null = & $SCRIPT_PATH -Uri $BASE_URI -WarningAction SilentlyContinue

        $pathCount = (Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath '../data/spec-paths.json') -Raw | ConvertFrom-Json).paths.Count
        Should -Invoke Invoke-WebRequest -Times $pathCount -Exactly -ParameterFilter { $Method -EQ 'Get' -AND $MaximumRedirection -EQ 0 }
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Method -NE 'Get' }
    }

    It 'unreachable: fails with a clear error on an unreachable host' {
        Mock Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('No such host is known.') }

        { & $SCRIPT_PATH -Uri $BASE_URI } | Should -Throw -ExceptionType ([System.InvalidOperationException]) -ExpectedMessage "Uri 'http://router.test/' must be reachable*"
    }

    It 'untrusted_certificate: stops after the first request and names SkipCertificateCheck' {
        $inner = [System.Security.Authentication.AuthenticationException]::new('The remote certificate is invalid because of errors in the certificate chain: UntrustedRoot')
        Mock Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('The SSL connection could not be established, see inner exception.', $inner) }

        { & $SCRIPT_PATH -Uri 'https://router.test' } | Should -Throw -ExceptionType ([System.Security.Authentication.AuthenticationException]) -ExpectedMessage "Uri 'https://router.test/' has a TLS certificate this machine does not trust (*UntrustedRoot)*-SkipCertificateCheck*"
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly
    }

    It 'invalid_uri: fails early on a URI that is not http(s)' {
        { & $SCRIPT_PATH -Uri 'ftp://router.test' } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*absolute http or https URI*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }
}
