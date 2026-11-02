# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./plugins/unwire

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
param ()

# ===========================================================================
# ======================   REQUEST WITHOUT REDIRECTS   ======================
# ===========================================================================
#
#   plain_response       Returns a 200 response unchanged.
#   redirect_returned    Returns a 3xx response instead of a terminating error.
#   other_error_thrown   Throws every error that is not the redirect error.
#

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../Invoke-UnwireWebRequest.ps1')

    $REQUEST_CONFIG = @{ Method = 'Get'; MaximumRedirection = 0; SkipHttpErrorCheck = $true }
    $TARGET_URI     = 'http://router.test/api-docs'
}

Describe 'Invoke-UnwireWebRequest' {
    BeforeEach {
        # Callers run with 'Stop', which turns the redirect error into a terminating one.
        $ErrorActionPreference = 'Stop'
    }

    It 'plain_response: returns a 200 response unchanged' {
        Mock Invoke-WebRequest { [PSCustomObject]@{ StatusCode = 200; Content = 'ok' } }

        $response = Invoke-UnwireWebRequest -RequestConfig $REQUEST_CONFIG -Uri $TARGET_URI

        $response.StatusCode | Should -Be 200
        $response.Content    | Should -Be 'ok'
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $MaximumRedirection -EQ 0 }
    }

    It 'redirect_returned: returns a 3xx response instead of a terminating error' {
        # Mirrors pwsh 7.4+: the 3xx response plus a MaximumRedirectExceeded error.
        Mock Invoke-WebRequest {
            Write-Error -Message 'The maximum redirection count has been exceeded.' -ErrorId 'MaximumRedirectExceeded'
            [PSCustomObject]@{ StatusCode = 301; Headers = @{ Location = @('/api-docs/') } }
        }

        $response = Invoke-UnwireWebRequest -RequestConfig $REQUEST_CONFIG -Uri $TARGET_URI

        $response.StatusCode           | Should -Be 301
        $response.Headers['Location']  | Should -Be '/api-docs/'
    }

    It 'other_error_thrown: throws every error that is not the redirect error' {
        Mock Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('No such host is known.') }

        { Invoke-UnwireWebRequest -RequestConfig $REQUEST_CONFIG -Uri $TARGET_URI } | Should -Throw -ExceptionType ([System.Net.Http.HttpRequestException]) -ExpectedMessage 'No such host is known.'
    }
}
