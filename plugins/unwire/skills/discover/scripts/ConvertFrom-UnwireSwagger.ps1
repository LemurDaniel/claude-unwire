# NOTE:
#   Converts a Swagger 2.0 spec (found by unwire:discover) into OpenAPI 3.0 for the rest of
#   the chain: servers, components, request bodies, response content, security schemes.
#   Adds the x-unwire-* extensions every operation needs, marked as taken from the device.
#
#   ./plugins/unwire/skills/discover/scripts/ConvertFrom-UnwireSwagger.ps1 -Path ./unwire/wiki/discover/swagger.v1.json -OutputFile ./unwire/gitea/openapi.json

#
#   Chapters:
#     HELPERS         $ref rewriting, schemas of parameters, responses and operations.
#     LOAD SWAGGER    Validates the file and checks the version.
#     BUILD OPENAPI   Root, components and paths of the OpenAPI document.
#     WRITE SPEC      Writes openapi.json and returns a summary.
#

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    <#
    [Required]
    Path to the Swagger 2.0 JSON file.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $Path,

    <#
    [Required]
    The openapi.json to write.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $OutputFile,

    <#
    [Optional]
    Value of x-unwire-source on the root and on every operation. Default is
    'discover:<file name>'.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String]
    $SourceLabel
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

$HTTP_METHODS     = @('get', 'put', 'post', 'delete', 'options', 'head', 'patch')
$WRITE_METHODS    = @('put', 'post', 'delete', 'patch')
$DEFAULT_MEDIA    = 'application/json'
# Keywords that move from a Swagger 2.0 parameter or header into its OpenAPI 3 schema
$SCHEMA_KEYWORDS  = @('type', 'format', 'items', 'enum', 'default', 'minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum', 'minLength', 'maxLength', 'pattern', 'minItems', 'maxItems', 'uniqueItems', 'multipleOf')
# '#/definitions/User' => '#/components/schemas/User'
$REF_PREFIXES     = [ordered]@{
    '#/definitions/' = '#/components/schemas/'
    '#/parameters/'  = '#/components/parameters/'
    '#/responses/'   = '#/components/responses/'
}

# ===========================================================================
# ===============================   HELPERS   ===============================
# ===========================================================================
#
#   Convert-UnwireRef               Rewrites every $ref to the OpenAPI 3 components.
#   ConvertTo-UnwireSchemaHolder    Moves schema keywords of a parameter or header into 'schema'.
#   ConvertTo-UnwireResponse        Response with 'content' per produced media type.
#   ConvertTo-UnwireOperation       Operation with requestBody, converted parameters, responses.
#

function Convert-UnwireRef {
    param (
        [System.Object] $Node
    )

    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in @($Node.Keys)) {
            if ($key -EQ '$ref' -AND $Node[$key] -is [System.String]) {
                foreach ($prefix in $REF_PREFIXES.Keys) {
                    if ($Node[$key].StartsWith($prefix)) {
                        $Node[$key] = $REF_PREFIXES[$prefix] + $Node[$key].Substring($prefix.Length)
                    }
                }
                continue
            }
            Convert-UnwireRef -Node $Node[$key]
        }
        return
    }
    if ($Node -is [System.Collections.IList]) {
        foreach ($child in $Node) {
            Convert-UnwireRef -Node $child
        }
    }
}

function ConvertTo-UnwireSchemaHolder {
    param (
        [System.Collections.IDictionary] $Source
    )

    # { name: 'page', in: 'query', type: 'integer' } => { name: 'page', in: 'query', schema: { type: 'integer' } }
    $result = [ordered]@{}
    $schema = [ordered]@{}
    foreach ($key in $Source.Keys) {
        if ($key -IN $SCHEMA_KEYWORDS) {
            $schema[$key] = $Source[$key]
        }
        elseif ($key -NE 'collectionFormat') {
            $result[$key] = $Source[$key]
        }
    }
    # 'file' does not exist in OpenAPI 3, it is a binary string.
    if ($schema['type'] -EQ 'file') {
        $schema['type']   = 'string'
        $schema['format'] = 'binary'
    }
    if ($schema.Count -GT 0) {
        $result['schema'] = $schema
    }
    return $result
}

