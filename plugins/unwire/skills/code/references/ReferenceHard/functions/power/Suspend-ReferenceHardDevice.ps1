function Suspend-ReferenceHardDevice {
    <#
    .SYNOPSIS
    Sends the device to standby.

    .DESCRIPTION
    Changes the device: asks before it sends, -WhatIf shows what it would send.
    The device is out of reach until it wakes up.

    .NOTES
    Operation:  POST /api/v1/power/standby (enterStandby)
    Confidence: high, not verified
    Source:     assets/views/power.html.inline.js:3
    Open:       Found in an onclick attribute of views/power.html, kept in the inline code of the signed-in page.

    .EXAMPLE

    PS> Suspend-ReferenceHardDevice
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High'
    )]
    param ()

    $Request = @{
        Method   = 'POST'
        Path     = '/api/v1/power/standby'
        Security = @('tokenAuth')
    }

    if ($PSCmdlet.ShouldProcess('device', 'POST /api/v1/power/standby')) {
        return Invoke-ReferenceHardRest @Request -Confirm:$false
    }
}
