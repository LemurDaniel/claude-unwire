# Examples
| Path | Content |
| --- | --- |
| `juiceshop/` | Unwire run against the testbed Juice Shop (2026-11-02): `openapi.json` with 88 operations from its Angular frontend, `API.html` (re-rendered after every template change, a Pester test checks, never edit), `live-get.json` and `candidates.json`; the downloaded `assets/` stay local (git-ignored, 6.8 MB). |
| `testbed/` | Docker Compose with local throwaway targets (Juice Shop, mock router with one port per login method), see [testbed/README.md](testbed/README.md). |
| `mocks/` | Unwire output of the 7 mock router variants (one per login method), and how to run each one, see [mocks/README.md](mocks/README.md). |
