# NOTE:
#   Not implemented yet (v1 scaffold).
#
#   Validates an Unwire openapi.json: valid JSON, OpenAPI 3.x root fields, and on every
#   operation the x-unwire-source, x-unwire-confidence and x-unwire-verified extensions.
#   Returns one finding per problem, nothing when the spec is valid.
#
#   ./scripts/Test-UnwireSpec.ps1 -Path ./unwire/router/openapi.json

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Stub, the parameters are the planned interface.')]
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

throw [System.NotImplementedException]::new('Test-UnwireSpec is not implemented yet.')
