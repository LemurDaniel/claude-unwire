# NOTE:
#   Downloads the static assets of a web UI for unwire-analyze: the start page, its frames,
#   every same-origin script, the chunks those scripts reference (also the lazy chunks of a
#   webpack runtime) and their source maps.
#   GET only, same origin only, redirects only within the origin. Nothing is executed.
#
#   Session mode for UIs whose code is behind a login: sends a session cookie and loads only
#   the start page and *.js, *.mjs, *.map files, never a page, frame, endpoint or redirect.
#   -PromptSession asks for the cookie with a masked prompt (interactive, nothing on disk),
#   -UseSession reads it from an environment variable (automation). The cookie never appears
#   in output, logs or manifest.
#
#   Writes the files below OutputDirectory, mirrored by URL path, plus unwire-assets.json
#   with every saved, skipped and failed asset.
#
#   ./plugins/unwire/core/unwire-analyze/scripts/Save-UnwireAsset.ps1 -Uri 'http://192.168.178.1' -OutputDirectory ./unwire/router/assets
#   ./plugins/unwire/core/unwire-analyze/scripts/Save-UnwireAsset.ps1 -Uri 'https://nas.local:5001' -OutputDirectory ./unwire/nas/assets -SkipCertificateCheck
#
#   ./plugins/unwire/core/unwire-analyze/scripts/Save-UnwireAsset.ps1 -Uri 'https://nas.local/gitea/' -OutputDirectory ./unwire/gitea/assets -PromptSession
#     Session cookie (name=value): ****                   # copied from the browser after the login
#
#   $env:UNWIRE_COOKIE = 'grafana_session=<VALUE>'
#   ./plugins/unwire/core/unwire-analyze/scripts/Save-UnwireAsset.ps1 -Uri 'https://nas.local/grafana/' -OutputDirectory ./unwire/grafana/assets -UseSession

#
#   Chapters:
#     HELPERS           Same-origin requests, file paths and reference extraction.
#     PREPARE CRAWL     Validates the input and queues the start page.
#     DOWNLOAD ASSETS   Downloads every queued asset and queues its references.
#     WRITE MANIFEST    Writes unwire-assets.json and returns a summary.
#

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
    session mode: only the start page and *.js, *.mjs, *.map files are requested, nothing
    on the denylist (logout, reboot, delete, ...), no redirects.
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
    Asks for the session cookie with a masked prompt and switches to session mode like
    UseSession. The cookie lives only in memory for this run: not on disk, not in the history.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [switch]
    $PromptSession
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

. $PSScriptRoot/../../../shared/ConvertTo-UnwireText.ps1

$MANIFEST_FILE     = 'unwire-assets.json'
$MAX_REDIRECTS     = 5
$REDIRECT_CODES    = @(301, 302, 303, 307, 308)
$SOURCE_MAP_HEADER = @('SourceMap', 'X-SourceMap')
# <base href="/grafana/">, <script src="/js/app.js">, <link rel="modulepreload" href="/js/chunk.js">, <frame src="menu.html">
$HTML_BASE_REF     = '<base\b[^>]*?\bhref\s*=\s*["'']?(?<ref>[^"''\s>]+)'
$HTML_SCRIPT_REF  = '<script\b[^>]*?\bsrc\s*=\s*["'']?(?<ref>[^"''\s>]+)'
$HTML_PRELOAD_REF  = '<link\b[^>]*?\bhref\s*=\s*["'']?(?<ref>[^"''\s>]+\.m?js(?:\?[^"''\s>]*)?)'
$HTML_FRAME_REF    = '<i?frame\b[^>]*?\bsrc\s*=\s*["'']?(?<ref>[^"''\s>]+)'
# //# sourceMappingURL=app.js.map (last one wins, bundlers append it at the end)
$JS_SOURCE_MAP_REF = '(?m)^\s*//[#@]\s*sourceMappingURL=(?<ref>\S+)\s*$'
# 'static/js/12.chunk.js', "./lazy.mjs", `/js/vendor.js`
$JS_CHUNK_REF      = '[''"`](?<ref>(?:\.{1,2}/|/)?(?:[\w.-]+/)*[\w.-]+\.m?js)[''"`]'
# Webpack runtime, the file name of a lazy chunk built from two maps:
# - ""+({123:"SupportBundles"}[e]||e)+"."+{123:"cbbdd876417c6516e99c"}[e]+".js"   => SupportBundles.cbbdd876417c6516e99c.js
# - "static/js/"+e+"."+{45:"0a1b2c3d"}[e]+".chunk.js"                              => static/js/45.0a1b2c3d.chunk.js
$JS_CHUNK_MAP      = '(?:"(?<prefix>[^"]*)"\+)?(?:\(\{(?<names>[^{}]*)\}\[\w+\]\|\|\w+\)|\b\w+)\+"(?<sep>[.-])"\+\{(?<hashes>[^{}]*)\}\[\w+\]\+"(?<suffix>(?:\.chunk)?\.m?js)"'
$JS_MAP_ENTRY      = '"?(?<key>[\w-]+)"?\s*:\s*"(?<value>[^"]*)"'
$JS_PUBLIC_PATH    = '\b\w+\.p\s*=\s*"(?<path>[^"]*)"'
$CHUNK_HASH        = '^[0-9a-fA-F]{6,}$'
# Session mode: what may be requested at all, and what never
$SESSION_STATIC    = '\.(m?js|map)$'
$SESSION_DENYLIST  = '(?i)(log-?out|sign-?out|reboot|restart|shutdown|reset|delete|remove|apply|save|firmware|upgrade|factory)'
# Line continuations of a pasted cURL command: bash '\', cmd '^', PowerShell '`'
$PASTE_CONTINUATION = '\s[\\^`]\s*$'
$MAX_PASTE_LINES    = 200

