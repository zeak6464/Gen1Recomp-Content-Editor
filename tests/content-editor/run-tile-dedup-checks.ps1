param([Parameter(Mandatory=$true)][string]$Runtime)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $workspace
try {
  $env:EDITOR_TEST_ROOT = $workspace
  $env:POKEPORT_RECOMP = (Resolve-Path -LiteralPath $Runtime).Path
  $result = Join-Path $PSScriptRoot 'tile-dedup-smoke/result.txt'
  Set-Content -LiteralPath $result -Value 'RUNNING'
  $process = Start-Process -FilePath (Join-Path $workspace 'love/love.exe') -ArgumentList 'tests/content-editor/tile-dedup-smoke' -WindowStyle Hidden -PassThru
  if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Tile dedup tests timed out' }
  $output = Get-Content -LiteralPath $result -Raw
  Write-Output $output
  if (-not $output.StartsWith('PASS:')) { throw 'Tile dedup tests failed' }
} finally { Pop-Location }
