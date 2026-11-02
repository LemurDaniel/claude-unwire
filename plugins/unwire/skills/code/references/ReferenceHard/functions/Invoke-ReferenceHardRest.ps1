# NOTE:
#   The one place of the module that sends a request, every function calls it.
#
#   Invoke-ReferenceHardRest -Method GET -Path '/api/v1/accounts' -Security tokenAuth

#
#   Chapters:
#     BUILD REQUEST   Validations, session values, url, query and body.
#     SEND REQUEST    Asks before a write, sends and parses the answer.
#

function Invoke-ReferenceHardRest {
    <#
    .SYNOPSIS
    Sends one request to the device, with the session of Connect-ReferenceHard.

    .DESCRIPTION
    Builds the url from the base URL, the server path of the spec, the path with its parameters
    and the query, and adds the session values the operation needs. Every function of the module
    sends through this one, it is the only place that calls Invoke-WebRequest.
    Requests that may change something (every method but GET and HEAD) support -WhatIf and -Confirm.
    Redirects are not followed: a 3xx usually means the session expired.
    Logs name the method and the path template only, never the url, a header or a session value.

    .OUTPUTS
    The parsed JSON, the text of any other answer, nothing for an empty one,
    or with -Raw the WebResponseObject of any status.

    .EXAMPLE

    Call an operation the module has no function for:

    PS> Invoke-ReferenceHardRest -Method GET -Path '/api/v1/accounts' -Security tokenAuth
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High'
    )]
    param (
        <#
        [Required]
        The HTTP method of the operation.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [Microsoft.PowerShell.Commands.WebRequestMethod]
        $Method,

        <#
        [Required]
        The path of the operation as the spec writes it, e.g. '/api/v1/accounts/{accountId}/lock'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $Path,

        <#
        [Optional]
        Values of the path parameters, e.g. @{ accountId = 'u-17' }. Escaped when inserted.
        #>
        [Parameter()]
        [System.Collections.Hashtable]
        $PathParameters = @{},

        <#
        [Optional]
        Query parameters, $null values are left out, an array repeats the parameter.
        #>
        [Parameter()]
        [System.Collections.Hashtable]
        $Query = @{},

        <#
        [Optional]
        The request body: an object sent as JSON, a string sent as it is.
        #>
        [Parameter()]
        [System.Object]
        $Body,

        <#
        [Optional]
        The media type of the body. Defaults to 'application/json'.
        #>
        [Parameter()]
        [System.String]
        $ContentType = 'application/json',

        <#
        [Optional]
        The security schemes of the operation, e.g. 'tokenAuth'. Empty for an operation without session.
        #>
        [Parameter()]
        [System.String[]]
        $Security = @(),

        <#
        [Optional]
        Returns the WebResponseObject of any status instead of the parsed answer.
        #>
        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Raw
    )

    # ===========================================================================
    # ============================   BUILD REQUEST   ============================
    # ===========================================================================
    #
    #   1. Validations   Fails early without a session or with a path parameter left open.
    #   2. Session       Adds the value of every security scheme of the operation.
    #   3. Request       Builds the url, the query and the body.
    #

    # ---------------------------------------------------------------------------
    # Validations
    #   Fails early without a session or with a path parameter left open.
    # ---------------------------------------------------------------------------

    $Session = $script:ReferenceHardSession
    if ($null -EQ $Session) {
        throw [System.InvalidOperationException]::new('Connect-ReferenceHard must run first, it sets the base URL and the session.')
    }
    foreach ($name in $Security) {
        if (-NOT $script:SECURITY_SCHEMES.ContainsKey($name)) {
            throw [System.ArgumentException]::new("Security must name a scheme of the spec ($($script:SECURITY_SCHEMES.Keys -join ', ')), got '$name'.")
        }
        if (-NOT $Session.Secrets.ContainsKey($name)) {
            throw [System.InvalidOperationException]::new("This operation needs the session value '$name': run Connect-ReferenceHard with it.")
        }
    }

    # '/api/v1/accounts/{accountId}/lock', @{ accountId = 'u 17' } => '/api/v1/accounts/u%2017/lock'
    $RequestPath = $Path
    foreach ($parameter in $PathParameters.GetEnumerator()) {
        $RequestPath = $RequestPath.Replace("{$($parameter.Name)}", [System.Uri]::EscapeDataString([System.String] $parameter.Value))
    }
    if ($RequestPath -MATCH '\{[^{}]+\}') {
        throw [System.ArgumentException]::new("PathParameters must fill every parameter of '$Path', '$($Matches[0])' is missing.")
    }

    # ---------------------------------------------------------------------------
    # Session
    #   Adds the value of every security scheme of the operation.
    # ---------------------------------------------------------------------------

    $Headers    = @{}
    $QueryPairs = [System.Collections.Generic.List[System.String]]::new()
    $Cookies    = [System.Collections.Generic.List[System.String]]::new()
    # '/' + '/api/v1/accounts' => '/api/v1/accounts'
    $FullPath   = $script:SERVER_PATH.TrimEnd('/') + $RequestPath

    foreach ($name in $Security) {
        $scheme = $script:SECURITY_SCHEMES[$name]
        $secret = $Session.Secrets[$name]
        $value  = $secret -is [System.Management.Automation.PSCredential] ? $null : [System.Net.NetworkCredential]::new('', $secret).Password

        <#
            > x-unwire-in path   -> ';<name>=<value>' as a segment after x-unwire-path-prefix
            > apiKey header      -> header <name>
            > apiKey query       -> query parameter <name>
            > apiKey cookie      -> '<name>=<value>' in the Cookie header
            > http basic         -> Authorization 'Basic <base64 of user:password>'
            > anything else      -> Authorization 'Bearer <value>'
        #>
        if ($scheme['x-unwire-in'] -EQ 'path') {
            # '/ui/', '/ui/status' => '/ui/;tok=<value>/status'
            $prefix   = $scheme['x-unwire-path-prefix'] ?? '/'
            $FullPath = $prefix + ";$($scheme['name'])=$value/" + $FullPath.Substring([System.Math]::Min($prefix.Length, $FullPath.Length))
        }
        elseif ($scheme['type'] -EQ 'apiKey' -AND $scheme['in'] -EQ 'header') {
            $Headers[$scheme['name']] = $value
        }
        elseif ($scheme['type'] -EQ 'apiKey' -AND $scheme['in'] -EQ 'query') {
            $QueryPairs.Add("$([System.Uri]::EscapeDataString($scheme['name']))=$([System.Uri]::EscapeDataString($value))")
        }
        elseif ($scheme['type'] -EQ 'apiKey' -AND $scheme['in'] -EQ 'cookie') {
            $Cookies.Add("$($scheme['name'])=$value")
        }
        elseif ($scheme['type'] -EQ 'http' -AND $scheme['scheme'] -EQ 'basic') {
            $pair = "$($secret.UserName):$($secret.GetNetworkCredential().Password)"
            $Headers['Authorization'] = 'Basic ' + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
        }
        else {
            $Headers['Authorization'] = "Bearer $value"
        }
    }
    if ($Cookies.Count -GT 0) {
        $Headers['Cookie'] = $Cookies -join '; '
    }

    # ---------------------------------------------------------------------------
    # Request
    #   Builds the url, the query and the body.
    # ---------------------------------------------------------------------------

    # @{ protocol = 'smb'; all = $true; tag = 'a', 'b' } => 'protocol=smb&all=true&tag=a&tag=b'
    foreach ($parameter in $Query.GetEnumerator() | Where-Object { $null -NE $_.Value }) {
        foreach ($item in @($parameter.Value)) {
            $text = $item -is [System.Boolean] ? $item.ToString().ToLowerInvariant() : [System.String] $item
            $QueryPairs.Add("$([System.Uri]::EscapeDataString($parameter.Name))=$([System.Uri]::EscapeDataString($text))")
        }
    }
    $QueryString = $QueryPairs.Count -GT 0 ? '?' + ($QueryPairs -join '&') : ''

    $Request = @{
        Method               = $Method
        Uri                  = $Session.BaseUrl.TrimEnd('/') + $FullPath + $QueryString
        Headers              = $Headers
        MaximumRedirection   = 0
        SkipHttpErrorCheck   = $true
        SkipCertificateCheck = $Session.SkipCertificateCheck
    }
    if ($null -NE $Body) {
        $isJson              = $ContentType -LIKE '*json*' -AND $Body -isnot [System.String]
        $Request.Body        = $isJson ? ($Body | ConvertTo-Json -Depth 20 -Compress) : $Body
        $Request.ContentType = $ContentType
    }

    # Never log the url or the headers, they may carry a session value.
    Write-Verbose "[Invoke-ReferenceHardRest] $Method $Path"

    # ===========================================================================
    # ============================   SEND REQUEST   =============================
    # ===========================================================================
    #
    #   1. Send and process the response   Asks before a request that may change
    #                                       something, then parses the answer.
    #

    # ---------------------------------------------------------------------------
    # Send and process the response
    #   Asks before a request that may change something, then parses the answer.
    # ---------------------------------------------------------------------------

    $isReadOnly = $Method -IN @([Microsoft.PowerShell.Commands.WebRequestMethod]::Get, [Microsoft.PowerShell.Commands.WebRequestMethod]::Head)
    if (-NOT $isReadOnly -AND -NOT $PSCmdlet.ShouldProcess("$Method $Path", 'Send to the device')) {
        return
    }

    try {
        $Response = Invoke-WebRequest @Request
    }
    catch {
        # pwsh 7.4+ reports a 3xx under MaximumRedirection 0 as an error.
        if ($_.FullyQualifiedErrorId -LIKE 'MaximumRedirectExceeded*') {
            throw [System.InvalidOperationException]::new("$Method $Path was redirected, the session probably expired: run Connect-ReferenceHard again.", $_.Exception)
        }
        throw
    }

    if ($Raw.IsPresent) {
        return $Response
    }
    if ($Response.StatusCode -GE 300) {
        Write-Verbose "[Invoke-ReferenceHardRest] HTTP $($Response.StatusCode) -> throwing, -Raw returns the response instead."
        throw [System.Net.Http.HttpRequestException]::new("$Method $Path answered HTTP $($Response.StatusCode). -Raw returns the response without this check.")
    }
    if ([System.String]::IsNullOrEmpty($Response.Content)) {
        return
    }
    if (([System.String] $Response.Headers['Content-Type']) -LIKE '*json*') {
        return $Response.Content | ConvertFrom-Json -Depth 100
    }
    return $Response.Content
}
