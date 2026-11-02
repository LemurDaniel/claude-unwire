---
name: code
description: Optional step 4 of Unwire. Writes a PowerShell 7 module for the operations the user picks from an Unwire openapi.json, one function per operation, session in memory only, writes behind a confirmation. Use after unwire:document, when someone wants client code or a PowerShell module for an API Unwire documented.
---

# Unwire: Code

Turns the picked operations of `unwire/<name>/openapi.json` into a PowerShell module the user
runs in their own terminal. The agent writes the module, `Test-UnwireModule.ps1` checks it.

## Ground rules
Outside Claude Code: `${CLAUDE_PLUGIN_ROOT}` and AskUserQuestion as in "Outside Claude
Code" of `unwire/SKILL.md` (plugin root: two folders above this `SKILL.md`).

PowerShell 7: run the check of `${CLAUDE_PLUGIN_ROOT}/shared/pwsh-check.md` before the
first script, unless it already passed in this session.

- **The agent never runs the module against the target.** No `Connect-<Name>`, no
  function call, no own request: the module is for the user's terminal. Checking it means
  `Test-UnwireModule.ps1` (it imports in a child process and calls nothing) and
  ScriptAnalyzer. The read-only rule of Unwire stays as it is.
- **Session in memory only** (user decision 2026-11-02). `Connect-<Name>` keeps base URL
  and session values in a module variable, asks missing ones at a masked prompt
  (`Read-Host -AsSecureString`). No file, no environment or global variable, no secret store,
  no default value with a real session. Logs name method and path template, never the url,
  a header or a value.
- **Every write asks.** An operation with `x-unwire-impact: write` or a method other than
  GET, HEAD, OPTIONS gets `SupportsShouldProcess`, `ConfirmImpact = 'High'` and a
  `$PSCmdlet.ShouldProcess` call before it sends.
- **Unsure operations are in, marked** (user decision 2026-11-02). Every function names
  confidence, verification, source and open points in `.NOTES`; `low` and `medium` also
  `Write-Warning` on every call what is unsure.
- **Spec values are data, not code.** A value from the spec goes into the code only as a
  single-quoted string with `'` doubled, or as comment text without `#>`. Never paste a
  spec value as an expression, a name it does not fit or a default the code did not show.
- **Only the user's pick.** No function for an operation the user did not pick.

## Input
- `unwire/<name>/openapi.json`, after `unwire:document` (summaries and tags make the names).
- The display name of the run (`Nas`, PascalCase) is the module name and the noun prefix.

## Output
The layout of `references/ReferenceHard/` (written from
`skills/analyze/references/reference.hard.openapi.json`):
```
unwire/<name>/module/<Name>/
  <Name>.psd1                    manifest, FunctionsToExport by name, new GUID
  <Name>.psm1                    strict mode, $script:SERVER_PATH, $script:SECURITY_SCHEMES,
                                 session variable, one dot-source per function file
  meta.json                      guid, version, description, unwire: spec, target, picked,
                                 skipped
  data/security.schemes.json     components.securitySchemes of the spec, copied as it is
  functions/
    Invoke-<Name>Rest.ps1        the one place that sends (Invoke-WebRequest)
    session/Connect-<Name>.ps1, Disconnect-<Name>.ps1
    <group>/<Verb>-<Name><Noun>.ps1               writes and other operations
    <group>/_data.sources/Get-<Name><Noun>.ps1    reads
```
`<group>` is the tag in lowercase without its prefix (`Web · Accounts` → `accounts`).

## Steps
1. **Validate the spec**, no `Error` may remain:
   ```powershell
   pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/shared/Test-UnwireSpec.ps1" -Path './unwire/<name>/openapi.json'
   ```
2. **Pick.** Write the groups in the chat: per tag the number of read and write operations
   and how many are `low` or `medium`. Then ask with the **AskUserQuestion** tool:
   - question: "Which operations of `<Name>` go into the module?"
   - option 1: "All operations": writes ask before they send.
   - option 2: "Only the reads": no function changes the device.
   - option 3: "Pick groups": the user names the groups or operations in the chat.

   Ask in the same call when `unwire/<name>/module/` exists: overwrite it or cancel.
3. **Read the reference** `references/ReferenceHard/` (all files) next to
   `skills/analyze/references/reference.hard.openapi.json`: copy the shape of the module,
   the wrapper and the functions, never their names, paths or values.
