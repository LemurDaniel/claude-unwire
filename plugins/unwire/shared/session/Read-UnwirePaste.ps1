function Read-UnwirePaste {
    <#
    .SYNOPSIS
        Reads one masked paste, also a multi-line "Copy as cURL".

    .DESCRIPTION
        A multi-line paste ends its lines with '\' (bash), '^' (cmd) or '`' (PowerShell). Every
        line is read here: a line left unread would run as a command in the user's shell.
        Returns the lines joined with spaces, the continuation characters removed.

    .EXAMPLE
        PS> $text = Read-UnwirePaste -Prompt 'Session ("Copy as cURL")'
    #>
    param (
        <#
        [Required]
        The prompt of the first line, the next lines show '...'.
        #>
        [System.String]
        $Prompt
    )

    # Line continuations of a pasted cURL command: bash '\', cmd '^', PowerShell '`'
    $pasteContinuation = '\s[\\^`]\s*$'
    $maxPasteLines     = 200

    $pastedLines = [System.Collections.Generic.List[System.String]]::new()
    do {
        $linePrompt = if ($pastedLines.Count -EQ 0) { $Prompt } else { '...' }
        $secureLine = Read-Host -Prompt $linePrompt -AsSecureString
        $pastedLine = [System.Net.NetworkCredential]::new('', $secureLine).Password
        $pastedLines.Add(($pastedLine -REPLACE $pasteContinuation, ''))
    } while ($pastedLine -MATCH $pasteContinuation -AND $pastedLines.Count -LT $maxPasteLines)

    return $pastedLines -join ' '
}
