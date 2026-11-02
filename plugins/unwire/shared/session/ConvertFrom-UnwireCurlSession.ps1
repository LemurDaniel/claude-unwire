function ConvertFrom-UnwireCurlSession {
    <#
    .SYNOPSIS
        Reads every session a pasted "Copy as cURL" carries.

    .DESCRIPTION
        Bash and cmd (^"...^") quoting:
        > -b / --cookie, else the cookie: header   -> Cookie
        > Authorization header                     -> Headers, as it is (Basic, Bearer, own
                                                      schemes); Digest is rejected, its answer
                                                      is valid for one URL and nonce only
        > Auth headers (X-Auth-Token, ...)         -> Headers, as they are
        > ';name=value' in the URL path            -> PathToken, with PathPrefix when it is a
                                                      segment of its own
        Other headers (accept, user-agent, ...) are dropped.

    .EXAMPLE
        PS> (ConvertFrom-UnwireCurlSession -Text "curl 'http://router.test/' -b 'sid=abc'").Cookie
        sid=abc
    #>
    param (
        <#
        [Required]
        The pasted cURL command, continuation lines already joined.
        #>
        [System.String]
        $Text
    )

    # Headers that carry a session: Authorization, X-Auth-Token, X-CSRF-Token, X-Api-Key
    $sessionHeader = '^(?i)(authorization|x-[\w-]*(auth|token|session|api-?key)[\w-]*)$'
    # Session token in the URL path:
    # - own segment:   '/cgi-bin/ui/;stok=abc/admin'  => prefix '/cgi-bin/ui/', token 'stok=abc'
    # - appended:      '/app/home.jsp;jsessionid=abc' => token 'jsessionid=abc'
    $pathTokenSegment = '^(?<prefix>/(?:[^/;]+/)*);(?<token>[\w.-]+=[^/;]+)(?:/|$)'
    $pathTokenSuffix  = '[^/;]+;(?<token>[\w.-]+=[^/;]+)$'

    $value = $Text.Trim()
    # cmd format escapes with '^': -b ^"a=b; c=d^" => -b "a=b; c=d"
    if ($value.Contains('^"')) {
        $value = $value -REPLACE '\^(.)', '$1'
    }
    $session = [PSCustomObject]@{ Cookie = $null; Headers = [ordered]@{}; PathToken = $null; PathPrefix = $null }

    # -b / --cookie, else the cookie: header
    $cookie = [System.Text.RegularExpressions.Regex]::Match($value, '(?:-b|--cookie)\s+(?<q>[''"])(?<value>.*?)\k<q>')
    if (-NOT $cookie.Success) {
        $cookie = [System.Text.RegularExpressions.Regex]::Match($value, '-H\s+(?<q>[''"])(?i:cookie):\s*(?<value>.*?)\k<q>')
    }
    if ($cookie.Success) {
        $session.Cookie = $cookie.Groups['value'].Value.Trim()
    }

    # Authorization and auth headers
    foreach ($header in [System.Text.RegularExpressions.Regex]::Matches($value, '-H\s+(?<q>[''"])(?<name>[\w-]+):\s*(?<value>.*?)\k<q>')) {
        $headerName = $header.Groups['name'].Value
        if ($headerName -NOTMATCH $sessionHeader) {
            continue
        }
        if ($header.Groups['value'].Value -MATCH '^(?i)Digest\s') {
            throw [System.ArgumentException]::new("The session must not be HTTP Digest: its Authorization header is valid for one URL only. Save the UI in the browser ('Save page as') and analyze the local folder instead.")
        }
        $session.Headers[$headerName] = $header.Groups['value'].Value.Trim()
    }

    # ';name=value' in the URL path
    $url = [System.Text.RegularExpressions.Regex]::Match($value, '^curl\s+(?:--url\s+)?(?<q>[''"])(?<url>[^''"]+)\k<q>')
    $curlUri = $null
    if ($url.Success -AND [System.Uri]::TryCreate($url.Groups['url'].Value, [System.UriKind]::Absolute, [ref] $curlUri)) {
        $segment = [System.Text.RegularExpressions.Regex]::Match($curlUri.AbsolutePath, $pathTokenSegment)
        $suffix  = [System.Text.RegularExpressions.Regex]::Match($curlUri.AbsolutePath, $pathTokenSuffix)
        if ($segment.Success) {
            $session.PathToken  = $segment.Groups['token'].Value
            $session.PathPrefix = $segment.Groups['prefix'].Value
        }
        elseif ($suffix.Success) {
            $session.PathToken = $suffix.Groups['token'].Value
        }
    }
    return $session
}
