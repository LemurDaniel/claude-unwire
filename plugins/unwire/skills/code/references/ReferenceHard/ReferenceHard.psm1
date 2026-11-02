# NOTE:
#   PowerShell client of ReferenceHard, written by unwire:code from its openapi.json.
#   Draft, AI-derived: every function sends what the spec says, check it before relying on it.
#
#   Import-Module ./ReferenceHard/ReferenceHard.psd1
#   Connect-ReferenceHard -BaseUrl 'https://nas.example.test:5443/'
#   Get-ReferenceHardAccount

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1.0

if ($PSVersionTable.PSVersion -lt [Version]'7.2') {
    throw 'PowerShell versions lower than 7.2 are not supported. Please upgrade to PowerShell 7.2 or higher.'
}

# servers[0].url of the spec, every path of the module is relative to it.
$script:SERVER_PATH      = '/'
# components.securitySchemes of the spec, Invoke-ReferenceHardRest adds them to a request.
$script:SECURITY_SCHEMES = Get-Content -Path "$PSScriptRoot/data/security.schemes.json" -Raw | ConvertFrom-Json -AsHashtable
# Base URL and session values of Connect-ReferenceHard, in memory only.
$script:ReferenceHardSession = $null

. "$PSScriptRoot/functions/Invoke-ReferenceHardRest.ps1"
. "$PSScriptRoot/functions/session/Connect-ReferenceHard.ps1"
. "$PSScriptRoot/functions/session/Disconnect-ReferenceHard.ps1"
. "$PSScriptRoot/functions/accounts/Lock-ReferenceHardAccount.ps1"
. "$PSScriptRoot/functions/accounts/_data.sources/Get-ReferenceHardAccount.ps1"
. "$PSScriptRoot/functions/jobs/Start-ReferenceHardJob.ps1"
. "$PSScriptRoot/functions/power/Suspend-ReferenceHardDevice.ps1"
. "$PSScriptRoot/functions/settings/Set-ReferenceHardSetting.ps1"
