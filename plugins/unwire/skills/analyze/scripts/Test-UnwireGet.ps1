# NOTE:
#   Last, optional step of unwire:analyze: sends the safe GET operations of an Unwire
#   openapi.json to the target, only after the user agreed for this run and this target.
#   Safe means: method GET, x-unwire-impact read, nothing on the denylist of
#   shared/data/request-denylist.json (pattern, and liveGetPattern: no token, secret or
#   backup path), and every path parameter (and required query parameter) filled with a
#   value the user gave in -Value. No redirect is followed.
#
#   Every operation goes out without a session first: that tells public from protected.
#   With -PromptSession or -UseSession it goes out a second time with the session of the
#   user's browser (shared/session). Of each answer only the status code, the media type and
#   the JSON shape (keys and types, no values) are kept: bodies never reach the disk, the
#   session never reaches a record, a log line or the spec.
#
#   Writes into the spec: x-unwire-verified true for every operation that answered 2xx, an
#   empty response schema filled with the observed shape, and one 'Live GET' open point per
#   tested operation. Writes live-get.json next to the spec with every planned, skipped and
#   tested operation.
#
#   -Plan lists what would be sent and why the rest is skipped, without any request.
#   A progress bar shows every request. -Window (or -PromptSession) ends with a line that
#   tells the user to close the window.
#
#   ./plugins/unwire/skills/analyze/scripts/Test-UnwireGet.ps1 -Path ./unwire/router/openapi.json -Uri 'http://192.168.178.1' -Plan
#   ./plugins/unwire/skills/analyze/scripts/Test-UnwireGet.ps1 -Path ./unwire/router/openapi.json -Uri 'http://192.168.178.1'
#   ./plugins/unwire/skills/analyze/scripts/Test-UnwireGet.ps1 -Path ./unwire/nas/openapi.json -Uri 'https://nas.local' -Value 'owner=me,repo=notes' -SkipCertificateCheck
#   ./plugins/unwire/skills/analyze/scripts/Test-UnwireGet.ps1 -Path ./unwire/nas/openapi.json -Uri 'https://nas.local' -PromptSession -Language de

#
#   Chapters:
#     HELPERS          Parameter references, URI building and the JSON shape.
#     PLAN REQUESTS    Validates the input and picks the safe GET operations.
#     SEND REQUESTS    Reads the session, sends every planned GET, keeps the shape.
#     WRITE RESULTS    Updates the spec, writes live-get.json, returns a summary.
#

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'The last line of the login guide is for the user in the window.')]
[CmdletBinding()]
param (
    <#
    [Required]
    The Unwire openapi.json to test, e.g. './unwire/router/openapi.json'.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $Path,

    <#
    [Required]
    URI of the target, e.g. 'http://192.168.178.1'. The first server of the spec is resolved
    against it and must stay on its origin.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $Uri,

    <#
    [Optional]
    Values for path parameters and query parameters as 'name=value', also as one comma list:
    'owner=me,repo=notes'. Only values the user gave, never guessed ones.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String[]]
    $Value = @(),

    <#
    [Optional]
    Lists the planned and skipped operations without sending anything and without writing.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [switch]
    $Plan,

    <#
    [Optional]
    Maximum number of requests, both passes counted. Default is 200.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(1, 2000)]
    [System.Int32]
    $MaxRequests = 200,

    <#
    [Optional]
    Pause between two requests in milliseconds, so a small device keeps up. Default is 100.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(0, 10000)]
    [System.Int32]
    $DelayMilliseconds = 100,

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
    Accepts self-signed certificates, only after the user agreed for this host.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [switch]
    $SkipCertificateCheck,

    <#
    [Optional]
    Sends every operation a second time with the session from the environment variable
    SessionVariable. For tests and the mock runs only, never set by the agent: it would
    put the cookie into its own shell. The agent uses PromptSession.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [switch]
    $UseSession,

    <#
    [Optional]
    Environment variable for UseSession. Default is UNWIRE_COOKIE.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String]
    $SessionVariable = 'UNWIRE_COOKIE',

    <#
    [Optional]
    Name of the URL parameter that carries the session, e.g. 'sid'.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidatePattern('^[\w-]+$')]
    [System.String]
    $SessionParameter,

    <#
    [Optional]
    Asks for the session with a masked prompt, like Save-UnwireAsset: the login guide of
    data/login-guide.json first, the session lives only in memory for this run.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [switch]
    $PromptSession,

    <#
    [Optional]
    Language of the login guide, a key of data/login-guide.json ('en', 'de'). Default is en.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String]
    $Language = 'en',

    <#
    [Optional]
    Runs in a window the user watches (Start-Process): ends with the 'done' line of the
    login guide, so the user knows when to close it. PromptSession implies it.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [switch]
    $Window
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

