# NOTE:
#   Validates an Unwire openapi.json before unwire:document renders it:
#   the OpenAPI 3.x structure both need, path parameters, unique operationIds,
#   local $ref targets, security against the defined schemes and the x-unwire-*
#   extensions on every operation.
#   Returns one finding per problem, nothing when the spec is valid.
#
#   A spec taken over by unwire:discover (root x-unwire-source 'discover:...') was written
#   by the device, so missing x-unwire-* extensions are only warnings there.
#
#   ./plugins/unwire/shared/Test-UnwireSpec.ps1 -Path ./unwire/router/openapi.json
#   ./plugins/unwire/shared/Test-UnwireSpec.ps1 -Path ./unwire/router/openapi.json | Where-Object Severity -EQ Error

#
#   Chapters:
#     HELPERS           Findings, $ref collection and JSON pointer resolution.
#     LOAD SPEC         Validates the file and parses the JSON.
#     CHECK SPEC        Checks the root, every operation and every $ref.
#     REPORT FINDINGS   Returns the findings, errors first.
#

[CmdletBinding()]
param (
    <#
    [Required]
    Path to the openapi.json to validate.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $Path
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

$HTTP_METHODS      = @('get', 'put', 'post', 'delete', 'options', 'head', 'patch', 'trace')
$WRITE_METHODS     = @('put', 'post', 'delete', 'patch')
$CONFIDENCE_VALUES = @('high', 'medium', 'low')
$IMPACT_VALUES     = @('read', 'write')
# '/api/devices/{id}/ports/{port}' => 'id', 'port'
$PATH_PARAM_REGEX  = '\{(?<name>[^{}]+)\}'

# ===========================================================================
# ===============================   HELPERS   ===============================
# ===========================================================================
#
#   Add-UnwireFinding             Adds one finding to the result list.
#   Get-UnwireJsonRef             Collects every '$ref' with its location.
#   Resolve-UnwireJsonPointer     Resolves a local '#/...' pointer, $null when missing.
#   Test-UnwireSecurity           Checks one security list against the defined schemes.
#

$Findings = [System.Collections.Generic.List[PSCustomObject]]::new()     # returned in REPORT FINDINGS

function Add-UnwireFinding {
    param (
        [ValidateSet('Error', 'Warning')]
        [System.String] $Severity,
        [System.String] $Location,
        [System.String] $Rule,
        [System.String] $Message
    )

    $Findings.Add([PSCustomObject]@{ Severity = $Severity; Location = $Location; Rule = $Rule; Message = $Message })
}

function Get-UnwireJsonRef {
    param (
        [System.Object] $Node,
        [System.String] $Location
    )

    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in $Node.Keys) {
            if ($key -EQ '$ref' -AND $Node[$key] -is [System.String]) {
                [PSCustomObject]@{ Location = $Location; Ref = $Node[$key] }
                continue
            }
            Get-UnwireJsonRef -Node $Node[$key] -Location "$Location/$key"
        }
        return
    }
    if ($Node -is [System.Collections.IList]) {
        for ($index = 0; $index -LT $Node.Count; $index++) {
            Get-UnwireJsonRef -Node $Node[$index] -Location "$Location/$index"
        }
    }
}

function Resolve-UnwireJsonPointer {
    param (
        [System.Collections.IDictionary] $Document,
        [System.String]                  $Pointer
    )

    # '#/components/schemas/Device~1List' => 'components', 'schemas', 'Device/List' (RFC 6901: ~1 = '/', ~0 = '~')
    $segments = $Pointer.Substring(2).Split('/') | ForEach-Object { [System.Uri]::UnescapeDataString($_).Replace('~1', '/').Replace('~0', '~') }

    $node = $Document
    foreach ($segment in $segments) {
        if ($node -is [System.Collections.IDictionary] -AND $node.Contains($segment)) {
            $node = $node[$segment]
            continue
        }
        if ($node -is [System.Collections.IList] -AND $segment -MATCH '^\d+$' -AND [System.Int32] $segment -LT $node.Count) {
            $node = $node[[System.Int32] $segment]
            continue
        }
        return $null
    }
    return , $node
}

