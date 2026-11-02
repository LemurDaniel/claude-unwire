function Get-UnwireCookieShape {
    <#
    .SYNOPSIS
        Describes pasted text without showing its content.

    .DESCRIPTION
        Only the shape: length and structure, never a single character of the value. Error
        messages about a bad paste use it, so the user sees what went wrong and the session
        stays out of the chat.

    .EXAMPLE
        PS> Get-UnwireCookieShape -Text 'abc123'
        6 characters, no '='
    #>
    param (
        <#
        [Required]
        The pasted text.
        #>
        [System.String]
        $Text
    )

    $traits = @(
        "$($Text.Length) characters"
        if ($Text.Contains('=')) { "contains '='" } else { "no '='" }
        if ($Text.Contains(';')) { "contains ';'" }
        if ($Text.Contains("`t")) { 'contains tabs' }
        if ($Text -MATCH '\s') { 'contains spaces' }
        if ($Text.TrimStart() -MATCH '^curl\s') { "starts with 'curl'" }
        if ($Text.TrimStart() -MATCH '^[''"{\[]') { 'starts with a quote or bracket' }
    )
    return $traits -join ', '
}
