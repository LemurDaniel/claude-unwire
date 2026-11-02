# Progress

The handoff between sessions. Read it at the start of one, rewrite it at the end of one.
Keep it tight: what is here is what the next session starts from. The git history holds how
things got here; this file holds what holds now, and the one next thing at the end.

## Goal

A Claude Code plugin that turns the undocumented HTTP API of a web UI (router, NAS, smart
home, web app) into an OpenAPI spec and a clickable HTML documentation, without ever
changing anything on the target. Client code for picked operations is planned (`unwire:code`).

## Decisions, and why

- **Read-only, one opt-in exception** (2026-11-01, exception 2026-11-02). Only GET on
  documentation paths and static assets. It is what makes running against real devices safe.
  No crawler, no probing, no capture proxy. The exception is the live GET below.
- **Live GET, asked per run and target** (2026-11-02, user decision). `Test-UnwireGet`, last
  step of `unwire:analyze`: only GET with `x-unwire-impact: read`, nothing on
  `shared/data/request-denylist.json` (`pattern`, plus `liveGetPattern`: token, secret,
  backup paths may create one), path parameters only with values the user gave, no
  redirects. Without session first, then optionally with the login window. Keeps status,
  media type and JSON keys and types (data keys like mails become `additionalProperties`),
  never a body. Sets `x-unwire-verified`, fills only empty schemas, one `Live GET` open point
  per operation. `-Plan` sends nothing; the skill asks with the counts before any request.
- **Discover, then analyze, then document** (2026-11-01). A published spec beats any analysis
  (Gitea publishes `swagger.v1.json`); code analysis fills the gaps; open points record what
  stays unknown instead of guessing. Published and derived routes under different bases: the
  common root is the server, the API paths get their prefix (`/api/v1/...`).
- **The documentation is the primary output, as one HTML page** (2026-11-02). Self-contained
  (no CDN), writes spec values only as text, tells documented from derived operations. "Try
  it" only builds PowerShell and cURL commands, cookie names and Basic user/password editable.
- **The spec is the contract** (2026-11-02). `openapi.json` with `x-unwire-source`,
  `-confidence`, `-verified`, `-impact`, `-open`; `Test-UnwireSpec` checks it (since
  2026-11-02 also that `servers` is a list).
- **Step 4 is `unwire:code`, not implemented** (2026-11-02). The plugin promises only what works.
- **Sessions only from a paste, in a window** (2026-11-02). `shared/session/`: a pasted cURL
  gives cookie, `Authorization` and auth headers, path token or URL parameter; the masked
  prompt asks again (up to 3 pastes) with the reason and a Fetch/XHR or POST hint, and the
  live GET asks once more when a paste carries only a cookie (Juice Shop sends its login as
  a Bearer header). Session values never reach a file, a log or the chat. Asset session mode
  loads code only (start page, `*.htm`, `*.js`, `*.mjs`, `*.map`), pages read, never saved.
- **PowerShell 7 only, deterministic scripts plus Claude for the meaning** (2026-11-01).
- **Missing pwsh: check, ask, never install unasked** (2026-11-02). `shared/pwsh-check.md`.
- **The login question is asked, never decided; Referer like a browser** (2026-11-02).
  `LoginForm` and `AccessDenied` lead to the question, own requests past the scripts are
  forbidden.
- **One plugin for every agent with skills** (2026-11-02). Claude Code, Copilot CLI, Codex and
  Gemini CLI install the same folder; three manifests, two marketplaces.

## State

- v0.3.0 on `master` (manifests not bumped for the live GET yet). Skills: unwire (entry),
  discover, analyze, document, code (stub). 8 scripts plus `shared/session/` (9 files),
  210 Pester tests (plus 5 in `docs/screenshots`), ScriptAnalyzer clean.
- `Save-UnwireAsset` reads webpack runtimes with one `if` per chunk and the automatic
  publicPath (Gitea: 48 assets instead of 4); `-Script` loads runtime-built module paths.
- Live runs on 2026-11-02:
  - Gitea (`/unwire/gitea/`, not committed): 406 published + 35 derived web routes, live GET
    46 of 226 GETs without values, 17 verified (API v1 needs a token, a browser cookie is
    not enough: 27 × 401 with and without session).
  - Juice Shop (`examples/juiceshop/`, committed): live GET 33 of 46, 30 of 89 operations
    verified, 8 more answered 200 with the Bearer header; open: `order-history/orders` 403
    (admin role), `country-mapping` and `security-question` 500.
- `examples/testbed` runs on 127.0.0.1 (Juice Shop :3000, Gitea :3003).

## Open

- **Version bump** for the live GET: all three manifests and the README notice (v0.3.0).
- **Asset crawl guesses webpack module ids** (`./node_modules/dayjs/...`) as chunk paths:
  50 × 404, then MaxGuessMisses. Harmless, but noise.
- **Path values for the live GET** come only from the user. Gitea: `owner`, `repo`, `org`,
  `username` would raise 46 to 129 planned GETs.
- **`unwire:code` is a stub.** Open: language(s) and shape.
- **C · Reference output inside the plugin** (Claude Code tip 3): a small reference spec in
  `skills/analyze/references/`, if wanted.
- **D · Eval loop with the testbed** (tips 13 to 16): a checkable goal per target, a check
  separate from the run, a cap on runs and cost, results remembered between runs.
- Marketplace install and `claude plugin validate` not run; Copilot CLI, Codex, Gemini CLI
  never ran Unwire (manifests follow their docs only).
- The Gitea analysis of candidates into operations used a scratch merge script; whether
  `unwire:analyze` alone gets there is untested.
- Socket.IO apps (Uptime Kuma) are a known limit, not handled.

## Next

Bump the version for the live GET (three manifests, README), then run the live GET against
Gitea with `-Value 'owner=…,repo=…'` of a test repository and an API token pasted as cURL
(`Authorization: token …`), to see the 401s of the published API turn into 200.
