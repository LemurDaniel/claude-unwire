function Disconnect-ReferenceHard {
    <#
    .SYNOPSIS
    Drops the base URL and the session of Connect-ReferenceHard.

    .DESCRIPTION
    Sends nothing to the device: a session on the device side stays valid until it expires there.

    .EXAMPLE

    PS> Disconnect-ReferenceHard
    #>

    [CmdletBinding()]
    param ()

    $script:ReferenceHardSession = $null
    Write-Verbose '[Disconnect-ReferenceHard] Session dropped.'
}
