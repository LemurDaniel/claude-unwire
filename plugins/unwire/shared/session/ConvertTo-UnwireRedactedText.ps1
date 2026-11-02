function ConvertTo-UnwireRedactedText {
    <#
    .SYNOPSIS
        Replaces every session value in a text with '<redacted>'.

    .DESCRIPTION
        Last line of defense before a text is written or shown: a session value never reaches
        the disk or a message, wherever the page, script or error put it.

    .EXAMPLE
        PS> ConvertTo-UnwireRedactedText -Text 'sid=abc123' -Secrets 'abc123'
        sid=<redacted>
    #>
    param (
        <#
        [Required]
        The text to write or show.
        #>
        [System.String]
        $Text,

        <#
        [Optional]
        The session values, e.g. the Secrets of Read-UnwireSession.
        #>
        [System.String[]]
        $Secrets
    )

    $redacted = $Text
    foreach ($secret in $Secrets) {
        $redacted = $redacted.Replace($secret, '<redacted>')
    }
    return $redacted
}
