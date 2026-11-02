function Set-ReferenceHardSetting {
    <#
    .SYNOPSIS
    Saves a settings group.

    .DESCRIPTION
    Changes the device: asks before it sends, -WhatIf shows what it would send.
    The keys of a group are not in the code: read them in the UI first, the body goes out as given.

    .NOTES
    Operation:  PUT /api/v1/settings/{group} (saveSettings)
    Confidence: medium, not verified
    Source:     assets/js/http.js:52
    Open:       Body: the form object of the view is passed through as it is, its keys are not in the code.

    .EXAMPLE

    Save the time settings:

    PS> Set-ReferenceHardSetting -Group time -Settings @{ timezone = 'Europe/Berlin' }
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High'
    )]
    param (
        <#
        [Required]
        The settings group. The views send 'network' and 'time'.
        #>
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [ArgumentCompleter({
            # $args: command name, parameter name, the word to complete
            $wordToComplete = $args[2]
            @('network', 'time') | Where-Object { $_ -LIKE "$wordToComplete*" }
        })]
        [System.String]
        $Group,

        <#
        [Required]
        The settings of the group, sent as JSON.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.Collections.Hashtable]
        $Settings
    )

    Write-Warning '[Set-ReferenceHardSetting] Confidence medium, not verified: the body keys are not in the code.'

    $Request = @{
        Method         = 'PUT'
        Path           = '/api/v1/settings/{group}'
        PathParameters = @{ group = $Group }
        Body           = $Settings
        Security       = @('tokenAuth')
    }

    if ($PSCmdlet.ShouldProcess("settings '$Group'", 'PUT /api/v1/settings/{group}')) {
        return Invoke-ReferenceHardRest @Request -Confirm:$false
    }
}
