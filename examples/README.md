# Examples
| Path | Content |
| --- | --- |
| `juiceshop/openapi.json` | Unwire spec of the testbed Juice Shop: 89 operations, derived from its Angular frontend. |
| `juiceshop/API.html` | The page rendered from it, re-rendered after every template change (a Pester test checks). Never edit. |
| `testbed/` | Docker Compose with local throwaway targets (Juice Shop, mock router with one port per login method), see [testbed/README.md](testbed/README.md). |
| `mocks/` | Unwire output of the 7 mock router variants (one per login method), and how to run each one, see [mocks/README.md](mocks/README.md). |