# ===========================================================================
# ===============================   HELPERS   ===============================
# ===========================================================================
#
#   Test-UnwireSameOrigin          Compares scheme, host and port of two URIs.
#   Get-UnwireSessionBlock         Why session mode must not request a URI, $null if it may.
#   ConvertTo-UnwireCookieHeader   Cookie header from the usual copy formats of a browser.
#   Get-UnwireCookieShape          Describes pasted text without showing its content.
#   Invoke-UnwireAssetRequest      GET with redirects followed only within the origin.
#   Get-UnwireAssetFile            Local file path of an asset, always inside the root.
#   Find-UnwireAssetReference      Scripts, frames, chunks and source maps of a text.
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
        > Anything else                   -> blocked (pages, frames, endpoints)
    #>

    if ("$($Target.AbsolutePath)$($Target.Query)" -MATCH $SESSION_DENYLIST) {
        return 'session mode: path on the denylist'
    }
    if ($Target.GetLeftPart([System.UriPartial]::Query) -EQ $Start.GetLeftPart([System.UriPartial]::Query)) {
        return $null
    }
    if ($Target.AbsolutePath.ToLowerInvariant() -MATCH $SESSION_STATIC) {
        return $null
    }
    return 'session mode: no static script or source map'
}

function ConvertTo-UnwireCookieHeader {
    param (
        [System.String] $Text
    )

    <#
        > cURL ("Copy as cURL")         -> the -b / --cookie value, else the cookie: header,
                                           bash and cmd (^"...^") quoting
        > Header line ("cookie: a=b")   -> everything after 'cookie:'
        > DevTools table row            -> 'name<TAB>value<TAB>domain...' => 'name=value'
        > Anything else                 -> trimmed as it is, 'a=b; c=d' stays a list
    #>

    $value = $Text.Trim()

    # cURL ("Copy as cURL")
    if ($value -MATCH '^curl\s') {
        # cmd format escapes with '^': -b ^"a=b; c=d^" => -b "a=b; c=d"
        if ($value.Contains('^"')) {
            $value = $value -REPLACE '\^(.)', '$1'
        }
        $curlCookie = [System.Text.RegularExpressions.Regex]::Match($value, '(?:-b|--cookie)\s+(?<q>[''"])(?<value>.*?)\k<q>')
        if (-NOT $curlCookie.Success) {
            $curlCookie = [System.Text.RegularExpressions.Regex]::Match($value, '-H\s+(?<q>[''"])(?i:cookie):\s*(?<value>.*?)\k<q>')
        }
        return $(if ($curlCookie.Success) { $curlCookie.Groups['value'].Value.Trim() } else { $value })
    }

    # Header line ("cookie: a=b")
    if ($value -MATCH '^(?i)cookie:\s*') {
        return ($value -REPLACE '^(?i)cookie:\s*', '').Trim()
    }

    # DevTools table row
    if ($value.Contains("`t")) {
        $fields = $value.Split("`t")
        return "$($fields[0].Trim())=$($fields[1].Trim())"
    }

    # Anything else
    return $value
}

