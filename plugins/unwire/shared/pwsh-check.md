# PowerShell 7 check

Every Unwire script runs with `pwsh`, so this check comes before the first script of a run
(`/unwire` or a skill called on its own). Once per session is enough when it passed.
Outside Claude Code the Bash tool is the agent's shell tool and AskUserQuestion a question
in the chat, as in "Outside Claude Code" of `skills/unwire/SKILL.md`.

1. **Check** with the Bash tool, not the PowerShell tool (that one may be Windows
   PowerShell 5.1 or need `pwsh` itself): the `check` command of `data/pwsh-install.json`.
   - Prints a number of at least `minimumMajor`: go on, say nothing.
   - Command not found: `found.missing`. A lower number: `found.outdated` with `{VERSION}`.
     Then step 2. Never fall back to Windows PowerShell 5.1, the scripts need 7.
2. **Ask**: Read `data/pwsh-install.json`, take the platform (`windows`, `macos`,
   `linux`) and the language key (`de`, `en`) of the conversation, then ask with the
   **AskUserQuestion** tool, copied exactly, only the placeholders replaced:
   - header: `header`
   - question: `question`, `{FOUND}` from step 1, `{COMMAND}` and `{DOCS}` from the platform
     (Linux has no `command`: replace `{COMMAND}` with the `docs` link)
   - option 1: `self.label`, description `self.description` (recommended)
   - option 2: `claude.label`, description `claude.description`, only when the platform
     has a `command` (not on Linux: the distro decides and `sudo` needs a terminal)
   - option 3: `cancel.label`, description `cancel.description`

   No other tool call between the Read and the answer. Never install without this answer,
   it changes the system outside the repo.
3. **After the answer**:
   - `self`: ask `done` with AskUserQuestion (Done / Cancel), then check again (step 1).
   - `claude`: run exactly the platform `command` with the Bash tool, once, nothing else.
     Then check again. Still not found right after an install: show `restart`, stop.
   - `cancel`, a custom answer or none: stop, run no script.
