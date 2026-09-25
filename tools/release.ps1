# 小鲸鱼 · 一键发版
#
# 做五件事：
#   1. 版本号 +1（pubspec.yaml、lib/config.dart、server/version.json 三处同步）
#   2. 静态检查 + 单元测试（不过就拒绝发版）
#   3. 构建 APK —— 用 tools/build.config.ps1 里的地址做 --dart-define 注入
#   4. 传到服务器，并更新服务器上的 version.json
#   5. 提交推送（jsDelivr 从仓库读备用清单）
#
# ★ 服务器地址不在代码里，在 tools/build.config.ps1（不进仓库）★
#   没这个文件也能构建，只是 App 不带更新检查。
#
# 用法：
#   .\tools\release.ps1 -Notes "修了 XX"
#   .\tools\release.ps1 -Notes "..." -Version 0.1.0
#   .\tools\release.ps1 -Notes "..." -SkipDeploy     # 只构建，不传服务器
#   .\tools\release.ps1 -Notes "..." -DryRun

param(
  [string]$Version = '',
  [Parameter(Mandatory = $true)][string]$Notes,
  [switch]$SkipDeploy,
  [switch]$SkipPush,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

function Say($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)  { Write-Host "    OK  $m" -ForegroundColor Green }
function Warn($m){ Write-Host "    !   $m" -ForegroundColor Yellow }

# ---------------------------------------------------------------- 读配置
$cfgPath = Join-Path $Root 'tools\build.config.ps1'
$cfg = @{ UpdateUrl=''; UpdateUrlAlt=''; DownloadPage=''; DownloadBase=''; ServerHost=''; ServerDir=''; JavaHome='' }
if (Test-Path $cfgPath) {
  $loaded = & $cfgPath
  foreach ($k in $loaded.Keys) { $cfg[$k] = $loaded[$k] }
  Say '已读取 tools/build.config.ps1'
} else {
  Warn '没有 tools/build.config.ps1 —— App 将不带更新检查（其它功能正常）'
  Warn '需要的话：copy tools\build.config.example.ps1 tools\build.config.ps1 再改'
}

if ($cfg.JavaHome) { $env:JAVA_HOME = $cfg.JavaHome }

# ---------------------------------------------------------------- 1. 版本号
Say '读取当前版本'
$pubspecPath  = Join-Path $Root 'pubspec.yaml'
$configPath   = Join-Path $Root 'lib\config.dart'
$manifestPath = Join-Path $Root 'server\version.json'

$m = [regex]::Match((Get-Content $pubspecPath -Raw), '(?m)^version:\s*([0-9.]+)\+(\d+)')
if (-not $m.Success) { throw 'pubspec.yaml 里找不到 version: x.y.z+n' }
$oldVer = $m.Groups[1].Value; $oldBuild = [int]$m.Groups[2].Value
$newVer = if ($Version) { $Version } else { $oldVer }
$newBuild = $oldBuild + 1
Write-Host "    $oldVer+$oldBuild  ->  $newVer+$newBuild"

# ---------------------------------------------------------------- 2. 检查
Say '静态检查 + 单元测试'
flutter analyze | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'flutter analyze 没过，先修干净再发版' }
Ok 'analyze 零问题'
flutter test | Out-Null
if ($LASTEXITCODE -ne 0) { throw '单元测试没过，先修干净再发版' }
Ok '单元测试全过'

if ($DryRun) { Say 'DryRun 结束'; exit 0 }

# ---------------------------------------------------------------- 3. 写版本号
Say '写入新版本号'
$ps = (Get-Content $pubspecPath -Raw) -replace '(?m)^version:\s*[0-9.]+\+\d+', "version: $newVer+$newBuild"
Set-Content $pubspecPath -Value $ps -NoNewline -Encoding utf8

$cf = Get-Content $configPath -Raw
$cf = $cf -replace "const String kAppVersion = '[^']*';", "const String kAppVersion = '$newVer';"
$cf = $cf -replace 'const int kAppBuild = \d+;', "const int kAppBuild = $newBuild;"
Set-Content $configPath -Value $cf -NoNewline -Encoding utf8