. $PSScriptRoot/../../../shared/Get-UnwireCertificateError.ps1
. $PSScriptRoot/../../../shared/Invoke-UnwireWebRequest.ps1
. $PSScriptRoot/../../../shared/ConvertTo-UnwireText.ps1
. $PSScriptRoot/../../../shared/session/Session.ps1

$RESULTS_FILE     = 'live-get.json'
$LOGIN_GUIDE_FILE = Join-Path -Path $PSScriptRoot -ChildPath '../data/login-guide.json'
$DEFAULT_LANGUAGE = 'en'
$denylists        = Get-Content -Path (Join-Path -Path $PSScriptRoot -ChildPath '../../../shared/data/request-denylist.json') -Raw | ConvertFrom-Json
$DENYLIST         = $denylists.pattern
# GETs that may create a token or return a credential: /registration-token, /backup
$LIVE_DENYLIST    = $denylists.liveGetPattern
# Open points this script wrote, replaced on every run: 'Live GET 2026-11-02: ...'
$LIVE_OPEN_PREFIX = 'Live GET '
# '/repos/{owner}/{repo}' => 'owner', 'repo'
$PATH_PARAMETER   = '\{(?<name>[^{}]+)\}'
# Keys of a JSON object that are names, not data: 'login', 'full_name', '$ref' (not 'a@b.test', '2024-01')
$JSON_NAME_KEY    = '^[A-Za-z_$][\w$-]{0,63}$'
$MAX_NAMED_KEYS   = 100
$MAX_SHAPE_DEPTH  = 8

# ===========================================================================
# ===============================   HELPERS   ===============================
# ===========================================================================
#
#   Resolve-UnwireParameter   A parameter or its local $ref target.
#   Get-UnwireJsonShape       JSON schema of a parsed value: keys and types, no values.
#   Get-UnwireMediaType       Media type of a Content-Type header, without parameters.
#   Test-UnwireEmptySchema    Whether a response schema says nothing yet.
#   Format-UnwireAnswer       One answer as text for the open point: 'HTTP 200 application/json'.
#

function Resolve-UnwireParameter {
    param (
        [System.Collections.IDictionary] $Parameter,
        [System.Collections.IDictionary] $Spec
    )

    # '#/components/parameters/limit' => $Spec.components.parameters.limit
    $ref = $Parameter['$ref']
    if ($ref -isnot [System.String] -OR -NOT $ref.StartsWith('#/')) {
        return $Parameter
    }
    $target = $Spec
    foreach ($segment in $ref.Substring(2).Split('/')) {
        if ($target -isnot [System.Collections.IDictionary] -OR -NOT $target.Contains($segment)) {
            return $Parameter
        }
        $target = $target[$segment]
    }
    return $target
}

