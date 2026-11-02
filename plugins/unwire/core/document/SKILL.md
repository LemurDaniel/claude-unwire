---
name: document
description: Step 3 of Unwire and its primary output. Renders an Unwire openapi.json as one self-contained, clickable HTML page (API.html) with groups, search, filters for confidence, write and derived operations, schemas and all open points. Use after unwire:analyze, or whenever someone wants to read or share what Unwire found.
---

# Unwire: Document

The documentation is what the user reads first: what exists, how sure it is, what is open.
Client code (`unwire:code`) is planned, not implemented yet.

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
   pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/core/document/scripts/ConvertTo-UnwireHtml.ps1" -Path './unwire/<name>/openapi.json'
   ```
   Writes `unwire/<name>/API.html` next to the spec. The page works offline, no CDN.
4. **Hand over**: give the user the path of `API.html`, the operation count per confidence,
   the number of write operations and the three most important open points.

## Rules
- Rendering is deterministic: change the spec and render again, never edit `API.html`.
- Every value in the spec comes from downloaded code. The page writes values only as text,
  keep it that way when changing `templates/tmpl.api.html` of this skill.
