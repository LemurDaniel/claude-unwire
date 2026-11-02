function ConvertTo-UnwireSession {
    <#
    .SYNOPSIS
        Turns pasted text into a session object, or fails with the reason.

    .DESCRIPTION
        > cURL                -> cookie, auth headers and path token, whatever it carries
        > SessionParameter    -> plus the value of that URL parameter, from the cURL or the
                                 pasted 'name=value' or bare value
        > Anything else       -> a cookie in one of the other copy formats
        Throws an ArgumentException when the text carries no usable session. Its message
        shows only the shape of the text (Get-UnwireCookieShape), never its content.

    .EXAMPLE
        PS> (ConvertTo-UnwireSession -Text 'sid=abc123').Kinds
        cookie
    #>
    param (
        <#
        [Required]
        The pasted text: a cURL, a cookie or, with SessionParameter, the parameter value.
        #>
        [System.String]
        $Text,

        <#
        [Optional]
        Name of the URL parameter that carries the session, e.g. 'sid'.
        #>
        [System.String]
        $SessionParameter
    )

    # Session value of SessionParameter: URL-safe characters only, it goes into the query
    $sessionValueRule = '^[\w.~%-]+$'
    # Session values shorter than this are no secret (lang=de) and are not scrubbed
    $minSecretLength  = 6

    $session = [PSCustomObject]@{
        Cookie         = $null
        Headers        = [ordered]@{}     # Authorization and auth headers of a cURL
        UriSession     = @{ Query = $null; PathToken = $null; PathPrefix = $null }     # added on the wire only
        IsUriSession   = $false
        RequestHeaders = [ordered]@{}     # Cookie and auth headers, ready for Invoke-WebRequest
        Kinds          = @()
        Secrets        = @()
    }
    $isCurlPaste = $Text.TrimStart() -MATCH '^curl\s'

    # cURL
    if ($isCurlPaste) {
        $curlSession                   = ConvertFrom-UnwireCurlSession -Text $Text
        $session.Cookie                = $curlSession.Cookie
        $session.Headers               = $curlSession.Headers
        $session.UriSession.PathToken  = $curlSession.PathToken
        $session.UriSession.PathPrefix = $curlSession.PathPrefix
        if ($null -NE $curlSession.PathToken -AND $curlSession.PathToken -NOTMATCH '^[\w.-]+=[\w.~%+-]+$') {
            throw [System.ArgumentException]::new("The session token in the cURL path must be 'name=value' with URL-safe characters. Got: $(Get-UnwireCookieShape -Text $curlSession.PathToken).")
        }
    }
    # SessionParameter
    if (-NOT [System.String]::IsNullOrEmpty($SessionParameter)) {
        $sessionValue = ConvertTo-UnwireSessionValue -Text $Text -Name $SessionParameter
        if ($sessionValue -NOTMATCH $sessionValueRule) {
            throw [System.ArgumentException]::new("The session must be a 'Copy as cURL' with '$SessionParameter=' in its URL or data, '$SessionParameter=<VALUE>' or the bare value, URL-safe characters only. Got: $(Get-UnwireCookieShape -Text $sessionValue).")
        }
        $session.UriSession.Query = "$SessionParameter=$sessionValue"
    }
    # Anything else
    elseif (-NOT $isCurlPaste) {
        $session.Cookie = ConvertTo-UnwireCookieHeader -Text $Text
        # A bare value without its name is the most common copy mistake.
        if ($session.Cookie -NOTMATCH '^[^=\s;]+=\S') {
            throw [System.ArgumentException]::new("The session cookie must be 'name=value', e.g. 'sid=<VALUE>' or 'session_id=<VALUE>', with the name from the browser's cookie list (a cURL without a cookie: the UI may keep its session in a URL parameter, see -SessionParameter). Got: $(Get-UnwireCookieShape -Text $session.Cookie).")
        }
    }

    # A cURL without any session is the wrong request (the reload before the POST, a script).
    if ($isCurlPaste -AND $null -EQ $session.Cookie -AND $session.Headers.Count -EQ 0 -AND $null -EQ $session.UriSession.PathToken -AND $null -EQ $session.UriSession.Query) {
        throw [System.ArgumentException]::new("The cURL must carry a session: a cookie, an Authorization or auth header (X-Auth-Token, ...) or a ';name=value' token in its path; a session in a form field needs -SessionParameter. Copy the first POST of type 'document' after the reload, else the reload itself. Got: $(Get-UnwireCookieShape -Text $Text).")
    }

    $session.IsUriSession = $null -NE $session.UriSession.Query -OR $null -NE $session.UriSession.PathToken
    if ($null -NE $session.Cookie) {
        $session.RequestHeaders.Cookie = $session.Cookie
    }
    foreach ($headerName in $session.Headers.Keys) {
        $session.RequestHeaders[$headerName] = $session.Headers[$headerName]
    }

    # Names only, for logs and records: 'cookie', 'header:Authorization', 'path-token', 'query:sid'
    $session.Kinds = @(
        if ($null -NE $session.Cookie) { 'cookie' }
        $session.Headers.Keys | ForEach-Object { "header:$_" }
        if ($null -NE $session.UriSession.PathToken) { 'path-token' }
        if ($null -NE $session.UriSession.Query) { "query:$SessionParameter" }
    )

    # Every session value, for ConvertTo-UnwireRedactedText.
    # 'sid=abc123; lang=de' => 'abc123' ('de' is too short to be a secret)
    # 'Basic dXNlcjpwdw==' => 'Basic dXNlcjpwdw==', 'dXNlcjpwdw=='
    $session.Secrets = @(
        @(
            if ($null -NE $session.UriSession.Query) { $session.UriSession.Query.Substring($session.UriSession.Query.IndexOf('=') + 1) }
            if ($null -NE $session.UriSession.PathToken) { $session.UriSession.PathToken.Substring($session.UriSession.PathToken.IndexOf('=') + 1) }
            if ($null -NE $session.Cookie) { $session.Cookie.Split(';') | ForEach-Object { $_.Substring($_.IndexOf('=') + 1).Trim() } }
            foreach ($headerValue in $session.Headers.Values) {
                $headerValue
                if ($headerValue.Contains(' ')) { $headerValue.Substring($headerValue.IndexOf(' ') + 1).Trim() }
            }
        ) | Where-Object { $_.Length -GE $minSecretLength }
    )
    return $session
}