function Get-UnwireJsonShape {
    param (
        [System.Object] $Node,
        [System.Int32]  $Depth = 0
    )

    <#
        > Deeper than MAX_SHAPE_DEPTH, null   -> {} (nothing known)
        > boolean, integer, number, string    -> { type }
        > list                                -> { type: array, items: shape of the first
                                                 element that is not null }
        > object with name keys               -> { type: object, properties: shape per key }
        > object with data keys (mails,       -> { type: object, additionalProperties: shape
          ids, dates) or too many keys           of the first value }: the keys are values
    #>

    if ($Depth -GT $MAX_SHAPE_DEPTH -OR $null -EQ $Node) {
        return [ordered]@{}
    }
    if ($Node -is [System.Boolean]) {
        return [ordered]@{ type = 'boolean' }
    }
    if ($Node -is [System.Int32] -OR $Node -is [System.Int64] -OR $Node -is [System.Numerics.BigInteger]) {
        return [ordered]@{ type = 'integer' }
    }
    if ($Node -is [System.Double] -OR $Node -is [System.Decimal]) {
        return [ordered]@{ type = 'number' }
    }
    if ($Node -is [System.String] -OR $Node -is [System.DateTime]) {
        return [ordered]@{ type = 'string' }
    }
    if ($Node -is [System.Collections.IDictionary]) {
        $keys       = @($Node.Keys)
        $isNameKeys = $keys.Count -LE $MAX_NAMED_KEYS -AND @($keys | Where-Object { $_ -NOTMATCH $JSON_NAME_KEY }).Count -EQ 0
        if (-NOT $isNameKeys) {
            return [ordered]@{ type = 'object'; additionalProperties = (Get-UnwireJsonShape -Node $Node[$keys[0]] -Depth ($Depth + 1)) }
        }
        $properties = [ordered]@{}
        foreach ($key in $keys) {
            $properties[$key] = Get-UnwireJsonShape -Node $Node[$key] -Depth ($Depth + 1)
        }
        return [ordered]@{ type = 'object'; properties = $properties }
    }
    if ($Node -is [System.Collections.IList]) {
        $first = @($Node | Where-Object { $null -NE $_ } | Select-Object -First 1)
        $items = if ($first.Count -GT 0) { Get-UnwireJsonShape -Node $first[0] -Depth ($Depth + 1) } else { [ordered]@{} }
        return [ordered]@{ type = 'array'; items = $items }
    }
    return [ordered]@{}
}

function Get-UnwireMediaType {
    param (
        [System.Object] $Response
    )

    # 'application/json; charset=utf-8' => 'application/json'
    $header = if ($null -NE $Response.Headers) { @($Response.Headers['Content-Type'])[0] } else { $null }
    if ([System.String]::IsNullOrEmpty($header)) {
        return $null
    }
    return $header.Split(';')[0].Trim().ToLowerInvariant()
}

function Test-UnwireEmptySchema {
    param (
        [System.Object] $Schema
    )

    # {} or missing says nothing, a $ref or any keyword is a real schema and stays.
    return $null -EQ $Schema -OR ($Schema -is [System.Collections.IDictionary] -AND $Schema.Count -EQ 0)
}

function Format-UnwireAnswer {
    param (
        [System.Collections.IDictionary] $Result
    )

    if ($null -EQ $Result) {
        return 'not sent'
    }
    if ($null -NE $Result.Error) {
        return "failed ($($Result.Error))"
    }
    return "HTTP $($Result.Status)$(if ($Result.MediaType) { " $($Result.MediaType)" })"
}

# ===========================================================================
# ============================   PLAN REQUESTS   ============================
# ===========================================================================
#
#   1. Validations   Fails early on a bad URI, a missing spec or a bad value.
#   2. Plan          Picks the safe GET operations and builds their URIs.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early on a bad URI, a missing spec or a bad value.
# ---------------------------------------------------------------------------

$TargetUri = $null
if (-NOT [System.Uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref] $TargetUri) -OR $TargetUri.Scheme -NOTIN @('http', 'https')) {
    throw [System.ArgumentException]::new("Uri must be an absolute http or https URI, e.g. 'http://192.168.178.1', got '$Uri'.")
}
if (-NOT (Test-Path -Path $Path -PathType Leaf)) {
    throw [System.ArgumentException]::new("Path '$Path' must be an existing openapi.json.")
}
if (-NOT $PromptSession -AND -NOT $UseSession -AND -NOT [System.String]::IsNullOrEmpty($SessionParameter)) {
    throw [System.ArgumentException]::new("SessionParameter '$SessionParameter' must be used with PromptSession or UseSession.")
}