function Test-UnwireSecurity {
    param (
        [System.Object]   $Security,
        [System.String]   $Location,
        [System.String[]] $SchemeNames
    )

    # [{ "bearerAuth": [] }] or [] (public): a list of requirement objects
    if ($Security -isnot [System.Collections.IList] -OR @($Security | Where-Object { $_ -isnot [System.Collections.IDictionary] }).Count -GT 0) {
        Add-UnwireFinding -Severity Error -Location $Location -Rule 'security' -Message 'security must be a list of requirement objects, e.g. [{ "bearerAuth": [] }], or [] for no auth.'
        return
    }
    foreach ($name in $Security | ForEach-Object { $_.Keys }) {
        if ($name -NOTIN $SchemeNames) {
            Add-UnwireFinding -Severity Error -Location $Location -Rule 'security' -Message "security scheme '$name' must be defined in components.securitySchemes."
        }
    }
}

# ===========================================================================
# ==============================   LOAD SPEC   ==============================
# ===========================================================================
#
#   1. Validations   Fails early on a missing file.
#   2. Parse         Parses the JSON, an invalid file is the only finding.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early on a missing file.
# ---------------------------------------------------------------------------

if (-NOT (Test-Path -Path $Path -PathType Leaf)) {
    throw [System.ArgumentException]::new("Path must be an existing openapi.json file, got '$Path'.")
}

# ---------------------------------------------------------------------------
# Parse
#   Parses the JSON, an invalid file is the only finding.
# ---------------------------------------------------------------------------

$SpecText = Get-Content -Path $Path -Raw
if (-NOT (Test-Json -Json $SpecText -ErrorAction SilentlyContinue)) {
    Add-UnwireFinding -Severity Error -Location '$' -Rule 'json' -Message 'The file must be valid JSON.'
    return $Findings.ToArray()
}
$Spec = $SpecText | ConvertFrom-Json -AsHashtable -Depth 200
if ($Spec -isnot [System.Collections.IDictionary]) {
    Add-UnwireFinding -Severity Error -Location '$' -Rule 'json' -Message 'The root must be a JSON object.'
    return $Findings.ToArray()
}

# ===========================================================================
# =============================   CHECK SPEC   ==============================
# ===========================================================================
#
#   1. Root         openapi 3.x, info, servers, x-unwire-open, paths, root security.
#   2. Operations   Path parameters, operationId, responses, x-unwire-* and security.
#   3. References   Every local $ref points to an existing target.
#

# ---------------------------------------------------------------------------
# Root
#   openapi 3.x, info, servers, x-unwire-open, paths, root security.
# ---------------------------------------------------------------------------

if (-NOT ([System.String] $Spec['openapi']).StartsWith('3.')) {
    Add-UnwireFinding -Severity Error -Location 'openapi' -Rule 'openapi-version' -Message "openapi must be a 3.x version, got '$($Spec['openapi'])'. Convert Swagger 2.0 first."
}

$Info = $Spec['info']
foreach ($field in @('title', 'version')) {
    if ($Info -isnot [System.Collections.IDictionary] -OR [System.String]::IsNullOrWhiteSpace($Info[$field])) {
        Add-UnwireFinding -Severity Error -Location "info.$field" -Rule 'info' -Message "info.$field must be a non-empty string."
    }
}

# servers: a list of objects with a url, a single object is a common conversion bug
$Servers = $Spec['servers']
if ($null -NE $Servers -AND ($Servers -isnot [System.Collections.IList] -OR @($Servers | Where-Object { $_ -isnot [System.Collections.IDictionary] -OR [System.String]::IsNullOrWhiteSpace($_['url']) }).Count -GT 0)) {
    Add-UnwireFinding -Severity Error -Location 'servers' -Rule 'servers' -Message 'servers must be a list of objects with a url, e.g. [{ "url": "/api" }].'
}

# Root x-unwire-open: the open points of the whole spec (auth, unresolved URLs)
$RootOpen = $Spec['x-unwire-open']
if ($null -NE $RootOpen -AND ($RootOpen -isnot [System.Collections.IList] -OR @($RootOpen | Where-Object { $_ -isnot [System.String] }).Count -GT 0)) {
    Add-UnwireFinding -Severity Error -Location 'x-unwire-open' -Rule 'x-unwire-open' -Message 'x-unwire-open must be a list of strings.'
}

$Paths = $Spec['paths']
if ($Paths -isnot [System.Collections.IDictionary]) {
    Add-UnwireFinding -Severity Error -Location 'paths' -Rule 'paths' -Message 'paths must be an object.'
    $Paths = @{}
}
elseif ($Paths.Count -EQ 0) {
    Add-UnwireFinding -Severity Warning -Location 'paths' -Rule 'paths' -Message 'paths is empty, the spec documents nothing.'
}

# A spec of unwire:discover comes from the device: missing x-unwire-* are only warnings.
$IsDiscovered       = ([System.String] $Spec['x-unwire-source']).StartsWith('discover:')
$ExtensionSeverity  = if ($IsDiscovered) { 'Warning' } else { 'Error' }

