# 打一个安卓包、传到 R2、更新 latest.json —— 发版就这一条命令。
#
#   .\tool\publish_apk.ps1 -Changelog "修了花园浇水的一处错算"
#
# 只做四件事：构建 → 从 APK 里读版本号 → 传 APK → 传清单。
# 清单（latest.json）是应用内更新唯一的入口，App 端在 lib/state/update_state.dart。
#
# 前提（一次性的）：wrangler 已登录、R2 桶存在且挂了自定义域，见 docs/android-update.md。
[CmdletBinding()]
param(
    # 版本日志：会原样写进弹窗。可以不填，App 里仍然能看 D1 里的版本日志。
    [string]$Changelog = '',

    # 跳过构建，直接传一个已经打好的包（配合 -ApkPath）
    [switch]$SkipBuild,

    # 直接用这个 APK，不去 build 目录里找
    [string]$ApkPath = '',

    # 打通用包（三种 ABI 都在里面，约 60MB）。默认只装 arm64 那一份，约 22MB。
    [switch]$Universal,

    [string]$Bucket = 'flclash-updates',
    [string]$Prefix = 'sekainook',
    [string]$PublicBaseUrl = 'https://pub.starrymiku.com'
)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

function Get-ApkVersionInfo([string]$Path) {
    # versionCode 以 APK 自己为准：pubspec 里的 build number 在
    # 「按 ABI 拆分」的构建里会被 Flutter 加 1000×ABI 偏移，照 pubspec 写清单会永远比本机小。
    $buildTools = Join-Path $env:ANDROID_HOME 'build-tools'
    if (-not (Test-Path $buildTools)) {
        throw "找不到 $buildTools —— 先设 ANDROID_HOME，或把 Android SDK 的 build-tools 装上"
    }
    $aapt2 = Get-ChildItem $buildTools -Directory |
        Sort-Object { [version]$_.Name } -Descending |
        ForEach-Object { Join-Path $_.FullName 'aapt2.exe' } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1
    if (-not $aapt2) { throw "build-tools 里没有 aapt2.exe" }

    $badging = (& $aapt2 dump badging $Path 2>$null) -join "`n"
    $versionName = [regex]::Match($badging, "versionName='([^']+)'").Groups[1].Value
    $versionCode = [regex]::Match($badging, "versionCode='([^']+)'").Groups[1].Value
    if (-not $versionName -or -not $versionCode) {
        throw "从 $Path 里读不到 versionName/versionCode"
    }
    return @{ VersionName = $versionName; VersionCode = [int]$versionCode }
}

function Publish-File([string]$LocalPath, [string]$Key, [string]$ContentType, [string]$CacheControl) {
    Write-Host "  → $Bucket/$Key" -ForegroundColor DarkGray
    # 一定要 --remote：wrangler 4 默认写的是本地模拟存储，公网还是旧的
    & wrangler r2 object put "$Bucket/$Key" --file $LocalPath `
        --content-type $ContentType --cache-control $CacheControl --remote
    if ($LASTEXITCODE -ne 0) { throw "上传失败：$Key" }
}

# 固定「单个包」的两种打法：都不带 ABI 过滤，所以 versionCode 就是 pubspec 里那个数。
# 千万别改成 --split-per-abi：那会给每个包加上 1000×ABI 偏移，版本号就不再单调递增了。
$buildArgs = @('build', 'apk', '--release')
$abiTag = 'arm64-v8a'
if (-not $Universal) {
    $buildArgs += @('--target-platform', 'android-arm64')
} else {
    $abiTag = 'universal'
}

if (-not $SkipBuild) {
    Write-Host "[build] $($buildArgs -join ' ')" -ForegroundColor Cyan
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) { throw "构建失败" }
}

if ($ApkPath) {
    $apk = (Resolve-Path $ApkPath).Path
} else {
    $apk = (Resolve-Path (Join-Path (Get-Location) 'build\app\outputs\flutter-apk\app-release.apk')).Path
}

$main = Get-ApkVersionInfo $apk
Write-Host "[apk] $apk" -ForegroundColor Cyan
Write-Host "[apk] versionName=$($main.VersionName) versionCode=$($main.VersionCode) ($abiTag)"

$fileName = "SekaiNook-$($main.VersionName)-android-$abiTag.apk"
Publish-File $apk "$Prefix/$fileName" 'application/vnd.android.package-archive' 'public, max-age=31536000, immutable'

$sha256 = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
$size = (Get-Item $apk).Length
$url = "$PublicBaseUrl/$Prefix/$fileName"

$manifest = [ordered]@{
    versionName = $main.VersionName
    versionCode = $main.VersionCode
    url         = $url
    sha256      = $sha256
    size        = $size
}
if ($Changelog) { $manifest['changelog'] = $Changelog }

$manifestPath = Join-Path (Get-Location) 'build\latest.json'
$json = $manifest | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($manifestPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[manifest] $manifestPath" -ForegroundColor Cyan
Write-Host $json

# 清单只有 60 秒缓存：新版本一发出去，装上旧版的手机下次打开就能看到
Publish-File $manifestPath "$Prefix/latest.json" 'application/json' 'public, max-age=60'

Write-Host ''
Write-Host "发布完成：$url" -ForegroundColor Green
Write-Host "核对一下：Invoke-RestMethod $PublicBaseUrl/$Prefix/latest.json" -ForegroundColor Green
