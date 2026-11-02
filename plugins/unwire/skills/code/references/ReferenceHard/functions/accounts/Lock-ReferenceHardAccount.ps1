function Lock-ReferenceHardAccount {
    <#
    .SYNOPSIS
    Locks an account.

    .DESCRIPTION
    Changes the device: asks before it sends, -WhatIf shows what it would send.

    .NOTES
    Operation:  POST /api/v1/accounts/{accountId}/lock (lockAccount)
    Confidence: medium, not verified
    Source:     assets/js/panels/accounts.js:37
    Open:       Path assembled from three parts, the {accountId} template is derived.

    .OUTPUTS
    Nothing, the device answers 204.

    .EXAMPLE

    Lock an account, with a reason:

    PS> Lock-ReferenceHardAccount -AccountId 'u-17' -Reason 'left the team'
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High'
    )]
    param (
        <#
        [Required]
        The id of the account, e.g. 'u-17'.
        #>
        [Parameter(
            Mandatory = $true,
            Position = 0
        )]
        [System.String]
        $AccountId,

        <#
        [Optional]
        Why the account is locked, the UI asks for it in a dialog.
        #>
        [Parameter()]
        [System.String]
        $Reason
    )

    Write-Warning '[Lock-ReferenceHardAccount] Confidence medium, not verified: the {accountId} template is derived from three parts of the code.'

    $Request = @{
        Method         = 'POST'
        Path           = '/api/v1/accounts/{accountId}/lock'
        PathParameters = @{ accountId = $AccountId }
        Body           = @{}
        Security       = @('tokenAuth')
    }
    # Only the given fields go into the body, a missing one is left out, not sent as null.
    if ($PSBoundParameters.ContainsKey('Reason')) {
        $Request.Body['reason'] = $Reason
    }

    if ($PSCmdlet.ShouldProcess("account '$AccountId'", 'POST /api/v1/accounts/{accountId}/lock')) {
        return Invoke-ReferenceHardRest @Request -Confirm:$false
    }
}
