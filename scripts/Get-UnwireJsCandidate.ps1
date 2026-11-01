# NOTE:
#   Not implemented yet (v1 scaffold).
#
#   Pre-filters JavaScript files for endpoint candidates (fetch, axios, XMLHttpRequest,
#   jQuery ajax, URL strings like '/api/...') and writes one entry per hit with file, line,
#   kind and a snippet. Reads local files only.
#
#   ./scripts/Get-UnwireJsCandidate.ps1 -Path ./unwire/router/assets -OutputFile ./unwire/router/candidates.json

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Stub, the parameters are the planned interface.')]
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    <#
    [Required]
    Folder with the downloaded or saved assets of the web UI.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $Path,

    <#
    [Required]
    JSON file to write the candidates into.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $OutputFile
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

throw [System.NotImplementedException]::new('Get-UnwireJsCandidate is not implemented yet. Search the assets for fetch/axios/XMLHttpRequest calls directly instead.')
