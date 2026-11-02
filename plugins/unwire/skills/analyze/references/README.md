# References
What a good `openapi.json` of `unwire:analyze` looks like, one simple and one hard case.
Step 4 of `SKILL.md` reads both before the spec is written: the shape is copied, never the
paths, names or values. Both are marked with `"x-unwire-reference": true`.

| File | Content |
| --- | --- |
| `reference.simple.openapi.json` | A UI without login: literal paths, `security: []`, a query parameter, a write with a body, a live GET note. |
| `reference.hard.openapi.json` | Code behind a login: session scheme in the query, the login call, a path parameter, a call from an `onclick` attribute, a form body with unknown keys, a low-confidence guess with its reasons, root open points. |

Generic wording only, no product or vendor names: the agent would read them as hints. A
Pester test (`tests/References.Tests.ps1`) checks both against `Test-UnwireSpec`.
