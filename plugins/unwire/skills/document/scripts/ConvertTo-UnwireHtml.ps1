# NOTE:
#   Renders an Unwire openapi.json as one self-contained, clickable HTML page: groups,
#   search, filters for confidence, write operations and open points, schemas, sources.
#   No CDN, no network, the page opens offline from the file system.
#
#   ./plugins/unwire/skills/document/scripts/ConvertTo-UnwireHtml.ps1 -Path ./unwire/router/openapi.json
#   ./plugins/unwire/skills/document/scripts/ConvertTo-UnwireHtml.ps1 -Path ./unwire/router/openapi.json -OutputFile ./docs/router.html

#
#   Chapters:
#     LOAD SPEC     Validates the file and reads title and operation count.
#     RENDER HTML   Fills the template and writes the page.
#

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    <#
    [Required]
    Path to the openapi.json to render.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $Path,

    <#
    [Optional]
    HTML file to write. Default is API.html next to the spec.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String]
    $OutputFile
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

$TEMPLATE_FILE       = Join-Path -Path $PSScriptRoot -ChildPath '../templates/tmpl.api.html'
$ICON_FILE           = Join-Path -Path $PSScriptRoot -ChildPath '../../../assets/icon.svg'
$PLACEHOLDER_PATTERN = '__UNWIRE_(?<name>TITLE|SPEC_JSON|FAVICON)__'
$HTTP_METHODS        = @('get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace')
# JSON escape of '<', built from char codes so no tool or editor turns it back into '<'.
$JSON_ESCAPED_LT     = -join [System.Char[]] @(92, 117, 48, 48, 51, 99)     # backslash u 0 0 3 c

# ===========================================================================
# ==============================   LOAD SPEC   ==============================
# ===========================================================================
#
#   1. Validations   Fails early on a missing file or invalid JSON.
#   2. Parse         Reads the title and counts the operations.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early on a missing file or invalid JSON.
# ---------------------------------------------------------------------------

if (-NOT (Test-Path -Path $Path -PathType Leaf)) {
    throw [System.ArgumentException]::new("Path must be an existing openapi.json file, got '$Path'.")
}
$SpecText = Get-Content -Path $Path -Raw
if (-NOT (Test-Json -Json $SpecText -ErrorAction SilentlyContinue)) {
    throw [System.ArgumentException]::new("Path '$Path' must contain valid JSON, run Test-UnwireSpec.ps1 for details.")
}

# ---------------------------------------------------------------------------
# Parse
#   Reads the title and counts the operations.
# ---------------------------------------------------------------------------

$Spec  = $SpecText | ConvertFrom-Json -AsHashtable -Depth 200
$Title = if ($Spec['info'] -is [System.Collections.IDictionary] -AND -NOT [System.String]::IsNullOrWhiteSpace($Spec['info']['title'])) {
    [System.String] $Spec['info']['title']
}
else {
    'API'
}

$OperationCount = 0
if ($Spec['paths'] -is [System.Collections.IDictionary]) {
    foreach ($pathItem in $Spec['paths'].Values) {
        if ($pathItem -is [System.Collections.IDictionary]) {
            $OperationCount += @($HTTP_METHODS | Where-Object { $pathItem.Contains($_) }).Count
        }
    }
}
Write-Verbose "[ConvertTo-UnwireHtml] '$Title' with $OperationCount operations."

# ===========================================================================
# =============================   RENDER HTML   =============================
# ===========================================================================
#
#   1. Fill    Replaces the placeholders in one pass, the spec escaped for <script>.
#   2. Write   Writes the page and returns its path and file URI.
#

# ---------------------------------------------------------------------------
# Fill
#   Replaces the placeholders in one pass, the spec escaped for <script>.
# ---------------------------------------------------------------------------

# '<' only occurs inside JSON strings. As the JSON escape backslash-u-003c it is the same
# string for JSON.parse, but no '</script>' or '<!--' can end the script block early.
$EmbeddedSpec = $SpecText.Trim().Replace('<', $JSON_ESCAPED_LT)
$EncodedTitle = [System.Net.WebUtility]::HtmlEncode($Title)
# The plugin icon as favicon, base64 keeps the page self-contained.
$EncodedIcon  = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($ICON_FILE))

# One pass: a title containing '__UNWIRE_SPEC_JSON__' is never replaced again.
$Html = [System.Text.RegularExpressions.Regex]::Replace(
    (Get-Content -Path $TEMPLATE_FILE -Raw),
    $PLACEHOLDER_PATTERN,
    {
        param ($match)
        switch ($match.Groups['name'].Value) {
            'TITLE'   { $EncodedTitle }
            'FAVICON' { $EncodedIcon }
            default   { $EmbeddedSpec }
        }
    }
)

# ---------------------------------------------------------------------------
# Write
#   Writes the page and returns its path and file URI.
# ---------------------------------------------------------------------------

# Order of precedence: parameter > API.html next to the spec
$TargetFile = if (-NOT [System.String]::IsNullOrEmpty($OutputFile)) {
    $OutputFile
}
else {
    Join-Path -Path (Split-Path -Path (Resolve-Path -Path $Path).Path -Parent) -ChildPath 'API.html'
}

if ($PSCmdlet.ShouldProcess($TargetFile, 'Write API documentation')) {
    $targetDirectory = Split-Path -Path $TargetFile -Parent
    if (-NOT [System.String]::IsNullOrEmpty($targetDirectory)) {
        $null = New-Item -ItemType Directory -Path $targetDirectory -Force
    }
    Set-Content -Path $TargetFile -Value $Html -NoNewline -Encoding utf8NoBOM
}

# The link to open the page in the browser, built here, not by Claude: drive letters and
# spaces need encoding.
# - C:\Users\Jo Doe\unwire\gitea\API.html  => file:///C:/Users/Jo%20Doe/unwire/gitea/API.html
$FullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TargetFile)
$FileUri  = [System.Uri]::new($FullPath).AbsoluteUri

return [PSCustomObject]@{
    OutputFile = $TargetFile
    FileUri    = $FileUri
    Title      = $Title
    Operations = $OperationCount
}
