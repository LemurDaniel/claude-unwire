function Get-ReferenceHardAccount {
    <#
    .SYNOPSIS
    Lists the accounts.

    .DESCRIPTION
    Returns every account with its login and whether it is an admin.

    .NOTES
    Operation:  GET /api/v1/accounts (listAccounts)
    Confidence: high, verified by the live GET
    Source:     assets/js/panels/accounts.js:11
    Open:       Live GET 2026-11-02: without session HTTP 401 application/json, with session HTTP 200 application/json.

    .OUTPUTS
    The accounts, each with login and isAdmin.

    .EXAMPLE

    List the admins:

    PS> Get-ReferenceHardAccount | Where-Object -Property isAdmin -EQ -Value $true
    #>

    [CmdletBinding()]
    param ()

    $Request = @{
        Method   = 'GET'
        Path     = '/api/v1/accounts'
        Security = @('tokenAuth')
    }

    return (Invoke-ReferenceHardRest @Request).accounts
}
