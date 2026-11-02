function Invoke-UnwireWebRequest {
    <#
    .SYNOPSIS
        Sends one request without following redirects and returns a 3xx as a response.

    .DESCRIPTION
        With MaximumRedirection 0, pwsh 7.4+ answers a 3xx with a MaximumRedirectExceeded
        error, which ErrorActionPreference 'Stop' turns into a terminating error. Returns the
        3xx response instead, so the caller decides about the redirect. Every other error
        (DNS, refused, certificate) is thrown unchanged.

    .EXAMPLE
        PS> (Invoke-UnwireWebRequest -RequestConfig $RequestConfig -Uri 'http://router.test/api-docs').StatusCode
        301
    #>
    param (
        <#
        [Required]
        The parameters for Invoke-WebRequest, with MaximumRedirection 0.
        #>
        [System.Collections.Hashtable]
        $RequestConfig,

        <#
        [Required]
        The URI to request.
        #>
        [System.Uri]
        $Uri
    )

    $response = Invoke-WebRequest @RequestConfig -Uri $Uri -ErrorAction SilentlyContinue -ErrorVariable requestErrors

    # Only the redirect error is expected, everything else bubbles up.
    foreach ($requestError in $requestErrors) {
        if ($requestError.FullyQualifiedErrorId -NOTLIKE 'MaximumRedirectExceeded*') {
            throw $requestError
        }
        Write-Verbose "[Invoke-UnwireWebRequest] '$Uri' answered with a redirect -> returning it."
    }
    return $response
}
