# Scripts
Deterministic helpers of the Unwire skills, plain PowerShell 7, no modules required.
The skills call them with `pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/scripts/<script>"`.

| File | Step | Content |
| --- | --- | --- |
| `Find-UnwireSpec.ps1` | Discover | Probes well-known documentation paths with GET (Swagger, OpenAPI, Gitea's `swagger.v1.json`, ...), saves found specs. |
| `Save-UnwireAsset.ps1` | Analyze | Downloads the page, frames, same-origin scripts, webpack chunks and source maps, writes `unwire-assets.json`. `-PromptSession` (masked prompt) or `-UseSession` (env variable) for code behind a login: scripts only. |
| `Get-UnwireJsCandidate.ps1` | Analyze | Pre-filters JS, HTML and source maps for endpoint candidates. |
| `Test-UnwireSpec.ps1` | Analyze | Validates openapi.json: structure, path parameters, operationIds, `$ref` targets, `x-unwire-*`. |
| `ConvertTo-UnwireHtml.ps1` | Document | Renders openapi.json as one self-contained, clickable `API.html`. |
| `data/spec-paths.json` | Discover | The paths `Find-UnwireSpec.ps1` probes by default. |
| `data/js-patterns.json` | Analyze | The endpoint patterns of `Get-UnwireJsCandidate.ps1`, in match order. |
| `lib/ConvertTo-UnwireText.ps1` | Shared | Decodes a response body (string or bytes), dot-sourced by the scripts. |
