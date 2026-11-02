# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./plugins/unwire

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The Read-Host mocks return fake test sessions.')]
param ()

# ===========================================================================
# ===========================   READ THE SESSION   ==========================
# ===========================================================================
#
#   no_session          Returns nothing without PromptSession and UseSession.
#   variable_cookie     Reads a cookie from the variable, kinds and secrets without names.
#   curl_headers        Takes cookie and auth headers out of a pasted cURL.
#   session_parameter   Takes the URL parameter, adds it to a URI only on the wire.
#   bare_value          Fails on a value without its name, shows only its shape.
#   short_values        Keeps values shorter than six characters out of the secrets.
#   prompt_retry        Asks again with the reason and the hint after a paste without session.
#   prompt_retry_limit  Throws after the third paste without session.
#   cookie_only_new     Shows the cookie hint once, a new paste with a header replaces it.
#   cookie_only_kept    Keeps the cookie when the user answers the hint with Enter.
#   cookie_only_off     Takes a cookie at once without ConfirmCookieOnly.
#   guide_texts         Every language has the retry and cookieOnly hints.
#

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath '../session/Session.ps1')

    $GUIDE_FILE = Join-Path -Path $PSScriptRoot -ChildPath '../../skills/analyze/data/login-guide.json'
}

Describe 'Read-UnwireSession' {
    It 'no_session: returns nothing without PromptSession and UseSession' {
        Read-UnwireSession | Should -BeNullOrEmpty
    }

    It 'variable_cookie: reads a cookie from the variable, kinds and secrets without names' {
        $env:UNWIRE_TEST_SESSION = 'sid=TOP-SECRET-VALUE'
        try {
            $session = Read-UnwireSession -UseSession -SessionVariable UNWIRE_TEST_SESSION
        }
        finally {
            Remove-Item -Path Env:UNWIRE_TEST_SESSION
        }

        $session.RequestHeaders.Cookie | Should -Be 'sid=TOP-SECRET-VALUE'
        $session.Kinds                 | Should -Be @('cookie')
        $session.Secrets               | Should -Be @('TOP-SECRET-VALUE')
        $session.IsUriSession          | Should -BeFalse
    }

    It 'curl_headers: takes cookie and auth headers out of a pasted cURL' {
        Mock Write-Host { }
        Mock Read-Host { ConvertTo-SecureString -String "curl 'http://router.test/api' -H 'accept: */*' -H 'Authorization: Bearer TOKEN-SECRET' -b 'sid=COOKIE-SECRET'" -AsPlainText -Force }

        $session = Read-UnwireSession -PromptSession -Uri 'http://router.test/' -GuideFile $GUIDE_FILE

        $session.RequestHeaders.Cookie        | Should -Be 'sid=COOKIE-SECRET'
        $session.RequestHeaders.Authorization | Should -Be 'Bearer TOKEN-SECRET'
        $session.RequestHeaders.Contains('accept') | Should -BeFalse
        $session.Kinds                        | Should -Be @('cookie', 'header:Authorization')
        $session.Secrets                      | Should -Contain 'TOKEN-SECRET'
    }

    It 'session_parameter: takes the URL parameter, adds it to a URI only on the wire' {
        $env:UNWIRE_TEST_SESSION = "curl 'http://router.test/menu.htm?sid=PARAM-SECRET&lang=de'"
        try {
            $session = Read-UnwireSession -UseSession -SessionVariable UNWIRE_TEST_SESSION -SessionParameter sid
        }
        finally {
            Remove-Item -Path Env:UNWIRE_TEST_SESSION
        }
        $uriSession = $session.UriSession

        $session.IsUriSession                                                     | Should -BeTrue
        $session.Kinds                                                            | Should -Be @('query:sid')
        (Get-UnwireRequestUri -Uri 'http://router.test/api/x?v=2' @uriSession).AbsoluteUri | Should -Be 'http://router.test/api/x?v=2&sid=PARAM-SECRET'
    }

    It 'bare_value: fails on a value without its name, shows only its shape' {
        $env:UNWIRE_TEST_SESSION = 'TOP-SECRET-VALUE'
        try {
            { Read-UnwireSession -UseSession -SessionVariable UNWIRE_TEST_SESSION } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "*must be 'name=value'*16 characters, no '='*"
        }
        finally {
            Remove-Item -Path Env:UNWIRE_TEST_SESSION
        }
    }

    It 'short_values: keeps values shorter than six characters out of the secrets' {
        $env:UNWIRE_TEST_SESSION = 'sid=LONG-SECRET; lang=de'
        try {
            $session = Read-UnwireSession -UseSession -SessionVariable UNWIRE_TEST_SESSION
        }
        finally {
            Remove-Item -Path Env:UNWIRE_TEST_SESSION
        }

        $session.Secrets | Should -Be @('LONG-SECRET')
    }

    Context 'prompt' {
        BeforeEach {
            # Every Read-Host answers with the next paste of the queue, '' as an empty Enter.
            $Pastes = [System.Collections.Generic.Queue[System.String]]::new()
            Mock Read-Host {
                $next = $Pastes.Dequeue()
                if ($next -EQ '') { return [System.Security.SecureString]::new() }
                ConvertTo-SecureString -String $next -AsPlainText -Force
            }
            Mock Write-Host { }
            $PromptConfig = @{ PromptSession = $true; Uri = 'http://router.test/'; GuideFile = $GUIDE_FILE }
        }

        It 'prompt_retry: asks again with the reason and the hint after a paste without session' {
            $Pastes.Enqueue("curl 'http://router.test/app.js' -H 'accept: */*'")
            $Pastes.Enqueue("curl 'http://router.test/api' -H 'Authorization: Bearer TOKEN-SECRET'")

            $session = Read-UnwireSession @PromptConfig

            $session.Kinds | Should -Be @('header:Authorization')
            Should -Invoke Read-Host -Times 2 -Exactly
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { "$Object" -LIKE "No usable session in this paste: The cURL must carry a session*Fetch/XHR*" }
            Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter { "$Object" -MATCH 'TOKEN-SECRET' }
        }

        It 'prompt_retry_limit: throws after the third paste without session' {
            1..3 | ForEach-Object { $Pastes.Enqueue('BARE-SECRET-VALUE') }

            { Read-UnwireSession @PromptConfig } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage "*must be 'name=value'*"
            Should -Invoke Read-Host -Times 3 -Exactly
        }

        It 'cookie_only_new: shows the cookie hint once, a new paste with a header replaces it' {
            $Pastes.Enqueue("curl 'http://router.test/' -b 'sid=COOKIE-SECRET'")
            $Pastes.Enqueue("curl 'http://router.test/rest/user/whoami' -H 'Authorization: Bearer TOKEN-SECRET' -b 'sid=COOKIE-SECRET'")

            $session = Read-UnwireSession @PromptConfig -ConfirmCookieOnly

            $session.Kinds | Should -Be @('cookie', 'header:Authorization')
            Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { "$Object" -LIKE "This paste carries only a cookie*" }
        }

        It 'cookie_only_kept: keeps the cookie when the user answers the hint with Enter' {
            $Pastes.Enqueue("curl 'http://router.test/' -b 'sid=COOKIE-SECRET'")
            $Pastes.Enqueue('')

            $session = Read-UnwireSession @PromptConfig -ConfirmCookieOnly

            $session.RequestHeaders.Cookie | Should -Be 'sid=COOKIE-SECRET'
            Should -Invoke Read-Host -Times 2 -Exactly
        }

        It 'cookie_only_off: takes a cookie at once without ConfirmCookieOnly' {
            $Pastes.Enqueue("curl 'http://router.test/' -b 'sid=COOKIE-SECRET'")

            $session = Read-UnwireSession @PromptConfig

            $session.Kinds | Should -Be @('cookie')
            Should -Invoke Read-Host -Times 1 -Exactly
        }
    }

    It 'guide_texts: every language has the retry and cookieOnly hints' {
        $guides = Get-Content -Path $GUIDE_FILE -Raw | ConvertFrom-Json -AsHashtable

        foreach ($language in $guides.Keys) {
            $guides[$language]['retry']      | Should -Match '\{REASON\}' -Because "$language.retry shows the reason"
            $guides[$language]['cookieOnly'] | Should -Match 'Authorization' -Because "$language.cookieOnly names the header"
        }
    }
}
