# NOTE:
#   Not implemented yet (v1 scaffold).
#
#   Downloads the static assets of a web UI for unwire-analyze: the HTML page, every
#   same-origin <script src> and the matching .js.map source maps. GET requests to static
#   files only, never to API endpoints.
#
#   ./scripts/Save-UnwireAsset.ps1 -Uri 'http://192.168.178.1' -OutputDirectory ./unwire/router/assets

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Stub, the parameters are the planned interface.')]
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

throw [System.NotImplementedException]::new('Save-UnwireAsset is not implemented yet. Save the page in the browser and pass the folder to unwire-analyze instead.')
