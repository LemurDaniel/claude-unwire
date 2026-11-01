function ConvertTo-UnwireText {
    <#
    .SYNOPSIS
        Turns a response body of Invoke-WebRequest into text.

    .DESCRIPTION
        Invoke-WebRequest returns text content types as string and everything else
        (application/octet-stream, unknown types) as bytes. Bytes are decoded as UTF-8.

    .EXAMPLE
        PS> ConvertTo-UnwireText -Content (Invoke-WebRequest -Uri 'http://192.168.178.1/app.js').Content
    #>
    param (
        <#
        [Required]
        The Content property of an Invoke-WebRequest response.
        #>
        [System.Object]
        $Content
    )

    if ($Content -is [System.Byte[]]) {
        return [System.Text.Encoding]::UTF8.GetString($Content)
    }
    return [System.String] $Content
}
