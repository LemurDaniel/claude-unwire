# Unwire testbed
Local targets Unwire may hit without any risk. Everything runs in throwaway containers bound to
`127.0.0.1`, without volumes: `docker compose down` resets every target to a fresh state.
Here even `unwire:module` may call write operations for real.

| Target | URL | Login | What it tests |
| --- | --- | --- | --- |
| OWASP Juice Shop | http://127.0.0.1:3000 | `admin@juice-sh.op` / `admin123` (public default) | Angular SPA, many undocumented REST endpoints, login, admin area |
| Grafana | http://127.0.0.1:3001 | from `.env` | Webpack runtime chunk map, lazy chunks, session mode |
| Gitea | http://127.0.0.1:3003 | from `.env`, created once (below) | `swagger.v1.json` + internal web routes, full run incl. module |
| Uptime Kuma (`extra`) | http://127.0.0.1:3002 | set on first visit | Limit of Unwire: calls over Socket.IO instead of HTTP |

## Start
```powershell
Copy-Item .env.example .env
docker compose up -d
docker compose --profile extra up -d      # also Uptime Kuma
```

Gitea admin, once after every fresh start (the test values of `.env.example`):
```powershell
docker compose exec -u git unwire-gitea gitea admin user create --admin --username unwire --password unwire-testbed --email unwire@example.test --must-change-password=false
```

## Run Unwire
```
/unwire http://127.0.0.1:3000 -Name JuiceShop
/unwire http://127.0.0.1:3001 -Name Grafana
/unwire http://127.0.0.1:3003 -Name Gitea
```

## Reset
```powershell
docker compose --profile extra down
```