function ConvertTo-UnwireResponse {
    param (
        [System.Collections.IDictionary] $Response,
        [System.String[]]                $Produces
    )

    if ($Response.Contains('$ref')) {
        return $Response
    }

    $result = [ordered]@{ description = if ($Response.Contains('description')) { $Response['description'] } else { '' } }
    if ($Response.Contains('headers')) {
        $headers = [ordered]@{}
        foreach ($headerName in $Response['headers'].Keys) {
            $headers[$headerName] = ConvertTo-UnwireSchemaHolder -Source $Response['headers'][$headerName]
        }
        $result['headers'] = $headers
    }
    if ($Response.Contains('schema')) {
        $content = [ordered]@{}
        foreach ($mediaType in $Produces) {
            $content[$mediaType] = [ordered]@{ schema = $Response['schema'] }
        }
        $result['content'] = $content
    }
    return $result
}

function ConvertTo-UnwireOperation {
    param (
        [System.Collections.IDictionary] $Operation,
        [System.String]                  $Method,
        [System.String[]]                $Consumes,
        [System.String[]]                $Produces
    )

    <#
        > Parameter in body       -> requestBody, one content entry per consumed media type
        > Parameters in formData  -> one requestBody object schema, multipart when a file
                                     or multipart is consumed, else form-urlencoded
        > Any other parameter     -> parameter with its schema keywords in 'schema'
        > Responses               -> 'content' per produced media type
        > x-unwire-*              -> set where missing: taken from the device, not executed
    #>

    $operationConsumes = if ($Operation.Contains('consumes') -AND @($Operation['consumes']).Count -GT 0) { @($Operation['consumes']) } else { $Consumes }
    $operationProduces = if ($Operation.Contains('produces') -AND @($Operation['produces']).Count -GT 0) { @($Operation['produces']) } else { $Produces }

    $result     = [ordered]@{}
    $parameters = [System.Collections.Generic.List[System.Object]]::new()
    $formFields = [ordered]@{}
    $formNeeded = [System.Collections.Generic.List[System.String]]::new()
    $hasFile    = $false

    foreach ($key in $Operation.Keys) {
        switch ($key) {
            { $_ -IN @('consumes', 'produces', 'parameters', 'responses', 'schemes') } { continue }
            default { $result[$key] = $Operation[$key] }
        }
    }

    foreach ($parameter in @($Operation['parameters'])) {
        if ($null -EQ $parameter) {
            continue
        }

        # Parameter in body
        if ($parameter['in'] -EQ 'body') {
            $content = [ordered]@{}
            foreach ($mediaType in $operationConsumes) {
                $content[$mediaType] = [ordered]@{ schema = $parameter['schema'] }
            }
            $result['requestBody'] = [ordered]@{ content = $content }
            if ($parameter.Contains('description')) { $result['requestBody']['description'] = $parameter['description'] }
            if ($parameter['required'] -EQ $true) { $result['requestBody']['required'] = $true }
            continue
        }

        # Parameters in formData
        if ($parameter['in'] -EQ 'formData') {
            $field = (ConvertTo-UnwireSchemaHolder -Source $parameter)['schema']
            if ($null -EQ $field) { $field = [ordered]@{ type = 'string' } }
            if ($parameter.Contains('description')) { $field['description'] = $parameter['description'] }
            if ($field['format'] -EQ 'binary') { $hasFile = $true }
            $formFields[$parameter['name']] = $field
            if ($parameter['required'] -EQ $true) { $formNeeded.Add($parameter['name']) }
            continue
        }

        # Any other parameter
        $parameters.Add((ConvertTo-UnwireSchemaHolder -Source $parameter))
    }

    if ($formFields.Count -GT 0) {
        $formMedia  = if ($hasFile -OR $operationConsumes -CONTAINS 'multipart/form-data') { 'multipart/form-data' } else { 'application/x-www-form-urlencoded' }
        $formSchema = [ordered]@{ type = 'object'; properties = $formFields }
        if ($formNeeded.Count -GT 0) { $formSchema['required'] = $formNeeded.ToArray() }
        $result['requestBody'] = [ordered]@{ content = [ordered]@{ $formMedia = [ordered]@{ schema = $formSchema } } }
    }
    if ($parameters.Count -GT 0) {
        $result['parameters'] = $parameters.ToArray()
    }

    # Responses
    $responses       = [ordered]@{}
    $sourceResponses = if ($Operation['responses'] -is [System.Collections.IDictionary]) { $Operation['responses'] } else { @{} }
    foreach ($statusCode in @($sourceResponses.Keys)) {
        $responses[[System.String] $statusCode] = ConvertTo-UnwireResponse -Response $Operation['responses'][$statusCode] -Produces $operationProduces
    }
    if ($responses.Count -EQ 0) {
        $responses['default'] = [ordered]@{ description = 'Not documented by the device.' }
    }
    $result['responses'] = $responses

    # x-unwire-*
    if (-NOT $result.Contains('x-unwire-source'))     { $result['x-unwire-source'] = $SourceLabel }
    if (-NOT $result.Contains('x-unwire-confidence')) { $result['x-unwire-confidence'] = 'high' }
    if (-NOT $result.Contains('x-unwire-verified'))   { $result['x-unwire-verified'] = $false }
    if (-NOT $result.Contains('x-unwire-impact'))     { $result['x-unwire-impact'] = if ($Method -IN $WRITE_METHODS) { 'write' } else { 'read' } }
    return $result
}