# Security: the schemes the spec defines, the root list is the default of every operation.
$SecuritySchemes = $Spec['components'] -is [System.Collections.IDictionary] ? $Spec['components']['securitySchemes'] : $null
$SchemeNames     = @($SecuritySchemes -is [System.Collections.IDictionary] ? $SecuritySchemes.Keys : @())
if ($Spec.Contains('security')) {
    Test-UnwireSecurity -Security $Spec['security'] -Location 'security' -SchemeNames $SchemeNames
}

# ---------------------------------------------------------------------------
# Operations
#   Path parameters, operationId, responses, x-unwire-* and security.
# ---------------------------------------------------------------------------

$OperationIds   = @{}     # operationId => location of its first use
$InheritedAuth  = 0       # derived operations without their own security, reported below the loop

foreach ($pathKey in $Paths.Keys) {
    $pathItem = $Paths[$pathKey]

    if (-NOT $pathKey.StartsWith('/')) {
        Add-UnwireFinding -Severity Error -Location "paths['$pathKey']" -Rule 'path' -Message "Path must start with '/', got '$pathKey'."
    }
    if ($pathItem -isnot [System.Collections.IDictionary]) {
        Add-UnwireFinding -Severity Error -Location "paths['$pathKey']" -Rule 'path' -Message 'Path item must be an object.'
        continue
    }

    $pathParamNames = @([System.Text.RegularExpressions.Regex]::Matches($pathKey, $PATH_PARAM_REGEX) | ForEach-Object { $_.Groups['name'].Value })

    foreach ($method in $HTTP_METHODS | Where-Object { $pathItem.Contains($_) }) {
        $operation = $pathItem[$method]
        $location  = "paths['$pathKey'].$method"

        if ($operation -isnot [System.Collections.IDictionary]) {
            Add-UnwireFinding -Severity Error -Location $location -Rule 'operation' -Message 'Operation must be an object.'
            continue
        }

        # Path parameters: declared on the path item or the operation, $refs resolved
        $declaredParams = @(
            @($pathItem['parameters']) + @($operation['parameters'])
            | Where-Object { $null -NE $_ }
            | ForEach-Object {
                if ($_ -is [System.Collections.IDictionary] -AND $_['$ref'] -is [System.String] -AND $_['$ref'].StartsWith('#/')) {
                    Resolve-UnwireJsonPointer -Document $Spec -Pointer $_['$ref']
                }
                else {
                    $_
                }
            }
            | Where-Object { $_ -is [System.Collections.IDictionary] -AND $_['in'] -EQ 'path' }
        )
        foreach ($paramName in $pathParamNames) {
            $declared = $declaredParams | Where-Object { $_['name'] -EQ $paramName } | Select-Object -First 1
            if ($null -EQ $declared) {
                Add-UnwireFinding -Severity Error -Location $location -Rule 'path-parameter' -Message "Path parameter '$paramName' must be declared with in: path."
            }
            elseif ($declared['required'] -NE $true) {
                Add-UnwireFinding -Severity Error -Location $location -Rule 'path-parameter' -Message "Path parameter '$paramName' must have required: true."
            }
        }

        # operationId: names the operation on the page
        $operationId = $operation['operationId']
        if ([System.String]::IsNullOrWhiteSpace($operationId)) {
            Add-UnwireFinding -Severity Error -Location $location -Rule 'operation-id' -Message 'operationId must be set, the operation is named after it.'
        }
        elseif ($OperationIds.ContainsKey($operationId)) {
            Add-UnwireFinding -Severity Error -Location $location -Rule 'operation-id' -Message "operationId '$operationId' must be unique, already used at $($OperationIds[$operationId])."
        }
        else {
            $OperationIds[$operationId] = $location
        }

        # responses: required by OpenAPI
        if ($operation['responses'] -isnot [System.Collections.IDictionary] -OR $operation['responses'].Count -EQ 0) {
            Add-UnwireFinding -Severity Error -Location $location -Rule 'responses' -Message 'responses must contain at least one response, use "default" when the schema is unknown.'
        }

        # x-unwire-source
        $source = $operation['x-unwire-source']
        if ([System.String]::IsNullOrWhiteSpace($source)) {
            Add-UnwireFinding -Severity $ExtensionSeverity -Location $location -Rule 'x-unwire-source' -Message "x-unwire-source must name where the operation was found, e.g. 'assets/app.js:1842'."
        }

        # x-unwire-confidence
        $confidence = $operation['x-unwire-confidence']
        if ($null -EQ $confidence) {
            Add-UnwireFinding -Severity $ExtensionSeverity -Location $location -Rule 'x-unwire-confidence' -Message "x-unwire-confidence must be one of: $($CONFIDENCE_VALUES -join ', ')."
        }
        elseif ($confidence -NOTIN $CONFIDENCE_VALUES) {
            Add-UnwireFinding -Severity Error -Location $location -Rule 'x-unwire-confidence' -Message "x-unwire-confidence must be one of: $($CONFIDENCE_VALUES -join ', '), got '$confidence'."
        }

        # x-unwire-verified
        $verified = $operation['x-unwire-verified']
        if ($null -EQ $verified) {
            Add-UnwireFinding -Severity $ExtensionSeverity -Location $location -Rule 'x-unwire-verified' -Message 'x-unwire-verified must be true or false.'
        }
        elseif ($verified -isnot [System.Boolean]) {
            Add-UnwireFinding -Severity Error -Location $location -Rule 'x-unwire-verified' -Message "x-unwire-verified must be a boolean, got '$verified'."
        }

        # x-unwire-open: optional, but a low confidence should say why
        $open = $operation['x-unwire-open']
        if ($null -NE $open -AND ($open -isnot [System.Collections.IList] -OR @($open | Where-Object { $_ -isnot [System.String] }).Count -GT 0)) {
            Add-UnwireFinding -Severity Error -Location $location -Rule 'x-unwire-open' -Message 'x-unwire-open must be a list of strings.'
        }
        if ($confidence -EQ 'low' -AND @($open).Where({ $null -NE $_ }).Count -EQ 0) {
            Add-UnwireFinding -Severity Warning -Location $location -Rule 'x-unwire-open' -Message 'x-unwire-confidence is low, x-unwire-open should say what is unclear.'
        }

        # x-unwire-impact: write methods must be marked, so the page flags them
        $impact = $operation['x-unwire-impact']
        if ($null -NE $impact -AND $impact -NOTIN $IMPACT_VALUES) {
            Add-UnwireFinding -Severity Error -Location $location -Rule 'x-unwire-impact' -Message "x-unwire-impact must be one of: $($IMPACT_VALUES -join ', '), got '$impact'."
        }
        elseif ($method -IN $WRITE_METHODS -AND $impact -NE 'write') {
            Add-UnwireFinding -Severity Error -Location $location -Rule 'x-unwire-impact' -Message "A $($method.ToUpper()) operation must have x-unwire-impact: write."
        }

        # security: checked when set; a derived operation without it only takes the default
        if ($operation.Contains('security')) {
            Test-UnwireSecurity -Security $operation['security'] -Location $location -SchemeNames $SchemeNames
        }
        elseif (-NOT ([System.String] $source).StartsWith('discover:')) {
            $InheritedAuth++
        }
    }
}

