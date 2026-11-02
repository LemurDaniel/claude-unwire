function Read-UnwireSession {
    <#
    .SYNOPSIS
        Reads the session of a signed-in browser from a masked prompt or a variable.

    .DESCRIPTION
        -PromptSession shows the login guide of GuideFile in Language, then asks with a masked
        prompt (interactive, nothing on disk). -UseSession reads the environment variable
        SessionVariable (tests and mock runs only, never the agent). ConvertTo-UnwireSession reads the text for every session
        it carries.

        In the prompt, up to three pastes:
        > No usable session          -> the reason (shape only) and the 'retry' hint of the
                                        guide, then a new paste; the last failure throws
        > Only a cookie, with        -> the 'cookieOnly' hint: a new paste replaces it, an
          ConfirmCookieOnly             empty one keeps the cookie
        > Otherwise                  -> the session
        Returns $null without PromptSession and UseSession. The session value never goes into
        a message, a log line or the result's Kinds; Secrets lists every value for
        ConvertTo-UnwireRedactedText.

    .EXAMPLE
        Ask in a window the user types into:

        PS> $session = Read-UnwireSession -PromptSession -Uri 'http://router.test/' -GuideFile ./data/login-guide.json -Language de
        PS> $session.Kinds
        cookie
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'The login guide is for the user in the PromptSession window, not pipeline output.')]
    param (
        <#
        [Optional]
        Asks for the session with a masked prompt.
        #>
        [switch]
        $PromptSession,

        <#
        [Optional]
        Reads the session from the environment variable SessionVariable.
        #>
        [switch]
        $UseSession,

        <#
        [Optional]
        Environment variable for UseSession. Default is UNWIRE_COOKIE.
        #>
        [System.String]
        $SessionVariable = 'UNWIRE_COOKIE',

        <#
        [Optional]
        Name of the URL parameter that carries the session, e.g. 'sid'.
        #>
        [System.String]
        $SessionParameter,

        <#
        [Optional]
        Asks once more when the paste carries only a cookie: API requests of many apps send
        the login as an Authorization header instead. For requests to endpoints.
        #>
        [switch]
        $ConfirmCookieOnly,

        <#
        [Optional]
        The page the user logs in to, shown in the login guide.
        #>
        [System.Uri]
        $Uri,

        <#
        [Optional]
        The login guide for PromptSession, e.g. skills/analyze/data/login-guide.json.
        #>
        [System.String]
        $GuideFile,

        <#
        [Optional]
        Language key of the guide ('en', 'de'). Default is en, an unknown one falls back to en.
        #>
        [System.String]
        $Language = 'en'
    )

    $defaultLanguage = 'en'
    $maxPastes       = 3

    <#
        Order of precedence:
        - PromptSession  -> masked prompt, with retries
        - UseSession     -> environment variable SessionVariable, fails at once
        - neither        -> no session
    #>
    # UseSession -> environment variable SessionVariable
    if (-NOT $PromptSession -AND $UseSession) {
        $variableText = [System.Environment]::GetEnvironmentVariable($SessionVariable)
        if ([System.String]::IsNullOrWhiteSpace($variableText)) {
            throw [System.ArgumentException]::new("Environment variable '$SessionVariable' must hold the session cookie for UseSession, e.g. 'session_id=<VALUE>'.")
        }
        return ConvertTo-UnwireSession -Text $variableText -SessionParameter $SessionParameter
    }
    # neither -> no session
    if (-NOT $PromptSession) {
        return $null
    }

    # PromptSession -> hard-coded guide, so the steps reach the user even when the chat only
    # announced them.
    $guides = Get-Content -Path $GuideFile -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    if (-NOT $guides.ContainsKey($Language)) {
        Write-Verbose "[Read-UnwireSession] No login guide in '$Language' -> using '$defaultLanguage'."
    }
    $loginGuide = $guides[$(if ($guides.ContainsKey($Language)) { $Language } else { $defaultLanguage })]

    Write-Host ''
    Write-Host $loginGuide.title.Replace('{URL}', $Uri.AbsoluteUri)
    Write-Host ''
    $loginGuide.steps | ForEach-Object { Write-Host $_.Replace('{URL}', $Uri.AbsoluteUri) }
    Write-Host ''
    Write-Host $loginGuide.warning
    Write-Host ''

    $cookieOnlySession = $null     # kept when the user answers the cookieOnly hint with Enter
    for ($paste = 1; $paste -LE $maxPastes; $paste++) {
        $pastedText = Read-UnwirePaste -Prompt $loginGuide.prompt

        # Only a cookie, then Enter: the user keeps the cookie.
        if ($null -NE $cookieOnlySession -AND [System.String]::IsNullOrWhiteSpace($pastedText)) {
            Write-Verbose '[Read-UnwireSession] Empty paste after the cookie hint -> keeping the cookie.'
            return $cookieOnlySession
        }

        # No usable session: the reason, the hint, a new paste; the last failure throws.
        try {
            $session = ConvertTo-UnwireSession -Text $pastedText -SessionParameter $SessionParameter
        }
        catch [System.ArgumentException] {
            if ($paste -GE $maxPastes) {
                if ($null -NE $cookieOnlySession) {
                    return $cookieOnlySession
                }
                throw
            }
            Write-Host ''
            Write-Host $loginGuide.retry.Replace('{REASON}', $_.Exception.Message)
            Write-Host ''
            continue
        }

        # Only a cookie, with ConfirmCookieOnly: one hint, a new paste replaces it.
        $isCookieOnly = $session.Headers.Count -EQ 0 -AND -NOT $session.IsUriSession
        if ($ConfirmCookieOnly -AND $isCookieOnly -AND $null -EQ $cookieOnlySession -AND $paste -LT $maxPastes) {
            $cookieOnlySession = $session
            Write-Host ''
            Write-Host $loginGuide.cookieOnly
            Write-Host ''
            continue
        }

        # Otherwise
        return $session
    }
}
