---
name: unwire-discover
description: Step 1 of Unwire. Checks a web UI for published API documentation (openapi.json, swagger.json, /v3/api-docs, Swagger UI, ReDoc, GraphiQL) with GET requests only. Use before any code analysis, when someone wants the API of a device, router, NAS or web app.
---

# Unwire: Discover

Finds documentation the target already publishes. A hit can save the whole code analysis.

## Ground rule
Only GET requests to the paths in `scripts/data/spec-paths.json`. No POST, also not for a
GraphQL introspection: a GraphiQL page is reported as a hit, the schema stays an open point.

## Steps
1. Run the probe from the plugin root (`${CLAUDE_PLUGIN_ROOT}`):
   ```powershell
   pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/scripts/Find-UnwireSpec.ps1" `
       -Uri '<URL>' -OutputDirectory './unwire/<name>/discover' -Verbose
   ```
   Add `-SkipCertificateCheck` only after the user agreed (self-signed device certificates).
2. Read the result, one object per hit:

   | Kind | Meaning | Next |
   | --- | --- | --- |
   | `OpenApi`, `Swagger` | JSON spec, saved in `discover/` | Copy to `openapi.json`, convert Swagger 2.0 to OpenAPI 3 |
   | `OpenApiYaml` | YAML spec, saved in `discover/` | Convert to `openapi.json` |
   | `SwaggerUi`, `ReDoc` | Documentation page | Find the spec URL in the page (`url:` / `spec-url`), probe it with `-Path` |
   | `GraphQLUi` | GraphiQL or Playground | Note as open point, schema needs introspection (POST) |

3. Judge the hit:
   - **Complete**: covers the UI's features. Ask the user whether to skip `unwire-analyze`.
   - **Partial** (e.g. only a public API, the UI uses more): continue with `unwire-analyze`
     and merge, the published spec wins on conflicts.
   - **None**: continue with `unwire-analyze`.

## Output
- `unwire/<name>/discover/*.json|yaml`: saved specs.
- When a spec is taken over: `unwire/<name>/openapi.json` with
  `x-unwire-source: "discover:<path>"` on the root object.
