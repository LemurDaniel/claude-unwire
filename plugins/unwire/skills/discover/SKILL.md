---
name: discover
description: Step 1 of Unwire. Checks a web UI for published API documentation (openapi.json, swagger.json, /v3/api-docs, Swagger UI, ReDoc, GraphiQL) with GET requests only. Use before any code analysis, when someone wants the API of a device, router, NAS or web app.
---

# Unwire: Discover

Finds documentation the target already publishes. A hit can save the whole code analysis.

## Ground rule
Outside Claude Code: `${CLAUDE_PLUGIN_ROOT}` and AskUserQuestion as in "Outside Claude
Code" of `unwire/SKILL.md` (plugin root: two folders above this `SKILL.md`).

PowerShell 7: run the check of `${CLAUDE_PLUGIN_ROOT}/shared/pwsh-check.md` before the
first script, unless it already passed in this session.

Only home systems the user owns: run `${CLAUDE_PLUGIN_ROOT}/shared/Test-UnwireTarget.ps1`
before the first request. `RequiresConfirmation: true` (public or unresolvable) means warn
and get an explicit "continue at my own risk" through the AskUserQuestion tool, exactly as
`unwire/SKILL.md` describes, or send nothing.

Only GET requests to the paths in `data/spec-paths.json` of this skill, plus, on a Swagger UI
page, its same-origin init scripts and the spec URL they name. A redirect is followed only
when it adds a trailing slash (`/api-docs` → `/api-docs/`). No POST, also not for a
GraphQL introspection: a GraphiQL page is reported as a hit, the schema stays an open point.

## Steps
1. Run the probe from the plugin root (`${CLAUDE_PLUGIN_ROOT}`):
   ```powershell
   pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/skills/discover/scripts/Find-UnwireSpec.ps1" `
       -Uri '<URL>' -OutputDirectory './unwire/<name>/discover' -Verbose
   ```
   Run without `-SkipCertificateCheck`. An untrusted certificate stops the script after the
   first request with "has a TLS certificate this machine does not trust": ask the user as
   `unwire/SKILL.md` describes, add the switch only after a yes.
2. Read the result, one object per hit:

   | Kind | Meaning | Next |
   | --- | --- | --- |
   | `OpenApi` | JSON spec, saved in `discover/` | Copy to `openapi.json` |
   | `Swagger` | Swagger 2.0, saved in `discover/` | Convert with `ConvertFrom-UnwireSwagger.ps1` (below) |
   | `OpenApiYaml` | YAML spec, saved in `discover/` | Convert to `openapi.json` |
   | `SwaggerUi` | Documentation page | The script already read its init scripts: an embedded spec comes as an extra `OpenApi`/`Swagger` hit (`…#swaggerDoc`), a same-origin `url:` is probed. No extra hit: find the spec URL in the page yourself and probe it with `-Path` |
   | `ReDoc` | Documentation page | Find the spec URL in the page (`spec-url`), probe it with `-Path` |
   | `GraphQLUi` | GraphiQL or Playground | Note as open point, schema needs introspection (POST) |

   Swagger 2.0 to OpenAPI 3, with the x-unwire-* extensions set on every operation:
   ```powershell
   pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/skills/discover/scripts/ConvertFrom-UnwireSwagger.ps1" `
       -Path './unwire/<name>/discover/swagger.v1.json' -OutputFile './unwire/<name>/openapi.json'
   ```
   Run `Test-UnwireSpec.ps1` right after: published specs have bugs too (e.g. one
   operationId used twice). Fix them in `openapi.json` and record each fix in `x-unwire-open`.
3. Judge the hit:
   - **Complete**: covers the UI's features. Ask the user whether to skip `unwire:analyze`.
   - **Partial** (e.g. only a public API, the UI uses more): continue with
     `unwire:analyze` and merge both specs.
     - On a conflict the published spec wins.
     - Different base URLs (e.g. API under `/api/v1`, web routes under the app root):
       the common root is the one server, every API path gets its base as prefix.
     - Example: `/notifications` of the web UI and `/api/v1/notifications` of the API
       stay two operations.
   - **None**: continue with `unwire:analyze`.

Report the result as observed (paths, status codes), no guess about vendor or product.

## Output
- `unwire/<name>/discover/*.json|yaml`: saved specs.
- `unwire/<name>/openapi.json`: only when a found spec is taken over as it is.
  - Mark the root object and every operation with `x-unwire-source: "discover:<file name>"`.
    API.html uses this mark to tell documented operations from derived ones.
  - Swagger 2: `ConvertFrom-UnwireSwagger.ps1` sets the mark.
  - OpenAPI 3: set the mark yourself.
