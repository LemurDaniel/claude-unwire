# Unwire plugin
> **ONLY USE FOR HOME SYSTEMS YOU OWN.** Prototype, AI-generated: review every result.
> See the notices in the [repository README](../../README.md).

| Path | Content |
| --- | --- |
| `.claude-plugin/plugin.json` | Manifest, skills from `core/`. |
| `commands/unwire.md` | `/unwire`, runs the chain. |
| `core/unwire-discover/` | Step 1: published docs (`Find-UnwireSpec`), Swagger 2.0 to OpenAPI 3 (`ConvertFrom-UnwireSwagger`). |
| `core/unwire-analyze/` | Step 2: static assets (`Save-UnwireAsset`), endpoint candidates (`Get-UnwireJsCandidate`). |
| `core/unwire-document/` | Step 3: openapi.json to API.html (`ConvertTo-UnwireHtml`). |
| `core/unwire-module/` | Step 4, on request: PowerShell module from picked operations. |
| `shared/` | Used by several skills: `Test-UnwireTarget` (home network or public), `Test-UnwireSpec`, `ConvertTo-UnwireText`. |

Every skill folder holds its `SKILL.md`, its `scripts/`, its `data/` or `templates/` and its
Pester `tests/`. Scripts are plain PowerShell 7, no modules required.
