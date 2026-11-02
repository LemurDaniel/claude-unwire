function ConvertTo-UnwireSessionValue {
    <#
    .SYNOPSIS
        Reads the value of the session URL parameter from pasted text.

    .DESCRIPTION
        > Text with 'name=value'   -> the value of the first one: the URL query or the --data
                                      body of a cURL (bash and cmd quoting), a cookie list
        > Anything else            -> trimmed as it is, the bare value

    .EXAMPLE
        PS> ConvertTo-UnwireSessionValue -Text "curl 'http://router.test/?sid=abc&lang=de'" -Name sid
        abc
    #>
    param (
        <#
        [Required]
        The pasted text: a cURL, 'name=value' or the bare value.
        #>
        [System.String]
        $Text,

        <#
        [Required]
        Name of the session URL parameter, e.g. 'sid'.
        #>
        [System.String]
        $Name
    )

    $value = $Text.Trim()
    # cmd format escapes with '^': ^"sid=abc^" => "sid=abc"
    if ($value.Contains('^"')) {
        $value = $value -REPLACE '\^(.)', '$1'
    }

    # Text with 'name=value': '...?sid=abc&lang=de', "--data-raw 'sid=abc&page='" => 'abc'
    $parameter = [System.Text.RegularExpressions.Regex]::Match($value, "(?<![\w-])$([System.Text.RegularExpressions.Regex]::Escape($Name))=(?<value>[^&;\s'`"]+)")
    if ($parameter.Success) {
        return $parameter.Groups['value'].Value
    }

    # Anything else
    return $value
}