# ===========================================================================
# ============================   LOAD SWAGGER   =============================
# ===========================================================================
#
#   1. Validations   Fails early on a missing file, invalid JSON or no Swagger 2.0.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early on a missing file, invalid JSON or no Swagger 2.0.
# ---------------------------------------------------------------------------

if (-NOT (Test-Path -Path $Path -PathType Leaf)) {
    throw [System.ArgumentException]::new("Path must be an existing Swagger 2.0 JSON file, got '$Path'.")
}
$SwaggerText = Get-Content -Path $Path -Raw
if (-NOT (Test-Json -Json $SwaggerText -ErrorAction SilentlyContinue)) {
    throw [System.ArgumentException]::new("Path '$Path' must contain valid JSON, a YAML spec has to be converted to JSON first.")
}
$Swagger = $SwaggerText | ConvertFrom-Json -AsHashtable -Depth 200
if ([System.String] $Swagger['swagger'] -NE '2.0') {
    throw [System.ArgumentException]::new("Path '$Path' must be a Swagger 2.0 spec (swagger: '2.0'), got '$($Swagger['swagger'])$($Swagger['openapi'])'.")
}

# Order of precedence: parameter > 'discover:<file name>'
if ([System.String]::IsNullOrEmpty($SourceLabel)) {
    $SourceLabel = "discover:$(Split-Path -Path $Path -Leaf)"
}

# ===========================================================================
# ============================   BUILD OPENAPI   ============================
# ===========================================================================
#
#   1. References   Rewrites every $ref to the components of OpenAPI 3.
#   2. Root         openapi, info, servers, tags, security and extensions.
#   3. Components   Schemas, parameters, responses and security schemes.
#   4. Paths        Every path item with its converted operations.
#

# ---------------------------------------------------------------------------
# References
#   Rewrites every $ref to the components of OpenAPI 3.
# ---------------------------------------------------------------------------

Convert-UnwireRef -Node $Swagger

# ---------------------------------------------------------------------------
# Root
#   openapi, info, servers, tags, security and extensions.
# ---------------------------------------------------------------------------

$Consumes = if (@($Swagger['consumes']).Count -GT 0 -AND $null -NE $Swagger['consumes']) { @($Swagger['consumes']) } else { @($DEFAULT_MEDIA) }
$Produces = if (@($Swagger['produces']).Count -GT 0 -AND $null -NE $Swagger['produces']) { @($Swagger['produces']) } else { @($DEFAULT_MEDIA) }

# host 'nas.local', basePath '/wiki/api/v1', schemes https, http => 'https://nas.local/wiki/api/v1', ...
# Without host the server URL stays relative to the page, as Swagger 2.0 defines it.
$BasePath = if ([System.String]::IsNullOrEmpty($Swagger['basePath'])) { '/' } else { $Swagger['basePath'] }
$Servers  = if ([System.String]::IsNullOrEmpty($Swagger['host'])) {
    @([ordered]@{ url = $BasePath })
}
else {
    @(@($Swagger['schemes']) | Where-Object { $null -NE $_ } | ForEach-Object { [ordered]@{ url = "$($_)://$($Swagger['host'])$BasePath" } })
}

$OpenApi = [ordered]@{
    openapi           = '3.0.3'
    info              = $Swagger['info']
    # @() again: the if above unrolls a single server into an object.
    servers           = @($Servers)
    'x-unwire-source' = $SourceLabel
}
foreach ($key in @('tags', 'security', 'externalDocs')) {
    if ($Swagger.Contains($key)) { $OpenApi[$key] = $Swagger[$key] }
}
foreach ($key in $Swagger.Keys | Where-Object { $_ -LIKE 'x-*' }) {
    $OpenApi[$key] = $Swagger[$key]
}

