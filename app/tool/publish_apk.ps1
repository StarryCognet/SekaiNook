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
# `--no-pub`：不加它，flutter 会先隐式跑一次 `pub get`，而本机 pub 请求走代理时常
# 直接连不上（`SocketException: 远程计算机拒绝网络连接 ... uri=https://pub.dev/...`），
# 整个发版就在这里断掉。依赖真变了（改过 pubspec 的 dependencies）就先手动跑
# `flutter pub get --offline` 再发版。
$buildArgs = @('build', 'apk', '--release', '--no-pub')
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

# ---- 签名闸门：debug 签名的包绝不能发出去 ----
# 2026-10-19 的教训：git subtree 搬家时 key.properties 与 .jks（两个都在 .gitignore 里）
# 没跟着过来，Gradle 按设计静默退回 debug 签名，2.0.0 发出去后家里人在手机上覆盖安装
# 直接失败 ——「安装失败(-7) 与已安装应用签名不同」。当时 build.gradle.kts 的注释里
# 写着「publish_apk.ps1 会拒绝上传 debug 签名的包」，但这个脚本里并没有那道检查。
if (-not $SkipBuild) {
    $keyProps = Join-Path (Get-Location) 'android\app\key.properties'
    if (-not (Test-Path $keyProps)) {
        throw "缺少 android/app/key.properties（正式签名）—— 现在打出来的会是 debug 包。补上 key.properties + sekainook-release.jks 再发（两个都在 .gitignore 里，换机器要手动拷）"
    }
}

$buildToolsDir = Join-Path $env:ANDROID_HOME 'build-tools'
$apksigner = Get-ChildItem $buildToolsDir -Directory -ErrorAction SilentlyContinue |
    Sort-Object { [version]$_.Name } -Descending |
    ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1
if ($apksigner) {
    $certs = (& $apksigner verify --print-certs $apk 2>&1) -join "`n"
    if ($certs -match 'Android Debug') {
        throw "这个 APK 是 debug 签名，发出去用户手机上会「安装失败(-7) 签名不同」。请补上 android/app/key.properties + sekainook-release.jks 后重打"
    }
    $sha = [regex]::Match($certs, 'SHA-256 digest:\s*([0-9a-fA-F]+)').Groups[1].Value
    Write-Host "[sign] 非 debug 签名（证书 SHA-256 ${sha}）" -ForegroundColor Green
} else {
    Write-Warning "没找到 apksigner，跳过签名校验 —— 请自己确认这个包不是 debug 签名"
}

# 文件名带上内容指纹（sha256 前 8 位）：
# R2 这套资源是 `immutable` + 一年强缓存，同一个 URL 换了内容之后，浏览器 / CDN / 代理
# 仍会继续发旧包 —— 2026-10-19 连踩两次：先是我重打签名后线上同 URL 还是旧的 debug 包，
# 接着家里人手机上应用内更新一直报「安装包校验未通过」（下到的旧包 sha256 对不上清单）。
# 内容变了 URL 就变，从根上绕开缓存，不用再让用户「关掉 VPN 再试」。
$sha256 = (Get-FileHash $apk -Algorithm SHA256).Hash.ToLower()
$fileName = "SekaiNook-$($main.VersionName)-android-$abiTag-$($sha256.Substring(0, 8)).apk"
Publish-File $apk "$Prefix/$fileName" 'application/vnd.android.package-archive' 'public, max-age=31536000, immutable'

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
