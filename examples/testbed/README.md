# Unwire testbed
Local targets Unwire may hit without any risk. Everything runs in throwaway containers bound to
`127.0.0.1`, without volumes: `docker compose down` resets every target to a fresh state.
Here even write operations may be called for real.

| Target | URL | Login | What it tests |
| --- | --- | --- | --- |
| OWASP Juice Shop | http://127.0.0.1:3000 | `admin@juice-sh.op` / `admin123` (public default) | Angular SPA, many undocumented REST endpoints, login, admin area |
| Mock none | http://127.0.0.1:3010 | none | Frame UI, scripts answer 403 without a same-origin `Referer` |
| Mock basic | http://127.0.0.1:3011 | from `.env`, browser dialog | HTTP Basic on every request, `HttpAuth: Basic` |
| Mock digest | http://127.0.0.1:3012 | from `.env`, browser dialog | HTTP Digest, Unwire must reject the session |
| Mock form | http://127.0.0.1:3013 | from `.env`, login form | Session cookie, code behind the login, `LoginForm` |
| Mock sid | http://127.0.0.1:3014 | from `.env`, login built by script | Session in the URL parameter `sid`, redacted inline values |
| Mock path | http://127.0.0.1:3015/ui/ | from `.env`, login built by script | Session token as path segment `/ui/;tok=<VALUE>/` |
| Mock bearer | http://127.0.0.1:3016 | from `.env`, `login.bearer.htm` | Public code, `/api/` needs `Authorization: Bearer` |

All mocks are one container, see [mock-router/README.md](mock-router/README.md); how to run
and check each one: [../mocks/README.md](../mocks/README.md).

## Start
```powershell
Copy-Item .env.example .env
docker compose up -d --build
```

## Run Unwire
From the repo root in Claude Code:

| Target | Command |
| --- | --- |
| Juice Shop | `/unwire http://127.0.0.1:3000 -Name JuiceShop` |
| Mock none | `/unwire http://127.0.0.1:3010 -Name MockNone` |
| Mock basic | `/unwire http://127.0.0.1:3011 -Name MockBasic` |
| Mock digest | `/unwire http://127.0.0.1:3012 -Name MockDigest` |
| Mock form | `/unwire http://127.0.0.1:3013 -Name MockForm` |
| Mock sid | `/unwire http://127.0.0.1:3014 -Name MockSid` |
| Mock path | `/unwire http://127.0.0.1:3015/ui/ -Name MockPath` |
| Mock bearer | `/unwire http://127.0.0.1:3016 -Name MockBearer` |

## Reset
```powershell
docker compose down
```
