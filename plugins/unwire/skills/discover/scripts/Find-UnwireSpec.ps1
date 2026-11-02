# NOTE:
#   Probes a web UI for published API documentation: OpenAPI and Swagger specs (JSON, YAML),
#   Swagger UI, ReDoc and GraphiQL pages. Sends GET requests to well-known paths only, so
#   nothing on the target is changed. A redirect is followed only when it adds a trailing
#   slash ('/api-docs' -> '/api-docs/'), any other one usually leads to a login page.
#   On a Swagger UI page it also reads the same-origin init scripts: a spec embedded as
#   "swaggerDoc" is saved as its own hit, a same-origin 'url:' is probed like a spec path,
#   one on another origin (the default Petstore example) is skipped.
#
#   ./plugins/unwire/skills/discover/scripts/Find-UnwireSpec.ps1 -Uri 'http://192.168.178.1'
#   ./plugins/unwire/skills/discover/scripts/Find-UnwireSpec.ps1 -Uri 'https://nas.local:5001' -SkipCertificateCheck -OutputDirectory ./unwire/nas/discover

#
#   Chapters:
#     HELPERS                  Documentation detection.
#     PROBE KNOWN SPEC PATHS   Probes every path, saves the specs and reports the hits.
#

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    <#
    [Required]
    Base URI of the web UI, e.g. 'http://192.168.178.1'.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $Uri,

    <#
    [Optional]
    Paths to probe, relative to Uri. Default is the list in data/spec-paths.json.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String[]]
    $Path,

    <#
    [Optional]
    Folder to save found specs into. Default is no saving.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String]
    $OutputDirectory,

    <#
    [Optional]
    Timeout per request in seconds. Default is 10.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(1, 300)]
    [System.Int32]
    $TimeoutSec = 10,

    <#
    [Optional]
    Accepts self-signed certificates, common on routers and NAS devices.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [switch]
    $SkipCertificateCheck
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

. $PSScriptRoot/../../../shared/ConvertTo-UnwireText.ps1
. $PSScriptRoot/../../../shared/Get-UnwireCertificateError.ps1
. $PSScriptRoot/../../../shared/Invoke-UnwireWebRequest.ps1

$SPEC_PATHS_FILE  = Join-Path -Path $PSScriptRoot -ChildPath '../data/spec-paths.json'
$SPEC_KINDS        = @('OpenApi', 'Swagger', 'OpenApiYaml')     # kinds that are saved as files
# 'openapi: 3.1.0' or "swagger: '2.0'" at the start of a line
$YAML_SPEC_PATTERN = '(?m)^(?<kind>openapi|swagger)\s*:\s*[''"]?(?<version>[\d.]+)'
$REDIRECT_CODES    = @(301, 302, 307, 308)
# Scripts of a Swagger UI page that configure it: swagger-ui-init.js, swagger-initializer.js, swagger-config.js
$SWAGGER_INIT_SCRIPT = '(?i)<script\b[^>]*?\bsrc\s*=\s*["''](?<src>[^"'']*(?:init|config)[^"'']*\.js)["'']'
# Inline script blocks of a Swagger UI page
$INLINE_SCRIPT     = '(?is)<script\b(?![^>]*\bsrc\s*=)[^>]*>(?<code>.*?)</script>'
# 'url: "/openapi.json"', "url: './v1.yaml'" in the options of SwaggerUIBundle, also inside 'urls: [...]'
$SWAGGER_UI_URL    = '\burl\s*:\s*["''](?<url>[^"'']+)["'']'

# ===========================================================================
# ===============================   HELPERS   ===============================
# ===========================================================================
#
#   Get-UnwireSpecMatch      Detects which kind of documentation a text is.
#   Invoke-UnwireProbe       One GET, a redirect followed only when it adds a trailing slash.
#   Get-UnwireJsonObject     The balanced JSON object that starts at an index of a text.
#   Get-UnwireSwaggerUiSpec  Embedded spec and spec URLs in the scripts of a Swagger UI page.
#