$mani = Get-Content $manifestPath -Raw | ConvertFrom-Json
$mani.build = $newBuild; $mani.version = $newVer; $mani.notes = $Notes; $mani.force = $false
$mani | ConvertTo-Json -Depth 5 | Set-Content $manifestPath -Encoding utf8
Ok '三处版本号已同步'

# ---------------------------------------------------------------- 4. 构建
Say '构建 APK'
$defines = @()
if ($cfg.UpdateUrl)    { $defines += "--dart-define=UPDATE_URL=$($cfg.UpdateUrl)" }
if ($cfg.UpdateUrlAlt) { $defines += "--dart-define=UPDATE_URL_ALT=$($cfg.UpdateUrlAlt)" }
if ($cfg.DownloadPage) { $defines += "--dart-define=DOWNLOAD_PAGE=$($cfg.DownloadPage)" }
if ($defines.Count -gt 0) { Ok "注入了 $($defines.Count) 个 --dart-define" } else { Warn '没有注入地址，App 不带更新检查' }

Remove-Item 'build\app\intermediates\flutter' -Recurse -Force -ErrorAction SilentlyContinue
flutter build apk --release --split-per-abi @defines | Out-Null
if ($LASTEXITCODE -ne 0) { throw '构建失败' }

$apkDir = Join-Path $Root 'build\app\outputs\flutter-apk'
Get-ChildItem $apkDir -Filter 'app-*-release.apk' | ForEach-Object {
  Ok "$($_.Name)  $([math]::Round($_.Length/1MB,1)) MB"
}

# ---------------------------------------------------------------- 5. 部署
$apkName = "xiaojingyu-$newVer-arm64-v8a.apk"
$apkPath = Join-Path $apkDir 'app-arm64-v8a-release.apk'

if ($SkipDeploy -or -not $cfg.ServerHost -or -not $cfg.ServerDir) {
  Say '跳过服务器部署'
  Write-Host "    手动： scp `"$apkPath`" <服务器>:$($cfg.ServerDir)/download/$apkName" -ForegroundColor DarkGray
  Write-Host "    并把 server\version.json 的内容同步到服务器上的 version.json" -ForegroundColor DarkGray
} else {
  Say "部署到 $($cfg.ServerHost)"
  scp -q -o BatchMode=yes $apkPath "$($cfg.ServerHost):$($cfg.ServerDir)/download/$apkName"
  if ($LASTEXITCODE -ne 0) { throw 'APK 上传失败' }
  Ok "APK 已上传 $apkName"

  # 服务器上的清单要带完整下载地址（App 优先用它）
  $dlUrl = if ($cfg.DownloadBase) { "$($cfg.DownloadBase)/$apkName" } else { '' }
  $serverMani = [ordered]@{ build = $newBuild; version = $newVer; url = $dlUrl; notes = $Notes; force = $false }
  $serverMani | ConvertTo-Json -Depth 5 | Set-Content "$env:TEMP\vjson.tmp" -Encoding utf8
  scp -q -o BatchMode=yes "$env:TEMP\vjson.tmp" "$($cfg.ServerHost):$($cfg.ServerDir)/version.json"
  if ($LASTEXITCODE -ne 0) { throw 'version.json 上传失败' }
  Ok '服务器清单已更新'
}

# ---------------------------------------------------------------- 6. 推送
if (-not $SkipPush) {
  Say '提交并推送'
  $env:GIT_TERMINAL_PROMPT = '0'
  git add -A
  git commit -m "release: v$newVer+$newBuild" -m "$Notes" | Out-Null
  git push origin HEAD
  if ($LASTEXITCODE -ne 0) { throw 'git push 失败（检查代理与凭据）' }
  Ok '已推送'
  Warn 'jsDelivr 有缓存，发版后如果备用清单没更新，执行：'
  Write-Host "      curl `"https://purge.jsdelivr.net/gh/<用户>/<仓库>@main/server/version.json`"" -ForegroundColor DarkGray
}

Write-Host ''
Say "发版完成 v$newVer (build $newBuild)"