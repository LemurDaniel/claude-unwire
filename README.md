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

## Install
```
/plugin marketplace add LemurDaniel/claude-unwire
/plugin install unwire@claude-unwire
```

## Layout
A marketplace repository with one plugin, laid out like Infrastructure-as-Skills-Azure.

| Path | Content |
| --- | --- |
| `.claude-plugin/marketplace.json` | Marketplace manifest, points to `plugins/unwire`. |
| `plugins/unwire/` | The plugin: skills in `core/`, each with its scripts and tests, see [plugins/unwire/README.md](plugins/unwire/README.md). |
| `examples/` | Example spec and its rendered page, plus a local testbed to run Unwire against, see [examples/testbed/README.md](examples/testbed/README.md). |

## Status
v0.2.0: all scripts work and are tested, one full run against Gitea (518 operations).
The module generation of `unwire-module` has not run yet.

## Development
```powershell
Invoke-ScriptAnalyzer -Path ./plugins/unwire -Recurse -Severity Warning, Error
Invoke-Pester -Path ./plugins/unwire
./plugins/unwire/core/unwire-document/scripts/ConvertTo-UnwireHtml.ps1 -Path ./examples/grafana/openapi.json   # re-render the example
claude --plugin-dir ./plugins/unwire      # load the plugin locally
```