function Get-UnwireSpecMatch {
    param (
        [System.String] $Text
    )

    if ([System.String]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    <#
        > JSON
            - 'openapi' property  -> OpenApi
            - 'swagger' property  -> Swagger
            - anything else       -> no documentation
        > YAML with 'openapi:' or 'swagger:' -> OpenApiYaml
        > HTML of a documentation UI          -> SwaggerUi, ReDoc, GraphQLUi
    #>

    # JSON
    if (Test-Json -Json $Text -ErrorAction SilentlyContinue) {
        $spec = $Text | ConvertFrom-Json -Depth 100
        if ($spec -IS [System.Array]) {
            return $null
        }
        if ($null -NE $spec.openapi) {
            return [PSCustomObject]@{ Kind = 'OpenApi'; Version = [System.String] $spec.openapi; Title = $spec.info.title }
        }
        if ($null -NE $spec.swagger) {
            return [PSCustomObject]@{ Kind = 'Swagger'; Version = [System.String] $spec.swagger; Title = $spec.info.title }
        }
        return $null
    }

    # YAML
    $yamlMatch = [System.Text.RegularExpressions.Regex]::Match($Text, $YAML_SPEC_PATTERN)
    if ($yamlMatch.Success) {
        $titleMatch = [System.Text.RegularExpressions.Regex]::Match($Text, '(?m)^\s+title\s*:\s*[''"]?(?<title>[^''"\r\n]+)')
        $title      = if ($titleMatch.Success) { $titleMatch.Groups['title'].Value.Trim() } else { $null }
        return [PSCustomObject]@{ Kind = 'OpenApiYaml'; Version = $yamlMatch.Groups['version'].Value; Title = $title }
    }

    # HTML of a documentation UI
    if ($Text -MATCH 'swagger-ui') {
        return [PSCustomObject]@{ Kind = 'SwaggerUi'; Version = $null; Title = $null }
    }
    if ($Text -MATCH '<redoc|redoc\.standalone') {
        return [PSCustomObject]@{ Kind = 'ReDoc'; Version = $null; Title = $null }
    }
    if ($Text -MATCH 'graphiql|graphql-playground') {
        return [PSCustomObject]@{ Kind = 'GraphQLUi'; Version = $null; Title = $null }
    }
    return $null
}

function Invoke-UnwireProbe {
    param (
        [System.Uri]                   $Target,
        [System.Collections.Hashtable] $RequestConfig
    )

    <#
        > no redirect                                -> the response
        > redirect to the same URL with a '/' added  -> followed once ('/api-docs' -> '/api-docs/')
        > any other redirect                         -> the redirect itself (usually a login page)
    #>
    $response = Invoke-UnwireWebRequest -RequestConfig $RequestConfig -Uri $Target
    if ($response.StatusCode -NOTIN $REDIRECT_CODES) {
        return [PSCustomObject]@{ Response = $response; FinalUri = $Target }
    }
    $location = if ($null -NE $response.Headers) { @($response.Headers['Location'])[0] } else { $null }
    if ([System.String]::IsNullOrEmpty($location)) {
        return [PSCustomObject]@{ Response = $response; FinalUri = $Target }
    }
    $next          = [System.Uri]::new($Target, $location)
    $isSlashAdded  = $next.GetLeftPart([System.UriPartial]::Authority) -EQ $Target.GetLeftPart([System.UriPartial]::Authority) -AND $next.AbsolutePath -EQ "$($Target.AbsolutePath.TrimEnd('/'))/" -AND $next.Query -EQ $Target.Query -AND -NOT $Target.AbsolutePath.EndsWith('/')
    if (-NOT $isSlashAdded) {
        Write-Verbose "[Invoke-UnwireProbe] '$Target' redirects to '$next' -> not followed."
        return [PSCustomObject]@{ Response = $response; FinalUri = $Target }
    }
    Write-Verbose "[Invoke-UnwireProbe] '$Target' only adds a slash -> following to '$next'."
    return [PSCustomObject]@{ Response = (Invoke-UnwireWebRequest -RequestConfig $RequestConfig -Uri $next); FinalUri = $next }
}

function Get-UnwireJsonObject {
    param (
        [System.String] $Text,
        [System.Int32]  $Start
    )

    # Counts braces outside of strings: '{"a":{"b":"}"}} tail' from 0 => '{"a":{"b":"}"}}'
    $depth    = 0
    $isString = $false
    for ($index = $Start; $index -LT $Text.Length; $index++) {
        $char = $Text[$index]
        if ($isString) {
            if ($char -EQ '\') { $index++ }
            elseif ($char -EQ '"') { $isString = $false }
            continue
        }
        if ($char -EQ '"') { $isString = $true }
        elseif ($char -EQ '{') { $depth++ }
        elseif ($char -EQ '}') {
            $depth--
            if ($depth -EQ 0) {
                return $Text.Substring($Start, $index - $Start + 1)
            }
        }
    }
    return $null
}

function Get-UnwireSwaggerUiSpec {
    param (
        [System.String] $Text
    )

    <#
        > "swaggerDoc": { ... }       -> the embedded spec (swagger-ui-express)
        > url: "...", urls: [{url}]   -> spec URLs, probed by the caller when on the same origin
    #>
    $embedded = $null
    $docMatch = [System.Text.RegularExpressions.Regex]::Match($Text, '"swaggerDoc"\s*:\s*\{')
    if ($docMatch.Success) {
        $embedded = Get-UnwireJsonObject -Text $Text -Start ($docMatch.Index + $docMatch.Length - 1)
    }
    $urls = @([System.Text.RegularExpressions.Regex]::Matches($Text, $SWAGGER_UI_URL) | ForEach-Object { $_.Groups['url'].Value } | Select-Object -Unique)
    return [PSCustomObject]@{ Embedded = $embedded; Urls = $urls }
}

# ===========================================================================
# ========================   PROBE KNOWN SPEC PATHS   =======================
# ===========================================================================
#
#   1. Validations   Fails early on a URI that is not absolute http(s).
#   2. Paths         Loads the paths to probe.
#   3. Probe         Sends one GET per path and detects documentation.
#   4. Report        Returns the hits, warns when there are none.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early on a URI that is not absolute http(s).
# ---------------------------------------------------------------------------

$BaseUri = $null
if (-NOT [System.Uri]::TryCreate($Uri.TrimEnd('/') + '/', [System.UriKind]::Absolute, [ref] $BaseUri) -OR $BaseUri.Scheme -NOTIN @('http', 'https')) {
    throw [System.ArgumentException]::new("Uri must be an absolute http or https URI, e.g. 'http://192.168.178.1', got '$Uri'.")
}

# ---------------------------------------------------------------------------
# Paths
#   Loads the paths to probe.
# ---------------------------------------------------------------------------

# Order of precedence: parameter > data/spec-paths.json
$ProbePaths = if ($null -NE $Path -AND $Path.Count -GT 0) {
    $Path
}
else {
    (Get-Content -Path $SPEC_PATHS_FILE -Raw | ConvertFrom-Json).paths
}
Write-Verbose "[Find-UnwireSpec] Probing $($ProbePaths.Count) paths on '$BaseUri'."

# ---------------------------------------------------------------------------
# Probe
#   Sends one GET per path and detects documentation.
# ---------------------------------------------------------------------------

$RequestConfig = @{
    Method               = 'Get'
    TimeoutSec           = $TimeoutSec
    MaximumRedirection   = 0          # a redirect usually leads to a login page, not to docs
    SkipHttpErrorCheck   = $true
    SkipCertificateCheck = $SkipCertificateCheck.IsPresent
}

$Hits      = [System.Collections.Generic.List[PSCustomObject]]::new()
$HitUris   = [System.Collections.Generic.HashSet[System.String]]::new()

# Saves a spec (pages are only reported) and records the hit once per URI.
$AddHit = {
    param ([System.String] $HitUri, [System.String] $HitPath, [System.String] $Text, [PSCustomObject] $SpecMatch, [System.String] $Directory)

    if (-NOT $HitUris.Add($HitUri)) {
        return
    }
    $savedFile = $null
    if (-NOT [System.String]::IsNullOrEmpty($Directory) -AND $SpecMatch.Kind -IN $SPEC_KINDS) {
        # 'swagger/v1/swagger.json' => 'swagger-v1-swagger.json', 'api-docs/swagger-ui-init.js#swaggerDoc' => 'api-docs-swagger-ui-init.js-swaggerDoc.json'
        $fileBase  = ($HitPath.Trim('/') -REPLACE '[^\w.-]+', '-') -REPLACE '\.(json|ya?ml)$', ''
        $extension = if ($SpecMatch.Kind -EQ 'OpenApiYaml') { 'yaml' } else { 'json' }
        $savedFile = Join-Path -Path $Directory -ChildPath "$fileBase.$extension"
        if ($PSCmdlet.ShouldProcess($savedFile, 'Save spec')) {
            $null = New-Item -ItemType Directory -Path $Directory -Force
            Set-Content -Path $savedFile -Value $Text -NoNewline -Encoding utf8NoBOM
        }
    }
    $Hits.Add([PSCustomObject]@{
            Uri       = $HitUri
            Path      = $HitPath
            Kind      = $SpecMatch.Kind
            Version   = $SpecMatch.Version
            Title     = $SpecMatch.Title
            SavedFile = $savedFile
        })
}

:PROBE_PATHS foreach ($probePath in $ProbePaths) {
    $target = [System.Uri]::new($BaseUri, $probePath.TrimStart('/'))

    try {
        $probe    = Invoke-UnwireProbe -Target $target -RequestConfig $RequestConfig
        $response = $probe.Response
        $target   = $probe.FinalUri
    }
    catch [System.Net.Http.HttpRequestException] {
        # Untrusted certificate: the user decides about SkipCertificateCheck, never the script.
        $certificateError = Get-UnwireCertificateError -Exception $_.Exception
        if ($null -NE $certificateError) {
            throw [System.Security.Authentication.AuthenticationException]::new("Uri '$BaseUri' has a TLS certificate this machine does not trust ($certificateError). Ask the user, then run again with -SkipCertificateCheck.", $_.Exception)
        }
        # Connection refused, DNS failure: every other path would fail the same way.
        throw [System.InvalidOperationException]::new("Uri '$BaseUri' must be reachable, the request to '$target' failed: $($_.Exception.Message)", $_.Exception)
    }
    catch [System.OperationCanceledException], [System.TimeoutException] {
        Write-Warning "[Find-UnwireSpec] '$target' timed out after $TimeoutSec s -> skipping."
        continue PROBE_PATHS
    }

    if ($response.StatusCode -NE 200) {
        Write-Verbose "[Find-UnwireSpec] '$target' returned $($response.StatusCode) -> skipping."
        continue PROBE_PATHS
    }

    $text      = ConvertTo-UnwireText -Content $response.Content
    $specMatch = Get-UnwireSpecMatch -Text $text
    if ($null -EQ $specMatch) {
        Write-Verbose "[Find-UnwireSpec] '$target' returned 200 but no documentation -> skipping."
        continue PROBE_PATHS
    }
    Write-Verbose "[Find-UnwireSpec] '$target' is $($specMatch.Kind) $($specMatch.Version)."
    & $AddHit -HitUri $target.AbsoluteUri -HitPath $probePath -Text $text -SpecMatch $specMatch -Directory $OutputDirectory
    if ($specMatch.Kind -NE 'SwaggerUi') {
        continue PROBE_PATHS
    }

    <#
        Swagger UI page: the spec is configured in its scripts, not in a well-known path.
        > inline scripts and same-origin init/config scripts of the page are read
        > "swaggerDoc": {...} in them            -> the embedded spec
        > url: "..." on the same origin           -> probed like a spec path
        > url: on another origin                  -> skipped (the default Petstore example)
    #>
    $configTexts = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($inline in [System.Text.RegularExpressions.Regex]::Matches($text, $INLINE_SCRIPT)) {
        $configTexts.Add([PSCustomObject]@{ Uri = $target; Text = $inline.Groups['code'].Value })
    }
    foreach ($scriptMatch in [System.Text.RegularExpressions.Regex]::Matches($text, $SWAGGER_INIT_SCRIPT)) {
        $scriptUri = [System.Uri]::new($target, $scriptMatch.Groups['src'].Value)
        if ($scriptUri.GetLeftPart([System.UriPartial]::Authority) -NE $BaseUri.GetLeftPart([System.UriPartial]::Authority)) {
            Write-Verbose "[Find-UnwireSpec] '$scriptUri' is on another origin -> skipping."
            continue
        }
        $scriptResponse = Invoke-UnwireWebRequest -RequestConfig $RequestConfig -Uri $scriptUri
        if ($scriptResponse.StatusCode -EQ 200) {
            $configTexts.Add([PSCustomObject]@{ Uri = $scriptUri; Text = (ConvertTo-UnwireText -Content $scriptResponse.Content) })
        }
    }

    foreach ($config in $configTexts) {
        $uiSpec   = Get-UnwireSwaggerUiSpec -Text $config.Text
        # 'http://shop.test/api-docs/swagger-ui-init.js' => 'api-docs/swagger-ui-init.js'
        $basePath = $BaseUri.AbsolutePath
        $relative = $config.Uri.AbsolutePath.Substring([System.Math]::Min($basePath.Length, $config.Uri.AbsolutePath.Length)).TrimStart('/')

        # "swaggerDoc": { ... }
        $embeddedMatch = if ($null -NE $uiSpec.Embedded) { Get-UnwireSpecMatch -Text $uiSpec.Embedded } else { $null }
        if ($null -NE $embeddedMatch -AND $embeddedMatch.Kind -IN $SPEC_KINDS) {
            Write-Verbose "[Find-UnwireSpec] '$($config.Uri)' embeds $($embeddedMatch.Kind) $($embeddedMatch.Version)."
            & $AddHit -HitUri "$($config.Uri.AbsoluteUri)#swaggerDoc" -HitPath "$relative#swaggerDoc" -Text $uiSpec.Embedded -SpecMatch $embeddedMatch -Directory $OutputDirectory
        }

        # url: "..."
        foreach ($specUrl in $uiSpec.Urls) {
            $specUri = $null
            if (-NOT [System.Uri]::TryCreate($config.Uri, $specUrl, [ref] $specUri) -OR $specUri.Scheme -NOTIN @('http', 'https')) {
                continue
            }
            if ($specUri.GetLeftPart([System.UriPartial]::Authority) -NE $BaseUri.GetLeftPart([System.UriPartial]::Authority)) {
                Write-Verbose "[Find-UnwireSpec] Swagger UI points to '$specUri' on another origin -> skipping."
                continue
            }
            $specResponse = Invoke-UnwireWebRequest -RequestConfig $RequestConfig -Uri $specUri
            $specText     = if ($specResponse.StatusCode -EQ 200) { ConvertTo-UnwireText -Content $specResponse.Content } else { $null }
            $urlMatch     = Get-UnwireSpecMatch -Text $specText
            if ($null -NE $urlMatch -AND $urlMatch.Kind -IN $SPEC_KINDS) {
                & $AddHit -HitUri $specUri.AbsoluteUri -HitPath $specUri.AbsolutePath.TrimStart('/') -Text $specText -SpecMatch $urlMatch -Directory $OutputDirectory
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Report
#   Returns the hits, warns when there are none.
# ---------------------------------------------------------------------------

if ($Hits.Count -EQ 0) {
    Write-Warning "[Find-UnwireSpec] No published documentation found on '$BaseUri' -> continue with unwire:analyze."
}

return $Hits.ToArray()
