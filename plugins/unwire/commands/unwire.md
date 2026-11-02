---
description: Reverse engineers the API of a web UI into openapi.json and a clickable HTML documentation. Read-only. A PowerShell module follows only on request.
argument-hint: <url|folder> -Name <api-name> [-SkipCertificateCheck]
---

# /unwire

Runs the Unwire chain for: `$ARGUMENTS`

## Ground rule
Unwire never changes anything on the target. Only GET requests to well-known documentation
paths and to static assets (HTML, JS, source maps) are allowed. Never call an API endpoint
found in the code, never submit a form, never execute downloaded JavaScript.

## Input
- `<url>`: base URI of the web UI, e.g. `http://192.168.178.1`.
- `<folder>`: a local copy of the web UI ("Save page as" in the browser), for UIs behind a login.
  Then step 1 is skipped and step 2 works fully offline.
- `-Name`: short name of the API, used for the output folder and the module prefix.
  Ask the user when it is missing.
- `-SkipCertificateCheck`: for devices with self-signed certificates. Ask before using it.
- Code behind a login: the user logs in in their own browser, `unwire-analyze` runs the
  download with `-PromptSession` in the user's terminal, they paste the cookie at the masked
  prompt (scripts only). Never ask for a password or for the cookie in the chat.

## Output
```
unwire/<name>/
  discover/          # step 1: found documentation
  assets/            # step 2: downloaded HTML, JS, maps (add to .gitignore)
  candidates.json    # step 2: pre-filtered endpoint candidates
  openapi.json       # the spec, the contract for steps 3 and 4
  API.html           # step 3: the clickable documentation, the primary output
  module/<Name>/     # step 4, only on request: the PowerShell module
```

## Steps
1. **Discover** with the `unwire-discover` skill. If a complete spec is found, show it to the
   user and ask whether to skip step 2.
2. **Analyze** with the `unwire-analyze` skill: static code analysis into `openapi.json`,
   open points in the spec.
3. **Document** with the `unwire-document` skill: `API.html`. Give the user its path and a short
   summary (operations per confidence, write operations, top open points).
4. **Module**: ask whether a PowerShell module is wanted and for which tags or paths. Only then
   run the `unwire-module` skill for the picked operations.

Stop after each step when it fails, and report what is missing.
