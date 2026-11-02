# NOTE:
#   Session of a signed-in browser for the scripts that request the target with a login
#   (Save-UnwireAsset, Test-UnwireGet). Dot-source this file, it loads every function:
#
#   . $PSScriptRoot/../../../shared/session/Session.ps1
#   $session = Read-UnwireSession -PromptSession -Uri $Uri -GuideFile $GuideFile -Language de

. $PSScriptRoot/ConvertFrom-UnwireCurlSession.ps1     # cookie, auth headers and path token of a cURL
. $PSScriptRoot/ConvertTo-UnwireCookieHeader.ps1      # Cookie header from the other copy formats
. $PSScriptRoot/ConvertTo-UnwireSessionValue.ps1      # value of the session URL parameter
. $PSScriptRoot/Get-UnwireCookieShape.ps1             # pasted text described without its content
. $PSScriptRoot/Get-UnwireRequestUri.ps1              # URI with token and parameter, wire only
. $PSScriptRoot/ConvertTo-UnwireRedactedText.ps1      # every session value replaced
. $PSScriptRoot/ConvertTo-UnwireSession.ps1           # pasted text to a session object
. $PSScriptRoot/Read-UnwirePaste.ps1                  # one masked paste, also multi-line
. $PSScriptRoot/Read-UnwireSession.ps1                # prompt with retries or variable
