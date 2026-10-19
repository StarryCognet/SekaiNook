# 生成安卓正式签名（只用一次，已经跑过了 —— 除非签名库丢了，别动这个脚本）
#
#   .\tool\make_keystore.ps1
#
# 它会：造一个自签名的 PKCS12 签名库 → 写 android/app/key.properties（口令一起写进去）。
# 两个文件都在 .gitignore 里，**请另行备份**：签名换了，装过旧版的手机就只能卸载重装。
#
# 已存在同名签名库时直接报错退出 —— 防止手滑把正在用的签名覆盖掉。
$ErrorActionPreference = 'Stop'

$app = Join-Path $PSScriptRoot '..\android\app'
$jks = Join-Path $app 'sekainook-release.jks'
$propsPath = Join-Path $app 'key.properties'
$alias = 'sekainook'

if (Test-Path $jks) { throw "签名库已存在，拒绝覆盖：$jks" }

$keytool = @(
    (Join-Path $env:JAVA_HOME 'bin\keytool.exe'),
    'C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot\bin\keytool.exe',
    'E:\IDE\Android Studio\jbr\bin\keytool.exe'
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $keytool) { throw '没找到 keytool：设一下 JAVA_HOME，或改脚本里的候选路径' }

# 28 位随机口令（去掉容易看错的 0/o/1/l/I）
$alphabet = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
$bytes = New-Object byte[] 28
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
$pwd = -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })

& $keytool -genkeypair -v -keystore $jks -storetype PKCS12 -keyalg RSA -keysize 2048 `
    -validity 36500 -alias $alias -storepass $pwd -keypass $pwd `
    -dname 'CN=SekaiNook, OU=Personal, O=Personal, L=Unknown, ST=Unknown, C=CN'
if ($LASTEXITCODE -ne 0) { throw "keytool 失败：$LASTEXITCODE" }

@(
    "storePassword=$pwd"
    "keyPassword=$pwd"
    "keyAlias=$alias"
    "storeFile=sekainook-release.jks"
) | Set-Content -Path $propsPath -Encoding UTF8

Write-Host "[签名库] $jks" -ForegroundColor Green
Write-Host "[口令]   $propsPath" -ForegroundColor Green
Write-Host "[别名]   $alias"
Write-Host "[sha256] $((Get-FileHash $jks -Algorithm SHA256).Hash)"
Write-Host '备份这两个文件：丢了就再也无法覆盖升级。' -ForegroundColor Yellow
