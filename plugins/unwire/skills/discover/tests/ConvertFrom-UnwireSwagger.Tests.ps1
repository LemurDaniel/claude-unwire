# NOTE:
#   Requires: Pester 5+.
#
#   Invoke-Pester -Path ./tests

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Pester shares BeforeAll variables with the It blocks.')]
param ()

# ===========================================================================
# =====================   CONVERT SWAGGER TO OPENAPI   ======================
# ===========================================================================
#
#   root_and_servers      Builds openapi 3.0.3, servers from host, basePath and schemes.
#   relative_server       Keeps a relative server URL when the host is missing.
#   refs_rewritten        Points every $ref to the OpenAPI 3 components.
#   query_parameter       Moves type, format and enum of a parameter into its schema.
#   body_parameter        Turns a body parameter into a required requestBody.
#   form_data_file        Turns formData with a file into a multipart requestBody.
#   response_content      Puts a response schema into content per produced media type.
#   security_schemes      Converts basic to http basic and keeps apiKey.
#   unwire_extensions     Adds x-unwire-* marked as taken from the device.
#   passes_spec_check     Produces a spec Test-UnwireSpec accepts.
#   not_swagger           Fails early on a spec that is not Swagger 2.0.
#

BeforeAll {
    $SCRIPT_PATH = Join-Path -Path $PSScriptRoot -ChildPath '../scripts/ConvertFrom-UnwireSwagger.ps1'
    $CHECK_PATH  = Join-Path -Path $PSScriptRoot -ChildPath '../../../shared/Test-UnwireSpec.ps1'

    # A small Swagger 2.0 spec in the shape of Gitea's swagger.v1.json.
    $SWAGGER = [ordered]@{
        swagger             = '2.0'
        info                = @{ title = 'Gitea API'; version = '1.24' }
        basePath            = '/gitea/api/v1'
        schemes             = @('https', 'http')
        consumes            = @('application/json')
        produces            = @('application/json')
        securityDefinitions = [ordered]@{
            BasicAuth   = @{ type = 'basic' }
            AccessToken = @{ type = 'apiKey'; name = 'access_token'; in = 'query' }
        }
        responses           = [ordered]@{
            Repository = @{ description = 'Repository'; schema = @{ '$ref' = '#/definitions/Repository' } }
        }
        definitions         = [ordered]@{
            Repository = @{ type = 'object'; properties = @{ name = @{ type = 'string' } } }
        }
        paths               = [ordered]@{
            '/repos/search'          = @{
                get = [ordered]@{
                    tags        = @('repository')
                    operationId = 'repoSearch'
                    parameters  = @(@{ name = 'sort'; in = 'query'; type = 'string'; enum = @('alpha', 'created') })
                    responses   = @{ '200' = @{ '$ref' = '#/responses/Repository' } }
                }
            }
            '/user/repos'            = @{
                post = [ordered]@{
                    operationId = 'createCurrentUserRepo'
                    parameters  = @(@{ name = 'body'; in = 'body'; required = $true; schema = @{ '$ref' = '#/definitions/Repository' } })
                    responses   = @{ '201' = @{ description = 'Created'; schema = @{ '$ref' = '#/definitions/Repository' } } }
                }
            }
            '/repos/{owner}/avatar'  = @{
                post = [ordered]@{
                    operationId = 'repoUpdateAvatar'
                    consumes    = @('multipart/form-data')
                    parameters  = @(
                        @{ name = 'owner'; in = 'path'; required = $true; type = 'string' }
                        @{ name = 'image'; in = 'formData'; required = $true; type = 'file' }
                    )
                    responses   = @{ '204' = @{ description = 'No content' } }
                }
            }
        }
    }

    function Invoke-TestConversion {
        param ([System.Collections.IDictionary] $Swagger = $SWAGGER)
        $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
        $null   = New-Item -ItemType Directory -Path $folder
        $source = Join-Path -Path $folder -ChildPath 'swagger.v1.json'
        $target = Join-Path -Path $folder -ChildPath 'openapi.json'
        $Swagger | ConvertTo-Json -Depth 50 | Set-Content -Path $source
        $null = & $SCRIPT_PATH -Path $source -OutputFile $target
        return [PSCustomObject]@{ File = $target; Spec = Get-Content -Path $target -Raw | ConvertFrom-Json -AsHashtable }
    }
}

