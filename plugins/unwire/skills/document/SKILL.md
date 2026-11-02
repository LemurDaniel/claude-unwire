---
name: document
description: Step 3 of Unwire and its primary output. Renders an Unwire openapi.json as one self-contained, clickable HTML page (API.html) with groups, search, filters for confidence, write and derived operations, schemas and all open points. Use after unwire:analyze, or whenever someone wants to read or share what Unwire found.
---

# Unwire: Document

The documentation is what the user reads first: what exists, how sure it is, what is open.
Client code (`unwire:code`) is planned, not implemented yet.

## Ground rule
Outside Claude Code: `${CLAUDE_PLUGIN_ROOT}` and AskUserQuestion as in "Outside Claude
Code" of `unwire/SKILL.md` (plugin root: two folders above this `SKILL.md`).

PowerShell 7: run the check of `${CLAUDE_PLUGIN_ROOT}/shared/pwsh-check.md` before the
first script, unless it already passed in this session.

## Steps
1. **Enrich the spec** before rendering, the page shows what the spec says:
   - `summary` on every operation: short, imperative, from the UI context ("Search teams").
   - `description` where the code tells more (side effects, what the UI does with the result).
   - `tags` on every operation, plus a root `tags` list with a `description` per tag.
     Group by feature as the UI does (Teams, Access Control), not by URL prefix.
   - Root `x-unwire-open`: the open points of the whole spec (auth flow, URLs built at runtime,
     skipped CDN scripts, failed assets). Operation-level points stay in the operation's
     `x-unwire-open`. There is no separate OPEN-POINTS.md, the page lists all of them.
2. **Validate**, no `Error` may remain:
   ```powershell
   pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/shared/Test-UnwireSpec.ps1" -Path './unwire/<name>/openapi.json'
   ```
3. **Render**:
   ```powershell
   pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/skills/document/scripts/ConvertTo-UnwireHtml.ps1" -Path './unwire/<name>/openapi.json'
   ```
   Writes `unwire/<name>/API.html` next to the spec. The page works offline, no CDN.
   It returns `OutputFile` and `FileUri`, the `file:///` link to the page.
   Every operation card has a "Try it" block: the user fills the session and parameters
   and copies a PowerShell or cURL command to run in their own terminal. A GET that changes
   nothing also gets an "Open in browser" link the user clicks. The page itself sends
   nothing (a Send button would fail on CORS), and the agent never runs these commands.
4. **Hand over**: the operation count per confidence, the number of write operations and the
   three most important open points. The reply ends with the link, `FileUri` copied exactly
   from the script output (never built by hand), in the language of the conversation:
   ```markdown
   🌐 **[API.html im Browser öffnen](<FileUri>)**
   Klick den Link oder öffne `<OutputFile>` im Browser.
   ```
   ```markdown
   🌐 **[Open API.html in the browser](<FileUri>)**
   Click the link or open `<OutputFile>` in your browser.
   ```
5. **Open**: right after the hand-over, ask with the **AskUserQuestion** tool, in the
   language of the conversation:
   - question: "API.html im Browser öffnen?" / "Open API.html in the browser?"
   - option 1: "Öffnen" / "Open": opens the local file in the default browser.
   - option 2: "Nicht jetzt" / "Not now": the link above stays.

   Only option 1 opens it, one tool call that does nothing else. `Invoke-Item` uses the
   default app of the OS (Windows, `open` on macOS, `xdg-open` on Linux):
   ```powershell
   pwsh -NoProfile -Command "Invoke-Item -LiteralPath '<OutputFile>'"
   ```
   It opens only the local page (no CDN, no request to the target). Fails it (no desktop,
   no browser): say so, the link and the path stay.

## Rules
- Rendering is deterministic: change the spec and render again, never edit `API.html`.
- Every value in the spec comes from downloaded code. The page writes values only as text,
  keep it that way when changing `templates/tmpl.api.html` of this skill.
