param([string[]]$Games = @('red','blue','yellow','gold','silver','crystal','firered','leafgreen','ruby','sapphire','emerald'), [switch]$Cries)
$ErrorActionPreference = 'Stop'
$taskRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$savedRoot = $env:EDITOR_TEST_ROOT
$savedGame = $env:GAME
$savedUpdates = $env:POKEPORT_NO_UPDATE_CHECK
$savedCries = $env:CRY_CHECK
Push-Location $taskRoot
try {
  $env:EDITOR_TEST_ROOT = $taskRoot
  $env:POKEPORT_NO_UPDATE_CHECK = '1'
  $env:CRY_CHECK = if ($Cries) { '1' } else { '0' }
  $failures = @()
  foreach ($taskGame in $Games) {
    if ($taskGame -notin @('red','blue','yellow','gold','silver','crystal','firered','leafgreen','ruby','sapphire','emerald')) { throw "Unknown game: $taskGame" }
    $env:GAME = $taskGame
    $outputDir = Join-Path $PSScriptRoot "new-species-all-games/out/$taskGame"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    $resultPath = Join-Path $outputDir 'result.txt'
    Set-Content -LiteralPath $resultPath -Value 'RUNNING'
    $process = Start-Process -FilePath (Join-Path $taskRoot 'love/love.exe') -ArgumentList 'tests/content-editor/new-species-all-games' -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit(30000)) { $process.Kill(); $failures += $taskGame; Write-Output "$taskGame TIMEOUT"; continue }
    $result = Get-Content -LiteralPath $resultPath -Raw
    Write-Output "$taskGame`n$result"
    if ($result -match 'FAIL' -or $result -notmatch 'PASS capture Pokédex registration rendered') { $failures += $taskGame }
    if ($Cries -and $result -notmatch 'PASS custom cry playback completed') { $failures += $taskGame }
  }
  if ($failures.Count) { throw "New species checks failed: $($failures -join ', ')" }
} finally {
  $env:EDITOR_TEST_ROOT = $savedRoot
  $env:GAME = $savedGame
  $env:POKEPORT_NO_UPDATE_CHECK = $savedUpdates
  $env:CRY_CHECK = $savedCries
  Pop-Location
}
