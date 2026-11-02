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
  it" builds PowerShell and cURL commands, cookie names and Basic user/password editable.
- **Open in browser, no Send button** (2026-11-02, user decision). A GET that changes nothing
  gets an http(s) link the user clicks, the browser adds its own cookie or Basic dialog;
  greyed out with the reason while it cannot work (no base URL, placeholders, a header). No
  `fetch`: a local page can neither read the device's answers (CORS) nor send its cookie.
- **The spec is the contract** (2026-11-02). `openapi.json` with `x-unwire-source`,
  `-confidence`, `-verified`, `-impact`, `-open`, root `x-unwire-target` (the URL of the run,
  default base URL of API.html, filled in by the live GET); `Test-UnwireSpec` checks it.
- **Step 4 is `unwire:code`, not implemented** (2026-11-02). The plugin promises only what works.
- **Sessions only from a paste, in a window** (2026-11-02). `shared/session/`: a pasted cURL
  gives cookie, `Authorization` and auth headers, path token or URL parameter; the masked
  prompt asks again (up to 3 pastes) with the reason and a Fetch/XHR or POST hint, and the
  live GET asks once more when a paste carries only a cookie (Juice Shop sends its login as
  a Bearer header). Session values never reach a file, a log or the chat. Asset session mode
  loads code only (start page, `*.htm`, `*.js`, `*.mjs`, `*.map`), pages read, never saved.
- **Two reference specs show the shape** (2026-11-02, Claude Code tip 3). `skills/analyze/references/`:
  a simple and a hard case from the mock router, generic, marked `x-unwire-reference`; step 4
  reads both before writing a spec, copies the shape, never paths or names.
- **PowerShell 7 only, deterministic scripts plus Claude for the meaning** (2026-11-01).
- **Missing pwsh: check, ask, never install unasked** (2026-11-02). `shared/pwsh-check.md`.
- **The login question is asked, never decided; Referer like a browser** (2026-11-02).
  `LoginForm`, `AccessDenied` and `HttpAuth: Basic` lead to the question (`HttpAuth: Digest`
  straight to the local folder), own requests past the scripts are forbidden.
- **The testbed is the regression suite** (2026-11-02, user decision). Juice Shop plus a mock
  router with one port per login method; Gitea, Uptime Kuma and Grafana removed. Test login
  `admin`/`admin`, session `admin-session` (6+ chars, shorter values are not scrubbed).
- **One plugin for every agent with skills** (2026-11-02). Claude Code, Copilot CLI, Codex and
  Gemini CLI install the same folder; three manifests, two marketplaces.

## State

- v0.4.0 on `master`, not pushed.
  Skills: unwire (entry), discover, analyze, document, code (stub). 8 scripts plus
  `shared/session/` (9 files), 223 Pester tests (plus 5 in `docs/screenshots`),
  ScriptAnalyzer clean.
- `Save-UnwireAsset`: webpack runtimes with one `if` per chunk and the automatic publicPath,
  `-Page`/`-Script` for paths built at runtime, `HttpAuth` for a 401 on the start page,
  session mode keeps inline scripts and `onclick`/`javascript:` code, guessed paths never
  count as `AccessDenied`. `Get-UnwireJsCandidate` reads the method only from the call's own
  arguments.
- Examples (committed, checked for secrets):
  - `examples/juiceshop/`: live GET 33 of 46, 30 of 89 operations verified, 8 more 200 with
    the Bearer header; open: `order-history/orders` 403 (admin), two 500s.
  - `examples/mocks/<variant>/`: all 7 mock variants after the fixes, 14 candidates each
    with and without login, live GET 5 of 5 per variant (401 → 200), Digest rejected by
    design, 0 session values in any file. The specs were built by a scratch script from
    the candidates, not by `unwire:analyze` in the chat.
- Marketplace install and the other agents: checked off by the user (2026-11-02).
- `examples/testbed`: Juice Shop :3000, mock router :3010-3016 (`mock-router/`, pwsh
  `HttpListener`, styled frame UI; Bearer sends a browser without token to its login page).

## Open

- **Asset crawl guesses webpack module ids** (`./node_modules/dayjs/...`) as chunk paths:
  50 × 404, then MaxGuessMisses. Harmless, but noise.
- **Path values for the live GET** come only from the user: GETs with path parameters stay
  skipped without `-Value`.
- **Path token in OpenAPI**: no scheme fits a `/;tok=<VALUE>/` segment; the mock spec uses
  a placeholder header, so "Try it" and the browser button cannot build that URL.
- **`unwire:code` is a stub.** Open: language(s) and shape.
- **D · Eval loop with the testbed** (tips 13 to 16): a checkable goal per target, a check
  separate from the run, a cap on runs and cost, results remembered between runs.
- Socket.IO apps are a known limit, not handled (Uptime Kuma, no longer in the testbed).

## Next

The whole
`/unwire` chain in the chat against one mock variant (e.g. :3014): does `unwire:analyze`
alone, without a scratch script, get to the spec in `examples/mocks/sid/`?