Describe 'ConvertFrom-UnwireSwagger' {
    BeforeAll {
        $Result = Invoke-TestConversion
        $Spec   = $Result.Spec
    }

    It 'root_and_servers: builds openapi 3.0.3, servers from host, basePath and schemes' {
        $swagger = $SWAGGER | ConvertTo-Json -Depth 50 | ConvertFrom-Json -AsHashtable
        $swagger['host'] = 'nas.local'

        $converted = (Invoke-TestConversion -Swagger $swagger).Spec

        $converted['openapi']       | Should -Be '3.0.3'
        $converted['servers'].url   | Should -Be @('https://nas.local/gitea/api/v1', 'http://nas.local/gitea/api/v1')
    }

    It 'relative_server: keeps a relative server URL when the host is missing' {
        $Spec['servers'].url | Should -Be @('/gitea/api/v1')
    }

    It 'refs_rewritten: points every $ref to the OpenAPI 3 components' {
        $Spec['paths']['/repos/search']['get']['responses']['200']['$ref'] | Should -Be '#/components/responses/Repository'
        $Spec['components']['responses']['Repository']['content']['application/json']['schema']['$ref'] | Should -Be '#/components/schemas/Repository'
        $Spec['components']['schemas']['Repository']['properties']['name']['type'] | Should -Be 'string'
    }

    It 'query_parameter: moves type, format and enum of a parameter into its schema' {
        $parameter = $Spec['paths']['/repos/search']['get']['parameters'][0]

        $parameter.Contains('type')  | Should -BeFalse
        $parameter['schema']['type'] | Should -Be 'string'
        $parameter['schema']['enum'] | Should -Be @('alpha', 'created')
    }

    It 'body_parameter: turns a body parameter into a required requestBody' {
        $operation = $Spec['paths']['/user/repos']['post']

        $operation.Contains('parameters') | Should -BeFalse
        $operation['requestBody']['required'] | Should -BeTrue
        $operation['requestBody']['content']['application/json']['schema']['$ref'] | Should -Be '#/components/schemas/Repository'
    }

    It 'form_data_file: turns formData with a file into a multipart requestBody' {
        $operation = $Spec['paths']['/repos/{owner}/avatar']['post']
        $schema    = $operation['requestBody']['content']['multipart/form-data']['schema']

        $schema['properties']['image']['format'] | Should -Be 'binary'
        $schema['required']                      | Should -Be @('image')
        $operation['parameters'].name            | Should -Be @('owner')
    }

    It 'response_content: puts a response schema into content per produced media type' {
        $Spec['paths']['/user/repos']['post']['responses']['201']['content']['application/json']['schema']['$ref'] | Should -Be '#/components/schemas/Repository'
        $Spec['paths']['/repos/{owner}/avatar']['post']['responses']['204'].Contains('content') | Should -BeFalse
    }

    It 'security_schemes: converts basic to http basic and keeps apiKey' {
        $Spec['components']['securitySchemes']['BasicAuth']['type']   | Should -Be 'http'
        $Spec['components']['securitySchemes']['BasicAuth']['scheme'] | Should -Be 'basic'
        $Spec['components']['securitySchemes']['AccessToken']['in']   | Should -Be 'query'
    }

    It 'unwire_extensions: adds x-unwire-* marked as taken from the device' {
        $Spec['x-unwire-source'] | Should -Be 'discover:swagger.v1.json'
        $Spec['paths']['/repos/search']['get']['x-unwire-impact'] | Should -Be 'read'
        $Spec['paths']['/user/repos']['post']['x-unwire-impact']  | Should -Be 'write'
        $Spec['paths']['/user/repos']['post']['x-unwire-confidence'] | Should -Be 'high'
        $Spec['paths']['/user/repos']['post']['x-unwire-verified'] | Should -BeFalse
    }

    It 'passes_spec_check: produces a spec Test-UnwireSpec accepts' {
        $findings = @(& $CHECK_PATH -Path $Result.File)

        $findings.Count | Should -Be 0
    }

    It 'not_swagger: fails early on a spec that is not Swagger 2.0' {
        $file = Join-Path -Path $TestDrive -ChildPath 'openapi3.json'
        @{ openapi = '3.1.0'; info = @{ title = 'x'; version = '1' }; paths = @{} } | ConvertTo-Json | Set-Content -Path $file

        { & $SCRIPT_PATH -Path $file -OutputFile (Join-Path $TestDrive 'out.json') } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*must be a Swagger 2.0 spec*'
    }
}
