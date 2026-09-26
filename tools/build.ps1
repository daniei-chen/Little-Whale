# 小鲸鱼 · 构建（只出 arm64-v8a）
#
# 【为什么只构建 v8a】用户明确要求：只发 arm64-v8a 那一个包。
# 2018 年之后的手机基本都是 arm64，armeabi-v7a 和 x86_64 没有实际用户，
# 每次构建三个包纯属浪费。
#
# 产物命名：小鲸鱼v{版本}.apk
#
# 用法：
#   .\tools\build.ps1                # 构建并拷到桌面
#   .\tools\build.ps1 -OutDir D:\x   # 指定输出目录

param([string]$OutDir = "$env:USERPROFILE\Desktop")

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)  { Write-Host "    OK  $m" -ForegroundColor Green }

# ---- 读配置（地址注入用）----
$cfgPath = Join-Path $Root 'tools\build.config.ps1'
$cfg = @{ UpdateUrl=''; UpdateUrlAlt=''; DownloadPage=''; JavaHome='' }
if (Test-Path $cfgPath) {
  $loaded = & $cfgPath
  foreach ($k in $loaded.Keys) { $cfg[$k] = $loaded[$k] }
}
if ($cfg.JavaHome) { $env:JAVA_HOME = $cfg.JavaHome }

# ---- 版本号 ----
$m = [regex]::Match((Get-Content (Join-Path $Root 'pubspec.yaml') -Raw),
                    '(?m)^version:\s*([0-9.]+)\+(\d+)')
if (-not $m.Success) { throw 'pubspec.yaml 里找不到 version' }
$ver = $m.Groups[1].Value
Say "版本 v$ver（只构建 arm64-v8a）"

# ---- 检查 ----
flutter analyze | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze 没过' }
Ok 'analyze 零问题'
flutter test | Out-Null
if ($LASTEXITCODE -ne 0) { throw '单元测试没过' }
Ok '单元测试全过'

# ---- 构建 ----
# 给 pubspec 加了 assets 之后增量构建偶尔会撞名（errno 183），先清掉
Remove-Item 'build\app\intermediates\flutter' -Recurse -Force -ErrorAction SilentlyContinue

$defines = @()
if ($cfg.UpdateUrl)    { $defines += "--dart-define=UPDATE_URL=$($cfg.UpdateUrl)" }
if ($cfg.UpdateUrlAlt) { $defines += "--dart-define=UPDATE_URL_ALT=$($cfg.UpdateUrlAlt)" }
if ($cfg.DownloadPage) { $defines += "--dart-define=DOWNLOAD_PAGE=$($cfg.DownloadPage)" }

flutter build apk --release --target-platform android-arm64 @defines | Out-Null
if ($LASTEXITCODE -ne 0) { throw '构建失败' }

$built = Join-Path $Root 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $built)) { throw "找不到产物 $built" }

# ---- 按要求的名字拷出去 ----
$name = "小鲸鱼v$ver.apk"
$dest = Join-Path $OutDir $name
Copy-Item $built $dest -Force

$sizeMb = [math]::Round((Get-Item $dest).Length / 1MB, 1)
$md5 = (Get-FileHash $dest -Algorithm MD5).Hash.ToLower()
Write-Host ''
Say "构建完成"
Write-Host "    文件  $name"
Write-Host "    大小  $sizeMb MB"
Write-Host "    MD5   $md5"
Write-Host "    位置  $dest"