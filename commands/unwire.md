---
description: Reverse engineers the API of a web UI into openapi.json, OPEN-POINTS.md and a PowerShell module. Read-only.
argument-hint: <url|folder> -Name <api-name> [-SkipCertificateCheck]
---

# /unwire

Runs the whole Unwire chain for: `$ARGUMENTS`

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

## Output
```
unwire/<name>/
  discover/          # step 1: found documentation
  assets/            # step 2: downloaded HTML, JS, maps (add to .gitignore)
  candidates.json    # step 2: pre-filtered endpoint candidates
  openapi.json       # the spec, the contract for step 4
  OPEN-POINTS.md     # everything that could not be resolved statically
  module/<Name>/     # step 4: the PowerShell module
```

## Steps
1. **Discover** with the `unwire-discover` skill. If a complete spec is found, show it to the
   user and ask whether to skip step 2.
2. **Analyze** with the `unwire-analyze` skill: static code analysis into `openapi.json`.
3. **Open points**: show the user a short summary of `OPEN-POINTS.md` and ask whether to
   continue with the module or clarify points first.
4. **Module** with the `unwire-module` skill.

Stop after each step when it fails, and report what is missing.
