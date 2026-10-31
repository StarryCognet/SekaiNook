# Build Flutter Web locally and upload it to the server.
#
# WHY LOCAL BUILDS: the server has no Flutter SDK (we deliberately dropped it
# when containerizing), and the old on-server incremental cache once produced
# a broken main.dart.js. See deploy/reinstall.md.
#
# MUST STAY PURE ASCII. Windows PowerShell 5.1 decodes BOM-less files with the
# system ANSI codepage (GBK here). Non-ASCII characters shift bytes and can
# swallow following quotes, which surfaces as bogus syntax/security errors.
# That is exactly what happened to server/pull-backup.ps1 before we fixed it.
#
# Usage:
#   .\server\deploy-web.ps1
#   .\server\deploy-web.ps1 -SkipBuild        # only re-upload app\build\web
#   .\server\deploy-web.ps1 -ApiBase http://140.143.240.238
#
# Tip: run it through server\deploy-web.cmd if your execution policy blocks .ps1.

[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [string]$ApiBase     = 'http://140.143.240.238',
    [string]$KeyPath     = "$env:USERPROFILE\.ssh\txysh.pem",
    [string]$Server      = 'ubuntu@140.143.240.238',
    [string]$RemoteWebDir = '/opt/sekainook/web'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

function Step([string]$msg) {
    Write-Host ''
    Write-Host ">> $msg" -ForegroundColor Cyan
}

if (-not (Test-Path $KeyPath)) { throw "SSH key not found: $KeyPath" }

# ---------- 1. build ----------
if (-not $SkipBuild) {
    Step 'flutter build web (base-href=/sekainook/)'
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    $flutterExe = if ($cmd) { $cmd.Source } else { 'D:\flutter\bin\flutter.bat' }
    if (-not (Test-Path $flutterExe)) { throw "flutter not found: $flutterExe" }
    Push-Location "$Root\app"
    try {
        & $flutterExe build web --no-pub --no-web-resources-cdn --base-href /sekainook/ --dart-define="API_BASE=$ApiBase"
        if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
}

$webDir = "$Root\app\build\web"
if (-not (Test-Path (Join-Path $webDir 'index.html'))) {
    throw "build output missing: $webDir\index.html"
}

# ---------- 2. pack ----------
Step 'packing build\web'
$tgz = Join-Path $env:TEMP 'web-sekainook.tgz'
if (Test-Path $tgz) { Remove-Item $tgz -Force }
& tar -czf $tgz -C $webDir .
if ($LASTEXITCODE -ne 0) { throw 'tar failed' }
Write-Host ('   {0:N1} MB' -f ((Get-Item $tgz).Length / 1MB))

# ---------- 3. upload ----------
Step "uploading to $Server (inbound traffic is free, this takes seconds)"
& scp -i $KeyPath -o BatchMode=yes $tgz "${Server}:/tmp/web-sekainook.tgz"
if ($LASTEXITCODE -ne 0) { throw 'scp failed' }

# ---------- 4. replace in place ----------
# WHY NOT mv: /opt/sekainook/web is a docker bind mount. Replacing the
# directory itself swaps the inode, and the container keeps serving the old
# (now unlinked) tree. Deleting the contents and extracting into it works.
Step "replacing $RemoteWebDir (in place, keeps the bind mount alive)"
$remote = @'
set -e
WEB=__WEBDIR__
echo "before: $(find "$WEB" -mindepth 1 | wc -l) entries"
sudo find "$WEB" -mindepth 1 -delete
sudo tar xzf /tmp/web-sekainook.tgz -C "$WEB"
sudo chown -R ubuntu:ubuntu "$WEB"
echo "after:  $(find "$WEB" -mindepth 1 | wc -l) entries"
grep -o '<base href="[^"]*"' "$WEB/index.html" || true
'@
$remote = $remote.Replace('__WEBDIR__', $RemoteWebDir)
$remote | & ssh -i $KeyPath -o BatchMode=yes $Server 'bash -s'
if ($LASTEXITCODE -ne 0) { throw 'remote replace failed' }

# ---------- 5. verify ----------
Step 'verify live version'
$url = 'http://140.143.240.238/sekainook/version.json'
try {
    $v = Invoke-RestMethod -Uri $url -TimeoutSec 15 -UseBasicParsing
    Write-Host ('   live: {0}+{1}  ({2})' -f $v.version, $v.build_number, $url) -ForegroundColor Green
} catch {
    Write-Host "   WARN could not reach $url : $_" -ForegroundColor Yellow
}

Write-Host ''
Write-Host 'DONE  http://140.143.240.238/sekainook/' -ForegroundColor Green
