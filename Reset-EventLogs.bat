@echo off
REM ============================================================================
REM  Reset-EventLogs.bat  --  double-click launcher for Reset-EventLogs.ps1
REM
REM  Design note (ASH): this .bat exists purely for ergonomics. Double-clicking
REM  a .ps1 does not run it by default on Windows; a .bat does. It launches the
REM  PowerShell script, which then handles its own UAC elevation and its own
REM  YES confirmation. This launcher deliberately holds NO logic of its own --
REM  all behaviour and all safety gates live in one place: the .ps1.
REM
REM  %* forwards every argument through, so the .bat is a full stand-in for the
REM  .ps1 from cmd:  Reset-EventLogs.bat --help
REM                  Reset-EventLogs.bat -DryRun
REM  Double-clicking passes nothing, which is the interactive path as before.
REM ============================================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Reset-EventLogs.ps1" %*
