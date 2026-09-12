# CLAUDE.md

1. This file is written for Claude. It describes this repository and how Claude should behave here.
2. Make sure user scope claude.md is also read and obeyed `%USERPROFILE%\.claude\CLAUDE.md`
   1. pay special attention to Conversation protocol, in there

## What This Repo Is

One PowerShell tool: `Reset-EventLogs.ps1` — backs up, resizes and clears every
Windows event log channel on a machine, in that order. `Reset-EventLogs.bat` is
a one-line double-click shim that forwards all arguments; it holds no logic.

`README.md` documents the flags and the reasoning. Keep it in step with the
script — the flag table and the `.bat` explanation are the contract.

## Working conventions

- All logic stays in the `.ps1`. Never move behaviour into the `.bat`.
- Destructive by nature: the backup-first order, the `-DryRun`/`-BackupOnly`
  paths and the `YES` gate are safety features. Do not weaken or bypass them.
- `Backups/` holds exported `.evtx` snapshots — working data, not source.
- Never run the script against this machine to "test" it. Use `-DryRun`.

## Behavioral Rules

1. **Do not invent URLs.**

## Ownership

- &copy; 2026 dbj@dbj.org | MIT — see `LICENSE`

## Document versioning

- Every markdown file **SHOULD** (not must) carry a decimal `version:` key in its front matter:

```yaml
---
version: 0.1
---
```

- `0.1` .. `1.0` — pre-releases leading up to release 1
- `1.1` .. `2.0` — releases 1.1 through 2.0
- and so on by the same pattern

SHOULD, not MUST: skip it where this repo forbids front matter, and where front matter already exists just add the `version` key without disturbing the rest.
