function Connect-ReferenceHard {
    <#
    .SYNOPSIS
    Sets the base URL and the session every function of the module sends with.

    .DESCRIPTION
    The session lives in memory only: it is gone with Disconnect-ReferenceHard, Remove-Module or
    the end of the shell, never written to a file, a log or the history.
    A session value not given as a parameter is asked at a masked prompt.
    Copy it from a signed-in browser tab (developer tools, Network, any request to /api/).

    .EXAMPLE

    Connect, the token is asked at a masked prompt:

    PS> Connect-ReferenceHard -BaseUrl 'https://nas.example.test:5443/'

    .EXAMPLE

    Connect to a device with a self-signed certificate, only for the operations without session:

    PS> Connect-ReferenceHard -BaseUrl 'https://nas.example.test:5443/' -SkipCertificateCheck -NoSession
    #>

    [CmdletBinding()]
    param (
        <#
        [Optional]
        The base URL of the web UI. Defaults to the URL Unwire ran against.
        #>
        [Parameter(
            Position = 0
        )]
        [System.Uri]
        $BaseUrl = 'https://nas.example.test:5443/',

        <#
        [Optional]
        tokenAuth: the value of the X-Auth-Token header the UI sends after its sign-in.
        Asked at a masked prompt when missing.
        #>
        [Parameter()]
        [System.Security.SecureString]
        $TokenAuth,

        <#
        [Optional]
        Connects without a session, only the operations without one work.
        #>
        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $NoSession,

        <#
        [Optional]
        Accepts a certificate this machine does not trust, e.g. a self-signed one of the device.
        #>
        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $SkipCertificateCheck
    )

    if (-NOT $BaseUrl.IsAbsoluteUri -OR $BaseUrl.Scheme -NOTIN @('http', 'https')) {
        throw [System.ArgumentException]::new("BaseUrl must be an absolute http(s) URL, e.g. 'https://nas.example.test:5443/', got '$BaseUrl'.")
    }

    # One entry per security scheme of the spec, SecureString or PSCredential (http basic).
    $Secrets = @{}
    if (-NOT $NoSession.IsPresent) {
        if ($null -EQ $TokenAuth) {
            Write-Verbose '[Connect-ReferenceHard] TokenAuth missing -> asking at a masked prompt.'
            $TokenAuth = Read-Host -Prompt 'tokenAuth (X-Auth-Token)' -AsSecureString
        }
        $Secrets['tokenAuth'] = $TokenAuth
    }

    $script:ReferenceHardSession = [PSCustomObject]@{
        BaseUrl              = $BaseUrl.AbsoluteUri
        Secrets              = $Secrets
        SkipCertificateCheck = $SkipCertificateCheck.IsPresent
    }
    Write-Verbose "[Connect-ReferenceHard] Connected to '$($BaseUrl.Authority)' with $($Secrets.Count) session values."
}
