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

    # 跳过「线上版本日志版本号一致」检查（只在救急回滚、日志确实来不及同步时用）
    [switch]$SkipChangelogCheck,

    [string]$Bucket = 'flclash-updates',
    [string]$Prefix = 'sekainook',
    [string]$PublicBaseUrl = 'https://pub.starrymiku.com'
)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

# ---- 前置检查：签名材料必须在构建之前就位（R-6）----
# 以前这段放在构建之后、而且只在没传 -SkipBuild 时才算，于是「忘了拷 jks」要等
# 构建几分钟、读到 APK 才炸；-SkipBuild 走手工包那条路时检查干脆形同虚设。
if (-not $env:ANDROID_HOME) {
    throw "没有设 ANDROID_HOME。先执行 `$env:ANDROID_HOME='E:\IDE\Android\Sdk'`（按本机实际路径改）再发版"
}
if (-not $SkipBuild) {
    $keyProps = Join-Path (Get-Location) 'android\app\key.properties'
    if (-not (Test-Path $keyProps)) {
        throw "缺少 android/app/key.properties（正式签名）—— 现在打出来的会是 debug 包。补上 key.properties + sekainook-release.jks 再发（两个都在 .gitignore 里，换机器要手动拷）"
    }
    $keystore = Join-Path (Get-Location) 'android\app\sekainook-release.jks'
    if (-not (Test-Path $keystore)) {
        throw "缺少 android/app/sekainook-release.jks（签名库）—— 同上，签名材料在 .gitignore 里，丢了就再也无法覆盖升级，只能让全家卸载重装"
    }
}

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
# 直接失败 ——「安装失败(-7) 与已安装应用签名不同」。
# 文件存在性检查已经挪到构建之前（见脚本顶部）；这里用 apksigner 复核成品，并把证书
# 指纹钉死：换过 keystore 的话，新包能装上、老用户却永远装不上，必须在发出去之前拦住。
$expectedCertSha256 = 'dafbd0ca318831669ec15ae2c9fd0881aa293d27d8d11ae73606ceb40b91296a'

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
    $sha = ([regex]::Match($certs, 'SHA-256 digest:\s*([0-9a-fA-F:]+)').Groups[1].Value).Replace(':', '').ToLower()
    if (-not $sha) {
        Write-Warning "apksigner 没读到证书指纹，无法校验签名一致性"
    } elseif ($sha -ne $expectedCertSha256) {
        throw "签名证书与预期不符（得到 $sha，预期 $expectedCertSha256）。换了 keystore 之后老用户覆盖安装会失败(-7)，只能卸载重装 —— 确认是无意换了库，就改脚本里的固定值并接受老用户重装"
    } else {
        Write-Host "[sign] 非 debug 签名，证书 SHA-256 与预期一致" -ForegroundColor Green
    }
} else {
    Write-Warning "没找到 apksigner，跳过签名校验 —— 请自己确认这个包不是 debug 签名"
}

# ---- 版本递增闸门（R-1）----
# versionCode 不递增 = 手机上「检查更新」永远认为已是最新，新包静默不生效。
# 2026-10 就踩过一次：改了代码、忘了改 pubspec 的 +N，家里人手机上毫无变化。
#
# 读清单必须直连且 fail-closed：
#   * 本机常年开着 HTTP_PROXY=127.0.0.1:7890，走代理读公网清单会超时；
#   * Windows PowerShell 5.1 没有 `Invoke-RestMethod -NoProxy`（那是 PS 7 的参数），
#     传了会直接报参数错误，被 catch 吃掉 → 闸门静默失效、照样发版（2026-10-25 实测）。
# 所以改用 WebClient 且 Proxy=$null；除「清单 404（首次发布）」外，读不到就中止发布。
$previous = $null
try {
    $webClient = New-Object System.Net.WebClient
    $webClient.Proxy = $null  # 直连
    try {
        $rawManifest = $webClient.DownloadString("$PublicBaseUrl/$Prefix/latest.json")
        $previous = $rawManifest | ConvertFrom-Json
    } finally {
        $webClient.Dispose()
    }
} catch [System.Net.WebException] {
    $statusCode = $null
    if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
    if ($statusCode -eq 404) {
        Write-Warning "线上还没有清单（首次发布？）—— 跳过 versionCode 递增检查"
    } else {
        throw "读不到线上清单（HTTP $statusCode / $($_.Exception.Message)）—— 版本递增闸门失效，不能发。确认网络后再试"
    }
} catch {
    throw "读不到线上清单（$($_.Exception.Message)）—— 版本递增闸门失效，不能发。确认网络后再试"
}
if ($previous -and $null -ne $previous.versionCode) {
    $prevCode = [int]$previous.versionCode
    if ($main.VersionCode -le $prevCode) {
        throw "versionCode 没有递增（线上 $prevCode，本包 $($main.VersionCode)）。把 app/pubspec.yaml 的 version 后面 +N 改大再重打 —— 否则手机上不会收到这次更新"
    }
    Write-Host "[version] $($previous.versionName)($prevCode) → $($main.VersionName)($($main.VersionCode))" -ForegroundColor Green
}

# ---- 版本日志闸门（R-3）----
# 只发 APK 不同步 D1 版本日志时，更新弹窗里是新包、日志却还停在旧版本。
# 先 sync 再发是铁律；这里用线上 /api/changelog 的最新版本号兜底断言。
if (-not $SkipChangelogCheck) {
    $remoteChangelogVersion = $null
    try {
        $webClient = New-Object System.Net.WebClient
        $webClient.Proxy = $null
        try {
            $remoteChangelog = $webClient.DownloadString('https://sn.starrymiku.com/api/changelog') | ConvertFrom-Json
            $remoteChangelogVersion = $remoteChangelog.version
        } finally {
            $webClient.Dispose()
        }
    } catch {
        throw "读不到线上版本日志 /api/changelog（$($_.Exception.Message)）—— 先 npm run changelog:sync 再发版；确实要跳过请加 -SkipChangelogCheck"
    }
    if ($remoteChangelogVersion -ne $main.VersionName) {
        throw "线上版本日志是 $remoteChangelogVersion，本包是 $($main.VersionName) —— 先改 src/config/changelog.ts 并 npm run changelog:sync 再发版（接口缓存 5 分钟，刚同步可等一会重试）；确实要跳过请加 -SkipChangelogCheck"
    }
    Write-Host "[changelog] 线上版本日志已是 $remoteChangelogVersion，与本包一致" -ForegroundColor Green
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

# 版本日志：留空时给一句默认文案，别让更新弹窗出现空白
if (-not $Changelog) { $Changelog = '小修小补，用起来更稳' }

$manifest = [ordered]@{
    versionName = $main.VersionName
    versionCode = $main.VersionCode
    url         = $url
    sha256      = $sha256
    size        = $size
    changelog   = $Changelog
}

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
