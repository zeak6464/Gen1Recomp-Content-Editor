param(
  [Parameter(Mandatory=$true)][string]$Runtime,
  [string]$Cache = "$env:APPDATA\LOVE\pokemon-love2d\firered"
)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $workspace
try {
  & './tools/tooling/luajit/luajit.exe' 'tests/content-editor/test_offline_gifts.lua'
  if ($LASTEXITCODE -ne 0) { throw 'Gen 1/2 gift tests failed' }
  & './tools/tooling/luajit/luajit.exe' 'tests/content-editor/test_world_activities.lua'
  if ($LASTEXITCODE -ne 0) { throw 'Safari / Trainer House tests failed' }
  $env:EDITOR_TEST_ROOT = $workspace
  $env:POKEPORT_RECOMP = (Resolve-Path -LiteralPath $Runtime).Path
  $env:POKEPORT_GEN3_CACHE = (Resolve-Path -LiteralPath $Cache).Path
  $result = Join-Path $PSScriptRoot 'gifts-smoke/result.txt'
  Set-Content -LiteralPath $result -Value 'RUNNING'
  $giftProcess = Start-Process -FilePath (Join-Path $workspace 'love/love.exe') -ArgumentList 'tests/content-editor/gifts-smoke' -WindowStyle Hidden -PassThru
  if (-not $giftProcess.WaitForExit(45000)) { $giftProcess.Kill(); throw 'Gift integration tests timed out' }
  $output = Get-Content -LiteralPath $result -Raw
  Write-Output $output
  if ($giftProcess.ExitCode -ne 0 -or -not $output.StartsWith('PASS:')) { throw 'Gift integration tests failed' }
} finally { Pop-Location }