# ---------------------------------------------------------------------------
# Components
#   Schemas, parameters, responses and security schemes.
# ---------------------------------------------------------------------------

$Components = [ordered]@{}
if ($Swagger.Contains('definitions')) {
    $Components['schemas'] = $Swagger['definitions']
}
if ($Swagger.Contains('parameters')) {
    $Components['parameters'] = [ordered]@{}
    foreach ($name in $Swagger['parameters'].Keys) {
        $Components['parameters'][$name] = ConvertTo-UnwireSchemaHolder -Source $Swagger['parameters'][$name]
    }
}
if ($Swagger.Contains('responses')) {
    $Components['responses'] = [ordered]@{}
    foreach ($name in $Swagger['responses'].Keys) {
        $Components['responses'][$name] = ConvertTo-UnwireResponse -Response $Swagger['responses'][$name] -Produces $Produces
    }
}
if ($Swagger.Contains('securityDefinitions')) {
    $Components['securitySchemes'] = [ordered]@{}
    foreach ($name in $Swagger['securityDefinitions'].Keys) {
        $definition = $Swagger['securityDefinitions'][$name]
        # basic => http basic, apiKey stays, oauth2 keeps its flow under 'flows'
        $Components['securitySchemes'][$name] = switch ($definition['type']) {
            'basic' { [ordered]@{ type = 'http'; scheme = 'basic'; description = $definition['description'] } }
            'oauth2' {
                $flowName = @{ implicit = 'implicit'; password = 'password'; application = 'clientCredentials'; accessCode = 'authorizationCode' }[$definition['flow']]
                $flow     = [ordered]@{ scopes = if ($definition.Contains('scopes')) { $definition['scopes'] } else { @{} } }
                if ($definition.Contains('authorizationUrl')) { $flow['authorizationUrl'] = $definition['authorizationUrl'] }
                if ($definition.Contains('tokenUrl')) { $flow['tokenUrl'] = $definition['tokenUrl'] }
                [ordered]@{ type = 'oauth2'; flows = [ordered]@{ $flowName = $flow } }
            }
            default { $definition }
        }
    }
}
$OpenApi['components'] = $Components

# ---------------------------------------------------------------------------
# Paths
#   Every path item with its converted operations.
# ---------------------------------------------------------------------------

$Paths          = [ordered]@{}
$OperationCount = 0
foreach ($pathKey in $Swagger['paths'].Keys) {
    $pathItem  = $Swagger['paths'][$pathKey]
    $converted = [ordered]@{}
    foreach ($key in $pathItem.Keys) {
        if ($key -IN $HTTP_METHODS) {
            $converted[$key] = ConvertTo-UnwireOperation -Operation $pathItem[$key] -Method $key -Consumes $Consumes -Produces $Produces
            $OperationCount++
        }
        elseif ($key -EQ 'parameters') {
            $converted[$key] = @($pathItem[$key] | ForEach-Object { ConvertTo-UnwireSchemaHolder -Source $_ })
        }
        else {
            $converted[$key] = $pathItem[$key]
        }
    }
    $Paths[$pathKey] = $converted
}
$OpenApi['paths'] = $Paths
Write-Verbose "[ConvertFrom-UnwireSwagger] Converted $OperationCount operations on $($Paths.Count) paths."

# ===========================================================================
# =============================   WRITE SPEC   ==============================
# ===========================================================================
#
#   1. Write   Writes openapi.json and returns a summary.
#

# ---------------------------------------------------------------------------
# Write
#   Writes openapi.json and returns a summary.
# ---------------------------------------------------------------------------

if ($PSCmdlet.ShouldProcess($OutputFile, 'Write OpenAPI 3 spec')) {
    $outputDirectory = Split-Path -Path $OutputFile -Parent
    if (-NOT [System.String]::IsNullOrEmpty($outputDirectory)) {
        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
    }
    $OpenApi | ConvertTo-Json -Depth 100 | Set-Content -Path $OutputFile -Encoding utf8NoBOM
}

return [PSCustomObject]@{
    OutputFile = $OutputFile
    Paths      = $Paths.Count
    Operations = $OperationCount
    Schemas    = if ($Components.Contains('schemas')) { $Components['schemas'].Count } else { 0 }
}