# One finding, not one per operation: with schemes defined, every derived operation should
# say whether it needs auth ([] for public ones like a login), the page shows the default otherwise.
if ($SchemeNames.Count -GT 0 -AND $InheritedAuth -GT 0) {
    Add-UnwireFinding -Severity Warning -Location 'paths' -Rule 'security' -Message "$InheritedAuth derived operations set no security of their own: set [] on public ones (login, register) and the scheme on the others."
}

# ---------------------------------------------------------------------------
# References
#   Every local $ref points to an existing target.
# ---------------------------------------------------------------------------

foreach ($reference in Get-UnwireJsonRef -Node $Spec -Location '#') {
    if (-NOT $reference.Ref.StartsWith('#/')) {
        Add-UnwireFinding -Severity Warning -Location $reference.Location -Rule 'ref' -Message "External `$ref '$($reference.Ref)' is not checked."
        continue
    }
    if ($null -EQ (Resolve-UnwireJsonPointer -Document $Spec -Pointer $reference.Ref)) {
        Add-UnwireFinding -Severity Error -Location $reference.Location -Rule 'ref' -Message "`$ref '$($reference.Ref)' must point to an existing target."
    }
}

# ===========================================================================
# ===========================   REPORT FINDINGS   ===========================
# ===========================================================================
#
#   1. Report   Returns the findings, errors first.
#

# ---------------------------------------------------------------------------
# Report
#   Returns the findings, errors first.
# ---------------------------------------------------------------------------

Write-Verbose "[Test-UnwireSpec] $($OperationIds.Count) operations checked, $($Findings.Count) findings."
return $Findings | Sort-Object -Property @{ Expression = { $_.Severity -EQ 'Warning' } }, Location -Stable
