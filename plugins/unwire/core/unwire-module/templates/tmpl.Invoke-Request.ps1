function Invoke-__PREFIX__Request {
    <#
    .SYNOPSIS
        Sends one request to the API, the only place of the module that calls the network.

    .DESCRIPTION
        Builds the URI from the session of Connect-__PREFIX__, adds the session headers and
        sends the body as JSON. Every public function delegates to this one.

    .EXAMPLE
        Lists all devices:

        PS> Invoke-__PREFIX__Request -Method Get -Path 'api/devices'
    #>
    [CmdletBinding()]
    param (
        <#
        [Required]
        The HTTP method of the operation.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [ValidateSet('Get', 'Post', 'Put', 'Patch', 'Delete')]
        [System.String]
        $Method,

        <#
        [Required]
        The path of the operation relative to the base URI, path parameters already filled in.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $Path,

        <#
        [Optional]
        Query parameters. Default is none.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.Collections.Hashtable]
        $Query = @{},

        <#
        [Optional]
        The request body, sent as JSON. Default is no body.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.Object]
        $Body
    )

    if ($null -EQ $script:__PREFIX__Session) {
        throw [System.InvalidOperationException]::new('Connect-__PREFIX__ must run before any request.')
    }
    $session = $script:__PREFIX__Session

    # 'api/devices' + @{ page = 2 } => 'http://<HOST>/api/devices?page=2'
    $builder = [System.UriBuilder]::new([System.Uri]::new($session.BaseUri, $Path.TrimStart('/')))
    if ($Query.Count -GT 0) {
        $builder.Query = @(
            $Query.GetEnumerator()
            | ForEach-Object { '{0}={1}' -f [System.Uri]::EscapeDataString($_.Key), [System.Uri]::EscapeDataString([System.String] $_.Value) }
        ) -join '&'
    }

    $RequestConfig = @{
        Method               = $Method
        Uri                  = $builder.Uri
        Headers              = $session.Headers
        WebSession           = $session.WebSession
        SkipCertificateCheck = $session.SkipCertificateCheck
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $RequestConfig.Body        = $Body | ConvertTo-Json -Depth 20
        $RequestConfig.ContentType = 'application/json'
    }

    Write-Verbose "[Invoke-__PREFIX__Request] $($Method.ToUpper()) $($builder.Uri)"
    return Invoke-RestMethod @RequestConfig
}
