---
name: unwire-module
description: Optional step 4 of Unwire, only on request. Generates a native PowerShell script module (.psm1, one function per file, Pester tests against mocks) for the operations the user picked from an Unwire openapi.json. Use after unwire-document, or when an existing OpenAPI spec should become a PowerShell client.
---

# Unwire: Module

Turns selected operations of `unwire/<name>/openapi.json` into an idiomatic PowerShell 7
script module. No compiled C#, no AutoRest.

## Precondition
- `Test-UnwireSpec.ps1` returns no `Error` for the spec. Stop and fix the spec otherwise:
  the function names come from `operationId`, the confirmations from `x-unwire-impact`.
- The user picked what to generate, by tag (`Teams`), by path prefix (`/api/teams`) or by
  `operationId`. Ask when nothing was picked: a module for every operation of a large spec
  is noise nobody reads. Write `meta.json.operations` with the picked operationIds.

## Layout
Start from `${CLAUDE_PLUGIN_ROOT}/core/unwire-module/templates/` and replace `__NAME__` and `__PREFIX__`:
```
unwire/<name>/module/<Name>/
  <Name>.psm1                         # dot-sources every file explicitly
  meta.json                           # name, prefix, spec version
  Private/Invoke-<Prefix>Request.ps1  # the one HTTP core: base URI, session, headers
  Public/Connect-<Prefix>.ps1         # auth, from the spec's securitySchemes
  Public/<Verb>-<Prefix><Noun>.ps1    # one function per operation
  Custom/                             # user code, never written by Unwire
  tests/                              # Pester, against mocks only
```

## Mapping operation → function
| Operation | Function |
| --- | --- |
| `GET /devices` | `Get-<Prefix>Device` |
| `GET /devices/{id}` | `Get-<Prefix>Device -Id` (same function, parameter set) |
| `POST /devices` | `New-<Prefix>Device` |
| `PUT`/`PATCH /devices/{id}` | `Set-<Prefix>Device` |
| `DELETE /devices/{id}` | `Remove-<Prefix>Device` |
| Action (`POST /system/reboot`) | Approved verb from the meaning: `Restart-<Prefix>System` |

Only approved verbs (`Get-Verb`), singular nouns.

## Rules per function
- Comment-based help from `summary`/`description`, one `.EXAMPLE`.
- Parameters from path, query and body, with types and `ValidateSet` from enums.
- Pipeline input by `Id` where it makes sense (`Get-XDevice | Remove-XDevice`).
- Every HTTP call goes through `Invoke-<Prefix>Request`, no `Invoke-RestMethod` elsewhere.
- Operations with `x-unwire-impact: "write"`: `SupportsShouldProcess`, `ConfirmImpact = 'High'`.
- `x-unwire-verified: false` on a write operation: `Write-Warning` that the call was never
  verified, until the user confirms it worked.
- `x-unwire-open` points go into `.NOTES` of the help.

## Regenerating
`Public/`, `Private/`, `tests/` and the `.psm1` are rewritten. `Custom/` is only read, to list
its files in the `.psm1`. Never write into it.

## Tests
- Mock `Invoke-<Prefix>Request`, never call the device.
- Per function: the expected method, path and body, with concrete values.
- Verify: parser, `Invoke-ScriptAnalyzer -Severity Warning, Error`, `Invoke-Pester`.
