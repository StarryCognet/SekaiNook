@echo off
rem ============================================================
rem  Wrapper for pull-backup.ps1
rem
rem  Why: Windows PowerShell refuses to run unsigned .ps1 files by
rem  default (PSSecurityException / UnauthorizedAccess). A .cmd file is
rem  not subject to that policy, so we launch PowerShell with
rem  -ExecutionPolicy Bypass for the child process only.
rem
rem  Usage (from the repo root E:\Git\SekaiNook):
rem    .\server\pull-backup.cmd
rem    .\server\pull-backup.cmd -Dest E:\backup -WithDaily
rem
rem  Keep this file pure ASCII with CRLF line endings: cmd.exe decodes
rem  batch files with the OEM codepage and chokes on UTF-8 Chinese.
rem ============================================================
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0pull-backup.ps1" %*
set RC=%ERRORLEVEL%
endlocal & exit /b %RC%
