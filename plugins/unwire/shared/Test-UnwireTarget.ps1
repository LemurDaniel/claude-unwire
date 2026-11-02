# NOTE:
#   Classifies the target of an Unwire run before the first request: a home system on a
#   private network, or something public. Resolves the host name and checks every address
#   against the private, loopback, link-local and shared ranges. Sends nothing to the target.
#
#   Public, mixed or unresolvable means: warn the user and ask for an explicit confirmation
#   (AskUserQuestion) before any request, at their own risk.
#
#   ./plugins/unwire/shared/Test-UnwireTarget.ps1 -Uri 'https://nas.home.arpa/wiki/'

#
#   Chapters:
#     HELPERS        Private range check of one address.
#     CHECK TARGET   Validates the URI, resolves the host and classifies it.
#

[CmdletBinding()]
param (
    <#
    [Required]
    URI of the target, e.g. 'http://192.168.178.1' or 'https://nas.local/wiki/'.
    #>
    [Parameter(
        Mandatory = $true
    )]
    [System.String]
    $Uri
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# Address ranges of home networks, as network/prefix length
$PRIVATE_RANGES = @(
    '10.0.0.0/8'         # RFC 1918
    '172.16.0.0/12'      # RFC 1918
    '192.168.0.0/16'     # RFC 1918
    '127.0.0.0/8'        # loopback
    '169.254.0.0/16'     # link-local
    '100.64.0.0/10'      # shared address space (CGNAT, Tailscale)
    '::1/128'            # IPv6 loopback
    'fe80::/10'          # IPv6 link-local
    'fc00::/7'           # IPv6 unique local (fd00::/8 in practice)
)

# ===========================================================================
# ===============================   HELPERS   ===============================
# ===========================================================================
#
#   Test-UnwirePrivateAddress   True when an address lies in one of PRIVATE_RANGES.
#

function Test-UnwirePrivateAddress {
    param (
        [System.Net.IPAddress] $Address
    )

    # '::ffff:192.168.1.10' (IPv4 mapped into IPv6) => '192.168.1.10'
    if ($Address.IsIPv4MappedToIPv6) {
        $Address = $Address.MapToIPv4()
    }
    $addressBytes = $Address.GetAddressBytes()

    foreach ($range in $PRIVATE_RANGES) {
        $network, $prefixText = $range.Split('/')
        $networkBytes = [System.Net.IPAddress]::Parse($network).GetAddressBytes()
        if ($networkBytes.Length -NE $addressBytes.Length) {
            continue
        }

        # Compare the first PrefixLength bits: whole bytes first, then the remaining bits.
        $prefixLength = [System.Int32] $prefixText
        $wholeBytes   = [System.Math]::Floor($prefixLength / 8)
        $restBits     = $prefixLength % 8
        $isMatch      = $true
        for ($index = 0; $index -LT $wholeBytes; $index++) {
            if ($addressBytes[$index] -NE $networkBytes[$index]) {
                $isMatch = $false
                break
            }
        }
        if ($isMatch -AND $restBits -GT 0) {
            $mask    = (0xFF -SHL (8 - $restBits)) -BAND 0xFF
            $isMatch = ($addressBytes[$wholeBytes] -BAND $mask) -EQ ($networkBytes[$wholeBytes] -BAND $mask)
        }
        if ($isMatch) {
            return $true
        }
    }
    return $false
}

# ===========================================================================
# ============================   CHECK TARGET   =============================
# ===========================================================================
#
#   1. Validations   Fails early on a URI that is not absolute http(s).
#   2. Resolve       Addresses of the host, the literal address for an IP.
#   3. Classify      Private, public or unknown, with the reason.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early on a URI that is not absolute http(s).
# ---------------------------------------------------------------------------

$TargetUri = $null
if (-NOT [System.Uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref] $TargetUri) -OR $TargetUri.Scheme -NOTIN @('http', 'https')) {
    throw [System.ArgumentException]::new("Uri must be an absolute http or https URI, e.g. 'http://192.168.178.1', got '$Uri'.")
}
$TargetHost = $TargetUri.IdnHost.Trim('[', ']')

# ---------------------------------------------------------------------------
# Resolve
#   Addresses of the host, the literal address for an IP.
# ---------------------------------------------------------------------------

$Addresses     = @()
$ResolveFailed = $false
$literal       = $null
if ([System.Net.IPAddress]::TryParse($TargetHost, [ref] $literal)) {
    $Addresses = @($literal)
}
else {
    try {
        $Addresses = @([System.Net.Dns]::GetHostAddresses($TargetHost))
    }
    catch [System.Net.Sockets.SocketException] {
        Write-Verbose "[Test-UnwireTarget] '$TargetHost' does not resolve: $($_.Exception.Message)"
        $ResolveFailed = $true
    }
}

# ---------------------------------------------------------------------------
# Classify
#   Private, public or unknown, with the reason.
# ---------------------------------------------------------------------------

<#
    > Host does not resolve           -> Unknown: cannot tell, treat like public
    > Every address private           -> Private: a home system, no confirmation needed
    > Any address public              -> Public: warn and ask, also when others are private
#>

$PublicAddresses = @($Addresses | Where-Object { -NOT (Test-UnwirePrivateAddress -Address $_) })

$Classification, $Reason = if ($ResolveFailed -OR $Addresses.Count -EQ 0) {
    'Unknown', "'$TargetHost' does not resolve from this machine, it cannot be checked."
}
elseif ($PublicAddresses.Count -EQ 0) {
    'Private', "Every address of '$TargetHost' lies in a private, loopback or link-local range."
}
else {
    'Public', "'$TargetHost' resolves to public address(es): $(($PublicAddresses | ForEach-Object { $_.ToString() }) -join ', ')."
}
Write-Verbose "[Test-UnwireTarget] $Classification -> $Reason"

return [PSCustomObject]@{
    Host                  = $TargetHost
    Addresses             = @($Addresses | ForEach-Object { $_.ToString() })
    Classification        = $Classification
    IsHomeSystem          = $Classification -EQ 'Private'
    RequiresConfirmation  = $Classification -NE 'Private'
    Reason                = $Reason
}
