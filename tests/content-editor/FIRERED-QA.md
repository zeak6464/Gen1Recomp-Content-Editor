# FireRed editor verification — 2026-09-20

Run the repeatable checks with:

```powershell
./tests/content-editor/run-firered-checks.ps1 -Runtime 'C:/path/to/gen1recomp'
```

The runner uses isolated test projects and a copy of FireRed-Test. It does not overwrite the user's project or player save. A failed assertion or integration timeout fails the run.

## Coverage

- 149 editor Lua files parsed successfully.
- Ten standalone test runs cover catalogs, validation, runtime writes, real-cache loading, starter replacement, manifest targets, map exports, playtest paths/options, palettes, and repeated save/reopen of a handwritten mod.
- The LÖVE harness executes 24 test modules and renders 31 primary panels, plus feature-specific screenshots.
- Integration assertions cover maps/layers/rotation and events; species, items, moves and trainers; encounter-form export; normal/shiny native form artwork; starters and gifts; breeding/abilities/behaviors; roaming Pokémon; Fly; dialogue and quests; carts; UI assets and intro replacements; Fame Checker; Town Maps; credits and custom area previews.
- A copied FireRed-Test project loads through the real mod loader, saves, reopens, and applies its starter-selection and gift hooks.
- Selected rendered screenshots were inspected, including encounter lists, area previews, Fame Checker, and form sprites. Rendering a panel is not proof that every possible interaction has been exercised.

## Issues found and fixed during this audit

- Default area-map matching could choose a nearby entrance instead of the area itself. Exact map matches now take precedence; Viridian Forest has a regression assertion.
- A remembered starter choice could replace an unrelated gift on the same map. Replacement now also checks the original gift species; unrelated gifts have a regression assertion. The generated FireRed-Test hook was updated too.
- Older standalone tests needed the linked runtime on their module path. The consolidated runner supplies it and fails clearly on errors.

## Remaining limits

This was automated integration testing using the real runtime and extracted ROM data, not a complete story playthrough or exhaustive testing of every combination of edits.

- Credits reproduce the sequence with approximate transition timing and static map snapshots.
- Mini-game images are previewable; their panel explicitly does not support asset replacement yet.
- Sevii Town Map artwork is editable; the UI currently marks in-game Sevii navigation and Fly destinations unsupported.
- FireRed provides Normal/Attack Deoxys artwork; Defense/Speed need imported artwork. Custom-form shiny previews currently show original ROM artwork, not a newly authored shiny palette for imported sprites.
- Existing party Pokémon and previously completed story events are not retroactively replaced by starter/gift edits.
