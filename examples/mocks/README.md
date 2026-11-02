# Mock router examples
Unwire output of the 7 variants of the testbed mock router
([testbed/mock-router](../testbed/mock-router/README.md)), one folder per login method.
Checked for secrets: no session value, password or Basic value of `.env` in any file.

| Folder | Content |
| --- | --- |
| `<variant>/assets-nosession/` | Crawl without session: what Unwire sees before a login. |
| `<variant>/assets/` | Crawl with session: scripts and the redacted `*.inline.js` of signed-in pages. |
| `<variant>/candidates.json` | Endpoint candidates of `assets/`. |
| `<variant>/openapi.json`, `API.html` | The spec after the live GET, and its page. |
| `<variant>/live-get.json` | Status and media type per GET, without and with session. |

Recorded 2026-11-02, after the four fixes of that day (`HttpAuth`, event handlers, method of
a call, guessed paths). Every variant with a session finds the same 14 candidates as the one
without a login, `/api/reboot` included, and its live GET verified 5 of 5 GETs (401 without,
200 with session; `none` 200 at once). `digest` holds only the crawl without session: its
session is rejected by design. `bearer/assets-nosession` also loaded `login.bearer.htm` with
`-Page` (the code names it only as a string).

## Start the mock
```powershell
Set-Location ./examples/testbed
Copy-Item .env.example .env      # test values only
docker compose up -d --build unwire-mock-router
Set-Location ../..
```

## Run one variant in Claude Code
From the repo root, the output goes to `/unwire/<name>/` (git-ignored), these examples stay.

| Variant | Command | Browser login | Expected without session |
| --- | --- | --- | --- |
| none | `/unwire http://127.0.0.1:3010 -Name MockNone` | none | Full crawl, 403 only for scripts without `Referer` |
| basic | `/unwire http://127.0.0.1:3011 -Name MockBasic` | browser dialog | `HttpAuth: Basic` → login question |
| digest | `/unwire http://127.0.0.1:3012 -Name MockDigest` | browser dialog | `HttpAuth: Digest` → local folder, no session possible |
| form | `/unwire http://127.0.0.1:3013 -Name MockForm` | login form | `LoginForm: True` → login question |
| sid | `/unwire http://127.0.0.1:3014 -Name MockSid` | login form (built by script) | `LoginForm: True`, the cURL has no cookie → `-SessionParameter sid` |
| path | `/unwire http://127.0.0.1:3015/ui/ -Name MockPath` | login form (built by script) | `LoginForm: True`, token in the cURL path |
| bearer | `/unwire http://127.0.0.1:3016 -Name MockBearer` | `login.bearer.htm`, the UI goes there without a token | Full crawl (the code is public), the API answers 401 without the header |

Log in with `MOCK_ROUTER_USER` / `MOCK_ROUTER_PASSWORD` from `.env` and copy any signed-in
request as cURL when the window asks. The pages under `pages/*.htm` and
`js/views/devices.js` are loaded by code only: Unwire has to find them in `js/app.js` and
load them with `-Page` and `-Script` (with `/ui` in front for the path variant).

## Run one variant with the scripts only
Without the chat and without a browser: the session comes from the test values of `.env`,
pasted as the cURL a browser would copy. From the repo root:
```powershell
# Test values of examples/testbed/.env into this shell
Get-Content ./examples/testbed/.env | ForEach-Object {
    if ($_ -match '^\s*(MOCK_ROUTER_\w+)=(.*)$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2] }
}
$S     = $env:MOCK_ROUTER_SESSION
$Basic = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($env:MOCK_ROUTER_USER):$($env:MOCK_ROUTER_PASSWORD)"))
$Analyze = './plugins/unwire/skills/analyze/scripts'
```

One block per variant, the cURL in `UNWIRE_COOKIE` stands for the user's paste:

| Variant | Uri | `$env:UNWIRE_COOKIE` | Extra |
| --- | --- | --- | --- |
| none | `http://127.0.0.1:3010/` | – (no session) | |
| basic | `http://127.0.0.1:3011/` | `"curl 'http://127.0.0.1:3011/' -H 'Authorization: Basic $Basic'"` | |
| digest | `http://127.0.0.1:3012/` | – (must be rejected) | |
| form | `http://127.0.0.1:3013/` | `"curl 'http://127.0.0.1:3013/' -b 'mock_form_session=$S'"` | |
| sid | `http://127.0.0.1:3014/` | `"curl 'http://127.0.0.1:3014/menu.htm?sid=$S'"` | `-SessionParameter sid` |
| path | `http://127.0.0.1:3015/ui/` | `"curl 'http://127.0.0.1:3015/ui/;tok=$S/main.htm'"` | pages and script with `/ui` in front |
| bearer | `http://127.0.0.1:3016/` | `"curl 'http://127.0.0.1:3016/api/status' -H 'Authorization: Bearer $S'"` | |

Example for `form`, the others differ only in the values of the table:
```powershell
$Uri = 'http://127.0.0.1:3013/'
$Out = './unwire/mock-form'

# 1. Without session: expect LoginForm True, AccessDenied 0
& "$Analyze/Save-UnwireAsset.ps1" -Uri $Uri -OutputDirectory "$Out/assets-nosession"

# 2. With session, plus the pages and the view the code loads at runtime
$env:UNWIRE_COOKIE = "curl 'http://127.0.0.1:3013/' -b 'mock_form_session=$S'"
& "$Analyze/Save-UnwireAsset.ps1" -Uri $Uri -OutputDirectory "$Out/assets" -UseSession `
    -Page '/pages/status.htm,/pages/wifi.htm,/pages/devices.htm,/pages/system.htm' -Script '/js/views/devices.js'

# 3. Candidates: expect /api/reboot (from onclick) and no method for js/app.js:13
& "$Analyze/Get-UnwireJsCandidate.ps1" -Path "$Out/assets" -OutputFile "$Out/candidates.json"

# 4. Live GET on a copy of the example spec: expect 401 without, 200 with session
Copy-Item ./examples/mocks/form/openapi.json "$Out/openapi.json"
& "$Analyze/Test-UnwireGet.ps1" -Path "$Out/openapi.json" -Uri $Uri -UseSession

# 5. Leak check: the session value must be in no file
Get-ChildItem $Out -Recurse -File | Select-String -SimpleMatch $S -List
Remove-Item Env:UNWIRE_COOKIE
```

For `digest` step 2 must fail with "The session must not be HTTP Digest", step 1 reports
`HttpAuth: Digest`. For `none` skip `-UseSession` and the cookie.
