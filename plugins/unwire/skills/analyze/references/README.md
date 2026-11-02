# References
What a good `openapi.json` of `unwire:analyze` looks like, one simple and one hard case.
Step 4 of `SKILL.md` reads both before the spec is written: the shape is copied, never the
paths, names or values. Both are marked with `"x-unwire-reference": true`.

| File | Content |
| --- | --- |
| `reference.simple.openapi.json` | A storage UI without login: literal paths, `security: []`, a query parameter with its values, a write with a body, a live GET note. |
| `reference.hard.openapi.json` | Code behind a login: a token header scheme, the sign-in call, a path parameter named after the code's variable, a call from an `onclick` attribute, a body passed through (`medium`), a guessed GET that starts something (`low`, marked write), root open points. |

Both describe an invented device. No path, operation or scheme may match a testbed target
(`examples/`): the testbed checks what the agent finds in the code, a reference that shares
its paths would hand over the answer. Generic wording only, no product or vendor names.
`tests/References.Tests.ps1` checks all of it.
