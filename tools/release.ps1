# 小鲸鱼 · 一键发版
#
# 做四件事：
#   1. 版本号 +1（同时改 pubspec.yaml、lib/config.dart、server/version.json）
#   2. 构建三个 ABI 的 APK
#   3. 提交并推送 —— jsDelivr 会从 GitHub 读 server/version.json，
#      推上去之后所有用户的 App 就能检查到新版本了
#   4. 把 APK 拷到指定目录（默认桌面），方便你上传到服务器
#
# 用法：
#   .\tools\release.ps1 -Notes "新增快手、知乎"                  # 构建号 +1
#   .\tools\release.ps1 -Version 1.1.0 -Notes "..."              # 指定版本号（构建号仍 +1）
#   .\tools\release.ps1 -Notes "..." -DownloadUrl "https://你的域名/app/download/x.apk"
#   .\tools\release.ps1 -Notes "..." -NoPush                     # 只构建，先不推
#
# 注意：APK 下载地址（version.json 里的 url）指向**你自己的服务器** ——
# GitHub Releases 在国内下不动，别往那放。

param(
  [string]$Version = '',
  [Parameter(Mandatory = $true)][string]$Notes,
  [string]$DownloadUrl = '',
  [string]$ApkOutDir = "$env:USERPROFILE\Desktop",
  [switch]$NoPush,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m) { Write-Host "    OK  $m" -ForegroundColor Green }

# ---------------------------------------------------------------- 1. 版本号
Say '读取当前版本'
$pubspecPath = Join-Path $Root 'pubspec.yaml'
$configPath = Join-Path $Root 'lib\config.dart'
$manifestPath = Join-Path $Root 'server\version.json'

$pubspec = Get-Content $pubspecPath -Raw
$m = [regex]::Match($pubspec, '(?m)^version:\s*([0-9.]+)\+(\d+)')
if (-not $m.Success) { throw 'pubspec.yaml 里找不到 version: x.y.z+n' }

$oldVer = $m.Groups[1].Value
$oldBuild = [int]$m.Groups[2].Value
$newVer = if ($Version) { $Version } else { $oldVer }
$newBuild = $oldBuild + 1

Write-Host "    $oldVer+$oldBuild  ->  $newVer+$newBuild"

if (-not $DownloadUrl) {
  # 没给就沿用 version.json 里已有的地址，只把文件名里的版本号换掉
  $old = Get-Content $manifestPath -Raw | ConvertFrom-Json
  $DownloadUrl = $old.url -replace "$oldVer", "$newVer"
  if ($DownloadUrl -match '请换成你的域名') {
    throw "version.json 里的下载地址还是占位符。请用 -DownloadUrl 指定真实地址（必须是国内能直连的）。"
  }
}

# ---------------------------------------------------------------- 2. 改文件
if (-not $DryRun) {
  Say '写入新版本号'
  $pubspec = $pubspec -replace '(?m)^version:\s*[0-9.]+\+\d+', "version: $newVer+$newBuild"
  Set-Content -Path $pubspecPath -Value $pubspec -NoNewline -Encoding utf8

  $cfg = Get-Content $configPath -Raw
  $cfg = $cfg -replace "const String kAppVersion = '[^']*';", "const String kAppVersion = '$newVer';"
  $cfg = $cfg -replace 'const int kAppBuild = \d+;', "const int kAppBuild = $newBuild;"
  Set-Content -Path $configPath -Value $cfg -NoNewline -Encoding utf8

  # version.json：保留 _说明 这类注释字段，只改关键几项
  $mani = Get-Content $manifestPath -Raw | ConvertFrom-Json
  $mani.build = $newBuild
  $mani.version = $newVer
  $mani.url = $DownloadUrl
  $mani.notes = $Notes
  $mani.force = $false
  $mani | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath -Encoding utf8
  Ok "pubspec.yaml / config.dart / server\version.json 已更新"
} else {
  Say '（DryRun，不写文件）'
  Write-Host "    将要写入：build=$newBuild version=$newVer"
  Write-Host "    下载地址：$DownloadUrl"
}

if ($DryRun) { Say 'DryRun 结束'; exit 0 }

# ---------------------------------------------------------------- 3. 构建
Say '静态检查 + 单元测试'
$env:JAVA_HOME = 'D:\phone\Java\jdk-17.0.20.1+1'
flutter analyze | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze 没过，先修干净再发版' }
Ok 'analyze 零问题'

flutter test | Out-Null
if ($LASTEXITCODE -ne 0) { throw '单元测试没过，先修干净再发版' }
Ok '单元测试全过'

Say '构建 APK（三个 ABI）'
# 给 pubspec 加了 assets 之后增量构建偶尔会撞名，先清掉
Remove-Item 'build\app\intermediates\flutter' -Recurse -Force -ErrorAction SilentlyContinue
flutter build apk --release --split-per-abi | Out-Null
if ($LASTEXITCODE -ne 0) { throw '构建失败' }

$apkDir = Join-Path $Root 'build\app\outputs\flutter-apk'
$apks = Get-ChildItem $apkDir -Filter 'app-*-release.apk'
foreach ($a in $apks) { Ok "$($a.Name)  $([math]::Round($a.Length/1MB,1)) MB" }

# ---------------------------------------------------------------- 4. 拷出产物
Say "拷贝 APK 到 $ApkOutDir"
$names = @{
  'app-arm64-v8a-release.apk'   = "xiaojingyu-$newVer-arm64-v8a.apk"
  'app-armeabi-v7a-release.apk' = "xiaojingyu-$newVer-armeabi-v7a.apk"
  'app-x86_64-release.apk'      = "xiaojingyu-$newVer-x86_64.apk"
}
foreach ($k in $names.Keys) {
  $src = Join-Path $apkDir $k
  if (Test-Path $src) { Copy-Item $src (Join-Path $ApkOutDir $names[$k]) -Force }
}
Get-ChildItem $ApkOutDir -Filter "xiaojingyu-$newVer-*.apk" | ForEach-Object { Ok $_.Name }

# ---------------------------------------------------------------- 5. 推送
if ($NoPush) {
  Say '按 -NoPush 要求跳过推送。记得手动 git push，否则 jsDelivr 读不到新版本文件。'
  exit 0
}

Say '提交并推送到 GitHub'
git add -A
git commit -m "release: v$newVer+$newBuild" -m "$Notes" | Out-Null
git push origin HEAD
if ($LASTEXITCODE -ne 0) { throw 'git push 失败（检查代理与凭据）' }
Ok '已推送'

Write-Host ''
Say '发版完成'
Write-Host @"
    新版本      v$newVer (build $newBuild)
    下载地址    $DownloadUrl

    接下来你还需要：
      1. 把 APK 传到 $DownloadUrl 指向的位置（自己的服务器）
      2. 等 1-2 分钟让 jsDelivr 刷新缓存，用户就能检测到更新了

    验证更新清单是否生效：
      curl "$((Get-Content $manifestPath -Raw | ConvertFrom-Json).url)"
"@ -ForegroundColor Yellow
