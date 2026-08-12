<#
================================================================================
  Reset-EventLogs.ps1
================================================================================

  Author  : ASH (Claude Code Harness)
  For     : dbjdbj
  Machine : single-owner workstation (MYMACHINE)
  Licence : MIT -- see LICENSE beside this file.
  Operator assumptions: see README.md ("User behavioural assumptions"). They
  are not incidental; read them before running this on a machine whose logs
  anyone else relies on.

--------------------------------------------------------------------------------
  DESIGN PHILOSOPHY  --  read this before changing anything
--------------------------------------------------------------------------------

  This script does exactly two things to EVERY event log channel on the box:
      (1) sets a fixed maximum size with an overwrite-oldest policy, and
      (2) clears the channel right now.

  It is deliberately small. The reasoning behind each design choice below is
  worth more than the code itself, so it is documented rather than assumed.

  1. "Clear" is all-or-nothing, and that is fine here.
     ---------------------------------------------------------------
     Windows event logs are effectively append-only. There is NO supported
     way to delete events "older than a date" from a live channel -- not via
     wevtutil, not via PowerShell, not via Event Viewer. The only removal
     primitive is clear-log, which wipes the entire channel. We are not
     fighting that limitation; we accept it. The owner has stated the machine
     is a stable, single-user box where losing historical events "logically
     does not matter." So a full wipe is the correct, honest operation -- we
     do not pretend to trim by date when the OS cannot.

  2. Sizing and clearing are INDEPENDENT operations.
     ---------------------------------------------------------------
     A common misconception: "shrink the max size and it will trim old events."
     It will not. Setting max size (/ms) only governs FUTURE growth; it never
     removes existing data on its own. The clear (/cl) is what empties the log.
     We therefore do both explicitly and never rely on one to accomplish the
     other. Order chosen: set size first, then clear, so the new cap is already
     in force as the (inevitably immediate) new events start flowing in.

  3. 20 MB is a ceiling, not a target -- and it sizes MOST channels UP.
     ---------------------------------------------------------------
     Roughly a thousand Microsoft-Windows-*/Operational channels default to
     1 MB. Setting everything to 20 MB RAISES their ceiling 20x. That is a
     conscious trade: the goal here is "clean slate + comfortable headroom so
     logs are useful again," NOT "minimise disk." A cap is a maximum potential
     allocation; only what actually fills is consumed. If disk minimisation
     ever becomes the goal, LOWER this number or scope the resize to the
     classic three -- do not blanket-raise. This is flagged so a future reader
     makes that call deliberately.

     The default was 5 MB and was changed to 20 MB on 2026-08-12, because
     5 MB quietly contradicted the paragraph above. It matched the DEFAULT
     size of Security/System/Application (20 MB) badly -- capping them at
     5 MB cut the three most useful logs on the machine to a quarter while
     claiming to be about headroom. Worse, it made the default disagree with
     what an informed operator chose after reading the dry run: 20 MB. A
     default is a decision made on the operator's behalf, so it should be the
     decision they would have made. Measured on MYMACHINE: 20 MB grows ~1000
     channels and shrinks 47; 5 MB shrank Security 20->5 and
     PowerShell/Admin 1000->5.

  4. Overwrite-oldest (/rt:false), no auto-backup (/ab:false).
     ---------------------------------------------------------------
     /rt:false  => when a channel hits its cap, drop the oldest events rather
                   than refusing to log new ones. On a workstation, never
                   blocking new events is more valuable than retaining old ones.
     /ab:false  => do not spray .evtx archive files to disk on rollover. We
                   chose to purge history; auto-archiving would quietly defeat
                   that and clutter the disk.

  5. Errors are expected, and are swallowed on purpose.
     ---------------------------------------------------------------
     Of ~1000 channels, many are disabled, some are OS-locked, and some
     Analytic/Debug channels must be disabled before they can be resized.
     Those will fail. That is NORMAL, not a bug. We suppress their noise
     (2>$null) and COUNT them instead, so the summary tells the truth about
     what happened without drowning the signal.

  6. Consent is explicit and irreversible actions are gated.
     ---------------------------------------------------------------
     The action cannot be undone, so the script refuses to run blind: it
     self-elevates (UAC), states plainly what it will do, and requires the
     literal word YES. -Force exists for automation but is opt-in, never the
     default. This mirrors the principle that destructive, outward-effecting
     operations get a confirmation you have to mean.

  7. Honesty in the summary.
     ---------------------------------------------------------------
     Clearing is itself audited by Windows (Security -> Event ID 1102, other
     logs -> 1104), and logs repopulate the instant they are cleared. The
     script does not hide either fact: the post-run listing WILL show small
     record counts, and that is reported as expected behaviour, not failure.

  8. -DryRun answers "what exactly am I about to lose?" -- and touches nothing.
     ---------------------------------------------------------------
     Because the action is irreversible (#1) and the consent gate is a blunt
     yes/no (#6), the owner deserves a way to SEE the blast radius before
     agreeing to it. -DryRun enumerates the same channel list the real run
     would walk, reports the record count that would be destroyed and the
     size change each channel would receive, and issues no sl/cl commands at
     all. It needs no elevation and asks no questions, because it cannot
     change anything.

     Note what it does NOT do: it does not promise which channels will fail.
     Whether `wevtutil sl` succeeds on a given locked or analytic channel is
     only knowable by attempting it (#5), so the report predicts rather than
     promises, and says so.

     It predicts resize and clear SEPARATELY, because they are separate
     operations (#2) with different failure modes. An earlier version of this
     report conflated them -- it used "channel is disabled" to predict the
     CLEAR failing, and was wrong by two orders of magnitude (it warned of 826
     skips; the real run skipped 4). The measured truth on this machine:
     `sl` succeeds only on channels Get-WinEvent can enumerate (472 of 1217),
     while `cl` succeeds almost everywhere (1213 of 1217), disabled or not.

  9. Back up first -- and back up BY DEFAULT.
     ---------------------------------------------------------------
     The original version of this script had no backup step, on the reasoning
     in #1: the owner said losing history "logically does not matter." That
     reasoning is sound but the default was wrong. `wevtutil epl` exports a
     channel to a .evtx file that Event Viewer can reopen, it costs seconds,
     and it converts an irreversible operation into a reversible one. There
     is no good argument for making the safe path the one you have to
     remember to ask for. So backup is ON by default; -NoBackup opts out.

     This lesson was paid for. On 2026-08-12 this script cleared 282,527
     events on MYMACHINE with no backup in place, and they are not recoverable.
     That is why the default flipped.

     Scope of the export: only channels that actually hold events. Exporting
     the ~1000 empty ones would produce a directory of near-identical 68KB
     stubs that obscure the handful of files you would ever actually open.

     What it is NOT: this is a point-in-time snapshot, not an archive
     strategy. Nothing here rotates or prunes old backup folders -- if you
     run this weekly, prune D:\...\Backups yourself.

 10. --help and -h work, because people type them.
     ---------------------------------------------------------------
     PowerShell's own answer to "what does this do?" is Get-Help, and its own
     spelling is -Help. But anyone arriving from a shell types --help or -h
     first, and getting a red parameter-binding error for that is a bad first
     impression on a script that deletes things.

     Two quirks of the binder make it work, and both are worth knowing before
     touching the param block:
       - PowerShell strips ONE leading dash when matching a parameter, so
         `--help` is looked up under the name "-help". An alias spelled
         literally '-help' is therefore what catches it.
       - An EXACT alias match beats a PREFIX match. Without the explicit 'v'
         alias, `-v` binds to the built-in -Verbose and is silently swallowed
         -- the script would run, not report its version. Measured, not
         assumed: a param block without that alias bound -v to -Verbose.

     Both flags return before the elevation check on purpose. Asking a script
     what it is must never raise a UAC prompt.

 11. Consent to a NUMBER, not to a category.
     ---------------------------------------------------------------
     The gate in #6 originally asked for YES before any count was on screen.
     It described the action ("all existing events") but never its size, so
     the operator was approving a category. On 2026-08-12 that gate approved
     the deletion of 282,527 events without that figure ever being displayed.

     Enumeration therefore happens BEFORE the prompt, and the prompt quotes
     the real number: "Type YES to export and then delete 282,527 events."
     The cost is a couple of seconds of Get-WinEvent; the benefit is that the
     operator's attention is spent on a fact rather than an abstraction.

     The prompt also changes shape with the stakes: with a backup it says
     "export and then delete", with -NoBackup it says "PERMANENTLY DELETE
     ... with NO backup". Same keystroke, different meaning -- the wording
     should not blur them.

     Known limitation, stated rather than hidden: the count is a snapshot.
     Logs keep growing between the prompt and the loop, so the number cleared
     will be slightly higher than the number quoted. It is accurate to the
     moment of asking, which is the moment that matters for consent.

--------------------------------------------------------------------------------
  USAGE
--------------------------------------------------------------------------------
      Double-click Reset-EventLogs.bat            (friendliest)
  or  right-click this file -> Run with PowerShell
  or  pwsh -File .\Reset-EventLogs.ps1 -MaxSizeBytes 20MB
  or  pwsh -File .\Reset-EventLogs.ps1 -Force      (unattended, no prompt)
  or  pwsh -File .\Reset-EventLogs.ps1 -DryRun     (report only, changes nothing)
  or  pwsh -File .\Reset-EventLogs.ps1 -BackupOnly (export .evtx, clear nothing)
  or  pwsh -File .\Reset-EventLogs.ps1 -NoBackup   (old behaviour: wipe, no export)

  Backups land in .\Backups\<yyyy-MM-dd_HHmmss>\ next to this script unless
  -BackupTo says otherwise. Reopen one with: Event Viewer -> Action -> Open
  Saved Log, or  Get-WinEvent -Path .\Backups\<stamp>\Security.evtx

================================================================================
#>

[CmdletBinding()]
param(
    # --- Informational flags (see philosophy #10) ---------------------------
    # The aliases are what make the GNU-style spellings work. PowerShell strips
    # ONE leading dash when matching, so '--help' is looked up as the name
    # "-help" -- hence the literal '-help' alias, odd as it looks. And an EXACT
    # alias match beats a PREFIX match, which is the only reason '-v' reaches
    # Version instead of being swallowed by the built-in -Verbose.
    [Alias('h','-help')][switch]$Help,
    [Alias('v','-version')][switch]$Version,

    # Max size applied to every channel, in bytes. Default 20 MB (see #3).
    # This is a CEILING for future growth, not a trim target.
    [int]$MaxSizeBytes = 20MB,

    # Skip the interactive confirmation. Opt-in only, for automation (see #6).
    # Combined with -DryRun there is no confirmation to skip, so it only
    # suppresses the trailing "Press Enter" pause -- useful when the output is
    # being piped or read by something other than a human at a console.
    [switch]$Force,

    # Report what WOULD happen and exit. Issues no sl/cl commands (see #8).
    [switch]$DryRun,

    # Where the .evtx exports go. Default: .\Backups\<timestamp> beside this
    # script. Created if missing (see #9).
    [string]$BackupTo,

    # Opt OUT of the backup. Restores the original wipe-with-no-net behaviour.
    # Kept because it is occasionally what you want -- never because it is safe.
    [switch]$NoBackup,

    # Export only. Resizes nothing, clears nothing. Needs admin (reading
    # Security requires it) but is entirely non-destructive.
    [switch]$BackupOnly
)

$ScriptVersion = '1.4.0'

# --- Informational flags exit before ANYTHING else (philosophy #10) ----------
# Deliberately above the elevation check: asking a script what it does must
# never trigger a UAC prompt. --help is a question, not an operation.
if ($Version) {
    Write-Host "Reset-EventLogs.ps1 $ScriptVersion"
    return
}

if ($Help) {
    Write-Host @"

Reset-EventLogs.ps1 $ScriptVersion
Back up, resize and clear every Windows event log channel on this machine.

USAGE
  Reset-EventLogs.ps1 [-MaxSizeBytes <bytes>] [-BackupTo <dir>]
                      [-DryRun] [-BackupOnly] [-NoBackup] [-Force]

  Per channel, in order:  export .evtx  ->  set max size  ->  clear.

OPTIONS
  -h, --help            Show this help and exit.
  -v, --version         Show version and exit.

  -DryRun               Report what would happen. Changes nothing, needs no
                        admin rights. Run this first when unsure.
  -BackupOnly           Export .evtx files only. Resizes and clears nothing.
  -NoBackup             Skip the export. The logs are then unrecoverable.
  -BackupTo <dir>       Where exports go.
                        Default: .\Backups\<yyyy-MM-dd_HHmmss>
  -MaxSizeBytes <n>     Max size per channel. Default 20MB. Accepts PowerShell
                        size suffixes: 20MB, 1GB.
                        NOTE: this is a CEILING for future growth, not a trim
                        target. It never deletes anything by itself.
  -Force                Skip the YES confirmation. For automation only.

EXAMPLES
  Reset-EventLogs.ps1 -DryRun                  See the blast radius, safely.
  Reset-EventLogs.ps1 -BackupOnly              Snapshot the logs, touch nothing.
  Reset-EventLogs.ps1 -MaxSizeBytes 20MB       Back up, cap at 20MB, clear.
  Reset-EventLogs.ps1 -Force -NoBackup         Unattended wipe, no net.

NOTES
  Clearing is irreversible; the export is the only way back. Windows cannot
  delete events by date -- clear is all-or-nothing. Elevation is requested
  automatically when needed. Failures on disabled/locked channels are normal.
  Backup folders are never pruned; clean .\Backups yourself.

"@
    return
}

# -NoBackup and -BackupOnly are contradictory instructions; refuse rather than
# silently privileging one, since guessing wrong here destroys data.
if ($NoBackup -and $BackupOnly) {
    Write-Host "-NoBackup and -BackupOnly cannot be combined." -ForegroundColor Red
    return
}
$doBackup = -not $NoBackup

# --- Self-elevate if not already administrator (philosophy #6) --------------
# Resizing/clearing channels requires admin. Rather than fail with an obscure
# access error, we relaunch ourselves elevated and hand our own args across.
# A dry run changes nothing, so it needs no rights and gets no UAC prompt (#8).
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $DryRun -and
    -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Not elevated -- relaunching with UAC..." -ForegroundColor Yellow
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`"",
                 '-MaxSizeBytes',$MaxSizeBytes)
    if ($Force)      { $argList += '-Force' }
    if ($NoBackup)   { $argList += '-NoBackup' }
    if ($BackupOnly) { $argList += '-BackupOnly' }
    if ($BackupTo)   { $argList += @('-BackupTo',"`"$BackupTo`"") }
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList
    return   # the elevated copy does the real work; this one exits.
}

$sizeMB = [math]::Round($MaxSizeBytes / 1MB, 2)

# Resolve the backup folder once, up front, so the banner can state exactly
# where the data is going before consent is given -- not after (#6, #9).
if ($doBackup) {
    if (-not $BackupTo) {
        $BackupTo = Join-Path $PSScriptRoot ('Backups\{0}' -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
    }
}

# --- Enumerate BEFORE asking (philosophy #11) -------------------------------
# This must happen ahead of the consent gate, not after it. Asking someone to
# approve "all events" is asking them to approve a category; asking them to
# approve "282,527 events" is asking them to approve a fact. Only the second
# is informed consent, and it costs a couple of seconds of Get-WinEvent.
#
# Two enumerations, because they see different things (measured, see #8):
#   wevtutil el          -> every channel that exists           (~1217)
#   Get-WinEvent -ListLog-> only those readable/enumerable      (~472)
# The record counts only exist in the second, so that is what the gate quotes.
Write-Host "Enumerating channels..." -ForegroundColor DarkGray
$logs  = wevtutil el
$state = @{}
Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
    ForEach-Object { $state[$_.LogName] = $_ }

$populated  = @($state.Values | Where-Object RecordCount -gt 0)
$eventCount = ($populated | Measure-Object RecordCount -Sum).Sum
if (-not $eventCount) { $eventCount = 0 }

# --- Declare intent plainly before doing anything irreversible (philosophy #6)
Write-Host ""
Write-Host "=== Reset Windows Event Logs ===" -ForegroundColor Cyan
Write-Host ("Found {0} channels; {1} of them hold {2:N0} events right now." -f
            $logs.Count, $populated.Count, $eventCount) -ForegroundColor White
Write-Host ""
if ($BackupOnly) {
    Write-Host "BACKUP ONLY -- every channel holding events will be exported to:" -ForegroundColor White
    Write-Host "  $BackupTo" -ForegroundColor Cyan
    Write-Host "Nothing will be resized and nothing will be cleared." -ForegroundColor White
} else {
    Write-Host "For EVERY event log channel on this machine, this will:" -ForegroundColor White
    if ($doBackup) {
        Write-Host "  0. EXPORT it to .evtx first, under:" -ForegroundColor Green
        Write-Host "       $BackupTo" -ForegroundColor Green
    } else {
        Write-Host "  0. NO BACKUP -- -NoBackup was specified (see philosophy #9)" -ForegroundColor Red
    }
    Write-Host "  1. Set max size to $sizeMB MB (overwrite oldest, no auto-backup)" -ForegroundColor White
    Write-Host "  2. CLEAR it now -- all existing events permanently deleted" -ForegroundColor White
}
Write-Host ""
if ($DryRun) {
    Write-Host "DRY RUN -- nothing will be changed. Report only." -ForegroundColor Yellow
} elseif ($BackupOnly) {
    Write-Host "Non-destructive: this run only reads and writes files." -ForegroundColor Green
} elseif ($doBackup) {
    Write-Host "Reversible ONLY as far as the export above. (Clear logs ID 1102/1104.)" -ForegroundColor Yellow
} else {
    Write-Host "This is IRREVERSIBLE. (The clear itself is logged: ID 1102/1104.)" -ForegroundColor Red
}
Write-Host ""

# -BackupOnly destroys nothing, so it does not need the destructive-action gate.
if (-not $Force -and -not $DryRun -and -not $BackupOnly) {
    # The prompt states the actual number, not the category (philosophy #11).
    # Wording differs by whether there is a net: with a backup this is a move,
    # without one it is a deletion, and the prompt should not blur the two.
    $prompt = if ($doBackup) {
        "Type YES to export and then delete {0:N0} events" -f $eventCount
    } else {
        "Type YES to PERMANENTLY DELETE {0:N0} events with NO backup" -f $eventCount
    }

    # -cne = case-SENSITIVE compare: only the exact string YES proceeds.
    $answer = Read-Host $prompt
    if ($answer -cne 'YES') {
        Write-Host "Aborted. Nothing was changed." -ForegroundColor Yellow
        return
    }
}

# --- The work loop (philosophy #2 and #5) -----------------------------------
# One pass over every channel. Size then clear, independently, counting the
# outcome of each so the summary is truthful. Failures are silenced, not fatal.
# $logs and $state were gathered before the gate (#11) and are reused here --
# note this means the counts quoted at the prompt are a snapshot, and the logs
# have kept growing since. That drift is unavoidable and harmless.
$total     = 0
$resized   = 0
$cleared   = 0
$skipped   = 0
$exported  = 0
$exportErr = 0

if ($DryRun) { $plan = [System.Collections.Generic.List[object]]::new() }

# Create the destination once, before the loop, so a bad path fails loudly
# NOW rather than after the first channel has already been cleared.
if ($doBackup -and -not $DryRun) {
    try {
        $null = New-Item -ItemType Directory -Path $BackupTo -Force -ErrorAction Stop
    } catch {
        Write-Host "Cannot create backup folder: $BackupTo" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "Refusing to clear anything without a place to put the backup." -ForegroundColor Red
        return
    }
}

foreach ($log in $logs) {
    $total++

    if ($DryRun) {
        # Record the intent; issue nothing. Note $state lookups may be $null.
        $cur = $state[$log]
        $plan.Add([pscustomobject]@{
            LogName      = $log
            Records      = if ($cur) { $cur.RecordCount } else { $null }
            CurrentMB    = if ($cur) { [math]::Round($cur.MaximumSizeInBytes/1MB,2) } else { $null }
            NewMB        = $sizeMB
            SizeChange   = if     (-not $cur)                              { 'unknown' }
                           elseif ($cur.MaximumSizeInBytes -gt $MaxSizeBytes) { 'SHRINK' }
                           elseif ($cur.MaximumSizeInBytes -lt $MaxSizeBytes) { 'grow'   }
                           else                                              { 'same'   }
            # Resize and clear succeed INDEPENDENTLY (#2), so predict them
            # separately. Measured on MYMACHINE 2026-08-12: of 1217 channels,
            # only the 472 that Get-WinEvent can enumerate accepted `sl`,
            # while `cl` succeeded on 1213 -- including disabled ones. So
            # readability predicts the RESIZE; it says nothing about the CLEAR.
            WouldResize  = if ($cur) { 'yes' } else { 'no (not enumerable)' }
            WouldClear   = 'yes (expected)'
            WouldExport  = if (-not $doBackup)      { 'no (-NoBackup)' }
                           elseif ($cur.RecordCount -gt 0) { 'yes' }
                           else                     { 'no (empty)' }
        })
        continue
    }

    $cur = $state[$log]

    # (0) Export BEFORE anything destructive (philosophy #9). Only channels
    #     that actually hold events; see #9 for why empties are skipped.
    if ($doBackup -and $cur -and $cur.RecordCount -gt 0) {
        # Channel names contain '/' and '%4', neither of which is a legal file
        # name. Flatten to a readable, collision-free name rather than dropping
        # the characters (which would merge Foo/Admin and Foo/Operational).
        $safe = ($log -replace '[\\/:*?"<>|]', '-')
        $dest = Join-Path $BackupTo "$safe.evtx"

        wevtutil epl "$log" "$dest" /ow:true 2>$null
        if ($LASTEXITCODE -eq 0) { $exported++ } else { $exportErr++ }
    }

    if ($BackupOnly) { continue }   # export-only run stops here per channel

    # (1) Set size + overwrite policy + no auto-backup. Expected to fail on
    #     disabled/locked/analytic channels -- that's fine (philosophy #5).
    wevtutil sl "$log" /ms:$MaxSizeBytes /rt:false /ab:false 2>$null
    if ($LASTEXITCODE -eq 0) { $resized++ }

    # (2) Clear now. Independent of the resize above (philosophy #2).
    wevtutil cl "$log" 2>$null
    if ($LASTEXITCODE -eq 0) { $cleared++ } else { $skipped++ }
}

# --- Dry run report, then stop before touching anything (philosophy #8) ------
if ($DryRun) {
    $withData  = $plan | Where-Object { $_.Records -gt 0 }
    $atRisk    = ($withData | Measure-Object Records -Sum).Sum
    $shrinking = $plan | Where-Object SizeChange -eq 'SHRINK'
    $noResize  = $plan | Where-Object WouldResize -like 'no*'

    Write-Host "=== DRY RUN -- nothing was changed ===" -ForegroundColor Yellow
    Write-Host ("Channels found            : {0}" -f $total)
    Write-Host ("Channels holding events   : {0}" -f $withData.Count)
    if ($doBackup) {
        Write-Host ("Events that would be SAVED: {0} across {1} .evtx file(s)" -f $atRisk, $withData.Count) -ForegroundColor Green
        Write-Host ("Backup destination        : {0}" -f $BackupTo) -ForegroundColor Green
    } else {
        Write-Host ("EVENTS THAT WOULD BE LOST : {0}  (-NoBackup)" -f $atRisk) -ForegroundColor Red
    }
    Write-Host ("Would be resized          : {0}" -f ($total - $noResize.Count))
    Write-Host ("Resize likely to fail     : {0}  (normal -- see philosophy #5)" -f $noResize.Count)
    Write-Host ("Would be cleared          : {0}  (clear succeeds where resize does not)" -f $total)
    Write-Host ""

    Write-Host "Top 20 channels by events that would be destroyed:" -ForegroundColor Cyan
    $withData | Sort-Object Records -Descending | Select-Object -First 20 |
        Format-Table LogName, Records, CurrentMB, NewMB, SizeChange, WouldResize -AutoSize

    # Shrinking a cap is the one outcome that quietly reduces future capacity,
    # so it gets its own callout rather than hiding in the table above (#3).
    if ($shrinking) {
        Write-Host ("{0} channel(s) would have their cap REDUCED to {1} MB:" -f $shrinking.Count, $sizeMB) -ForegroundColor Yellow
        $shrinking | Sort-Object CurrentMB -Descending | Select-Object -First 15 |
            Format-Table LogName, CurrentMB, NewMB -AutoSize
        Write-Host "Lowering a cap does not delete anything by itself; it limits FUTURE" -ForegroundColor DarkGray
        Write-Host "retention. Raise -MaxSizeBytes if these channels matter to you." -ForegroundColor DarkGray
        Write-Host ""
    }

    Write-Host "Re-run without -DryRun to apply." -ForegroundColor Cyan
    if (-not $Force) { Read-Host "Press Enter to close" | Out-Null }
    return
}

# --- Honest summary (philosophy #7) -----------------------------------------
Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host ("Channels found  : {0}" -f $total)

if ($doBackup) {
    $files = @(Get-ChildItem -Path $BackupTo -Filter *.evtx -ErrorAction SilentlyContinue)
    $mb    = [math]::Round((($files | Measure-Object Length -Sum).Sum) / 1MB, 2)
    Write-Host ("Exported        : {0} channel(s), {1} file(s), {2} MB" -f $exported, $files.Count, $mb) -ForegroundColor Green
    Write-Host ("Backup folder   : {0}" -f $BackupTo) -ForegroundColor Green
    if ($exportErr) {
        # Export failures matter more than resize/clear failures: they are the
        # difference between recoverable and not. Never silence these (#7).
        Write-Host ("Export FAILED   : {0} channel(s) -- their events were NOT saved" -f $exportErr) -ForegroundColor Red
    }
}

if (-not $BackupOnly) {
    Write-Host ("Resized to {0}MB : {1}" -f $sizeMB, $resized)
    Write-Host ("Cleared         : {0}" -f $cleared)
    Write-Host ("Skipped/failed  : {0}  (disabled or locked channels -- normal)" -f $skipped)
}
Write-Host ""

if ($BackupOnly) {
    Write-Host "Backup only -- nothing was resized or cleared. Reopen a file with:" -ForegroundColor Cyan
    Write-Host "  Get-WinEvent -Path '<file>.evtx'   or   Event Viewer -> Open Saved Log" -ForegroundColor DarkGray
    if (-not $Force) { Read-Host "Press Enter to close" | Out-Null }
    return
}

Write-Host "Logs repopulate instantly, so small counts below are EXPECTED, not failure:" -ForegroundColor DarkGray
Get-WinEvent -ListLog * -ErrorAction SilentlyContinue |
    Where-Object RecordCount -gt 0 |
    Sort-Object RecordCount -Descending |
    Select-Object -First 10 LogName, RecordCount |
    Format-Table -AutoSize

if (-not $Force) { Read-Host "Press Enter to close" | Out-Null }