$SpecPath = (Resolve-Path -Path $Path).Path
$Spec     = Get-Content -Path $SpecPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100

# pwsh -File hands a list over as one string: 'owner=me,repo=notes' => owner, repo
$Values = @{}
foreach ($pair in ($Value -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -NE '' })) {
    $separator = $pair.IndexOf('=')
    if ($separator -LT 1) {
        throw [System.ArgumentException]::new("Value must be 'name=value', e.g. 'owner=me', got '$pair'.")
    }
    $Values[$pair.Substring(0, $separator).Trim()] = $pair.Substring($separator + 1).Trim()
}

# The first server, resolved against the target: '/api/v1' => 'http://router.test/api/v1'
$firstServer = @($Spec['servers'] | Where-Object { $_ -is [System.Collections.IDictionary] }) | Select-Object -First 1
$ServerUrl   = if ($null -NE $firstServer -AND -NOT [System.String]::IsNullOrEmpty($firstServer['url'])) { $firstServer['url'] } else { '/' }
$ServerUri   = [System.Uri]::new($TargetUri, $ServerUrl)
if (0 -NE [System.Uri]::Compare($ServerUri, $TargetUri, [System.UriComponents]::SchemeAndServer, [System.UriFormat]::SafeUnescaped, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw [System.ArgumentException]::new("The first server of the spec ('$ServerUrl') must be on the origin of Uri '$TargetUri', the test only sends to the target the user named.")
}
$ServerPath = $ServerUri.AbsolutePath.TrimEnd('/')

# ---------------------------------------------------------------------------
# Plan
#   Picks the safe GET operations and builds their URIs.
# ---------------------------------------------------------------------------

<#
    Per GET operation, the first rule that matches:
    > x-unwire-impact is not read          -> skipped
    > Path or a value on the denylist      -> skipped
    > Path may create a token or           -> skipped (liveGetPattern of the denylist)
      return a credential
    > Path parameter without a value       -> skipped, names the parameter
    > Required query without a value       -> skipped, names the parameter
    > Otherwise                            -> planned, every query parameter with a value
                                              in the query
#>

$Operations = [System.Collections.Generic.List[PSCustomObject]]::new()     # sent in SEND REQUESTS

foreach ($pathKey in $Spec['paths'].Keys) {
    $pathItem  = $Spec['paths'][$pathKey]
    $operation = $pathItem['get']
    if ($operation -isnot [System.Collections.IDictionary]) {
        continue
    }
    $entry = [PSCustomObject]@{
        OperationId = $operation['operationId']
        Path        = $pathKey
        Uri         = $null
        Status      = 'skipped'
        Reason      = $null
        Anonymous   = $null
        Session     = $null
        Operation   = $operation
    }
    $Operations.Add($entry)

    # x-unwire-impact is not read
    if ($operation['x-unwire-impact'] -NE 'read') {
        $entry.Reason = "x-unwire-impact is '$($operation['x-unwire-impact'])', not read"
        continue
    }

    # Parameters of the path item and the operation, the operation wins on the same name.
    $parameters = [ordered]@{}
    foreach ($parameter in @(@($pathItem['parameters']) + @($operation['parameters']) | Where-Object { $_ -is [System.Collections.IDictionary] })) {
        $resolved = Resolve-UnwireParameter -Parameter $parameter -Spec $Spec
        $parameters["$($resolved['in']):$($resolved['name'])"] = $resolved
    }

    # Path or a value on the denylist
    $usedValues = @([System.Text.RegularExpressions.Regex]::Matches($pathKey, $PATH_PARAMETER) | ForEach-Object { $Values[$_.Groups['name'].Value] })
    if ("$pathKey $($usedValues -join ' ')" -MATCH $DENYLIST) {
        $entry.Reason = 'on the denylist (logout, reboot, delete, ...)'
        continue
    }
    if ($pathKey -MATCH $LIVE_DENYLIST) {
        $entry.Reason = 'may create a token or return a credential (token, secret, backup, ...)'
        continue
    }

    # Path parameter without a value
    $missing = @([System.Text.RegularExpressions.Regex]::Matches($pathKey, $PATH_PARAMETER) | ForEach-Object { $_.Groups['name'].Value } | Where-Object { -NOT $Values.ContainsKey($_) })
    if ($missing.Count -GT 0) {
        $entry.Reason = "needs a value for $(($missing | ForEach-Object { "'$_'" }) -join ', ')"
        continue
    }

    # Required query without a value
    $queryParameters = @($parameters.Values | Where-Object { $_['in'] -EQ 'query' })
    $missing         = @($queryParameters | Where-Object { $_['required'] -EQ $true -AND -NOT $Values.ContainsKey($_['name']) } | ForEach-Object { $_['name'] })
    if ($missing.Count -GT 0) {
        $entry.Reason = "needs a value for the query $(($missing | ForEach-Object { "'$_'" }) -join ', ')"
        continue
    }

    # Otherwise: '/repos/{owner}/{repo}' + owner=me => '/api/v1/repos/me/...'
    $filledPath = [System.Text.RegularExpressions.Regex]::Replace($pathKey, $PATH_PARAMETER, { param ($match) [System.Uri]::EscapeDataString($Values[$match.Groups['name'].Value]) })
    $query      = @($queryParameters | Where-Object { $Values.ContainsKey($_['name']) } | ForEach-Object { "$([System.Uri]::EscapeDataString($_['name']))=$([System.Uri]::EscapeDataString($Values[$_['name']]))" }) -join '&'
    $builder    = [System.UriBuilder]::new($ServerUri)
    $builder.Path  = "$ServerPath$filledPath"
    $builder.Query = $query
    $entry.Uri     = $builder.Uri
    $entry.Status  = 'planned'
}

$Planned = @($Operations | Where-Object Status -EQ 'planned')
Write-Verbose "[Test-UnwireGet] $($Planned.Count) of $($Operations.Count) GET operations planned."

if ($Plan) {
    return $Operations | Select-Object -Property OperationId, Path, Uri, Status, Reason
}

# ===========================================================================
# ============================   SEND REQUESTS   ============================
# ===========================================================================
#
#   1. Session    Reads the session of the user's browser, when one was asked for.
#   2. Requests   Sends every planned GET without and with the session.
#

# ---------------------------------------------------------------------------
# Session
#   Reads the session of the user's browser, when one was asked for.
# ---------------------------------------------------------------------------

# The session value never goes into a message, a log line, a record or the spec.
$SessionConfig = @{
    PromptSession     = $PromptSession
    UseSession        = $UseSession
    SessionVariable   = $SessionVariable
    SessionParameter  = $SessionParameter
    # Endpoints often need the Authorization header of an API request, not the page cookie.
    ConfirmCookieOnly = $true
    Uri               = $TargetUri
    GuideFile         = $LOGIN_GUIDE_FILE
    Language          = $Language
}
$Session        = Read-UnwireSession @SessionConfig
$SessionSecrets = if ($null -NE $Session) { $Session.Secrets } else { @() }

# ---------------------------------------------------------------------------
# Requests
#   Sends every planned GET without and with the session.
# ---------------------------------------------------------------------------

<#
    Per planned operation, each pass (without session, then with one):
    > MaxRequests reached                -> skipped
    > Request fails on the first one     -> throws: certificate (ask the user) or unreachable
    > Request fails later                -> failed, the exception type only
    > Answer                             -> status, media type; for 2xx JSON the shape,
                                            the body is dropped right after
    No redirect is followed: a 3xx is the answer (often the login page).
#>

$RequestConfig = @{
    Method               = 'Get'
    TimeoutSec           = $TimeoutSec
    MaximumRedirection   = 0
    SkipHttpErrorCheck   = $true
    SkipCertificateCheck = $SkipCertificateCheck.IsPresent
    Headers              = @{ Accept = 'application/json, */*;q=0.5' }
}
$SessionRequestConfig = $null
if ($null -NE $Session) {
    $SessionRequestConfig         = $RequestConfig.Clone()
    $SessionRequestConfig.Headers = @{ Accept = $RequestConfig.Headers.Accept } + $Session.RequestHeaders
    Write-Verbose "[Test-UnwireGet] Second pass with $($Session.Kinds -join ', ')."
}

$RequestCount = 0
$IsFirst      = $true
# Progress for the user in the PromptSession window: path templates only, never a session.
$PassCount     = if ($null -NE $SessionRequestConfig) { 2 } else { 1 }
$ProgressTotal = [System.Math]::Max(1, [System.Math]::Min($MaxRequests, $Planned.Count * $PassCount))
$PROGRESS_NAME = 'Unwire: live GET'

:OPERATIONS foreach ($entry in $Planned) {
    $passes = @(
        @{ Name = 'Anonymous'; Config = $RequestConfig }
        if ($null -NE $SessionRequestConfig) { @{ Name = 'Session'; Config = $SessionRequestConfig } }
    )
    foreach ($pass in $passes) {
        # MaxRequests reached
        if ($RequestCount -GE $MaxRequests) {
            $entry.Status = if ($null -EQ $entry.Anonymous) { 'skipped' } else { 'tested' }
            $entry.Reason = "MaxRequests $MaxRequests reached"
            break OPERATIONS
        }
        if ($RequestCount -GT 0 -AND $DelayMilliseconds -GT 0) {
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
        $RequestCount++
        $passLabel = if ($pass.Name -EQ 'Session') { 'with session' } else { 'without session' }
        Write-Progress -Activity $PROGRESS_NAME -Status "$RequestCount / $($ProgressTotal): GET $($entry.Path) ($passLabel)" -PercentComplete ([System.Math]::Min(100, [System.Int32] (100 * $RequestCount / $ProgressTotal)))

        # The session in the URL only on the wire, no verbose line of the request shows it.
        $requestUri     = $entry.Uri
        $requestVerbose = $VerbosePreference
        if ($pass.Name -EQ 'Session' -AND $Session.IsUriSession) {
            $uriSession     = $Session.UriSession
            $requestUri     = Get-UnwireRequestUri -Uri $entry.Uri @uriSession
            $requestVerbose = 'SilentlyContinue'
        }

        $result = [ordered]@{ Status = $null; MediaType = $null; Error = $null }
        try {
            $response = & {
                $VerbosePreference = $requestVerbose
                Invoke-UnwireWebRequest -RequestConfig $pass.Config -Uri $requestUri
            }
        }
        catch [System.Net.Http.HttpRequestException], [System.OperationCanceledException], [System.TimeoutException] {
            # Request fails on the first one
            $certificateError = Get-UnwireCertificateError -Exception $_.Exception
            if ($IsFirst -AND $null -NE $certificateError) {
                throw [System.Security.Authentication.AuthenticationException]::new("Uri '$TargetUri' has a TLS certificate this machine does not trust ($certificateError). Ask the user, then run again with -SkipCertificateCheck.", $_.Exception)
            }
            if ($IsFirst) {
                throw [System.InvalidOperationException]::new("Uri '$TargetUri' must be reachable, the first request failed: $(ConvertTo-UnwireRedactedText -Text $_.Exception.Message -Secrets $SessionSecrets)", $_.Exception)
            }
            # Request fails later
            $result.Error = $_.Exception.GetType().Name
            $entry.$($pass.Name) = $result
            continue
        }
        $IsFirst = $false

        # Answer: the body is parsed in memory, only its shape is kept.
        $result.Status    = [System.Int32] $response.StatusCode
        $result.MediaType = Get-UnwireMediaType -Response $response
        if ($result.Status -GE 200 -AND $result.Status -LT 300 -AND "$($result.MediaType)" -MATCH '[/+]json$') {
            try {
                $parsed = ConvertTo-UnwireText -Content $response.Content | ConvertFrom-Json -AsHashtable -Depth 64 -NoEnumerate
                $result.Shape = Get-UnwireJsonShape -Node $parsed
            }
            catch [System.ArgumentException] {
                Write-Verbose "[Test-UnwireGet] '$($entry.Path)' says JSON but is none -> no shape."
            }
        }
        Write-Verbose "[Test-UnwireGet] GET $($entry.Path) ($($pass.Name)) -> HTTP $($result.Status)."
        $entry.$($pass.Name) = $result
        $response = $null
    }
    $entry.Status = 'tested'
}

Write-Progress -Activity $PROGRESS_NAME -Completed

# MaxRequests reached: what is still planned was never sent.
foreach ($entry in @($Planned | Where-Object Status -EQ 'planned')) {
    $entry.Status = 'skipped'
    $entry.Reason = "MaxRequests $MaxRequests reached"
}

# Last step of the guide: the user closes the window only after this line.
if ($PromptSession -OR $Window) {
    $guides = Get-Content -Path $LOGIN_GUIDE_FILE -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    Write-Host ''
    Write-Host $guides[$(if ($guides.ContainsKey($Language)) { $Language } else { $DEFAULT_LANGUAGE })].done
}

# ===========================================================================
# ============================   WRITE RESULTS   ============================
# ===========================================================================
#
#   1. Spec      Marks verified operations, fills empty schemas, notes the answers.
#   2. Results   Writes live-get.json and returns a summary.
#

# ---------------------------------------------------------------------------
# Spec
#   Marks verified operations, fills empty schemas, notes the answers.
# ---------------------------------------------------------------------------

<#
    Per tested operation:
    > Any pass answered 2xx            -> x-unwire-verified true
    > 2xx JSON, schema of that status  -> the observed shape (session pass first),
      empty or missing                    a published schema stays as it is
    > Always                           -> one 'Live GET' open point with both answers,
                                          plus a hint when the answers contradict security
#>

$Today = [System.DateTime]::Now.ToString('yyyy-MM-dd')

foreach ($entry in @($Operations | Where-Object Status -EQ 'tested')) {
    $operation = $entry.Operation
    $passes    = @($entry.Session, $entry.Anonymous) | Where-Object { $null -NE $_ -AND $null -NE $_.Status }
    $success   = @($passes | Where-Object { $_.Status -GE 200 -AND $_.Status -LT 300 })

    # Any pass answered 2xx
    if ($success.Count -GT 0) {
        $operation['x-unwire-verified'] = $true
    }

    # 2xx JSON, schema of that status empty or missing
    $observed = @($success | Where-Object { $_.Contains('Shape') }) | Select-Object -First 1
    $isFilled = $false
    if ($null -NE $observed) {
        if ($operation['responses'] -isnot [System.Collections.IDictionary]) {
            $operation['responses'] = [ordered]@{}
        }
        $code     = [System.String] $observed.Status
        $response = $operation['responses'][$code]
        if ($null -EQ $response) {
            $response = [ordered]@{ description = 'Observed by Test-UnwireGet.' }
            $operation['responses'][$code] = $response
        }
        if ($response -is [System.Collections.IDictionary] -AND -NOT $response.Contains('$ref')) {
            if ($response['content'] -isnot [System.Collections.IDictionary]) {
                $response['content'] = [ordered]@{}
            }
            $media = $response['content'][$observed.MediaType]
            if ($null -EQ $media) {
                $media = [ordered]@{}
                $response['content'][$observed.MediaType] = $media
            }
            if (Test-UnwireEmptySchema -Schema $media['schema']) {
                $media['schema'] = $observed.Shape
                $isFilled        = $true
            }
        }
    }

    # Always: one open point, the old ones of this script replaced
    $security  = if ($operation.Contains('security')) { @($operation['security']) } else { @($Spec['security']) }
    $isPublic  = @($security | Where-Object { $_ -is [System.Collections.IDictionary] -AND $_.Count -EQ 0 }).Count -GT 0 -OR @($security | Where-Object { $null -NE $_ }).Count -EQ 0
    $anonymous = $entry.Anonymous
    $notes     = @(
        "$($LIVE_OPEN_PREFIX)$($Today): without session $(Format-UnwireAnswer -Result $anonymous), with session $(Format-UnwireAnswer -Result $entry.Session)."
        if ($null -NE $anonymous -AND $anonymous.Status -GE 200 -AND $anonymous.Status -LT 300 -AND -NOT $isPublic) { 'It answered without a session, security may be [].' }
        if ($null -NE $anonymous -AND $anonymous.Status -IN @(401, 403) -AND $isPublic) { 'It refused without a session although security is [].' }
        if ($isFilled) { 'Response schema from the live answer: keys and types only, check it.' }
    ) -join ' '
    $openPoints = @(@($operation['x-unwire-open']) | Where-Object { $_ -is [System.String] -AND -NOT $_.StartsWith($LIVE_OPEN_PREFIX) })
    $operation['x-unwire-open'] = @($openPoints) + $notes
}

# The target is the default base URL of API.html, an analysis may have left it out.
if (-NOT $Spec.Contains('x-unwire-target')) {
    $Spec['x-unwire-target'] = $TargetUri.AbsoluteUri
}
$Spec | ConvertTo-Json -Depth 100 | Set-Content -Path $SpecPath -Encoding utf8NoBOM

# ---------------------------------------------------------------------------
# Results
#   Writes live-get.json and returns a summary.
# ---------------------------------------------------------------------------

$ResultsPath = Join-Path -Path (Split-Path -Path $SpecPath -Parent) -ChildPath $RESULTS_FILE
$resultsJson = [ordered]@{
    target       = $TargetUri.GetLeftPart([System.UriPartial]::Authority)
    testedAt     = [System.DateTime]::Now.ToString('o')
    sessionKinds = if ($null -NE $Session) { $Session.Kinds } else { @() }     # names only
    requests     = $RequestCount
    operations   = @(
        $Operations | ForEach-Object {
            [ordered]@{
                operationId = $_.OperationId
                path        = $_.Path
                uri         = if ($null -NE $_.Uri) { $_.Uri.AbsoluteUri } else { $null }     # never with the session
                status      = $_.Status
                reason      = $_.Reason
                anonymous   = if ($null -NE $_.Anonymous) { [ordered]@{ status = $_.Anonymous.Status; mediaType = $_.Anonymous.MediaType; error = $_.Anonymous.Error } } else { $null }
                session     = if ($null -NE $_.Session) { [ordered]@{ status = $_.Session.Status; mediaType = $_.Session.MediaType; error = $_.Session.Error } } else { $null }
            }
        }
    )
}
| ConvertTo-Json -Depth 6
# Last line of defense: no session value in the file, wherever it came from.
ConvertTo-UnwireRedactedText -Text $resultsJson -Secrets $SessionSecrets
| Set-Content -Path $ResultsPath -Encoding utf8NoBOM

$Tested = @($Operations | Where-Object Status -EQ 'tested')
return [PSCustomObject]@{
    OutputFile = $ResultsPath
    Spec       = $SpecPath
    Planned    = $Planned.Count
    Tested     = $Tested.Count
    Verified   = @($Tested | Where-Object { $_.Operation['x-unwire-verified'] -EQ $true }).Count
    Skipped    = @($Operations | Where-Object Status -EQ 'skipped').Count
    Requests   = $RequestCount
}