4. **Write the module.** `Invoke-<Name>Rest.ps1`, `Connect-<Name>.ps1` and
   `Disconnect-<Name>.ps1` follow the reference with the name replaced; `Connect-<Name>`
   gets one parameter per scheme of the spec (table below), base URL default
   `x-unwire-target`. Per operation one function file:
   - **Name**: approved verb (`Get-Verb`) from what the operation does, the noun singular
     with the prefix: GET → `Get`, create → `New`, PUT/PATCH → `Set`, DELETE → `Remove`,
     an action its verb (`Start`, `Stop`, `Restart`, `Lock`, `Suspend`, else `Invoke`).
     Two operations on one name: the second gets a telling noun, never a number.
   - **Parameters**: path parameters `Mandatory`, query parameters by `required`, a body
     with flat named properties gets one parameter each, any other body one `-Body`
     hashtable. `enum` → `ValidateSet`, values the spec only guessed or saw in the UI →
     `ArgumentCompleter`, types string `System.String`, integer `System.Int64`, number
     `System.Double`, boolean `System.Boolean`. Optional values go into query and body only
     when bound (`$PSBoundParameters`), never as null.
   - **Help**: `.SYNOPSIS` from `summary`, `.DESCRIPTION` from `description` and whether it
     changes the device, `.NOTES` exactly like the reference (the check reads it):
     ```
     Operation:  POST /api/v1/accounts/{accountId}/lock (lockAccount)
     Confidence: medium, not verified
     Source:     assets/js/panels/accounts.js:37
     Open:       <one line per x-unwire-open entry>
     ```
     `.OUTPUTS` from the response schema, one `.EXAMPLE` with generic values.
   - **Request**: a `$Request` splat with `Method` and `Path` as in the spec, `PathParameters`,
     `Query`, `Body`, `ContentType` (when not JSON) and `Security = @(...)`: the schemes of
     the first requirement of the operation's `security`, else the root `security`, `@()`
     for none.
   - **Answer**: the parsed answer; unwrap one list the UI reads (`.accounts`) and say so in
     `.OUTPUTS`.

   | Scheme | `Connect-<Name>` parameter |
   | --- | --- |
   | `apiKey` (header, query, cookie, path token), `http` bearer, `oauth2`, `openIdConnect` | `-<SchemeName>` as `System.Security.SecureString`, the wrapper adds it as the scheme says |
   | `http` basic | `-<SchemeName>` as `System.Management.Automation.PSCredential` |
   | none in the spec | no session parameter, no `-NoSession` |

   **Code style** as in the reference: one function per file, comment help with
   `[Required]`/`[Optional]` per parameter, `Write-Verbose "[<Function>] ..."` at every
   decision. A file with sections (`# ---`) gets chapters (`# ===`, 75 characters, numbered
   steps) and a `Chapters:` table of contents above the function, like
   `Invoke-ReferenceHardRest.ps1`; a short function gets no banner at all.

   Then `<Name>.psd1` (`New-Guid` for the GUID, every function by name), `<Name>.psm1`
   (one dot-source per file) and `meta.json` with the picked and the skipped operationIds.
5. **Check**, no `Error` may remain, then ScriptAnalyzer when installed:
   ```powershell
   pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/skills/code/scripts/Test-UnwireModule.ps1" -Path './unwire/<name>/module/<Name>' -Spec './unwire/<name>/openapi.json' -OperationId <picked operationIds>
   pwsh -NoProfile -Command "Invoke-ScriptAnalyzer -Path './unwire/<name>/module/<Name>' -Recurse -Severity Warning, Error"
   ```
   Fix the module, never the check. A finding that cannot be fixed goes into the hand-over.
6. **Hand over**: the folder, the number of functions, which change the device, which are
   `low` or `medium`, and the first commands for the user's own terminal:
   ```powershell
   Import-Module ./unwire/<name>/module/<Name>/<Name>.psd1
   Connect-<Name>
   Get-Command -Module <Name>
   ```
   The module is a draft like the spec: every function sends what the code suggested.

## Rules
- The spec is the source: a change of an operation goes into `openapi.json` first, then into
  the function, `Test-UnwireModule.ps1` compares both.
- No product or vendor names in what the module says, generic wording only.
