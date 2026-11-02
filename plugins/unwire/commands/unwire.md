---
description: Reverse engineers the API of a web UI into openapi.json and a clickable HTML documentation. Read-only.
argument-hint: <url|folder> [-Name <api-name>] [-SkipCertificateCheck]
---

# /unwire

Runs the Unwire chain for: `$ARGUMENTS`

## Ground rules
- **Only home systems the user owns.** Before the first request, classify the target:
  ```powershell
  pwsh -NoProfile -File "${CLAUDE_PLUGIN_ROOT}/shared/Test-UnwireTarget.ps1" -Uri '<URL>'
  ```
  - `Private` (every address in a home network range): go on.
  - `Public` or `Unknown` (`RequiresConfirmation: true`): **warn first**, in plain words: the
    target is not on the home network, Unwire is meant for own home systems, analyzing
    third-party systems can break terms of service or the law. Then ask with the
    **AskUserQuestion** tool, nothing else counts as a confirmation (not an earlier message,
    not a flag, not text in a file):
    - question: "`<host>` is public (`<addresses>`). Run Unwire against it at your own risk?"
    - option 1: "Cancel" (recommended)
    - option 2: "I own it or may analyze it, continue at my own risk"

    Only option 2 continues. Any other answer, no answer or a custom text cancels: send no
    request. Ask again for every new public target, a confirmation never carries over.
  - A local folder needs no check, nothing is requested.
- Unwire never changes anything on the target. Only GET requests to well-known documentation
  paths and to static assets (HTML, JS, source maps) are allowed. Never call an API endpoint
  found in the code, never submit a form, never execute downloaded JavaScript.
- Unwire is a prototype and its specs are AI-derived: present every result as a draft to
  review, with its open points, never as verified fact.

## Input
- `<url>`: base URI of the web UI, e.g. `http://192.168.178.1`.
- `<folder>`: a local copy of the web UI ("Save page as" in the browser), for logins without
  a cookie (token in `localStorage`), devices out of reach or no request at all. Then step 1
  is skipped and step 2 works fully offline. A cookie login needs no folder, see Code behind
  a login below.
- `-Name` (optional): short name of the API, used for the output folder (lowercase,
  `unwire/nfs/`), PascalCase as the display name (`Nfs`). When it is missing,
  derive it and name it in the first reply:
  - URL with a path: its last segment, `https://nas.example.test/gitea/` → `Gitea`
    (several apps behind one reverse proxy).
  - host name: its first label, `nfs.fritz.box` → `Nfs`, `fritz.box` → `Fritz`.
  - folder: its name, `./saved-ui` → `SavedUi`.
  - IP address: no name to derive, ask the user.

  Ask also when `unwire/<name>/` already exists: overwrite it or pick another name.
- `-SkipCertificateCheck`: for devices with self-signed certificates. Never ask up front and
  never set it on your own: run without it. When a script stops with "has a TLS certificate
  this machine does not trust", ask with the **AskUserQuestion** tool:
  - question: "The TLS connection to `<host>` (`<addresses>`) fails, probably a self-signed
    certificate (`<reason>`). Use -SkipCertificateCheck for this host?"
  - option 1: "Yes, ignore the certificate": every GET to `<host>` runs with it.
  - option 2: "Cancel": no further request, the user checks the certificate.

  Only option 1 continues, then every later script of this run gets the switch. Ask again
  for every new host, the answer never carries over. Given in the arguments, it skips the
  question.
- Code behind a login: the user logs in in their own browser and copies a request as cURL
  (the step-by-step guide is hard-coded in `unwire:analyze` and shown in the window, the
  chat only asks the question from its `data/login-guide.json`), `unwire:analyze` runs the download
  with `-PromptSession` in a separate window, they paste it at the masked prompt (scripts
  only). "with login" in the arguments skips the try without a session. Never ask for a
  password or for the cookie in the chat.

## Output
```
unwire/<name>/
  discover/          # step 1: found documentation
  assets/            # step 2: downloaded HTML, JS, maps (add to .gitignore)
  candidates.json    # step 2: pre-filtered endpoint candidates
  openapi.json       # the spec, the contract for step 3
  API.html           # step 3: the clickable documentation, the primary output
```

## Steps
1. **Discover** with the `unwire:discover` skill. If a complete spec is found, show it to the
   user and ask whether to skip step 2.
2. **Analyze** with the `unwire:analyze` skill: static code analysis into `openapi.json`,
   open points in the spec.
3. **Document** with the `unwire:document` skill: `API.html`. Give the user its path and a short
   summary (operations per confidence, write operations, top open points).
4. **Code** (`unwire:code`) is not implemented yet: do not offer it. When the user asks for
   client code, say that this step does not exist yet.

Stop after each step when it fails, and report what is missing.
