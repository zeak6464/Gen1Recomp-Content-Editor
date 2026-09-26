param(
  [Parameter(Mandatory=$true)][string]$Runtime,
  [ValidateSet('firered')][string]$Game = 'firered',
  [string]$Cache
)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if (-not $Cache) { $Cache = Join-Path "$env:APPDATA/LOVE/pokemon-love2d" $Game }
Push-Location $workspace
try {
  $env:EDITOR_TEST_ROOT = $workspace
  $env:POKEPORT_RECOMP = (Resolve-Path -LiteralPath $Runtime).Path
  $env:POKEPORT_GEN3_CACHE = (Resolve-Path -LiteralPath $Cache).Path
  $env:POKEPORT_VERSION = $Game
  & './tools/tooling/luajit/luajit.exe' 'tests/content-editor/test_gen3_blocks.lua'
  if ($LASTEXITCODE -ne 0) { throw 'Block data tests failed' }
  $result = Join-Path $PSScriptRoot 'blocks-smoke/result.txt'
  Set-Content -LiteralPath $result -Value 'RUNNING'
  $process = Start-Process -FilePath (Join-Path $workspace 'love/love.exe') -ArgumentList 'tests/content-editor/blocks-smoke' -WindowStyle Hidden -PassThru
  if (-not $process.WaitForExit(90000)) { $process.Kill(); throw 'Block tests timed out' }
  $output = Get-Content -LiteralPath $result -Raw
  Write-Output "$Game`: $output"
  if (-not $output.StartsWith('PASS:')) { throw 'Block tests failed' }
} finally { Pop-Location }
