# Getting started with ReferenceHard

PowerShell client of ReferenceHard, written by Unwire from the code of its web UI.
**Draft, AI-derived:** every function sends what the code suggested, check it before you rely on it.
Use it only against your own device.

## 1. Import
```powershell
Import-Module ./ReferenceHard/ReferenceHard.psd1
Get-Command -Module ReferenceHard
```
Needs PowerShell 7.2 or newer, nothing else.

## 2. Connect
```powershell
Connect-ReferenceHard -BaseUrl 'https://nas.example.test:5443/'
```
- **tokenAuth** (header `X-Auth-Token`): asked at a masked prompt. Sign in in the browser,
  open the developer tools (F12) → Network, click any request to `/api/` and copy the
  value of its `X-Auth-Token` header.
- The session stays in memory only: gone with `Disconnect-ReferenceHard`, `Remove-Module` or the
  end of the shell. Nothing is written to a file.
- `-NoSession` connects without one, only operations without a session work then.
- `-SkipCertificateCheck` for a device with a self-signed certificate.

## 3. Read
```powershell
Get-ReferenceHardAccount
Get-Help Get-ReferenceHardAccount -Full     # source, confidence and open points in .NOTES
```

## 4. Change
Every function that changes the device asks first. Try it with `-WhatIf`:
```powershell
Lock-ReferenceHardAccount -AccountId 'u-17' -WhatIf
```
Functions of `low` or `medium` confidence print a warning on every call: what they send is
derived, not seen. `Get-Help <function> -Full` names why.

## 5. Anything else
`Invoke-ReferenceHardRest` sends any operation of the spec, with the same session:
```powershell
Invoke-ReferenceHardRest -Method GET -Path '/api/v1/accounts' -Security tokenAuth
```
A redirect or HTTP 401 usually means the session expired: run `Connect-ReferenceHard` again.

| Function | Changes the device | Confidence |
| --- | --- | --- |
| `Get-ReferenceHardAccount` | no | high, verified |
| `Lock-ReferenceHardAccount` | yes | medium |
| `Set-ReferenceHardSetting` | yes | medium |
| `Start-ReferenceHardJob` | yes | low |
| `Suspend-ReferenceHardDevice` | yes | high |
