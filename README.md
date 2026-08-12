# dbj_event_logs_management

`Reset-EventLogs.ps1` 

1. back up
2. resize and 
3. clear 

Every Windows event log [channel](#vocabulary) on a machine, in that order.

```mermaid
flowchart LR
    A["export .evtx"] --> B["set max size"] --> C["clear"]
```

Windows has no supported way to delete events specified by date. The only
removal primitive the OS offers is clear-the-whole-channel. This script does not
pretend otherwise: it takes a snapshot first, then wipes.

---

## Quick start

```powershell
.\Reset-EventLogs.ps1 --help        # what it does
.\Reset-EventLogs.ps1 -DryRun       # what it WOULD do, changes nothing
.\Reset-EventLogs.ps1 -BackupOnly   # snapshot only, destroys nothing
.\Reset-EventLogs.ps1               # the real thing (asks for YES)
```

Double-clicking `Reset-EventLogs.bat` runs the interactive path. The `.bat`
holds no logic of its own and forwards all arguments, so
`Reset-EventLogs.bat --help` works too.

| Flag | Effect |
|---|---|
| `-h`, `--help` | Help then exit |
| `-v`, `--version` | Version then exit. |
| `-DryRun` | Report the plan. Changes nothing, needs no admin. |
| `-BackupOnly` | Export `.evtx` only. Nothing resized, nothing cleared. |
| `-NoBackup` | Skip the export. Logs become unrecoverable. |
| `-BackupTo <dir>` | Export destination. Default `.\Backups\<yyyy-MM-dd_HHmmss>`. |
| `-MaxSizeBytes <n>` | Cap per channel. Default `20MB`. Accepts `20MB`, `1GB`. |
| `-Force` | Skip the `YES` gate. Automation purpose. |

Reopen a backup with `Get-WinEvent -Path .\Backups\<stamp>\Security.evtx`, or
Event Viewer UI → Action → Open Saved Log.

---

## Behavioural assumptions for you

This is the part worth reading before you run anything. The script encodes a
model of who is operating it. That model is stated here rather than left
implicit in the code.

### The assumed operator role

> **A single owner, on their own machine, who reads before agreeing, and for
> whom event history has no dramatic value.**

Every design choice descends from that sentence.

| Assumption | Where it shows up | Why |
|---|---|---|
| You own this box alone | No per-channel selection, no exclusion list — it is all ~1200 channels or nothing | Nobody else's forensics depend on these logs |
| Event Log History, has limited value to you | Clearing is the whole point; the backup is a net, not an archive | Stated by the owner: losing history "logically does not matter" |
| You read the prompt, when asked | The `YES` gate is the only defence on an irreversible act | Consent you have to type is consent you meant |
| You dry-run when unsure | `-DryRun` exists; nothing forces you through it | Treats you as capable, not as a hazard |
| You think then pick the size on purpose | `-MaxSizeBytes` is a ceiling for *future* growth, never a trim | The right cap is situational |
| You clean up after it | Nothing prunes `Backups\` | Rotation policy is yours |
| `-Force` means you already decided | Skips the gate entirely | Automation needs a way in |
| `-NoBackup` means you meant it | Restores the original no-net behaviour | Occasionally what you want; never what is safe |

### What the script owes you in return

Assumptions about you (the operator) are only fair if the script holds up to that. Two places where it did not, and what changed:

**1. The default contradicted the philosophy.**
A default *is* a decision made on your behalf, so it should be the decision you would have made.
**Default is now `20MB`**, which (on this) grows ~1000 channels and shrinks 47. But unlikely on yours.

**2. The script wrongly asked for consent**
Enumeration now happens *before* the `YES` prompt, which quotes the real figure:

```
Type YES to export and then delete 282,527 events
```

With `-NoBackup` the wording changes to match the stakes:

```
Type YES to PERMANENTLY DELETE 282,527 events with NO backup
```

### What the script does *not* assume

- That you have read the source. The `--help` and the prompt are meant to be
  sufficient on their own.
- That errors are bugs. Of ~1200 channels, many are disabled or OS-locked.
  Failures there are normal and counted, not hidden.
- That a clean log stays clean. Logs repopulate instantly, and clearing is
  itself audited (Security → event ID 1102, others → 1104). Small non-zero
  counts immediately after a run are expected.

---

## Measured behaviour

Numbers observed on `MYMACHINE`, recorded because they are unintuitive and
correct a plausible-sounding wrong guess:

| | Count |
|---|---|
| Channels `wevtutil el` enumerates | 1217 |
| Channels `Get-WinEvent -ListLog` can read | 472 |
| Channels that accept a resize (`wevtutil sl`) | 472 |
| Channels that accept a clear (`wevtutil cl`) | 1213 |

Resize and clear succeed **independently** not as one atomic operation. Readability predicts the resize; it
says nothing about the clear, which succeeds on disabled channels too. An earlier version of the dry-run report conflated the two and was wrong by two orders of magnitude — it warned of 826 skips where the real run skipped 4.

Setting a max size never deletes anything on its own. It governs future growth only. The clear is what empties a log. The script does both explicitly and relies on neither to accomplish the other.

---

## Design notes

The reasoning behind each choice lives in the comment header of `Reset-EventLogs.ps1` — eleven numbered points covering why clearing is all-or-nothing, why sizing and clearing are independent, why errors are swallowed, why backup defaults to on, and why `--help` needs an alias spelled `-help` to work at all. The header is longer than the code, deliberately.

---

## Vocabulary

**Channel** — in this context a named log stream that Windows writes events into. Each channel is its own container with its own file, size cap, and access rules.

The familiar ones appear in Event Viewer as Application, System, Security,
Setup, and Forwarded Events — the classic five. Behind them sits a much larger
set: the per-component channels named like
`Microsoft-Windows-PowerShell/Operational` or
`Microsoft-Windows-Kernel-Boot/Operational`, one or more per Windows component.
That is why the counts above are what they are — `wevtutil el` enumerates 1217
channels on `MYMACHINE`, and each is backed up, resized, and cleared in turn.

The word matters because the channel is the unit the OS actually operates on.
You can clear a channel; you cannot delete individual events inside one. That
is the constraint this script is built around.

---

Benevolent Dictator, Human Supervisor and Deep Inspirator: &copy; 2026 by dbj@dbj.org | MIT — see [LICENSE](LICENSE)