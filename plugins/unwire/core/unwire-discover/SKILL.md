---
name: unwire-discover
description: Step 1 of Unwire. Checks a web UI for published API documentation (openapi.json, swagger.json, /v3/api-docs, Swagger UI, ReDoc, GraphiQL) with GET requests only. Use before any code analysis, when someone wants the API of a device, router, NAS or web app.
---

# Unwire: Discover

Finds documentation the target already publishes. A hit can save the whole code analysis.

## Ground rule
Only home systems the user owns: run `${CLAUDE_PLUGIN_ROOT}/shared/Test-UnwireTarget.ps1`
before the first request. `RequiresConfirmation: true` (public or unresolvable) means warn
and get an explicit "continue at my own risk" through the AskUserQuestion tool, exactly as
`commands/unwire.md` describes, or send nothing.

Only GET requests to the paths in `data/spec-paths.json` of this skill. No POST, also not for a
GraphQL introspection: a GraphiQL page is reported as a hit, the schema stays an open point.

## Steps
1. Run the probe from the plugin root (`${CLAUDE_PLUGIN_ROOT}`):
   ```powershell
   pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/core/unwire-discover/scripts/Find-UnwireSpec.ps1" `
       -Uri '<URL>' -OutputDirectory './unwire/<name>/discover' -Verbose
   ```
   Run without `-SkipCertificateCheck`. An untrusted certificate stops the script after the
   first request with "has a TLS certificate this machine does not trust": ask the user as
   `commands/unwire.md` describes, add the switch only after a yes.
2. Read the result, one object per hit:

   | Kind | Meaning | Next |
   | --- | --- | --- |
   | `OpenApi` | JSON spec, saved in `discover/` | Copy to `openapi.json` |
   | `Swagger` | Swagger 2.0, saved in `discover/` | Convert with `ConvertFrom-UnwireSwagger.ps1` (below) |
   | `OpenApiYaml` | YAML spec, saved in `discover/` | Convert to `openapi.json` |
   | `SwaggerUi`, `ReDoc` | Documentation page | Find the spec URL in the page (`url:` / `spec-url`), probe it with `-Path` |
   | `GraphQLUi` | GraphiQL or Playground | Note as open point, schema needs introspection (POST) |

   Swagger 2.0 to OpenAPI 3, with the x-unwire-* extensions set on every operation:
   ```powershell
   pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/core/unwire-discover/scripts/ConvertFrom-UnwireSwagger.ps1" `
       -Path './unwire/<name>/discover/swagger.v1.json' -OutputFile './unwire/<name>/openapi.json'
   ```
   Run `Test-UnwireSpec.ps1` right after: published specs have bugs too (Gitea's uses one
   operationId twice). Fix them in `openapi.json` and record each fix in `x-unwire-open`.
3. Judge the hit:
   - **Complete**: covers the UI's features. Ask the user whether to skip `unwire-analyze`.
   - **Partial** (e.g. only a public API, the UI uses more): continue with `unwire-analyze`
     and merge, the published spec wins on conflicts. When both live under different base
     URLs (Gitea: API under `/api/v1`, web routes under the app root), use the common root
     as the one server and prefix the API paths with their base: `/notifications` of the
     web UI and `/api/v1/notifications` of the API must stay two operations.
   - **None**: continue with `unwire-analyze`.

## Output
- `unwire/<name>/discover/*.json|yaml`: saved specs.
- When a spec is taken over: `unwire/<name>/openapi.json` with
  `x-unwire-source: "discover:<file name>"` on the root object and on every operation (set by `ConvertFrom-UnwireSwagger.ps1`; for an OpenAPI 3 spec set it yourself). The page tells documented and derived operations apart by it.
