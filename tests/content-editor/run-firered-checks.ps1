param(
  [Parameter(Mandatory=$true)][string]$Runtime,
  [string]$Cache = "$env:APPDATA\LOVE\pokemon-love2d\firered"
)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Push-Location $workspace
try {
  $env:EDITOR_TEST_ROOT = $workspace
  $env:POKEPORT_RECOMP = (Resolve-Path -LiteralPath $Runtime).Path
  $env:POKEPORT_GEN3_CACHE = (Resolve-Path -LiteralPath $Cache).Path
  $env:POKEPORT_GEN3_MOD = Join-Path $env:POKEPORT_RECOMP 'mods/example_mew_starter'
  $env:POKEPORT_GEN3_TEST_MOD = Join-Path $PSScriptRoot 'gen3-smoke/mew-project'
  $env:POKEPORT_VERSION = 'firered'
  $env:LUA_PATH = "tools/save-editor/?.lua;$env:POKEPORT_RECOMP/?.lua;;"
  $lua = Join-Path $workspace 'tools/tooling/luajit/luajit.exe'
  $checks = @('gen3','gen3_real','gen3_mod_content','gen3_battle_positions','gen3_behavior_options','gen3_collisions','gen3_doors','gen3_starter_choices','manifest_target','mapbuilder_manifest','playtest_options','playtest_paths','tileset_export','world_palette_overrides')
  foreach ($check in $checks) {
    & $lua "tests/content-editor/test_$check.lua"
    if ($LASTEXITCODE -ne 0) { throw "Failed: $check" }
  }
  $roundtrip = Join-Path $PSScriptRoot 'gen3-smoke/roundtrip-audit'
  New-Item -ItemType Directory -Path $roundtrip -Force | Out-Null
  Get-ChildItem -LiteralPath $env:POKEPORT_GEN3_MOD | Copy-Item -Destination $roundtrip -Recurse -Force
  $env:POKEPORT_GEN3_TEST_MOD = $roundtrip
  & $lua 'tests/content-editor/test_gen3_roundtrip.lua'
  if ($LASTEXITCODE -ne 0) { throw 'Failed: save/reopen roundtrip' }
  $env:POKEPORT_GEN3_TEST_MOD = Join-Path $PSScriptRoot 'gen3-smoke/mew-project'
  # Refresh only the disposable audit copy; the real project is read-only here.
  $source = Join-Path $workspace 'mods/FireRed-Test'
  $audit = Join-Path $PSScriptRoot 'gen3-smoke/audit-project'
  if (Test-Path -LiteralPath $source) {
    New-Item -ItemType Directory -Path $audit -Force | Out-Null
    Get-ChildItem -LiteralPath $source | Copy-Item -Destination $audit -Recurse -Force
  }
  $result = Join-Path $PSScriptRoot 'gen3-smoke/result.txt'
  Set-Content -LiteralPath $result -Value 'RUNNING'
  $process = Start-Process -FilePath (Join-Path $workspace 'love/love.exe') -ArgumentList 'tests/content-editor/gen3-smoke' -WindowStyle Hidden -PassThru
  if (-not $process.WaitForExit(180000)) { $process.Kill(); throw 'FireRed integration tests timed out' }
  $output = Get-Content -LiteralPath $result -Raw
  Write-Output $output
  if (-not $output.StartsWith('PASS:')) { throw 'FireRed integration tests failed' }
} finally { Pop-Location }
