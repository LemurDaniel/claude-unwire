function Get-UnwireRequestUri {
    <#
    .SYNOPSIS
        Adds the session token and parameter to a URI, for the wire only.

    .DESCRIPTION
        > PathToken with PathPrefix   -> inserted after the prefix, only below it:
                                         '/ui/admin' => '/ui/;stok=abc/admin', '/static/a.js' stays
        > PathToken without prefix    -> appended to the path: '/a.js' => '/a.js;jsessionid=abc'
        > Query                       -> appended to the query: '?v=2' => '?v=2&sid=abc'
        The result never goes into a record, a Referer or a log line.

    .EXAMPLE
        PS> Get-UnwireRequestUri -Uri 'http://router.test/a.js?v=2' -Query 'sid=abc'
        http://router.test/a.js?v=2&sid=abc
    #>
    param (
        <#
        [Required]
        The URI without session.
        #>
        [System.Uri]
        $Uri,

        <#
        [Optional]
        'name=value' of the session URL parameter.
        #>
        [System.String]
        $Query,

        <#
        [Optional]
        'name=value' of the session token in the path.
        #>
        [System.String]
        $PathToken,

        <#
        [Optional]
        The path the token is a segment below, e.g. '/ui/'.
        #>
        [System.String]
        $PathPrefix
    )

    $builder = [System.UriBuilder]::new($Uri)
    if (-NOT [System.String]::IsNullOrEmpty($PathToken) -AND -NOT [System.String]::IsNullOrEmpty($PathPrefix)) {
        if ($builder.Path.StartsWith($PathPrefix, [System.StringComparison]::Ordinal)) {
            $builder.Path = "$PathPrefix;$PathToken/$($builder.Path.Substring($PathPrefix.Length))"
        }
    }
    elseif (-NOT [System.String]::IsNullOrEmpty($PathToken)) {
        $builder.Path = "$($builder.Path);$PathToken"
    }
    if (-NOT [System.String]::IsNullOrEmpty($Query)) {
        $builder.Query = if ($builder.Query.Length -GT 1) { "$($builder.Query.Substring(1))&$Query" } else { $Query }
    }
    return $builder.Uri
}
