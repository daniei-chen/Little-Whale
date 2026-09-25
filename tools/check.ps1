# 小鲸鱼 · 本地验证
#
# CI 只能跑静态检查和单元测试 —— **集成测试需要真实设备上的 WebView**，
# 那边跑不了。所以发版前在本机跑这个。
#
# 用法：
#   .\tools\check.ps1              # 静态检查 + 单元测试
#   .\tools\check.ps1 -Integration # 再加上真机/模拟器上的集成测试
#   .\tools\check.ps1 -All         # 全部，含三个报障回归

param(
  [switch]$Integration,
  [switch]$All
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$cfgPath = Join-Path $Root 'tools\build.config.ps1'
if (Test-Path $cfgPath) {
  $cfg = & $cfgPath
  if ($cfg.JavaHome) { $env:JAVA_HOME = $cfg.JavaHome }
}

function Step($name, $block) {
  Write-Host "==> $name" -ForegroundColor Cyan
  & $block
  if ($LASTEXITCODE -ne 0) {
    Write-Host "    ✗ 失败：$name" -ForegroundColor Red
    exit 1
  }
  Write-Host "    ✓ 通过" -ForegroundColor Green
}

Step '静态检查' { flutter analyze }
Step '单元测试' { flutter test }

if ($Integration -or $All) {
  $runner = Join-Path (Split-Path -Parent $Root) '验收\run-itest.ps1'
  if (Test-Path $runner) {
    Step '集成：六平台主链路' { & $runner -TestFile 'local_parse_test.dart' }
    Step '集成：快手'         { & $runner -TestFile 'kuaishou_test.dart' }
    Step '集成：知乎'         { & $runner -TestFile 'zhihu_test.dart' }
    Step '集成：微博'         { & $runner -TestFile 'weibo_test.dart' }
  } else {
    Write-Host "    ! 找不到 $runner，跳过集成测试" -ForegroundColor Yellow
  }
}

if ($All) {
  $runner = Join-Path (Split-Path -Parent $Root) '验收\run-itest.ps1'
  Step '集成：用户报障回归' { & $runner -TestFile 'user_cases_test.dart' }
}

Write-Host ''
Write-Host '全部通过 ✅' -ForegroundColor Green
