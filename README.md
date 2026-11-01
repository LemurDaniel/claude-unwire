# claude-unwire
Claude Code plugin that reverse engineers the undocumented HTTP API of a web UI (router, NAS,
smart home device, web app) into an OpenAPI spec and a clickable HTML documentation.
A PowerShell module for the parts you need follows on request.

**Read-only by design:** Unwire finds published documentation and analyzes the static
frontend code. It never calls an API endpoint, never submits a form, never executes
downloaded JavaScript.

```
1. Discover   swagger.json, openapi.json, /v3/api-docs, Swagger UI …   GET on well-known paths
2. Analyze    HTML + JS bundles + source maps → openapi.json           static assets only
3. Document   openapi.json → API.html (primary output)                 offline, no CDN
4. Module     picked operations → PowerShell module + Pester tests     only on request
```

Open points (auth flow, URLs built at runtime, unknown schemas) live in the spec and show up
on the page, per operation and as one list.

## Usage
```
/unwire http://192.168.178.1 -Name FritzBox
/unwire ./saved-ui -Name Nas        # local copy of a UI behind a login, fully offline
```

Example output: [examples/grafana/API.html](examples/grafana/API.html), rendered from
[examples/grafana/openapi.json](examples/grafana/openapi.json).

## Layout
| Path | Content |
| --- | --- |
| `.claude-plugin/plugin.json` | Plugin manifest. |
| `commands/unwire.md` | `/unwire`, runs the chain. |
| `skills/unwire-discover/` | Step 1: published documentation. |
| `skills/unwire-analyze/` | Step 2: static code analysis, open points. |
| `skills/unwire-document/` | Step 3: openapi.json → API.html. |
| `skills/unwire-module/` | Step 4: picked operations → PowerShell module. |
| `scripts/` | Deterministic PowerShell helpers, see [scripts/README.md](scripts/README.md). |
| `templates/docs/` | Template of the HTML documentation. |
| `templates/module/` | Template of the generated module, see [templates/module/README.md](templates/module/README.md). |
| `examples/` | Example spec and its rendered page. |
| `tests/` | Pester tests of `scripts/`. |

## Status
v0.1.0: all scripts work and are tested. Not yet run end to end as `/unwire`, the module
generation of `unwire-module` is untested.

## Development
```powershell
'./scripts', './templates', './tests' | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Recurse -Severity Warning, Error }
Invoke-Pester -Path ./tests
./scripts/ConvertTo-UnwireHtml.ps1 -Path ./examples/grafana/openapi.json   # re-render the example
claude --plugin-dir .      # load the plugin locally
```
