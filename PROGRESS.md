# Progress

The handoff between sessions. Read it at the start of one, rewrite it at the end of one.
Keep it tight: what is here is what the next session starts from. The git history holds how
things got here; this file holds what holds now, and the one next thing at the end.

## Goal

A Claude Code plugin that turns the undocumented HTTP API of a web UI (router, NAS, smart
home, web app) into an OpenAPI spec and a clickable HTML documentation, without ever
changing anything on the target. Client code for picked operations is planned (`unwire:code`).

## Decisions, and why

- **Read-only, no exceptions without asking** (2026-11-01). Only GET on documentation paths
  and static assets, never an endpoint. It is what makes running against real devices safe.
  No crawler, no probing, no capture proxy: too risky and too much work for the user.
- **Discover, then analyze, then document** (2026-11-01). A published spec beats any analysis
  (Gitea publishes `swagger.v1.json`); code analysis fills the gaps; open points record what
  stays unknown instead of guessing.
- **The documentation is the primary output, as one HTML page** (2026-11-02). Every operation
  is unverified, a module would look finished when it is not. The page is self-contained
  (no CDN), writes spec values only as text, and tells documented from derived operations.
- **The spec is the contract** (2026-11-02). `openapi.json` with `x-unwire-source`,
  `-confidence`, `-verified`, `-impact`, `-open`; the page (and later the code) is a view of
  it, and `Test-UnwireSpec` checks it before.
- **Step 4 is `unwire:code`, not implemented** (2026-11-02). The PowerShell module generator
  never ran: renamed, emptied to a stub, templates removed (still in the git history before
  this commit). The plugin promises only what works.
- **Session mode loads code only** (2026-11-02). Cookie from a masked prompt in the user's
  terminal (or an env variable for automation), then only the start page and `*.js`, `*.mjs`,
  `*.map`. The signed-in page is read, never saved. Bearer tokens and MCP servers were
  declined: an MCP server documents itself, `tools/list` would break the read-only rule.
- **PowerShell 7 only, deterministic scripts plus Claude for the meaning** (2026-11-01).
  Scripts do the mechanics (download, pre-filter, convert, validate, render); Claude reads
  the candidates, names operations, writes the spec.
- **Missing pwsh: check, ask, never install unasked** (2026-11-02). `shared/pwsh-check.md`
  runs before the first script (Bash tool, PS >= 7), then AskUserQuestion: install yourself
  (recommended), Claude runs winget/brew (not on Linux, sudo), or cancel. No 5.1 fallback.
- **Marketplace layout like Infrastructure-as-Skills** (2026-11-02). `plugins/unwire/core/<skill>/`
  with its own scripts, data or templates and tests; `shared/` for what several skills use.

## State

- v0.2.0 on `master`. Skills: discover, analyze, document, code (stub). 7 scripts, 129 Pester
  tests (plus 5 in `docs/screenshots`). The hand-over ends with a
  `file:///` link to `API.html` (`FileUri` from `ConvertTo-UnwireHtml`), then asks to open
  it in the default browser (`Invoke-Item`).
- `API.html`: light default with a dark toggle, summary cards, group tiles, views Operations,
  Open points and Authentication. `examples/juiceshop/` is the reference page, re-rendered
  with every template change (a test checks), README screenshot from `docs/screenshots/`.
- Live runs: Grafana (webpack, base tag, 243 candidates), Gitea without and with login
  (full run to `API.html`: 471 documented + 47 derived operations, 0 spec findings).
- `examples/testbed`: Juice Shop, Grafana, Gitea, Uptime Kuma on 127.0.0.1, not started yet.

## Open

- **Auth per operation is new and untested in a run** (2026-11-02). `unwire:analyze` now sets
  `security` per derived operation (`[]` for public), `Test-UnwireSpec` warns otherwise. The
  Juice Shop example predates it: all 88 derived operations take the root default, so the
  Authentication view lists the login under bearerAuth. A new Juice Shop run fixes it.
- **`unwire:code` is a stub.** Open: which language(s), what shape; the old PowerShell
  module design (SKILL.md, templates) is in the history of `core/module/`.
- **C · Reference output inside the plugin** (Claude Code tip 3, "show what good looks
  like"). The Grafana example in `examples/` was dropped on 2026-11-02 at the user's
  request (git history has it). If wanted: a small reference spec in
  `core/analyze/references/` and the skills pointing at it.
- **D · Eval loop with the testbed** (tips 13 to 16). A checkable goal per target (e.g. Juice
  Shop: these endpoints must be found), a check separate from the run, a cap on runs and cost,
  results remembered between runs, like `evals/` in Infrastructure-as-Skills.
- Install through the marketplace (`/plugin marketplace add LemurDaniel/claude-unwire`) and
  `claude plugin validate` were not run, the CLI is not on PATH in the desktop app shell.
- The analysis of candidates into operations was done by hand with a scratch script in the
  Gitea run; whether `unwire:analyze` alone gets there is untested.
- Socket.IO apps (Uptime Kuma) are a known limit, not handled.

## Next

Start a fresh session: bring up the testbed, create the Gitea admin, run the full chain
against the local Gitea up to `API.html` and compare it with the published `swagger.v1.json`.
