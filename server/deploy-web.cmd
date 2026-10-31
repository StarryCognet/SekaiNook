@echo off
REM Wrapper so deploy-web.ps1 runs even when the execution policy blocks unsigned scripts.
REM Keep this file PURE ASCII with CRLF line endings: Windows PowerShell 5.1 + cmd
REM decode BOM-less files with the system ANSI codepage (GBK here), and non-ASCII
REM bytes shift into quote characters, producing bogus syntax errors.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-web.ps1" %*
