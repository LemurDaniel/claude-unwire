# claude-unwire
Claude Code plugin that reverse engineers the undocumented HTTP API of a web UI (router, NAS,
smart home device, web app) into an OpenAPI spec and a native PowerShell module.

**Read-only by design:** Unwire finds published documentation and analyzes the static
frontend code. It never calls an API endpoint, never submits a form, never executes
downloaded JavaScript.

```
1. Discover   swagger.json, openapi.json, /v3/api-docs, Swagger UI …   GET on well-known paths
2. Analyze    HTML + JS bundles + source maps → openapi.json           static assets only
3. Open       OPEN-POINTS.md: everything not resolvable statically
4. Module     openapi.json → PowerShell script module + Pester tests
```

## Usage
```
/unwire http://192.168.178.1 -Name FritzBox
/unwire ./saved-ui -Name Nas        # local copy of a UI behind a login, fully offline
```

## Layout
| Path | Content |
| --- | --- |
| `.claude-plugin/plugin.json` | Plugin manifest. |
| `commands/unwire.md` | `/unwire`, runs the whole chain. |
| `skills/unwire-discover/` | Step 1: published documentation. |
| `skills/unwire-analyze/` | Step 2 and 3: static code analysis, open points. |
| `skills/unwire-module/` | Step 4: openapi.json → PowerShell module. |
| `scripts/` | Deterministic PowerShell helpers, see [scripts/README.md](scripts/README.md). |
| `templates/module/` | Template of the generated module, see [templates/module/README.md](templates/module/README.md). |
| `tests/` | Pester tests of `scripts/`. |

## Status
v0.1.0 scaffold: `Find-UnwireSpec.ps1` works, the other scripts are stubs.

## Development
```powershell
'./scripts', './templates', './tests' | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Recurse -Severity Warning, Error }
Invoke-Pester -Path ./tests
claude --plugin-dir .      # load the plugin locally
```
