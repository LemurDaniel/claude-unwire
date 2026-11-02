# NOTE:
#   Mock router of the Unwire testbed: one frame UI from www/, served on one port per login
#   method (data/mock-router.variants.json). Every bug Unwire hit on real routers is built in
#   on purpose: framesets, pages loaded by XHR, a view loader with runtime import paths,
#   session values rendered into inline scripts, a Referer check, a script-built login.
#   Throwaway target: nothing is stored, write operations answer ok and change nothing.
#
#   Requires: the test values MOCK_ROUTER_USER, MOCK_ROUTER_PASSWORD and MOCK_ROUTER_SESSION
#   as environment variables (docker-compose.yaml takes them from .env).
#
#   docker compose up -d unwire-mock-router
#   pwsh ./Start-MockRouter.ps1                      # local run, ports 3010-3016

#
#   Chapters:
#     HELPERS          Responses, templates, the session checks per login method.
#     PREPARE SERVER   Validates the test values and opens one prefix per variant.
#     SERVE REQUESTS   Answers every request until the container stops.
#

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'The request log goes to the container log, not to a pipeline.')]
[CmdletBinding()]
param (
    <#
    [Optional]
    Host part of the listener prefixes. Default is '+', every address of the container.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String]
    $ListenHost = '+'
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

$WWW_ROOT       = Join-Path -Path $PSScriptRoot -ChildPath 'www'
$VARIANTS_FILE  = Join-Path -Path $PSScriptRoot -ChildPath 'data/mock-router.variants.json'
$REALM          = 'mock-router'
$FORM_COOKIE    = 'mock_form_session'
$PATH_PREFIX    = '/ui/'
$PATH_TOKEN     = 'tok'
$CONTENT_TYPES  = @{
    '.htm'  = 'text/html; charset=utf-8'
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
}

# ===========================================================================
# ===============================   HELPERS   ===============================
# ===========================================================================
#
#   Send-MockResponse      Writes status, headers and body, closes the response.
#   Send-MockFile          Sends a file of www/ with its placeholders filled in.
#   Get-MockMd5            Hex MD5 of a string, for HTTP Digest.
#   Test-MockDigest        Checks a Digest Authorization header (qop=auth).
#   Test-MockSession       Whether a request carries the session of its variant.
#   Test-MockPublicPath    Whether a path is reachable without a session.
#   Invoke-MockApi         Answers the API with fixed JSON test data.
#

