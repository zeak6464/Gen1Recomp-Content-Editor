param(
  [Parameter(Mandatory=$true)][string]$Runtime,
  [ValidateSet('firered','leafgreen')][string]$Game = 'firered',
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
  $result = Join-Path $PSScriptRoot 'dynamic-forms-smoke/result.txt'
  Set-Content -LiteralPath $result -Value 'RUNNING'
  $process = Start-Process -FilePath (Join-Path $workspace 'love/love.exe') -ArgumentList 'tests/content-editor/dynamic-forms-smoke' -WindowStyle Hidden -PassThru
  if (-not $process.WaitForExit(50000)) { $process.Kill(); throw 'Dynamic form tests timed out' }
  $output = Get-Content -LiteralPath $result -Raw
  Write-Output "$Game`: $output"
  if (-not $output.StartsWith('PASS:')) { throw 'Dynamic form tests failed' }
} finally { Pop-Location }

