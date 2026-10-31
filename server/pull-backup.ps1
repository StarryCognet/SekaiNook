# ============================================================
# Pull a complete SekaiNook snapshot from the server to this PC.
#
# Four steps: upload packer -> pack on server -> scp back -> verify SHA256
#
# Usage (from repo root E:\Git\SekaiNook):
#   .\server\pull-backup.cmd                    # Desktop\sekainook-backup\<timestamp>\
#   .\server\pull-backup.cmd -Dest E:\backup
#   .\server\pull-backup.cmd -WithDaily         # also pull the daily backups
#
# !! THIS FILE MUST STAY PURE ASCII !!
# Windows PowerShell 5.1 decodes BOM-less files with the system ANSI codepage
# (GBK on Chinese Windows). Non-ASCII characters become mojibake, and some
# byte sequences swallow the following quote, turning the script into a parse
# error. That is why every message below is English. Do not add Chinese here;
# if you must, save the file as UTF-8 WITH BOM instead.
# ============================================================
param(
    [string]$SshTarget = "ubuntu@140.143.240.238",
    [string]$Dest      = (Join-Path $env:USERPROFILE "Desktop\sekainook-backup"),
    [switch]$WithDaily,
    [switch]$SkipUpload
)

$ErrorActionPreference = 'Stop'

function Say {
    param([string]$Msg, [string]$Color = 'Cyan')
    Write-Host $Msg -ForegroundColor $Color
}

function Need {
    param([string]$Cmd)
    if (-not (Get-Command $Cmd -ErrorAction SilentlyContinue)) {
        throw "Command '$Cmd' not found. The OpenSSH client is required (Windows 10+ ships it)."
    }
}

Need ssh
Need scp

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dir = Join-Path $Dest $stamp
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$packer = Join-Path $PSScriptRoot 'full-backup.sh'
if (-not (Test-Path $packer)) { throw "Packer script not found: $packer" }

# ---------- 1. upload ----------
if (-not $SkipUpload) {
    Say "[1/4] Uploading packer to the server..."
    scp $packer "${SshTarget}:/tmp/full-backup.sh"
    if ($LASTEXITCODE -ne 0) { throw "scp upload failed (check network / IP / password)" }
}

# ---------- 2. pack on server ----------
Say "[2/4] Packing on the server (sudo password will be asked; this takes a while)..."
ssh $SshTarget "chmod +x /tmp/full-backup.sh && sudo /tmp/full-backup.sh /tmp"
if ($LASTEXITCODE -ne 0) { throw "Packing on the server failed. Read the [snapshot] log above." }

# ---------- 3. fetch ----------
Say "[3/4] Locating the newest archive..."
$remotePath = (ssh $SshTarget "ls -t /tmp/sekainook-full-*.tar.gz 2>/dev/null | head -1")
if (-not $remotePath) { throw "No /tmp/sekainook-full-*.tar.gz found on the server." }
$remotePath = $remotePath.Trim()
$leaf = Split-Path $remotePath -Leaf
Say "      -> $leaf"

scp "${SshTarget}:$remotePath" $dir
if ($LASTEXITCODE -ne 0) { throw "scp download of the archive failed" }
scp "${SshTarget}:$remotePath.sha256" $dir
if ($LASTEXITCODE -ne 0) { throw "scp download of the .sha256 file failed" }

# ---------- 4. verify ----------
Say "[4/4] Verifying SHA256 locally..."
$file = Join-Path $dir $leaf
$actual = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
$expected = (Get-Content "$file.sha256" -TotalCount 1).Trim().Split(' ')[0].ToLower()
if ($actual -ne $expected) {
    throw "Checksum mismatch: local $actual != remote $expected. The transfer was corrupted; run again."
}
Say "      OK $($actual.Substring(0,16))..." 'Green'

# ---------- optional: daily backups ----------
if ($WithDaily) {
    Say "[extra] Pulling /opt/sekainook-backups (daily db + images)..."
    $dailyDir = Join-Path $dir 'daily'
    New-Item -ItemType Directory -Force -Path $dailyDir | Out-Null
    # -O forces the legacy scp protocol so the wildcard is expanded by the
    # remote shell; the default SFTP mode does not glob on the server side.
    scp -O -r "${SshTarget}:/opt/sekainook-backups/*" $dailyDir
    if ($LASTEXITCODE -ne 0) {
        Say "      [warn] daily backup pull failed; you can scp it separately later" 'Yellow'
    }
}

# ---------- summary ----------
Say ""
Say "Done -> $dir" 'Green'
Get-ChildItem $dir | Sort-Object Name | Format-Table `
    Name, @{n='MB'; e={[math]::Round($_.Length/1MB, 1)}}, LastWriteTime -AutoSize

Say "WARNING: the archive contains .env (ADMIN_PASSWORD) and sudoers." 'Yellow'
Say "         Keep it on this machine only. Never upload it anywhere." 'Yellow'
Say "To restore on a new machine: read RESTORE.md inside the archive." 'Yellow'
