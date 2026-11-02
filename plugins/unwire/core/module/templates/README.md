# Module template
Copied by the `unwire:module` skill into `unwire/<name>/module/<Name>/`.
The placeholders are valid PowerShell identifiers, so the templates parse and lint as they are.

| Placeholder | Replaced with |
| --- | --- |
| `__NAME__` | Module name, e.g. `FritzBox` |
| `__PREFIX__` | Noun prefix of every function, e.g. `FritzBox` |
| `__SPEC_VERSION__` | `info.version` of the openapi.json |
| `__PUBLIC_IMPORTS__`, `__CUSTOM_IMPORTS__` | The dot-source lines of `Public/` and `Custom/` |

| File | Becomes |
| --- | --- |
| `tmpl.module.psm1` | `<Name>.psm1` |
| `tmpl.meta.json` | `meta.json` |
| `tmpl.Invoke-Request.ps1` | `Private/Invoke-<Prefix>Request.ps1` |
