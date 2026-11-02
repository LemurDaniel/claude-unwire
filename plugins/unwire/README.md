# Unwire plugin
> **ONLY USE FOR HOME SYSTEMS YOU OWN.** Prototype, AI-generated: review every result.
> See the notices in the [repository README](../../README.md).

| Path | Content |
| --- | --- |
| `.claude-plugin/plugin.json` | Claude Code manifest, skills from `skills/`. |
| `plugin.json` | Agent Plugins 1.0 manifest for Codex and Copilot CLI, skills from `skills/` by convention. |
| `gemini-extension.json` | Gemini CLI extension manifest, skills from `skills/` by convention. |
| `assets/` | `icon.svg` (source, also the favicon `ConvertTo-UnwireHtml` embeds in every API.html) and `icon.png` (512 px, Claude directory `icon`, Codex `composerIcon` and `logo`). Re-render: `./docs/screenshots/New-UnwireScreenshot.ps1 -Path ./plugins/unwire/assets/icon.svg -OutputFile ./plugins/unwire/assets/icon.png -Width 512 -Height 512 -Scale 1`. |
| `skills/unwire/` | `/unwire` (`unwire:unwire`), runs the chain; explains the Claude-only names for other agents. |
| `skills/discover/` | Step 1: published docs (`Find-UnwireSpec`), Swagger 2.0 to OpenAPI 3 (`ConvertFrom-UnwireSwagger`). |
| `skills/analyze/` | Step 2: static assets (`Save-UnwireAsset`), endpoint candidates (`Get-UnwireJsCandidate`). |
| `skills/document/` | Step 3: openapi.json to API.html (`ConvertTo-UnwireHtml`). |
| `skills/code/` | Step 4, not implemented yet: client code from picked operations. |
| `shared/` | Used by several skills: `Test-UnwireTarget` (home network or public), `Test-UnwireSpec`, `ConvertTo-UnwireText`; `pwsh-check.md` with `data/pwsh-install.json` (PowerShell 7 check, asks before an install). |

Every skill folder holds its `SKILL.md`, its `scripts/`, its `data/` or `templates/` and its
Pester `tests/`. Scripts are plain PowerShell 7, no modules required.