function Get-UnwireCookieShape {
    param (
        [System.String] $Text
    )

    # Only the shape: length and structure, never a single character of the value.
    $traits = @(
        "$($Text.Length) characters"
        if ($Text.Contains('=')) { "contains '='" } else { "no '='" }
        if ($Text.Contains(';')) { "contains ';'" }
        if ($Text.Contains("`t")) { 'contains tabs' }
        if ($Text -MATCH '\s') { 'contains spaces' }
        if ($Text.TrimStart() -MATCH '^curl\s') { "starts with 'curl'" }
        if ($Text.TrimStart() -MATCH '^[''"{\[]') { 'starts with a quote or bracket' }
    )
    return $traits -join ', '
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
        $response = Invoke-WebRequest @RequestConfig -Uri $current
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
        > HTML  -> <script src>, <link href="*.js"> as js, <frame>/<iframe src> as html,
                   relative to the <base href> of the page, else to the page itself
        > JS    -> the last sourceMappingURL as map, relative to the script
                -> webpack runtime chunk maps as js, exact names, relative to the literal
                   publicPath (against the page base), else to the runtime's folder
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

    # JS: webpack runtime chunk maps
    $chunkMaps = [System.Text.RegularExpressions.Regex]::Matches($Text, $JS_CHUNK_MAP)
    if ($chunkMaps.Count -GT 0) {
        $publicPath = [System.Text.RegularExpressions.Regex]::Match($Text, $JS_PUBLIC_PATH)
        $chunkBase  = if ($publicPath.Success -AND $publicPath.Groups['path'].Value -NE 'auto') { [System.Uri]::new($PageBase, $publicPath.Groups['path'].Value) } else { [System.Uri]::new($AssetUri, './') }

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
#   1. Validations   Fails early on a bad URI or a missing session cookie.
#   2. Queue         Queues the start page and prepares the request settings.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early on a bad URI or a missing session cookie.
# ---------------------------------------------------------------------------

$StartUri = $null
if (-NOT [System.Uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref] $StartUri) -OR $StartUri.Scheme -NOTIN @('http', 'https')) {
    throw [System.ArgumentException]::new("Uri must be an absolute http or https URI, e.g. 'http://192.168.178.1', got '$Uri'.")
}

# PromptSession is session mode too, only the source of the cookie differs.
$IsSessionMode = $UseSession.IsPresent -OR $PromptSession.IsPresent

if ($IsSessionMode -AND $null -NE (Get-UnwireSessionBlock -Target $StartUri -Start $StartUri)) {
    throw [System.ArgumentException]::new("Uri '$StartUri' must not match the session denylist (logout, reboot, delete, ...).")
}

<#
    The cookie value never goes into a message, a log line or the manifest.
    Order of precedence:
    - PromptSession  -> masked prompt
    - UseSession     -> environment variable SessionVariable
    - neither        -> no session
#>
$SessionCookie = $null
# PromptSession -> masked prompt
if ($PromptSession) {
    # A multi-line paste ("Copy as cURL" ends its lines with '\', '^' or '`') must be read
    # completely here: every line left unread would run as a command in the user's shell.
    $pastedLines = [System.Collections.Generic.List[System.String]]::new()
    do {
        $prompt     = if ($pastedLines.Count -EQ 0) { 'Session cookie (name=value, cookie header or "Copy as cURL")' } else { '...' }
        $secureLine = Read-Host -Prompt $prompt -AsSecureString
        $pastedLine = [System.Net.NetworkCredential]::new('', $secureLine).Password
        $pastedLines.Add(($pastedLine -REPLACE $PASTE_CONTINUATION, ''))
    } while ($pastedLine -MATCH $PASTE_CONTINUATION -AND $pastedLines.Count -LT $MAX_PASTE_LINES)

    $SessionCookie = ConvertTo-UnwireCookieHeader -Text ($pastedLines -join ' ')
}
# UseSession -> environment variable SessionVariable
elseif ($UseSession) {
    $variableCookie = [System.Environment]::GetEnvironmentVariable($SessionVariable)
    if ([System.String]::IsNullOrWhiteSpace($variableCookie)) {
        throw [System.ArgumentException]::new("Environment variable '$SessionVariable' must hold the session cookie for UseSession, e.g. 'grafana_session=<VALUE>'.")
    }
    $SessionCookie = ConvertTo-UnwireCookieHeader -Text $variableCookie
}

# A bare value without its name is the most common copy mistake.
if ($IsSessionMode -AND $SessionCookie -NOTMATCH '^[^=\s;]+=\S') {
    throw [System.ArgumentException]::new("The session cookie must be 'name=value', e.g. 'i_like_gitea=<VALUE>' or 'grafana_session=<VALUE>', with the name from the browser's cookie list. Got: $(Get-UnwireCookieShape -Text $SessionCookie).")
}

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
if ($IsSessionMode) {
    $RequestConfig.Headers = @{ Cookie = $SessionCookie }
    Write-Verbose "[Save-UnwireAsset] Session mode: cookie from $(if ($PromptSession) { 'the prompt' } else { "'$SessionVariable'" }), only the start page and *.js, *.mjs, *.map."
}

$Queue     = [System.Collections.Generic.Queue[PSCustomObject]]::new()
$Visited   = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::Ordinal)
$UsedFiles = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
$Records   = [System.Collections.Generic.List[PSCustomObject]]::new()     # written in WRITE MANIFEST

