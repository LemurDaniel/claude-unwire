function Get-UnwireCertificateError {
    <#
    .SYNOPSIS
        Tells a failed TLS certificate check apart from other connection errors.

    .DESCRIPTION
        Invoke-WebRequest wraps a rejected certificate (self-signed, expired, wrong name) in an
        HttpRequestException whose inner exception is an AuthenticationException. Returns the
        reason of that inner exception, $null for every other error (DNS, refused, timeout).

    .EXAMPLE
        PS> Get-UnwireCertificateError -Exception $_.Exception
        The remote certificate is invalid because of errors in the certificate chain: UntrustedRoot
    #>
    param (
        <#
        [Required]
        The exception a request threw.
        #>
        [System.Exception]
        $Exception
    )

    # Walks the chain, the AuthenticationException may sit one or two levels deep.
    $current = $Exception
    while ($null -NE $current) {
        if ($current -is [System.Security.Authentication.AuthenticationException]) {
            return $current.Message
        }
        $current = $current.InnerException
    }
    return $null
}
