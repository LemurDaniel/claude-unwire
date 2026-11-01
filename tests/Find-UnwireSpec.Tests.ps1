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
#   openapi_json        Detects an OpenAPI JSON spec with version and title.
#   swagger_yaml        Detects a Swagger YAML spec.
#   swagger_ui          Reports a Swagger UI page as documentation.
#   redirect_ignored    Ignores redirects, they usually lead to a login page.
#   no_hits             Returns nothing and warns when no path has docs.
#   saves_specs         Saves found specs into OutputDirectory.
#   get_only            Never sends anything but GET.
#   unreachable         Fails with a clear error on an unreachable host.
#   invalid_uri         Fails early on a URI that is not http(s).
#

BeforeAll {
    $SCRIPT_PATH = Join-Path -Path $PSScriptRoot -ChildPath '../scripts/Find-UnwireSpec.ps1'
    $BASE_URI    = 'http://router.test'

    function New-TestResponse {
        param ([System.Int32] $StatusCode, [System.String] $Content = '')
        return [PSCustomObject]@{ StatusCode = $StatusCode; Content = $Content }
    }
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

        $pathCount = (Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath '../scripts/data/spec-paths.json') -Raw | ConvertFrom-Json).paths.Count
        Should -Invoke Invoke-WebRequest -Times $pathCount -Exactly -ParameterFilter { $Method -EQ 'Get' -AND $MaximumRedirection -EQ 0 }
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Method -NE 'Get' }
    }

    It 'unreachable: fails with a clear error on an unreachable host' {
        Mock Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('No such host is known.') }

        { & $SCRIPT_PATH -Uri $BASE_URI } | Should -Throw -ExceptionType ([System.InvalidOperationException]) -ExpectedMessage "Uri 'http://router.test/' must be reachable*"
    }

    It 'invalid_uri: fails early on a URI that is not http(s)' {
        { & $SCRIPT_PATH -Uri 'ftp://router.test' } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*absolute http or https URI*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }
}
