# NOTE:
#   Probes a web UI for published API documentation: OpenAPI and Swagger specs (JSON, YAML),
#   Swagger UI, ReDoc and GraphiQL pages. Sends GET requests to well-known paths only and
#   follows no redirects, so nothing on the target is changed.
#
#   ./scripts/Find-UnwireSpec.ps1 -Uri 'http://192.168.178.1'
#   ./scripts/Find-UnwireSpec.ps1 -Uri 'https://nas.local:5001' -SkipCertificateCheck -OutputDirectory ./unwire/nas/discover

#
#   Chapters:
#     HELPERS                  Text decoding and documentation detection.
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

$SPEC_PATHS_FILE   = Join-Path -Path $PSScriptRoot -ChildPath 'data/spec-paths.json'
$SPEC_KINDS        = @('OpenApi', 'Swagger', 'OpenApiYaml')     # kinds that are saved as files
# 'openapi: 3.1.0' or "swagger: '2.0'" at the start of a line
$YAML_SPEC_PATTERN = '(?m)^(?<kind>openapi|swagger)\s*:\s*[''"]?(?<version>[\d.]+)'

# ===========================================================================
# ===============================   HELPERS   ===============================
# ===========================================================================
#
#   ConvertTo-UnwireText     Turns a response body (string or bytes) into text.
#   Get-UnwireSpecMatch      Detects which kind of documentation a text is.
#

function ConvertTo-UnwireText {
    param (
        [System.Object] $Content
    )

    if ($Content -is [System.Byte[]]) {
        return [System.Text.Encoding]::UTF8.GetString($Content)
    }
    return [System.String] $Content
}

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

$Hits = [System.Collections.Generic.List[PSCustomObject]]::new()

:PROBE_PATHS foreach ($probePath in $ProbePaths) {
    $target = [System.Uri]::new($BaseUri, $probePath.TrimStart('/'))

    try {
        $response = Invoke-WebRequest @RequestConfig -Uri $target
    }
    catch [System.Net.Http.HttpRequestException] {
        # Connection refused, DNS or TLS failure: every other path would fail the same way.
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

    # Saves specs only, documentation pages are reported but not saved.
    $savedFile = $null
    if (-NOT [System.String]::IsNullOrEmpty($OutputDirectory) -AND $specMatch.Kind -IN $SPEC_KINDS) {
        # 'swagger/v1/swagger.json' => 'swagger-v1-swagger.json', 'v3/api-docs' => 'v3-api-docs.json'
        $fileBase  = ($probePath.Trim('/') -REPLACE '[^\w.-]+', '-') -REPLACE '\.(json|ya?ml)$', ''
        $extension = if ($specMatch.Kind -EQ 'OpenApiYaml') { 'yaml' } else { 'json' }
        $savedFile = Join-Path -Path $OutputDirectory -ChildPath "$fileBase.$extension"

        if ($PSCmdlet.ShouldProcess($savedFile, 'Save spec')) {
            $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
            Set-Content -Path $savedFile -Value $text -NoNewline -Encoding utf8NoBOM
        }
    }

    $Hits.Add([PSCustomObject]@{
            Uri       = $target.AbsoluteUri
            Path      = $probePath
            Kind      = $specMatch.Kind
            Version   = $specMatch.Version
            Title     = $specMatch.Title
            SavedFile = $savedFile
        })
}

# ---------------------------------------------------------------------------
# Report
#   Returns the hits, warns when there are none.
# ---------------------------------------------------------------------------

if ($Hits.Count -EQ 0) {
    Write-Warning "[Find-UnwireSpec] No published documentation found on '$BaseUri' -> continue with unwire-analyze."
}

return $Hits.ToArray()
