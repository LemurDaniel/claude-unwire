# NOTE:
#   Downloads the static assets of a web UI for unwire:analyze: the start page, its frames,
#   every same-origin script, the chunks those scripts reference (also the lazy chunks of a
#   webpack runtime) and their source maps.
#   GET only, same origin only, redirects only within the origin. Nothing is executed.
#   Every asset goes out with the page that loaded it as Referer, like a browser: some
#   devices answer 403 to scripts without it. Scripts that still answer 401 or 403
#   are counted as AccessDenied: the code is probably behind a login, try session mode.
#   A start page with a password field or a script named after a login (login.js) is
#   reported as LoginForm: without a session only the code of the login page is there.
#
#   Session mode for UIs whose code is behind a login: sends a session cookie and loads only
#   the start page, *.htm/*.html pages and frames and *.js, *.mjs, *.map files, never an
#   endpoint or redirect. Signed-in pages are read, never saved: only their inline script
#   code is kept, with the string values of 'var x = "..."' assignments and of object
#   properties redacted (plain paths stay). The session value itself is scrubbed from every
#   file before it is written.
#   -PromptSession shows the login guide of data/login-guide.json in -Language, then asks for
#   the cookie with a masked prompt (interactive, nothing on disk), -UseSession reads it from
#   an environment variable (automation). The cookie never appears in output, logs or manifest.
#   A pasted cURL is read for every session it carries: the cookie, the Authorization header
#   (Basic, Bearer, own schemes; Digest is rejected), auth headers like X-Auth-Token and a
#   ';name=value' token in the URL path ('/ui/;stok=<VALUE>/', ';jsessionid=<VALUE>').
#   -SessionParameter 'sid' adds a session URL parameter, for UIs that keep it in the URL or
#   form data. A token or parameter goes only on the wire, never into a record, a Referer or
#   a log line.
#
#   Writes the files below OutputDirectory, mirrored by URL path, plus unwire-assets.json
#   with every saved, skipped and failed asset.
#
#   ./plugins/unwire/skills/analyze/scripts/Save-UnwireAsset.ps1 -Uri 'http://192.168.178.1' -OutputDirectory ./unwire/router/assets
#   ./plugins/unwire/skills/analyze/scripts/Save-UnwireAsset.ps1 -Uri 'https://nas.local:5001' -OutputDirectory ./unwire/nas/assets -SkipCertificateCheck
#   ./plugins/unwire/skills/analyze/scripts/Save-UnwireAsset.ps1 -Uri 'http://192.168.178.1' -OutputDirectory ./unwire/router/assets -Page '/main/status.htm,/frame/menu.htm'
#   ./plugins/unwire/skills/analyze/scripts/Save-UnwireAsset.ps1 -Uri 'http://192.168.178.1' -OutputDirectory ./unwire/router/assets -Script '/js/views/status.js'
#
#   ./plugins/unwire/skills/analyze/scripts/Save-UnwireAsset.ps1 -Uri 'https://nas.local/wiki/' -OutputDirectory ./unwire/wiki/assets -PromptSession -Language en
#     Unwire: login for https://nas.local/wiki/        # the guide, then the masked prompt
#     Session cookie (...): ****                        # "Copy as cURL" from the browser
#
#   $env:UNWIRE_COOKIE = 'session_id=<VALUE>'
#   ./plugins/unwire/skills/analyze/scripts/Save-UnwireAsset.ps1 -Uri 'https://nas.local/dashboard/' -OutputDirectory ./unwire/dashboard/assets -UseSession
#
#   ./plugins/unwire/skills/analyze/scripts/Save-UnwireAsset.ps1 -Uri 'https://router.test' -OutputDirectory ./unwire/router/assets -PromptSession -SessionParameter sid

