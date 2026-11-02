# Progress

The handoff between sessions. Read it at the start of one, rewrite it at the end of one.
Keep it tight: what is here is what the next session starts from. The git history holds how
things got here; this file holds what holds now, and the one next thing at the end.

## Goal

A Claude Code plugin that turns the undocumented HTTP API of a web UI (router, NAS, smart
home, web app) into an OpenAPI spec and a clickable HTML documentation, without ever
changing anything on the target. A PowerShell module for picked operations follows on request.

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
  `-confidence`, `-verified`, `-impact`, `-open`; page and module are views of it, and
  `Test-UnwireSpec` checks it before either.
- **Session mode loads code only** (2026-11-02). Cookie from a masked prompt in the user's
  terminal (or an env variable for automation), then only the start page and `*.js`, `*.mjs`,
  `*.map`. The signed-in page is read, never saved. Bearer tokens and MCP servers were
  declined: an MCP server documents itself, `tools/list` would break the read-only rule.
- **PowerShell 7 only, deterministic scripts plus Claude for the meaning** (2026-11-01).
  Scripts do the mechanics (download, pre-filter, convert, validate, render); Claude reads
  the candidates, names operations, writes the spec.
- **Marketplace layout like Infrastructure-as-Skills** (2026-11-02). `plugins/unwire/core/<skill>/`
  with its own scripts, data or templates and tests; `shared/` for what several skills use.

## State

- v0.2.0 on `master`. Skills: discover, analyze, document, module. 7 scripts, 91 Pester tests.
- Live runs: Grafana (webpack, base tag, 243 candidates), Gitea without and with login
  (full run to `API.html`: 471 documented + 47 derived operations, 0 spec findings).
- `examples/testbed`: Juice Shop, Grafana, Gitea, Uptime Kuma on 127.0.0.1, not started yet.

## Open

- **`unwire-module` has never run.** Skill and templates exist, nothing was generated yet.
- **C · Reference output inside the plugin** (Claude Code tip 3, "show what good looks
  like"). `examples/` is outside `plugins/unwire/` and missing after an install. Put a small
  reference spec into `core/unwire-analyze/references/` and point the skills at it.
- **D · Eval loop with the testbed** (tips 13 to 16). A checkable goal per target (e.g. Juice
  Shop: these endpoints must be found), a check separate from the run, a cap on runs and cost,
  results remembered between runs, like `evals/` in Infrastructure-as-Skills.
- Install through the marketplace (`/plugin marketplace add LemurDaniel/claude-unwire`) and
  `claude plugin validate` were not run, the CLI is not on PATH in the desktop app shell.
- The analysis of candidates into operations was done by hand with a scratch script in the
  Gitea run; whether `unwire-analyze` alone gets there is untested.
- Socket.IO apps (Uptime Kuma) are a known limit, not handled.

## Next

Start a fresh session: bring up the testbed, create the Gitea admin, run the full chain
against the local Gitea and then `unwire-module` for the tags `repository` and `issue`,
calling the generated cmdlets for real against the throwaway instance.