function Send-MockResponse {
    param (
        [System.Net.HttpListenerResponse] $Response,
        [System.Int32] $Status,
        [System.String] $Body = '',
        [System.String] $ContentType = 'application/json; charset=utf-8',
        [System.Collections.IDictionary] $Headers = @{}
    )

    $Response.StatusCode  = $Status
    $Response.ContentType = $ContentType
    foreach ($headerName in $Headers.Keys) {
        $Response.AddHeader($headerName, $Headers[$headerName])
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.Close()
}

function Send-MockFile {
    param (
        [System.Net.HttpListenerResponse] $Response,
        [System.String] $RelativePath,
        [System.Collections.IDictionary] $Placeholders
    )

    # '/js/app.js' => '<www>/js/app.js', nothing outside www/ ('..' is refused)
    $filePath = [System.IO.Path]::GetFullPath((Join-Path -Path $WWW_ROOT -ChildPath $RelativePath.TrimStart('/')))
    if (-NOT $filePath.StartsWith($WWW_ROOT, [System.StringComparison]::Ordinal) -OR -NOT (Test-Path -Path $filePath -PathType Leaf)) {
        Send-MockResponse -Response $Response -Status 404 -Body '{"error":"not found"}'
        return
    }

    $extension = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()
    $content   = Get-Content -Path $filePath -Raw -Encoding utf8
    # Placeholders only in pages: the session lands where a router renders it, in inline scripts.
    if ($extension -IN '.htm', '.html') {
        foreach ($placeholder in $Placeholders.Keys) {
            $content = $content.Replace("{{$placeholder}}", $Placeholders[$placeholder])
        }
    }
    $contentType = $CONTENT_TYPES[$extension] ?? 'application/octet-stream'
    Send-MockResponse -Response $Response -Status 200 -Body $content -ContentType $contentType
}

function Get-MockMd5 {
    param ([System.String] $Text)
    $hash = [System.Security.Cryptography.MD5]::HashData([System.Text.Encoding]::UTF8.GetBytes($Text))
    return [System.Convert]::ToHexString($hash).ToLowerInvariant()
}

function Test-MockDigest {
    param (
        [System.String] $Header,
        [System.String] $Method,
        [System.String] $Nonce
    )

    if ($Header -NOTMATCH '^Digest\s') {
        return $false
    }
    # 'Digest username="admin", uri="/", qop=auth' => @{ username = 'admin'; uri = '/'; qop = 'auth' }
    $fields = @{}
    foreach ($field in [System.Text.RegularExpressions.Regex]::Matches($Header, '(\w+)=(?:"([^"]*)"|([^\s,]+))')) {
        $fields[$field.Groups[1].Value] = $field.Groups[2].Success ? $field.Groups[2].Value : $field.Groups[3].Value
    }
    if ($fields['username'] -NE $env:MOCK_ROUTER_USER -OR $fields['nonce'] -NE $Nonce) {
        return $false
    }

    $ha1      = Get-MockMd5 -Text "$($fields['username']):${REALM}:$env:MOCK_ROUTER_PASSWORD"
    $ha2      = Get-MockMd5 -Text "${Method}:$($fields['uri'])"
    $expected = Get-MockMd5 -Text "${ha1}:${Nonce}:$($fields['nc']):$($fields['cnonce']):$($fields['qop']):${ha2}"
    return $fields['response'] -EQ $expected
}

function Test-MockSession {
    param (
        [System.Net.HttpListenerRequest] $Request,
        [PSCustomObject] $Variant,
        [System.String] $PathToken,
        [System.String] $Nonce
    )

    $session       = $env:MOCK_ROUTER_SESSION
    $authorization = $Request.Headers['Authorization'] ?? ''
    $basicValue    = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$($env:MOCK_ROUTER_USER):$($env:MOCK_ROUTER_PASSWORD)"))

    switch ($Variant.auth) {
        'none'   { return $true }
        'basic'  { return $authorization -EQ "Basic $basicValue" }
        'digest' { return Test-MockDigest -Header $authorization -Method $Request.HttpMethod -Nonce $Nonce }
        'form'   { return $null -NE $Request.Cookies[$FORM_COOKIE] -AND $Request.Cookies[$FORM_COOKIE].Value -EQ $session }
        'sid'    { return $Request.QueryString['sid'] -EQ $session }
        'path'   { return $PathToken -EQ $session }
        'bearer' { return $authorization -EQ "Bearer $session" }
    }
    throw [System.InvalidOperationException]::new("Variant auth must be one of none, basic, digest, form, sid, path, bearer, got '$($Variant.auth)'.")
}

function Test-MockPublicPath {
    param (
        [PSCustomObject] $Variant,
        [System.String] $Path
    )

    <#
        > Basic, Digest   -> nothing, the browser asks before the first page
        > Bearer          -> everything but /api/ and /cgi-bin/, the code of the app is public
        > Form, sid, path -> the login page, its scripts and the login call
    #>
    if ($Variant.auth -IN 'basic', 'digest') {
        return $false
    }
    if ($Variant.auth -EQ 'bearer') {
        $isApi = $Path.StartsWith('/api/') -OR $Path.StartsWith('/cgi-bin/')
        return -NOT $isApi -OR $Path -EQ '/api/login'
    }
    return $Path -IN '/', "/login.$($Variant.auth).htm", "/js/login.$($Variant.auth).js", '/api/login', '/css/style.css'
}

function Invoke-MockApi {
    param (
        [System.Net.HttpListenerRequest] $Request,
        [System.Net.HttpListenerResponse] $Response,
        [System.String] $Path
    )

    # Fixed test data, documentation addresses only (RFC 5737, locally administered MACs).
    $routes = @{
        'GET /api/status'          = @{ uptime = 86400; version = '1.0.0-mock'; wan = @{ ip = '192.0.2.10'; isConnected = $true } }
        'GET /api/wifi'            = @{ ssid = 'mock-net'; channel = 6; isEnabled = $true; security = 'wpa2' }
        'POST /api/wifi'           = @{ result = 'ok' }
        'GET /api/devices'         = @{ devices = @(@{ mac = '02:00:00:00:00:01'; name = 'laptop'; ip = '192.168.0.10' }) }
        'GET /api/logs'            = @{ level = $Request.QueryString['level'] ?? 'info'; entries = @(@{ time = '2026-11-02T00:00:00Z'; message = 'wan up' }) }
        'POST /api/reboot'         = @{ result = 'ok'; note = 'mock, nothing restarts' }
        'GET /cgi-bin/config.cgi'  = @{ section = $Request.QueryString['section'] ?? 'lan'; values = @{ dhcp = $true; netmask = '255.255.255.0' } }
        'POST /cgi-bin/config.cgi' = @{ result = 'ok' }
    }
    # '/api/devices/02:00:00:00:00:01/block' => 'POST /api/devices/{mac}/block'
    $routeKey = "$($Request.HttpMethod) $($Path -REPLACE '^/api/devices/[^/]+/block$', '/api/devices/{mac}/block')"
    if ($routeKey -EQ 'POST /api/devices/{mac}/block') {
        $routes[$routeKey] = @{ result = 'ok' }
    }

    if (-NOT $routes.ContainsKey($routeKey)) {
        Send-MockResponse -Response $Response -Status 404 -Body '{"error":"no such endpoint"}'
        return
    }
    Send-MockResponse -Response $Response -Status 200 -Body ($routes[$routeKey] | ConvertTo-Json -Depth 5 -Compress)
}

# ===========================================================================
# ===========================   PREPARE SERVER   ============================
# ===========================================================================
#
#   1. Validations   Fails early on missing test values.
#   2. Listener      Opens one prefix per variant, a fresh Digest nonce per start.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early on missing test values.
# ---------------------------------------------------------------------------

foreach ($variableName in 'MOCK_ROUTER_USER', 'MOCK_ROUTER_PASSWORD', 'MOCK_ROUTER_SESSION') {
    if ([System.String]::IsNullOrEmpty([System.Environment]::GetEnvironmentVariable($variableName))) {
        throw [System.ArgumentException]::new("Environment variable '$variableName' must hold a test value, see .env.example.")
    }
}
# The session goes into a query, a path segment and a cookie: URL-safe characters only.
if ($env:MOCK_ROUTER_SESSION -NOTMATCH '^[\w.~-]{6,}$') {
    throw [System.ArgumentException]::new('MOCK_ROUTER_SESSION must be at least 6 URL-safe characters (letters, digits, . _ ~ -).')
}

# ---------------------------------------------------------------------------
# Listener
#   Opens one prefix per variant, a fresh Digest nonce per start.
# ---------------------------------------------------------------------------

$Variants = (Get-Content -Path $VARIANTS_FILE -Raw -Encoding utf8 | ConvertFrom-Json).variants
$Nonce    = [System.Convert]::ToHexString([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(16)).ToLowerInvariant()

$Listener = [System.Net.HttpListener]::new()
foreach ($variant in $Variants) {
    $Listener.Prefixes.Add("http://${ListenHost}:$($variant.port)/")
}
$Listener.Start()
Write-Host "[MockRouter] Listening on ports $(($Variants.port) -join ', ')."

# ===========================================================================
# ===========================   SERVE REQUESTS   ============================
# ===========================================================================
#
#   1. Request loop   One request at a time, the crawl of Unwire is sequential.
#

# ---------------------------------------------------------------------------
# Request loop
#   One request at a time, the crawl of Unwire is sequential.
# ---------------------------------------------------------------------------

try {
    while ($Listener.IsListening) {
        $context  = $Listener.GetContext()
        $request  = $context.Request
        $response = $context.Response
        $variant  = $Variants | Where-Object -Property port -EQ -Value $request.Url.Port

        try {
            # '/ui/;tok=abc/js/app.js?x=1' => token 'abc', path '/js/app.js' (path variant only)
            $path      = $request.RawUrl.Split('?')[0]
            $pathToken = $null
            if ($variant.auth -EQ 'path') {
                $tokenMatch = [System.Text.RegularExpressions.Regex]::Match($path, "^$([regex]::Escape($PATH_PREFIX));$PATH_TOKEN=(?<token>[^/]+)(?<rest>/.*)?$")
                if ($tokenMatch.Success) {
                    $pathToken = $tokenMatch.Groups['token'].Value
                    $path      = $tokenMatch.Groups['rest'].Success ? $tokenMatch.Groups['rest'].Value : '/'
                }
                elseif ($path.StartsWith($PATH_PREFIX)) {
                    $path = '/' + $path.Substring($PATH_PREFIX.Length)
                }
            }
            if ($path -EQ '/' -AND $variant.auth -IN 'none', 'basic', 'digest', 'bearer') {
                $path = '/index.htm'
            }
            # Logged without query and token: the session never reaches the container log.
            $logLine = "[MockRouter] $($variant.name) $($request.HttpMethod) $path"

            $isSignedIn = Test-MockSession -Request $request -Variant $variant -PathToken $pathToken -Nonce $Nonce
            $isPublic   = Test-MockPublicPath -Variant $variant -Path $path

            <#
                > Favicon                                       -> the icon, public in every variant
                > Script without a same-origin Referer (none)   -> 403, like some devices
                > Login call                                    -> session for the right test user
                > Neither signed in nor public                  -> what the login method answers
                > Start page                                    -> login page or frameset
                > API                                           -> fixed JSON
                > Anything else                                 -> file of www/
            #>
            # Favicon: browsers ask for it on every origin, before and after a login
            if ($path -IN '/favicon.ico', '/favicon.svg') {
                Write-Host "$logLine -> icon"
                $icon = Get-Content -Path (Join-Path -Path $WWW_ROOT -ChildPath 'favicon.svg') -Raw -Encoding utf8
                Send-MockResponse -Response $response -Status 200 -Body $icon -ContentType 'image/svg+xml'
                continue
            }

            # Script without a same-origin Referer (none)
            $referer = $request.Headers['Referer'] ?? ''
            if ($variant.auth -EQ 'none' -AND $path.StartsWith('/js/') -AND -NOT $referer.StartsWith("http://$($request.Url.Authority)/")) {
                Write-Host "$logLine -> 403 (no Referer)"
                Send-MockResponse -Response $response -Status 403 -Body '{"error":"forbidden"}'
                continue
            }

            # Login call
            if ($path -EQ '/api/login' -AND $request.HttpMethod -EQ 'POST') {
                $reader = [System.IO.StreamReader]::new($request.InputStream, [System.Text.Encoding]::UTF8)
                $body   = $reader.ReadToEnd()
                # '{"username":"a","password":"b"}' or 'username=a&password=b'
                $credentials = $body.TrimStart().StartsWith('{') ? ($body | ConvertFrom-Json -AsHashtable) : [System.Web.HttpUtility]::ParseQueryString($body)
                if ($credentials['username'] -NE $env:MOCK_ROUTER_USER -OR $credentials['password'] -NE $env:MOCK_ROUTER_PASSWORD) {
                    Write-Host "$logLine -> 401 (wrong test user)"
                    Send-MockResponse -Response $response -Status 401 -Body '{"error":"wrong user or password"}'
                    continue
                }
                Write-Host "$logLine -> 200 (login)"
                if ($variant.auth -EQ 'form') {
                    $loginHeaders = @{ 'Set-Cookie' = "$FORM_COOKIE=$($env:MOCK_ROUTER_SESSION); Path=/; HttpOnly"; Location = '/' }
                    Send-MockResponse -Response $response -Status 302 -Headers $loginHeaders
                    continue
                }
                $loginBody = ($variant.auth -EQ 'sid') ? @{ sid = $env:MOCK_ROUTER_SESSION } : @{ token = $env:MOCK_ROUTER_SESSION }
                Send-MockResponse -Response $response -Status 200 -Body ($loginBody | ConvertTo-Json -Compress)
                continue
            }

            # Neither signed in nor public
            if (-NOT $isSignedIn -AND -NOT $isPublic) {
                $isPage = $path -LIKE '*.htm' -OR $path -EQ '/'
                if ($variant.auth -EQ 'basic') {
                    Write-Host "$logLine -> 401 (Basic)"
                    Send-MockResponse -Response $response -Status 401 -Headers @{ 'WWW-Authenticate' = "Basic realm=`"$REALM`"" }
                }
                elseif ($variant.auth -EQ 'digest') {
                    Write-Host "$logLine -> 401 (Digest)"
                    Send-MockResponse -Response $response -Status 401 -Headers @{ 'WWW-Authenticate' = "Digest realm=`"$REALM`", qop=`"auth`", nonce=`"$Nonce`", algorithm=MD5" }
                }
                elseif ($isPage -AND $variant.auth -EQ 'form') {
                    Write-Host "$logLine -> 302 (login page)"
                    Send-MockResponse -Response $response -Status 302 -Headers @{ Location = '/login.form.htm' }
                }
                elseif ($isPage -AND $variant.auth -IN 'sid', 'path') {
                    Write-Host "$logLine -> 200 (login page)"
                    Send-MockFile -Response $response -RelativePath "/login.$($variant.auth).htm" -Placeholders @{}
                }
                else {
                    Write-Host "$logLine -> 401"
                    Send-MockResponse -Response $response -Status 401 -Body '{"error":"login required"}'
                }
                continue
            }

            # Start page
            if ($path -EQ '/') {
                $path = $isSignedIn ? '/index.htm' : "/login.$($variant.auth).htm"
            }

            # API
            if ($path.StartsWith('/api/') -OR $path.StartsWith('/cgi-bin/')) {
                Write-Host "$logLine -> api"
                Invoke-MockApi -Request $request -Response $response -Path $path
                continue
            }

            # Anything else
            $placeholders = @{
                # The session where a signed-in router renders it, a device id where there is none
                SESSION     = ($variant.auth -IN 'form', 'sid', 'path') ? $env:MOCK_ROUTER_SESSION : 'device-0001'
                SID_SUFFIX  = ($variant.auth -EQ 'sid') ? "?sid=$($env:MOCK_ROUTER_SESSION)" : ''
                AUTH_SCRIPT = "js/auth.$($variant.auth).js"
            }
            Write-Host "$logLine -> file"
            Send-MockFile -Response $response -RelativePath $path -Placeholders $placeholders
        }
        catch {
            Write-Host "[MockRouter] $($variant.name) request failed: $($_.Exception.Message)"
            try { Send-MockResponse -Response $response -Status 500 -Body '{"error":"mock failed"}' } catch { Write-Host '[MockRouter] Response already closed.' }
        }
    }
}
finally {
    $Listener.Stop()
}
