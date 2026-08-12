# dbj_event_logs_management

`Reset-EventLogs.ps1` — back up, resize, and clear every Windows event log
channel on a machine, in that order.

```
Per channel:   export .evtx   →   set max size   →   clear
```

Windows has no supported way to delete events *older than a date*. The only
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
| `-h`, `--help` | Usage, then exit. Never triggers UAC. |
| `-v`, `--version` | Version, then exit. |
| `-DryRun` | Report the plan. Changes nothing, needs no admin. |
| `-BackupOnly` | Export `.evtx` only. Nothing resized, nothing cleared. |
| `-NoBackup` | Skip the export. Logs become unrecoverable. |
| `-BackupTo <dir>` | Export destination. Default `.\Backups\<yyyy-MM-dd_HHmmss>`. |
| `-MaxSizeBytes <n>` | Cap per channel. Default `20MB`. Accepts `20MB`, `1GB`. |
| `-Force` | Skip the `YES` gate. Automation only. |

Reopen a backup with `Get-WinEvent -Path .\Backups\<stamp>\Security.evtx`, or
Event Viewer → Action → Open Saved Log.

---

## User behavioural assumptions

This is the part worth reading before you run anything. The script encodes a
model of who is operating it, and that model is stated here rather than left
implicit in the code.

### The assumed operator

> **A single owner, on their own machine, who reads before agreeing, and for
> whom event history has no evidentiary value.**

Every design choice descends from that sentence.

| Assumption | Where it shows up | Why |
|---|---|---|
| You own this box alone | No per-channel selection, no exclusion list — it is all ~1200 channels or nothing | Nobody else's forensics depend on these logs |
| History has limited value to you | Clearing is the whole point; the backup is a net, not an archive | Stated by the owner: losing history "logically does not matter" |
| You read the prompt | The `YES` gate is the only defence on an irreversible act | Consent you have to type is consent you meant |
| You dry-run when unsure | `-DryRun` exists; nothing forces you through it | Treats you as capable, not as a hazard |
| You pick the size on purpose | `-MaxSizeBytes` is a ceiling for *future* growth, never a trim | The right cap is situational |
| You clean up after it | Nothing prunes `Backups\` | Rotation policy is yours, not the script's |
| `-Force` means you already decided | Skips the gate entirely | Automation needs a way in |
| `-NoBackup` means you meant it | Restores the original no-net behaviour | Occasionally what you want; never what is safe |

### What the script owes you in return

Assumptions about the operator are only fair if the script holds up its side.
Two places where it did not, and what changed:

**1. The default contradicted the philosophy.**
The header insists the cap is a deliberate call, then shipped `5MB` as the
default — which quietly cut `Security`, `System`, and `Application` from 20 MB
to 5 MB while claiming to be about headroom, and disagreed with what an
informed operator actually chose after reading a dry run. A default *is* a
decision made on your behalf, so it should be the decision you would have made.
**Default is now `20MB`**, which grows ~1000 channels and shrinks 47.

**2. The gate asked for consent to a category, not a fact.**
`YES` was demanded before any count reached the screen. On 2026-08-12 that gate
approved the deletion of **282,527 events** without that number ever being
displayed, and they are not recoverable. Enumeration now happens *before* the
prompt, which quotes the real figure:

```
Type YES to export and then delete 282,527 events
```

With `-NoBackup` the wording changes to match the stakes:

```
Type YES to PERMANENTLY DELETE 282,527 events with NO backup
```

Same keystroke, different meaning — the prompt should not blur the two.

The count is a snapshot: logs keep growing between the prompt and the loop, so
slightly more will be cleared than quoted. It is accurate to the moment of
asking, which is the moment that matters for consent.

### What it does *not* assume

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

Resize and clear succeed **independently**. Readability predicts the resize; it
says nothing about the clear, which succeeds on disabled channels too. An
earlier version of the dry-run report conflated the two and was wrong by two
orders of magnitude — it warned of 826 skips where the real run skipped 4.

Setting a max size never deletes anything on its own. It governs future growth
only. The clear is what empties a log. The script does both explicitly and
relies on neither to accomplish the other.

---

## Design notes

The reasoning behind each choice lives in the comment header of
`Reset-EventLogs.ps1` — eleven numbered points covering why clearing is
all-or-nothing, why sizing and clearing are independent, why errors are
swallowed, why backup defaults to on, and why `--help` needs an alias spelled
`-help` to work at all. The header is longer than the code, deliberately.

## Licence

Benevolent Dictator and Human Supervisor and Deep Inspirator: &copy; 2026 by dbj@dbj.org | MIT — see [LICENSE](LICENSE)
