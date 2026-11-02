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
  terminal (or an env variable for automation), then only the start page, `*.htm`/`*.html`
  pages and frames (since 2026-11-02, user decision: frame-based router UIs keep their API
  calls there), `*.js`, `*.mjs`, `*.map`. Pages are read, never saved, only their inline
  scripts with string values redacted. Bearer tokens and MCP servers were
  declined: an MCP server documents itself, `tools/list` would break the read-only rule.
- **PowerShell 7 only, deterministic scripts plus Claude for the meaning** (2026-11-01).
  Scripts do the mechanics (download, pre-filter, convert, validate, render); Claude reads
  the candidates, names operations, writes the spec.
- **Missing pwsh: check, ask, never install unasked** (2026-11-02). `shared/pwsh-check.md`
  runs before the first script (Bash tool, PS >= 7), then AskUserQuestion: install yourself
  (recommended), Claude runs winget/brew (not on Linux, sudo), or cancel. No 5.1 fallback.
- **The login question is asked, never decided** (2026-11-02). A router served its login
  page with 200 and all scripts with the Referer, the skill had no trigger and analyzed
  only the login page. `Save-UnwireAsset` reports `LoginForm` (password field on the start
  page), the skill then asks with AskUserQuestion: with login, without, cancel.
- **Referer like a browser, 401/403 means login** (2026-11-02). A TP-Link router answered
  403 to its scripts without a Referer; the agent guessed and fetched them by hand.
  `Save-UnwireAsset` now sends the loading page as Referer and reports `AccessDenied`, which
  leads to the login question; own requests past the scripts are forbidden.
- **Marketplace layout like Infrastructure-as-Skills** (2026-11-02). `plugins/unwire/skills/<skill>/`
  with its own scripts, data or templates and tests; `shared/` for what several skills use.
- **One plugin for every agent with skills** (2026-11-02). Claude Code, Copilot CLI, Codex and
  Gemini CLI install the same folder: `core/` became `skills/` (the convention all of them
  read), `/unwire` became the skill `skills/unwire/`, three manifests and two marketplaces.
  Without AskUserQuestion the confirmation is a question in the chat (user approved).

## State

- v0.3.0 on `master`. Skills: unwire (entry), discover, analyze, document, code (stub). 7 scripts, 136 Pester
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

- **Auth per operation: one run, not yet from scratch** (2026-11-02). Juice Shop re-run:
  main.js byte-identical, so the 88 derived operations were taken over from the previous run
  and only `security` + `x-unwire-auth` were derived fresh (route guards, isLoggedIn(), bid
  from the login): 34 public, 47 bearer, 7 unclear with an open point, 0 spec findings.
  A full run on a new target (Grafana, Gitea) still has to show the rule works end to end.
- **`unwire:code` is a stub.** Open: which language(s), what shape; the old PowerShell
  module design (SKILL.md, templates) is in the history of `core/module/`.
- **C · Reference output inside the plugin** (Claude Code tip 3, "show what good looks
  like"). The Grafana example in `examples/` was dropped on 2026-11-02 at the user's
  request (git history has it). If wanted: a small reference spec in
  `skills/analyze/references/` and the skills pointing at it.
- **D · Eval loop with the testbed** (tips 13 to 16). A checkable goal per target (e.g. Juice
  Shop: these endpoints must be found), a check separate from the run, a cap on runs and cost,
  results remembered between runs, like `evals/` in Infrastructure-as-Skills.
- Install through the marketplace (`/plugin marketplace add LemurDaniel/claude-unwire`) and
  `claude plugin validate` were not run, the CLI is not on PATH in the desktop app shell.
- **Copilot CLI, Codex, Gemini CLI never ran Unwire** (2026-11-02). Manifests follow their docs
  only. Unconfirmed: whether they replace `${CLAUDE_PLUGIN_ROOT}` in SKILL.md (the skills fall
  back to two folders above the SKILL.md), whether the Codex CLI reads `.claude-plugin/`.
- The analysis of candidates into operations was done by hand with a scratch script in the
  Gitea run; whether `unwire:analyze` alone gets there is untested.
- Socket.IO apps (Uptime Kuma) are a known limit, not handled.

## Next

Start a fresh session: bring up the testbed, create the Gitea admin, run the full chain
against the local Gitea up to `API.html` and compare it with the published `swagger.v1.json`.