#
#   Chapters:
#     HELPERS           Same-origin requests, file paths and reference extraction.
#     PREPARE CRAWL     Validates the input and queues the start page.
#     DOWNLOAD ASSETS   Downloads every queued asset and queues its references.
#     WRITE MANIFEST    Writes unwire-assets.json and returns a summary.
#

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'The login guide is for the user in the PromptSession window, not pipeline output.')]
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    <#
    [Required]
    URI of the web UI's start page, e.g. 'http://192.168.178.1'.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $Uri,

    <#
    [Required]
    Folder to save the assets into.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $OutputDirectory,

    <#
    [Optional]
    Extra pages to load besides the start page, e.g. '/main/status.htm': pages the UI loads
    at runtime (XHR) and no tag names, derived from the code by the agent. Only same-origin
    *.htm or *.html paths, resolved against Uri, the denylist applies in session mode.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String[]]
    $Page = @(),

    <#
    [Optional]
    Extra scripts to load besides the start page, e.g. '/js/views/status.js': modules the UI
    imports at runtime from a path built in code, derived from the code by the agent. Only
    same-origin *.js or *.mjs paths, resolved against Uri, the denylist applies in session mode.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String[]]
    $Script = @(),

    <#
    [Optional]
    Maximum number of saved assets, source maps included. Default is 1000, a webpack app
    easily has a few hundred chunks.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(1, 10000)]
    [System.Int32]
    $MaxAssets = 1000,

    <#
    [Optional]
    Maximum link depth from the start page: 1 = its scripts and frames, 2 = also the chunks
    those scripts reference. Source maps are always loaded for a saved script. Default is 3.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(1, 10)]
    [System.Int32]
    $MaxDepth = 3,

    <#
    [Optional]
    Timeout per request in seconds. Default is 15.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(1, 300)]
    [System.Int32]
    $TimeoutSec = 15,

    <#
    [Optional]
    Guessed paths (chunk strings in scripts, '<script>.map' probes) that may answer 404
    before guessing stops. Default is 50.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(0, 5000)]
    [System.Int32]
    $MaxGuessMisses = 50,

    <#
    [Optional]
    Does not try '<script>.map' for scripts without a sourceMappingURL.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [switch]
    $SkipSourceMapProbe,

    <#
    [Optional]
    Accepts self-signed certificates, common on routers and NAS devices.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [switch]
    $SkipCertificateCheck,

    <#
    [Optional]
    Sends the session cookie from the environment variable SessionVariable and switches to
    session mode: only the start page, *.htm/*.html pages and *.js, *.mjs, *.map files are
    requested, nothing on the denylist (logout, reboot, delete, ...), no redirects.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [switch]
    $UseSession,

    <#
    [Optional]
    Environment variable holding the Cookie header for UseSession, e.g. 'sid=...; theme=dark'.
    Default is UNWIRE_COOKIE.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String]
    $SessionVariable = 'UNWIRE_COOKIE',

    <#
    [Optional]
    Name of the URL parameter that carries the session, e.g. 'sid', for UIs that keep the
    session in the URL or form data instead of a cookie. Session mode then appends
    'name=<VALUE>' to the query of every request instead of sending a Cookie header. The
    value comes from the prompt or the session variable: a cURL with the parameter in its URL
    or data, 'name=value' or the bare value.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidatePattern('^[\w-]+$')]
    [System.String]
    $SessionParameter,

    <#
    [Optional]
    Asks for the session cookie with a masked prompt and switches to session mode like
    UseSession. The cookie lives only in memory for this run: not on disk, not in the history.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [switch]
    $PromptSession,

    <#
    [Optional]
    Language of the login guide and prompt of PromptSession, a key of data/login-guide.json
    ('en', 'de'). Default is en, an unknown language falls back to en.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String]
    $Language = 'en'
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

. $PSScriptRoot/../../../shared/ConvertTo-UnwireText.ps1
. $PSScriptRoot/../../../shared/Get-UnwireCertificateError.ps1
. $PSScriptRoot/../../../shared/Invoke-UnwireWebRequest.ps1
. $PSScriptRoot/../../../shared/session/Session.ps1

$MANIFEST_FILE     = 'unwire-assets.json'
$LOGIN_GUIDE_FILE  = Join-Path -Path $PSScriptRoot -ChildPath '../data/login-guide.json'
$DEFAULT_LANGUAGE  = 'en'
$MAX_REDIRECTS     = 5
$REDIRECT_CODES    = @(301, 302, 303, 307, 308)
$SOURCE_MAP_HEADER = @('SourceMap', 'X-SourceMap')
# <input type="password" ...>, <input id="pw" type='password'>
$HTML_PASSWORD_FIELD = '(?i)<input\b[^>]*?\btype\s*=\s*["'']?password\b'
# <base href="/app/">, <script src="/js/app.js">, <link rel="modulepreload" href="/js/chunk.js">, <frame src="menu.html">
$HTML_BASE_REF     = '<base\b[^>]*?\bhref\s*=\s*["'']?(?<ref>[^"''\s>]+)'
$HTML_SCRIPT_REF  = '<script\b[^>]*?\bsrc\s*=\s*["'']?(?<ref>[^"''\s>]+)'
$HTML_PRELOAD_REF  = '<link\b[^>]*?\bhref\s*=\s*["'']?(?<ref>[^"''\s>]+\.m?js(?:\?[^"''\s>]*)?)'
$HTML_FRAME_REF    = '<i?frame\b[^>]*?\bsrc\s*=\s*["'']?(?<ref>[^"''\s>]+)'
# Inline module scripts: import login from "/js/login.js", import "./a.mjs", import("/js/lazy.js")
$HTML_IMPORT_REF   = '\bimport\s*(?:\(\s*|[\w$*{}\s,]+?\s*from\s*)?["''](?<ref>[^"''\s]+\.m?js)["'']'
# Script file names of a login page: login.js, box-login.js, signin.mjs (not catalog.js)
$LOGIN_SCRIPT_NAME = '(?i)(?<![a-z])(log-?in|sign-?in)'
# //# sourceMappingURL=app.js.map (last one wins, bundlers append it at the end)
$JS_SOURCE_MAP_REF = '(?m)^\s*//[#@]\s*sourceMappingURL=(?<ref>\S+)\s*$'
# 'static/js/12.chunk.js', "./lazy.mjs", `/js/vendor.js`, not a name fragment like ".0a1b2c3d.js"
$JS_CHUNK_REF      = '[''"`](?!\.[\w-])(?<ref>(?:\.{1,2}/|/)?(?:[\w.-]+/)*[\w.-]+\.m?js)[''"`]'
# Webpack runtime, the file name of a lazy chunk built from two maps:
# - ""+({123:"SupportBundles"}[e]||e)+"."+{123:"cbbdd876417c6516e99c"}[e]+".js"   => SupportBundles.cbbdd876417c6516e99c.js
# - "static/js/"+e+"."+{45:"0a1b2c3d"}[e]+".chunk.js"                              => static/js/45.0a1b2c3d.chunk.js
$JS_CHUNK_MAP      = '(?:"(?<prefix>[^"]*)"\+)?(?:\(\{(?<names>[^{}]*)\}\[\w+\]\|\|\w+\)|\b\w+)\+"(?<sep>[.-])"\+\{(?<hashes>[^{}]*)\}\[\w+\]\+"(?<suffix>(?:\.chunk)?\.m?js)"'
$JS_MAP_ENTRY      = '"?(?<key>[\w-]+)"?\s*:\s*"(?<value>[^"]*)"'
# Webpack runtime, one if per named chunk instead of a map:
# - if(e==="sortablejs")return"js/"+e+".deb655b2.js"                               => js/sortablejs.deb655b2.js
$JS_CHUNK_IF       = '\b(?<var>\w+)===?"(?<name>[\w.~-]+)"\)return"(?<prefix>[^"]*)"\+\k<var>\+"(?<sep>[.-])(?<hash>[0-9a-fA-F]{6,})(?<suffix>(?:\.chunk)?\.m?js)"'
$JS_PUBLIC_PATH    = '\b\w+\.p\s*=\s*"(?<path>[^"]*)"'
# Automatic publicPath, relative to the folder of the running script: b.p=e+"../"
$JS_PUBLIC_PATH_AUTO = '\b\w+\.p\s*=\s*\w+\+"(?<path>(?:\.\./)+|\./)"'
$CHUNK_HASH        = '^[0-9a-fA-F]{6,}$'
# Session mode: what may be requested at all, and what never
$SESSION_STATIC    = '\.(m?js|map)$'
$SESSION_PAGE      = '\.html?$'
$EXTRA_SCRIPT      = '\.m?js$'
# Inline script blocks of a page: <script>...</script> without src
$HTML_INLINE_SCRIPT = '(?is)<script\b(?![^>]*\bsrc\s*=)[^>]*>(?<code>.*?)</script>'
# Server-rendered values: var name = "value"; => var name = "<redacted>";
$JS_STRING_ASSIGNMENT = '(?<head>\b(?:var|let|const)\s+[\w$]+\s*=\s*)(?<q>["''])(?:\\.|(?!\k<q>)[^\\\r\n])*\k<q>'
# Server-rendered objects: {"sid":"value", user: 'value'} => {"sid":"<redacted>", user: "<redacted>"}
$JS_PROPERTY_STRING = '(?<head>(?:"[\w$-]+"|''[\w$-]+''|\b[\w$]+)\s*:\s*)(?<q>["''])(?<value>(?:\\.|(?!\k<q>)[^\\\r\n])*)\k<q>'
# Property values kept for the analysis: plain paths without a query, '/api/status', './x.js'
$JS_PATH_VALUE      = '^\.{0,2}/[\w./-]*$'
# Never requested in session mode: logout, reboot, delete, ... (shared with Test-UnwireGet)
$SESSION_DENYLIST  = (Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../../shared/data/request-denylist.json') -Raw | ConvertFrom-Json).pattern

# ===========================================================================
# ===============================   HELPERS   ===============================
# ===========================================================================
#
#   Test-UnwireSameOrigin          Compares scheme, host and port of two URIs.
#   Get-UnwireSessionBlock         Why session mode must not request a URI, $null if it may.
#   Get-UnwireInlineScript         Inline script code of a page, string values redacted.
#   Get-UnwireCleanUri             URI with the session token and parameter removed.
#   Invoke-UnwireAssetRequest      GET with redirects followed only within the origin.
#   Get-UnwireAssetFile            Local file path of an asset, always inside the root.
#   Find-UnwireAssetReference      Scripts, frames, chunks and source maps of a text.
#   Test-UnwireLoginPage           Whether a page is a login page.
#   ConvertFrom-UnwireDataUri      Decodes an inline 'data:' source map.
#

function Test-UnwireSameOrigin {
    param (
        [System.Uri] $Left,
        [System.Uri] $Right
    )

    return 0 -EQ [System.Uri]::Compare($Left, $Right, [System.UriComponents]::SchemeAndServer, [System.UriFormat]::SafeUnescaped, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-UnwireSessionBlock {
    param (
        [System.Uri] $Target,
        [System.Uri] $Start
    )

    <#
        > Path or query on the denylist   -> blocked, also the start page
        > The start page itself           -> allowed
        > *.js, *.mjs, *.map              -> allowed
        > *.htm, *.html                   -> allowed (pages and frames, read, never saved)
        > Anything else                   -> blocked (endpoints, pages without extension)
    #>

    if ("$($Target.AbsolutePath)$($Target.Query)" -MATCH $SESSION_DENYLIST) {
        return 'session mode: path on the denylist'
    }
    if ($Target.GetLeftPart([System.UriPartial]::Query) -EQ $Start.GetLeftPart([System.UriPartial]::Query)) {
        return $null
    }
    $path = $Target.AbsolutePath.ToLowerInvariant()
    if ($path -MATCH $SESSION_STATIC -OR $path -MATCH $SESSION_PAGE) {
        return $null
    }
    return 'session mode: no static script, source map or .htm page'
}

function Get-UnwireInlineScript {
    param (
        [System.String] $Text
    )

    # Only the code between the tags; string values of simple assignments and of object
    # properties are redacted, a signed-in page renders its data there
    # (var wlanKey = "secret";, const data = {"sid":"secret"}). Plain paths stay for the analysis.
    $blocks = [System.Text.RegularExpressions.Regex]::Matches($Text, $HTML_INLINE_SCRIPT)
    | ForEach-Object { $_.Groups['code'].Value.Trim() }
    | Where-Object { -NOT [System.String]::IsNullOrEmpty($_) }
    if ($null -EQ $blocks) {
        return $null
    }
    $assignmentsRedacted = [System.Text.RegularExpressions.Regex]::Replace((@($blocks) -join "`n;`n"), $JS_STRING_ASSIGNMENT, '${head}"<redacted>"')
    return [System.Text.RegularExpressions.Regex]::Replace($assignmentsRedacted, $JS_PROPERTY_STRING, {
            param ($match)
            if ($match.Groups['value'].Value -MATCH $JS_PATH_VALUE) {
                return $match.Value
            }
            return "$($match.Groups['head'].Value)`"<redacted>`""
        })
}

function Get-UnwireCleanUri {
    param (
        [System.Uri]    $Uri,
        [System.String] $Query,
        [System.String] $PathToken,
        [System.String] $PathPrefix
    )

    # Links of a signed-in page may already carry the session: removed before the URI is
    # recorded, Get-UnwireRequestUri adds it again on the wire only.
    # '/ui/;stok=abc/admin?x=1&sid=abc' => '/ui/admin?x=1'
    $builder = [System.UriBuilder]::new($Uri)
    # Own segment (with PathPrefix) or appended to a segment, as Get-UnwireRequestUri adds it
    if (-NOT [System.String]::IsNullOrEmpty($PathToken) -AND -NOT [System.String]::IsNullOrEmpty($PathPrefix)) {
        $builder.Path = $builder.Path.Replace(";$PathToken/", '')
    }
    elseif (-NOT [System.String]::IsNullOrEmpty($PathToken)) {
        $builder.Path = $builder.Path.Replace(";$PathToken", '')
    }
    if (-NOT [System.String]::IsNullOrEmpty($Query) -AND $builder.Query.Length -GT 1) {
        $builder.Query = ($builder.Query.Substring(1).Split('&') | Where-Object { $_ -NE $Query }) -join '&'
    }
    return $builder.Uri
}

function Invoke-UnwireAssetRequest {
    param (
        [System.Uri]                  $Target,
        [System.Uri]                  $Origin,
        [System.Collections.Hashtable] $RequestConfig,
        [System.Boolean]              $IsRedirectAllowed
    )

    $current = $Target
    for ($redirect = 0; $redirect -LE $MAX_REDIRECTS; $redirect++) {
        $response = Invoke-UnwireWebRequest -RequestConfig $RequestConfig -Uri $current
        if ($response.StatusCode -NOTIN $REDIRECT_CODES) {
            return [PSCustomObject]@{ Response = $response; FinalUri = $current; Reason = $null }
        }
        # Session mode: a redirect target is a page the positive list never checked.
        if (-NOT $IsRedirectAllowed) {
            return [PSCustomObject]@{ Response = $null; FinalUri = $current; Reason = "HTTP $($response.StatusCode) redirect, not followed in session mode" }
        }

        $location = if ($null -NE $response.Headers) { @($response.Headers['Location'])[0] } else { $null }
        if ([System.String]::IsNullOrEmpty($location)) {
            return [PSCustomObject]@{ Response = $null; FinalUri = $current; Reason = "HTTP $($response.StatusCode) without Location" }
        }

        $next = [System.Uri]::new($current, $location)
        if (-NOT (Test-UnwireSameOrigin -Left $next -Right $Origin)) {
            return [PSCustomObject]@{ Response = $null; FinalUri = $current; Reason = "cross-origin redirect to '$next'" }
        }
        Write-Verbose "[Invoke-UnwireAssetRequest] '$current' redirects to '$next'."
        $current = $next
    }
    return [PSCustomObject]@{ Response = $null; FinalUri = $current; Reason = "more than $MAX_REDIRECTS redirects" }
}

function Get-UnwireAssetFile {
    param (
        [System.Uri]    $AssetUri,
        [System.String] $Root,
        [System.String] $Kind
    )

    # '/static/js/main.4f2a.js' => 'static/js/main.4f2a.js', '/' => 'index.html', '/login' => 'login.html'
    $invalidChars = [System.Text.RegularExpressions.Regex]::Escape(-join [System.IO.Path]::GetInvalidFileNameChars())
    $segments     = @(
        [System.Uri]::UnescapeDataString($AssetUri.AbsolutePath).Split('/')
        | Where-Object { $_ -NOTIN @('', '.', '..') }
        | ForEach-Object { $_ -REPLACE "[$invalidChars]", '_' }
    )
    if ($segments.Count -EQ 0 -OR $AssetUri.AbsolutePath.EndsWith('/')) {
        $segments += 'index.html'
    }
    if ($Kind -EQ 'html' -AND [System.String]::IsNullOrEmpty([System.IO.Path]::GetExtension($segments[-1]))) {
        $segments[-1] += '.html'
    }

    # Downloaded paths are untrusted: the file must stay inside the root.
    $fullPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine([System.String[]] (@($Root) + $segments)))
    if (-NOT $fullPath.StartsWith($Root + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw [System.InvalidOperationException]::new("Asset file '$fullPath' must be inside '$Root'.")
    }
    return $fullPath
}

function Find-UnwireAssetReference {
    param (
        [System.String] $Text,
        [System.String] $Kind,
        [System.Uri]    $AssetUri,
        [System.Uri]    $PageBase
    )

    <#
        > HTML  -> <script src>, <link href="*.js">, import of inline modules as js,
                   <frame>/<iframe src> as html,
                   relative to the <base href> of the page, else to the page itself
        > JS    -> the last sourceMappingURL as map, relative to the script
                -> webpack runtime chunk maps and chunk ifs as js, exact names, relative to
                   the literal publicPath (against the page base), else to the automatic
                   publicPath (against the runtime's folder), else to the runtime's folder
                -> chunk paths as js: './x.js', '../x.js', '/x.js' relative to the script,
                   bare 'static/js/x.js' relative to the base of the page that loaded
                   the script (webpack publicPath)
        Every reference carries the PageBase its own references resolve against, and
        whether it is Guessed (chunk strings may be any '*.js' text, not a real file).
    #>

    $references = [System.Collections.Generic.List[PSCustomObject]]::new()

    # HTML
    if ($Kind -EQ 'html') {
        $baseMatch    = [System.Text.RegularExpressions.Regex]::Match($Text, $HTML_BASE_REF, 'IgnoreCase')
        $documentBase = if ($baseMatch.Success) { [System.Uri]::new($AssetUri, $baseMatch.Groups['ref'].Value) } else { $AssetUri }

        $htmlRefs = @(
            [System.Text.RegularExpressions.Regex]::Matches($Text, $HTML_SCRIPT_REF, 'IgnoreCase') | ForEach-Object { @{ Ref = $_.Groups['ref'].Value; Kind = 'js' } }
            [System.Text.RegularExpressions.Regex]::Matches($Text, $HTML_PRELOAD_REF, 'IgnoreCase') | ForEach-Object { @{ Ref = $_.Groups['ref'].Value; Kind = 'js' } }
            [System.Text.RegularExpressions.Regex]::Matches($Text, $HTML_IMPORT_REF) | ForEach-Object { @{ Ref = $_.Groups['ref'].Value; Kind = 'js' } }
            [System.Text.RegularExpressions.Regex]::Matches($Text, $HTML_FRAME_REF, 'IgnoreCase') | ForEach-Object { @{ Ref = $_.Groups['ref'].Value; Kind = 'html' } }
        )
        foreach ($htmlRef in $htmlRefs) {
            if ($htmlRef.Ref -MATCH '^(data|blob|javascript|about):') {
                continue
            }
            # A frame is a page of its own with its own base, a script keeps this page's base.
            $references.Add([PSCustomObject]@{ Uri = [System.Uri]::new($documentBase, $htmlRef.Ref); Kind = $htmlRef.Kind; Data = $null; PageBase = $documentBase; Guessed = $false })
        }
        return $references
    }

    # JS: source map
    $mapMatches = [System.Text.RegularExpressions.Regex]::Matches($Text, $JS_SOURCE_MAP_REF)
    if ($mapMatches.Count -GT 0) {
        $mapRef = $mapMatches[$mapMatches.Count - 1].Groups['ref'].Value
        if ($mapRef.StartsWith('data:')) {
            $references.Add([PSCustomObject]@{ Uri = $AssetUri; Kind = 'map-inline'; Data = $mapRef; PageBase = $PageBase; Guessed = $false })
        }
        else {
            $references.Add([PSCustomObject]@{ Uri = [System.Uri]::new($AssetUri, $mapRef); Kind = 'map'; Data = $null; PageBase = $PageBase; Guessed = $false })
        }
    }

    # JS: webpack runtime chunk maps and chunk ifs
    $chunkMaps = [System.Text.RegularExpressions.Regex]::Matches($Text, $JS_CHUNK_MAP)
    $chunkIfs  = [System.Text.RegularExpressions.Regex]::Matches($Text, $JS_CHUNK_IF)
    if ($chunkMaps.Count -GT 0 -OR $chunkIfs.Count -GT 0) {
        # Order of precedence: literal publicPath > automatic publicPath > the runtime's folder
        $publicPath     = [System.Text.RegularExpressions.Regex]::Match($Text, $JS_PUBLIC_PATH)
        $publicPathAuto = [System.Text.RegularExpressions.Regex]::Match($Text, $JS_PUBLIC_PATH_AUTO)
        $chunkBase      = if ($publicPath.Success -AND $publicPath.Groups['path'].Value -NE 'auto') {
            [System.Uri]::new($PageBase, $publicPath.Groups['path'].Value)
        }
        elseif ($publicPathAuto.Success) {
            [System.Uri]::new($AssetUri, "./$($publicPathAuto.Groups['path'].Value)")
        }
        else {
            [System.Uri]::new($AssetUri, './')
        }

        foreach ($chunkIf in $chunkIfs) {
            $chunkFile = "$($chunkIf.Groups['prefix'].Value)$($chunkIf.Groups['name'].Value)$($chunkIf.Groups['sep'].Value)$($chunkIf.Groups['hash'].Value)$($chunkIf.Groups['suffix'].Value)"
            $references.Add([PSCustomObject]@{ Uri = [System.Uri]::new($chunkBase, $chunkFile); Kind = 'js'; Data = $null; PageBase = $PageBase; Guessed = $false })
        }

        foreach ($chunkMap in $chunkMaps) {
            $names = @{}
            foreach ($entry in [System.Text.RegularExpressions.Regex]::Matches($chunkMap.Groups['names'].Value, $JS_MAP_ENTRY)) {
                $names[$entry.Groups['key'].Value] = $entry.Groups['value'].Value
            }
            foreach ($entry in [System.Text.RegularExpressions.Regex]::Matches($chunkMap.Groups['hashes'].Value, $JS_MAP_ENTRY)) {
                # Only content hashes: an object of other strings is no chunk map.
                if ($entry.Groups['value'].Value -NOTMATCH $CHUNK_HASH) {
                    continue
                }
                $chunkId   = $entry.Groups['key'].Value
                $chunkName = if ($names.ContainsKey($chunkId)) { $names[$chunkId] } else { $chunkId }
                $chunkFile = "$($chunkMap.Groups['prefix'].Value)$chunkName$($chunkMap.Groups['sep'].Value)$($entry.Groups['value'].Value)$($chunkMap.Groups['suffix'].Value)"
                $references.Add([PSCustomObject]@{ Uri = [System.Uri]::new($chunkBase, $chunkFile); Kind = 'js'; Data = $null; PageBase = $PageBase; Guessed = $false })
            }
        }
    }

    # JS: chunks
    foreach ($chunkMatch in [System.Text.RegularExpressions.Regex]::Matches($Text, $JS_CHUNK_REF)) {
        $chunkRef = $chunkMatch.Groups['ref'].Value
        $baseUri  = if ($chunkRef -MATCH '^(\.{1,2})?/') { $AssetUri } else { $PageBase }
        $references.Add([PSCustomObject]@{ Uri = [System.Uri]::new($baseUri, $chunkRef); Kind = 'js'; Data = $null; PageBase = $PageBase; Guessed = $true })
    }
    return $references
}

function Test-UnwireLoginPage {
    param (
        [System.String] $Text,
        [System.Uri]    $PageUri
    )

    <#
        > A password field                         -> login page
        > A script or import named after a login   -> login page, the form is built by script
        > Anything else                            -> no login page
    #>

    if ($Text -MATCH $HTML_PASSWORD_FIELD) {
        return $true
    }
    $loginScripts = Find-UnwireAssetReference -Text $Text -Kind 'html' -AssetUri $PageUri -PageBase $PageUri
    | Where-Object { $_.Kind -EQ 'js' -AND [System.IO.Path]::GetFileName($_.Uri.AbsolutePath) -MATCH $LOGIN_SCRIPT_NAME }
    return $null -NE $loginScripts
}

function ConvertFrom-UnwireDataUri {
    param (
        [System.String] $DataUri
    )

    # 'data:application/json;charset=utf-8;base64,eyJ2...' => header 'data:application/json;charset=utf-8;base64', payload 'eyJ2...'
    $separator = $DataUri.IndexOf(',')
    if ($separator -LT 0) {
        return $null
    }
    $header  = $DataUri.Substring(0, $separator)
    $payload = $DataUri.Substring($separator + 1)

    if ($header -MATCH ';base64$') {
        return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload))
    }
    return [System.Uri]::UnescapeDataString($payload)
}

# ===========================================================================
# ============================   PREPARE CRAWL   ============================
# ===========================================================================
#
#   1. Validations   Fails early on a bad URI, a bad page or a missing session cookie.
#   2. Queue         Queues the start page, extra pages and scripts, prepares the request
#                    settings.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early on a bad URI or a missing session cookie.
# ---------------------------------------------------------------------------

$StartUri = $null
if (-NOT [System.Uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref] $StartUri) -OR $StartUri.Scheme -NOTIN @('http', 'https')) {
    throw [System.ArgumentException]::new("Uri must be an absolute http or https URI, e.g. 'http://192.168.178.1', got '$Uri'.")
}

# Extra pages: checked before any prompt, so a bad path never costs the user a login.
# pwsh -File hands a list over as one string: '/a.htm,/b.htm' => '/a.htm', '/b.htm'
$PagePaths  = $Page -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -NE '' }
$ExtraPages = foreach ($pagePath in $PagePaths) {
    $pageUri = [System.Uri]::new($StartUri, $pagePath)
    if (-NOT (Test-UnwireSameOrigin -Left $pageUri -Right $StartUri) -OR $pageUri.AbsolutePath -NOTMATCH $SESSION_PAGE) {
        throw [System.ArgumentException]::new("Page must be a same-origin *.htm or *.html path, e.g. '/main/status.htm', got '$pagePath'.")
    }
    $pageUri
}

# Extra scripts: same check, '/a.js,/b.mjs' => '/a.js', '/b.mjs'
$ScriptPaths  = $Script -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -NE '' }
$ExtraScripts = foreach ($scriptPath in $ScriptPaths) {
    $scriptUri = [System.Uri]::new($StartUri, $scriptPath)
    if (-NOT (Test-UnwireSameOrigin -Left $scriptUri -Right $StartUri) -OR $scriptUri.AbsolutePath -NOTMATCH $EXTRA_SCRIPT) {
        throw [System.ArgumentException]::new("Script must be a same-origin *.js or *.mjs path, e.g. '/js/views/status.js', got '$scriptPath'.")
    }
    $scriptUri
}

# PromptSession is session mode too, only the source of the cookie differs.
$IsSessionMode = $UseSession.IsPresent -OR $PromptSession.IsPresent

if ($IsSessionMode -AND $null -NE (Get-UnwireSessionBlock -Target $StartUri -Start $StartUri)) {
    throw [System.ArgumentException]::new("Uri '$StartUri' must not match the session denylist (logout, reboot, delete, ...).")
}
if (-NOT $IsSessionMode -AND -NOT [System.String]::IsNullOrEmpty($SessionParameter)) {
    throw [System.ArgumentException]::new("SessionParameter '$SessionParameter' must be used with PromptSession or UseSession.")
}

# The session value never goes into a message, a log line or the manifest: cookie, auth
# headers, path token and URL parameter, whatever the paste carries (shared/session).
$SessionConfig = @{
    PromptSession    = $PromptSession
    UseSession       = $UseSession
    SessionVariable  = $SessionVariable
    SessionParameter = $SessionParameter
    Uri              = $StartUri
    GuideFile        = $LOGIN_GUIDE_FILE
    Language         = $Language
}
$Session = Read-UnwireSession @SessionConfig

$UriSession     = if ($null -NE $Session) { $Session.UriSession } else { @{ Query = $null; PathToken = $null; PathPrefix = $null } }     # added on the wire in DOWNLOAD ASSETS
$IsUriSession   = $null -NE $Session -AND $Session.IsUriSession
$SessionKinds   = if ($null -NE $Session) { $Session.Kinds } else { @() }
# Every session value, scrubbed from each text before it is written in DOWNLOAD ASSETS.
$SessionSecrets = if ($null -NE $Session) { $Session.Secrets } else { @() }

# ---------------------------------------------------------------------------
# Queue
#   Queues the start page and prepares the request settings.
# ---------------------------------------------------------------------------

# Absolute path relative to the PowerShell location, the folder is created on the first save.
$RootPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar)

$RequestConfig = @{
    Method               = 'Get'
    TimeoutSec           = $TimeoutSec
    MaximumRedirection   = 0          # followed by Invoke-UnwireAssetRequest, only within the origin
    SkipHttpErrorCheck   = $true
    SkipCertificateCheck = $SkipCertificateCheck.IsPresent
}
if ($null -NE $Session -AND $Session.RequestHeaders.Count -GT 0) {
    $RequestConfig.Headers = @{} + $Session.RequestHeaders
}
if ($IsSessionMode) {
    Write-Verbose "[Save-UnwireAsset] Session mode: $($SessionKinds -join ', ') from $(if ($PromptSession) { 'the prompt' } else { "'$SessionVariable'" }), only the start page, *.htm pages and *.js, *.mjs, *.map."
}

$Queue     = [System.Collections.Generic.Queue[PSCustomObject]]::new()
$Visited   = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)
$UsedFiles = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
$Records   = [System.Collections.Generic.List[PSCustomObject]]::new()     # written in WRITE MANIFEST

$SavedHashes = [System.Collections.Generic.Dictionary[System.String, System.String]]::new()     # content hash => saved file

$Queue.Enqueue([PSCustomObject]@{ Uri = $StartUri; Kind = 'html'; Depth = 0; FoundIn = $null; PageBase = $StartUri; Guessed = $false; Referer = $null })
# Pages the UI loads at runtime: one level below the start page, which is their Referer.
foreach ($pageUri in $ExtraPages) {
    $Queue.Enqueue([PSCustomObject]@{ Uri = $pageUri; Kind = 'html'; Depth = 1; FoundIn = '-Page'; PageBase = $pageUri; Guessed = $false; Referer = $StartUri })
}
# Scripts the UI imports from runtime paths: like a script of the start page.
foreach ($scriptUri in $ExtraScripts) {
    $Queue.Enqueue([PSCustomObject]@{ Uri = $scriptUri; Kind = 'js'; Depth = 1; FoundIn = '-Script'; PageBase = $StartUri; Guessed = $false; Referer = $StartUri })
}

# ===========================================================================
# ===========================   DOWNLOAD ASSETS   ===========================
# ===========================================================================
#
#   1. Crawl   Downloads every queued asset, saves it and queues its references.
#

# ---------------------------------------------------------------------------
# Crawl
#   Downloads every queued asset, saves it and queues its references.
# ---------------------------------------------------------------------------

<#
    > Already visited                       -> skip silently
    > Cross-origin, blocked in session      -> record as skipped, nothing is requested
      mode, MaxAssets or MaxGuessMisses
      reached
    > Guessed path or source map answers    -> record as not-found, count the miss when
      404                                      guessed
    > Request fails or not HTTP 200         -> record as failed (the start page throws)
    > Script that is HTML (SPA fallback)    -> record as skipped
    > Map that is no source map             -> record as skipped
    > Same content as a saved asset         -> record as skipped (iframes that only differ
                                               in the query string)
    > Page in session mode                  -> record as read, queue its scripts, not saved
    > Otherwise                             -> save, record, queue references:
        - html  -> scripts and frames, while inside MaxDepth
        - js    -> its source map always, chunks while inside MaxDepth
#>

$SavedCount  = 0
$GuessMisses = 0
$IsLoginForm = $false     # reported in WRITE MANIFEST

:CRAWL while ($Queue.Count -GT 0) {
    $item = $Queue.Dequeue()
    # A link of a signed-in page may carry the session: recorded without it, sent with it.
    if ($IsUriSession) {
        $item.Uri = Get-UnwireCleanUri -Uri $item.Uri @UriSession
    }
    $key  = $item.Uri.GetLeftPart([System.UriPartial]::Query)

    # Already visited
    if (-NOT $Visited.Add($key)) {
        continue CRAWL
    }
    $record = [PSCustomObject]@{ Uri = $key; Kind = $item.Kind; Status = 'skipped'; Reason = $null; File = $null; FoundIn = $item.FoundIn }
    $Records.Add($record)

    # Cross-origin, blocked in session mode, MaxAssets or MaxGuessMisses reached
    if (-NOT (Test-UnwireSameOrigin -Left $item.Uri -Right $StartUri)) {
        $record.Reason = 'cross-origin'
        Write-Verbose "[Save-UnwireAsset] '$key' is cross-origin -> skipping."
        continue CRAWL
    }
    $sessionBlock = if ($IsSessionMode) { Get-UnwireSessionBlock -Target $item.Uri -Start $StartUri } else { $null }
    if ($null -NE $sessionBlock) {
        $record.Reason = $sessionBlock
        Write-Verbose "[Save-UnwireAsset] '$key' -> $sessionBlock -> skipping."
        continue CRAWL
    }
    if ($SavedCount -GE $MaxAssets) {
        $record.Reason = "MaxAssets $MaxAssets reached"
        continue CRAWL
    }
    if ($item.Guessed -AND $GuessMisses -GE $MaxGuessMisses) {
        $record.Reason = "MaxGuessMisses $MaxGuessMisses reached"
        continue CRAWL
    }

    # Referer like a browser: the page that loaded the asset, none for the start page.
    $itemConfig = $RequestConfig
    if ($null -NE $item.Referer) {
        $itemConfig         = $RequestConfig.Clone()
        $itemConfig.Headers = @{ Referer = $item.Referer.AbsoluteUri }
        if ($null -NE $RequestConfig.Headers) {
            $itemConfig.Headers += $RequestConfig.Headers
        }
    }

    # Session in the URL (parameter or path token): only on the wire. No verbose line of the
    # request may show it, the record, the Referer and the file name keep the URI without it.
    $requestUri     = $item.Uri
    $requestVerbose = $VerbosePreference
    if ($IsUriSession) {
        $requestUri     = Get-UnwireRequestUri -Uri $item.Uri @UriSession
        $requestVerbose = 'SilentlyContinue'
    }

    # Request fails or not HTTP 200
    try {
        $result = & {
            $VerbosePreference = $requestVerbose
            Invoke-UnwireAssetRequest -Target $requestUri -Origin $StartUri -RequestConfig $itemConfig -IsRedirectAllowed (-NOT $IsSessionMode)
        }
        # Session mode follows no redirect, so the final URI is the requested one.
        if ($IsUriSession) {
            $result.FinalUri = $item.Uri
        }
    }
    catch [System.Net.Http.HttpRequestException], [System.OperationCanceledException], [System.TimeoutException] {
        # Untrusted certificate on the start page: the user decides about SkipCertificateCheck.
        $certificateError = Get-UnwireCertificateError -Exception $_.Exception
        if ($item.Depth -EQ 0 -AND $null -NE $certificateError) {
            throw [System.Security.Authentication.AuthenticationException]::new("Uri '$StartUri' has a TLS certificate this machine does not trust ($certificateError). Ask the user, then run again with -SkipCertificateCheck.", $_.Exception)
        }
        if ($item.Depth -EQ 0) {
            throw [System.InvalidOperationException]::new("Uri '$StartUri' must be reachable, the request failed: $($_.Exception.Message)", $_.Exception)
        }
        $record.Status = 'failed'
        $record.Reason = $_.Exception.Message
        Write-Warning "[Save-UnwireAsset] '$key' failed: $($_.Exception.Message)"
        continue CRAWL
    }
    if (($item.Guessed -OR $item.Kind -EQ 'map') -AND $null -NE $result.Response -AND $result.Response.StatusCode -EQ 404) {
        # A map named in sourceMappingURL but not deployed is common in production builds.
        $record.Status = 'not-found'
        $record.Reason = if ($item.Guessed) { 'HTTP 404 on a guessed path' } else { 'HTTP 404, source map referenced but not deployed' }
        if ($item.Guessed) {
            $GuessMisses++
        }
        continue CRAWL
    }
    if ($null -EQ $result.Response -OR $result.Response.StatusCode -NE 200) {
        $record.Status = 'failed'
        $record.Reason = if ($null -NE $result.Reason) { $result.Reason } else { "HTTP $($result.Response.StatusCode)" }
        Write-Verbose "[Save-UnwireAsset] '$key' -> $($record.Reason)."
        if ($item.Depth -EQ 0 -AND $IsSessionMode -AND $result.Reason -LIKE '*redirect*') {
            Write-Warning "[Save-UnwireAsset] Start page '$StartUri' redirects, the session cookie is probably expired: log in again and update the session."
        }
        elseif ($item.Depth -EQ 0) {
            Write-Warning "[Save-UnwireAsset] Start page '$StartUri' could not be loaded: $($record.Reason)."
        }
        continue CRAWL
    }
    $text = ConvertTo-UnwireText -Content $result.Response.Content

    # A page is the Referer of what it loads, a script passes on the page that loaded it.
    $referer = if ($item.Kind -EQ 'html') { $result.FinalUri } else { $item.Referer }

    # Script that is HTML (SPA fallback)
    if ($item.Kind -EQ 'js' -AND $text.TrimStart().StartsWith('<')) {
        $record.Reason = 'HTML instead of a script (SPA fallback)'
        Write-Verbose "[Save-UnwireAsset] '$key' returned HTML -> skipping."
        continue CRAWL
    }

    # Map that is no source map
    if ($item.Kind -EQ 'map' -AND -NOT ((Test-Json -Json $text -ErrorAction SilentlyContinue) -AND $text -MATCH '"(sources|mappings)"\s*:')) {
        $record.Reason = 'not a source map'
        Write-Verbose "[Save-UnwireAsset] '$key' is no source map -> skipping."
        continue CRAWL
    }

    # Same content as a saved asset
    $hash = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($text)))
    if ($SavedHashes.ContainsKey($hash)) {
        $record.Reason = "same content as '$($SavedHashes[$hash])'"
        Write-Verbose "[Save-UnwireAsset] '$key' has the same content as '$($SavedHashes[$hash])' -> skipping."
        continue CRAWL
    }

    # Login page as start page: without a session only its code is here, in session mode the
    # session was not accepted (warned in WRITE MANIFEST).
    if ($item.Depth -EQ 0 -AND $item.Kind -EQ 'html' -AND (Test-UnwireLoginPage -Text $text -PageUri $result.FinalUri)) {
        $IsLoginForm = $true
        Write-Verbose "[Save-UnwireAsset] Start page '$key' has a password field or a login script -> login page."
    }

    # Session mode: the signed-in page may hold personal data or tokens, it is only read for
    # its references and its inline script code (values redacted), never written to disk.
    if ($IsSessionMode -AND $item.Kind -EQ 'html') {
        $record.Status = 'read'
        $record.Reason = 'session mode: page read for scripts and frames, not saved'
        Write-Verbose "[Save-UnwireAsset] '$key' read in session mode, not saved."

        $inlineCode = Get-UnwireInlineScript -Text $text
        if ($null -NE $inlineCode) {
            # 'main/status.htm' => 'main/status.htm.inline.js'
            $inlineFile = "$(Get-UnwireAssetFile -AssetUri $result.FinalUri -Root $RootPath -Kind 'html').inline.js"
            if ($UsedFiles.Add($inlineFile) -AND $PSCmdlet.ShouldProcess($inlineFile, "Save inline scripts of '$key'")) {
                $null = New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($inlineFile)) -Force
                Set-Content -Path $inlineFile -Value (ConvertTo-UnwireRedactedText -Text $inlineCode -Secrets $SessionSecrets) -NoNewline -Encoding utf8NoBOM
                $SavedCount++
                $Records.Add([PSCustomObject]@{ Uri = "$key (inline scripts)"; Kind = 'js'; Status = 'saved'; Reason = 'session mode: inline script code, string values redacted'; File = [System.IO.Path]::GetRelativePath($RootPath, $inlineFile).Replace('\', '/'); FoundIn = $key })
            }
        }

        foreach ($reference in Find-UnwireAssetReference -Text $text -Kind 'html' -AssetUri $result.FinalUri -PageBase $item.PageBase) {
            if ($item.Depth + 1 -GT $MaxDepth) {
                continue
            }
            $Queue.Enqueue([PSCustomObject]@{ Uri = $reference.Uri; Kind = $reference.Kind; Depth = $item.Depth + 1; FoundIn = $key; PageBase = $reference.PageBase; Guessed = $reference.Guessed; Referer = $referer })
        }
        continue CRAWL
    }

    # Otherwise: save
    $file = Get-UnwireAssetFile -AssetUri $result.FinalUri -Root $RootPath -Kind $item.Kind
    if (-NOT $UsedFiles.Add($file)) {
        # Same path with another query string: keep both
        $file = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($file), "$([System.IO.Path]::GetFileNameWithoutExtension($file))~$($Records.Count)$([System.IO.Path]::GetExtension($file))")
        $null = $UsedFiles.Add($file)
    }
    if ($PSCmdlet.ShouldProcess($file, "Save '$key'")) {
        $null = New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($file)) -Force
        Set-Content -Path $file -Value (ConvertTo-UnwireRedactedText -Text $text -Secrets $SessionSecrets) -NoNewline -Encoding utf8NoBOM
    }
    $SavedCount++
    $record.Status = 'saved'
    $record.File   = [System.IO.Path]::GetRelativePath($RootPath, $file).Replace('\', '/')
    $SavedHashes[$hash] = $record.File
    Write-Verbose "[Save-UnwireAsset] Saved '$key' as '$($record.File)'."

    if ($item.Kind -EQ 'map') {
        continue CRAWL
    }

    # Otherwise: queue references
    $references = @(Find-UnwireAssetReference -Text $text -Kind $item.Kind -AssetUri $result.FinalUri -PageBase $item.PageBase)

    if ($item.Kind -EQ 'js') {
        $hasMapReference = $null -NE ($references | Where-Object -Property Kind -IN -Value @('map', 'map-inline'))
        $headerMap       = $SOURCE_MAP_HEADER | ForEach-Object { if ($null -NE $result.Response.Headers) { @($result.Response.Headers[$_])[0] } } | Where-Object { -NOT [System.String]::IsNullOrEmpty($_) } | Select-Object -First 1

        # Order of precedence: sourceMappingURL comment > SourceMap header > '<script>.map' probe
        if (-NOT $hasMapReference -AND $null -NE $headerMap) {
            $references += [PSCustomObject]@{ Uri = [System.Uri]::new($result.FinalUri, $headerMap); Kind = 'map'; Data = $null; PageBase = $item.PageBase; Guessed = $false }
        }
        elseif (-NOT $hasMapReference -AND -NOT $SkipSourceMapProbe) {
            $references += [PSCustomObject]@{ Uri = [System.Uri]::new($result.FinalUri.GetLeftPart([System.UriPartial]::Path) + '.map'); Kind = 'map'; Data = $null; PageBase = $item.PageBase; Guessed = $true }
        }
    }

    foreach ($reference in $references) {
        # Inline source map: saved right away next to its script
        if ($reference.Kind -EQ 'map-inline') {
            $mapText = ConvertFrom-UnwireDataUri -DataUri $reference.Data
            if ($null -NE $mapText -AND $PSCmdlet.ShouldProcess("$file.map", 'Save inline source map')) {
                Set-Content -Path "$file.map" -Value (ConvertTo-UnwireRedactedText -Text $mapText -Secrets $SessionSecrets) -NoNewline -Encoding utf8NoBOM
                $Records.Add([PSCustomObject]@{ Uri = "$key (inline)"; Kind = 'map'; Status = 'saved'; Reason = $null; File = "$($record.File).map"; FoundIn = $key })
            }
            continue
        }
        if ($reference.Kind -NE 'map' -AND $item.Depth + 1 -GT $MaxDepth) {
            continue
        }
        $Queue.Enqueue([PSCustomObject]@{ Uri = $reference.Uri; Kind = $reference.Kind; Depth = $item.Depth + 1; FoundIn = $key; PageBase = $reference.PageBase; Guessed = $reference.Guessed; Referer = $referer })
    }
}

# ===========================================================================
# ===========================   WRITE MANIFEST   ============================
# ===========================================================================
#
#   1. Report   Writes unwire-assets.json and returns a summary.
#

# ---------------------------------------------------------------------------
# Report
#   Writes unwire-assets.json and returns a summary.
# ---------------------------------------------------------------------------

$ManifestPath = Join-Path -Path $RootPath -ChildPath $MANIFEST_FILE
if ($PSCmdlet.ShouldProcess($ManifestPath, 'Write manifest')) {
    $null = New-Item -ItemType Directory -Path $RootPath -Force
    $manifestJson = [PSCustomObject]@{
        startUri         = $StartUri.AbsoluteUri
        session          = $IsSessionMode       # whether a session was sent, never its value
        sessionParameter = $SessionParameter    # its URL parameter name, empty for a cookie
        sessionKinds     = $SessionKinds        # names only: cookie, header:Authorization, path-token
        assets           = $Records
    }
    | ConvertTo-Json -Depth 5
    # Last line of defense, as for every saved file in DOWNLOAD ASSETS.
    ConvertTo-UnwireRedactedText -Text $manifestJson -Secrets $SessionSecrets
    | Set-Content -Path $ManifestPath -Encoding utf8NoBOM
}

# Last step of the guide in PREPARE CRAWL: the user closes the window only after this line.
if ($PromptSession) {
    $guides = Get-Content -Path $LOGIN_GUIDE_FILE -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    Write-Host ''
    Write-Host $guides[$(if ($guides.ContainsKey($Language)) { $Language } else { $DEFAULT_LANGUAGE })].done
}

# Scripts or maps that answer 401/403 even with a Referer: the code is behind a login.
$AccessDenied = @(
    $Records
    | Where-Object { $_.Status -EQ 'failed' -AND $_.Kind -IN @('js', 'map') -AND $_.Reason -IN @('HTTP 401', 'HTTP 403') }
).Count
if ($AccessDenied -GT 0 -AND -NOT $IsSessionMode) {
    Write-Warning "[Save-UnwireAsset] $AccessDenied scripts or maps answered 401/403 although the Referer was sent: the code is probably behind a login, use session mode."
}

if ($IsLoginForm -AND $IsSessionMode) {
    Write-Warning "[Save-UnwireAsset] The start page still is a login form in session mode: the session was probably not accepted (expired, or the UI expects it elsewhere, see -SessionParameter)."
}
elseif ($IsLoginForm) {
    Write-Warning "[Save-UnwireAsset] The start page is a login form: without a session only the code of the login page was saved."
}

return [PSCustomObject]@{
    OutputDirectory = $RootPath
    AccessDenied    = $AccessDenied
    LoginForm       = $IsLoginForm
    Manifest        = $ManifestPath
    Saved           = @($Records | Where-Object -Property Status -EQ -Value 'saved').Count
    Skipped         = @($Records | Where-Object -Property Status -EQ -Value 'skipped').Count
    Failed          = @($Records | Where-Object -Property Status -EQ -Value 'failed').Count
    NotFound        = @($Records | Where-Object -Property Status -EQ -Value 'not-found').Count
    ReadOnly        = @($Records | Where-Object -Property Status -EQ -Value 'read').Count
}
