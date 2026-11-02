function ConvertTo-UnwireCookieHeader {
    <#
    .SYNOPSIS
        Turns the other copy formats of a browser into a Cookie header.

    .DESCRIPTION
        > Header line ("cookie: a=b")   -> everything after 'cookie:'
        > DevTools table row            -> 'name<TAB>value<TAB>domain...' => 'name=value'
        > Anything else                 -> trimmed as it is, 'a=b; c=d' stays a list
        A cURL goes to ConvertFrom-UnwireCurlSession.

    .EXAMPLE
        PS> ConvertTo-UnwireCookieHeader -Text 'cookie: sid=abc'
        sid=abc
    #>
    param (
        <#
        [Required]
        The pasted cookie text.
        #>
        [System.String]
        $Text
    )

    $value = $Text.Trim()

    # Header line ("cookie: a=b")
    if ($value -MATCH '^(?i)cookie:\s*') {
        return ($value -REPLACE '^(?i)cookie:\s*', '').Trim()
    }

    # DevTools table row
    if ($value.Contains("`t")) {
        $fields = $value.Split("`t")
        return "$($fields[0].Trim())=$($fields[1].Trim())"
    }

    # Anything else
    return $value
}
