# Scripts
Deterministic helpers of the Unwire skills, plain PowerShell 7, no modules required.
The skills call them with `pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/scripts/<script>"`.

| File | Step | Content |
| --- | --- | --- |
| `Find-UnwireSpec.ps1` | Discover | Probes well-known documentation paths with GET, saves found specs. |
| `Save-UnwireAsset.ps1` | Analyze | *Not implemented.* Downloads HTML, same-origin JS and source maps. |
| `Get-UnwireJsCandidate.ps1` | Analyze | Pre-filters JS, HTML and source maps for endpoint candidates. |
| `Test-UnwireSpec.ps1` | Analyze | *Not implemented.* Validates openapi.json and the `x-unwire-*` extensions. |
| `data/spec-paths.json` | Discover | The paths `Find-UnwireSpec.ps1` probes by default. |
| `data/js-patterns.json` | Analyze | The endpoint patterns of `Get-UnwireJsCandidate.ps1`, in match order. |
