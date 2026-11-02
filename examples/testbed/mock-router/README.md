# Mock router
One frame UI, served on one port per login method. It rebuilds the traps Unwire hit on real
routers (see "Traps already hit" in `CLAUDE.md`), so every one of them can be run again
without a real device. Throwaway: nothing is stored, write calls answer `ok` and change nothing.

| File | Content |
| --- | --- |
| `Start-MockRouter.ps1` | The server: `HttpListener`, one prefix per variant, session checks, fixed JSON API. |
| `Dockerfile` | `pwsh` 7.4 image, no modules. |
| `data/mock-router.variants.json` | Ports and login method of every variant. |
| `www/` | The UI: frameset, menu with session values in inline scripts, pages loaded by XHR, a view loaded by runtime `import`, one `js/auth.<method>.js` and one login page per method. |

## Variants
Test login `MOCK_ROUTER_USER` / `MOCK_ROUTER_PASSWORD`, every login answers with
`MOCK_ROUTER_SESSION` (all from `../.env`).

| Port | Method | What Unwire must do |
| --- | --- | --- |
| 3010 | none | Send the page as `Referer`, scripts answer 403 without it. |
| 3011 | HTTP Basic | Report `HttpAuth: Basic` (start page 401), session from a cURL with `Authorization: Basic`. |
| 3012 | HTTP Digest | Report `HttpAuth: Digest`, reject the cURL, offer the local folder. |
| 3013 | Form + cookie | `LoginForm` without session (`AccessDenied` 0, only a guessed map answers 401), cookie `mock_form_session` from the cURL. |
| 3014 | `sid` parameter | Login built by an inline module `import`, no cookie in the cURL, `-SessionParameter sid`. `menu.htm` renders `var sessionId = "..."` and `{"sid":"..."}`: both must be redacted. |
| 3015 | Path token | Start at `/ui/`, token from `/ui/;tok=<VALUE>/` in the cURL. |
| 3016 | Bearer | Code public, `/api/` and `/cgi-bin/` need `Authorization: Bearer`. The UI itself sends a browser without a token to `login.bearer.htm`. |

Shared in every variant: pages under `pages/*.htm` only reachable by `-Page`
(`loadPage` builds the path), `js/views/devices.js` only by `-Script` (`loadView`),
`POST /api/reboot` only in an `onclick` attribute.

How to run Unwire against each variant, and its recorded output: [examples/mocks](../../mocks/README.md).