$SavedHashes = [System.Collections.Generic.Dictionary[System.String, System.String]]::new()     # content hash => saved file

$Queue.Enqueue([PSCustomObject]@{ Uri = $StartUri; Kind = 'html'; Depth = 0; FoundIn = $null; PageBase = $StartUri; Guessed = $false })

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

:CRAWL while ($Queue.Count -GT 0) {
    $item = $Queue.Dequeue()
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

    # Request fails or not HTTP 200
    try {
        $result = Invoke-UnwireAssetRequest -Target $item.Uri -Origin $StartUri -RequestConfig $RequestConfig -IsRedirectAllowed (-NOT $IsSessionMode)
    }
    catch [System.Net.Http.HttpRequestException], [System.OperationCanceledException], [System.TimeoutException] {
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
            Write-Warning "[Save-UnwireAsset] Start page '$StartUri' redirects, the session cookie is probably expired: log in again and update '$SessionVariable'."
        }
        elseif ($item.Depth -EQ 0) {
            Write-Warning "[Save-UnwireAsset] Start page '$StartUri' could not be loaded: $($record.Reason)."
        }
        continue CRAWL
    }
    $text = ConvertTo-UnwireText -Content $result.Response.Content

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

    # Session mode: the signed-in page may hold personal data or tokens, it is only read for
    # its script references and never written to disk.
    if ($IsSessionMode -AND $item.Kind -EQ 'html') {
        $record.Status = 'read'
        $record.Reason = 'session mode: page read for script references only, not saved'
        Write-Verbose "[Save-UnwireAsset] '$key' read in session mode, not saved."
        foreach ($reference in Find-UnwireAssetReference -Text $text -Kind 'html' -AssetUri $result.FinalUri -PageBase $item.PageBase) {
            $Queue.Enqueue([PSCustomObject]@{ Uri = $reference.Uri; Kind = $reference.Kind; Depth = $item.Depth + 1; FoundIn = $key; PageBase = $reference.PageBase; Guessed = $reference.Guessed })
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
        Set-Content -Path $file -Value $text -NoNewline -Encoding utf8NoBOM
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
                Set-Content -Path "$file.map" -Value $mapText -NoNewline -Encoding utf8NoBOM
                $Records.Add([PSCustomObject]@{ Uri = "$key (inline)"; Kind = 'map'; Status = 'saved'; Reason = $null; File = "$($record.File).map"; FoundIn = $key })
            }
            continue
        }
        if ($reference.Kind -NE 'map' -AND $item.Depth + 1 -GT $MaxDepth) {
            continue
        }
        $Queue.Enqueue([PSCustomObject]@{ Uri = $reference.Uri; Kind = $reference.Kind; Depth = $item.Depth + 1; FoundIn = $key; PageBase = $reference.PageBase; Guessed = $reference.Guessed })
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
    [PSCustomObject]@{
        startUri = $StartUri.AbsoluteUri
        session  = $IsSessionMode     # whether a cookie was sent, never its value
        assets   = $Records
    }
    | ConvertTo-Json -Depth 5
    | Set-Content -Path $ManifestPath -Encoding utf8NoBOM
}

return [PSCustomObject]@{
    OutputDirectory = $RootPath
    Manifest        = $ManifestPath
    Saved           = @($Records | Where-Object -Property Status -EQ -Value 'saved').Count
    Skipped         = @($Records | Where-Object -Property Status -EQ -Value 'skipped').Count
    Failed          = @($Records | Where-Object -Property Status -EQ -Value 'failed').Count
    NotFound        = @($Records | Where-Object -Property Status -EQ -Value 'not-found').Count
    ReadOnly        = @($Records | Where-Object -Property Status -EQ -Value 'read').Count
}