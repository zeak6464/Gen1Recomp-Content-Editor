param(
  [Parameter(Mandatory=$true)][string]$Runtime,
  [string]$Cache = "$env:APPDATA\LOVE\pokemon-love2d\leafgreen"
)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $workspace
try {
  $env:EDITOR_TEST_ROOT = $workspace
  $env:POKEPORT_RECOMP = (Resolve-Path -LiteralPath $Runtime).Path
  $env:POKEPORT_GEN3_CACHE = (Resolve-Path -LiteralPath $Cache).Path
  $result = Join-Path $PSScriptRoot 'leafgreen-smoke/result.txt'
  Set-Content -LiteralPath $result -Value 'RUNNING'
  $process = Start-Process -FilePath (Join-Path $workspace 'love/love.exe') -ArgumentList 'tests/content-editor/leafgreen-smoke' -WindowStyle Hidden -PassThru
  if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'LeafGreen tests timed out' }
  $output = Get-Content -LiteralPath $result -Raw
  Write-Output $output
  if (-not $output.StartsWith('PASS:')) { throw 'LeafGreen tests failed' }
} finally { Pop-Location }
