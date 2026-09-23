# Content editor

LÖVE app that authors Gen1Recomp mods: maps, dialog, trainers, items,
Pokémon, and simple quest scripts.

The contextual **Maps** workspace provides standalone 16×16 layered map authoring,
custom PNG tilesets, collision, animations, safe resizing, and guided warps.
Editable layers stay in `editor_project.lua`; Save generates the normal map
and tileset records plus a legal asset-transform recipe inside the same
shareable mod.

The former Map Builder and Maps workflows are unified here. The left column
contains maps and tile sources, the center switches between **Terrain** and
**Events**, and the right drawer contains **Map**, **Layers**, **Animate**, and
**Warps**. Existing maps are prepared for the 16×16 grid when selected; use
**+ New Map** for a new layered map and **World View** for connected neighbors.

## Teachy TV

In the Gen 3 UI workspace, select **Teachy TV**. The **Artwork** tab shows the
TV frame, title, end graphic, scrolling background and static strip at their
original dimensions, with PNG import, export and revert controls.
Use **Dialogue** to edit all six lesson titles,
introductions and conclusions, plus the host greeting, menu labels and TM
explanations. Text comes from the selected game's imported cache. The editor
includes a paged dialogue preview and **Restore original dialogue**. Use `\n`
for a new line and `\f` for a new page; preserve displayed control tokens.
Save and playtest to see the changes in Teachy TV. Demonstration battles,
animations and TM Case unlock requirements retain their original behavior.

## LeafGreen

With a linked runtime that supports LeafGreen, select **Project → Target game →
LeafGreen**, or start `ContentEditor-LeafGreen.bat`. The shortcut uses the linked
development runtime under Downloads, or accepts its folder as the first argument.
The editor reads LeafGreen's own imported cache and preserves `leafgreen` as the
project, manifest, cartridge and playtest target. Shared Gen 3 map, Pokémon, item,
trainer, script, animation and asset editors use that edition's extracted data.

Supplementary extraction that still relies on fixed FireRed USA 1.0 offsets
(including native form artwork, trade presets and Town Map artwork) remains
FireRed-only. Those tools report this limitation in LeafGreen rather than reading
a remembered FireRed ROM. Cache-backed editing and custom imported assets remain
available. Requires the updated runtime; the older bundled runtime has no
LeafGreen engine support.

## Combine duplicate tiles

In **Maps**, open the tile palette's **More options → Combine tiles**. Select
image-based maps, then **Scan selected maps** to preview the tile count reduction
and matching examples. **Apply combined tileset** builds compact shared PNG
sources and updates every use of the selected sources, including other maps,
hidden layers, map borders, stamps and assembly groups. Save and playtest normally.

This works with imported 16×16 PNG sources in Gen 1, 2 and 3. Matches require
identical RGBA pixels; palette and true-color sources stay separate, and animated
tiles merge only when their frame pixels and timing also match. Collision,
elevation, events and map dimensions stay intact. Original PNGs are retained,
and the change supports Undo/Redo. Native ROM metatiles are not included.

## Tile animations

Import a 16×16-tile PNG with **+ New PNG**, select the animated starting tile,
and click **Animate tile**. Choose an initial frame count in the **Animate**
drawer, then set every frame's source tile and duration independently. Frames
can be reordered, added, or deleted; **Static** removes the animation. Animated
starting tiles are marked **A** in the palette.

Save emits `tileset.animatedTiles` plus `mapbuilder_transforms.lua`. Gen1Recomp
builds the derived frame images on first load. Playback therefore requires a
Gen1Recomp runtime with `animatedTiles` support; the development runtime used by
this project is `D:\decomp\gen1recomp` (`src/render/TileRenderer.lua`).

```sh
git submodule update --init --recursive
./ContentEditor.sh
./ContentEditor.sh --mod mods/my_content
```

Windows (bundled runtime in this checkout):

```powershell
.\love\love-11.5-win64\love.exe . --content-editor
```

Portable zip for sharing (Windows):

```powershell
.\scripts\pack_content_editor.ps1
```

Outputs (no ROM cache):

- `dist/win/gen1recomp-content-editor-win64.zip` → `ContentEditor.bat`
- `dist/linux/gen1recomp-content-editor-linux64.tar.gz` → `./ContentEditor.sh`

Then **Link Recomp** or **Import ROM** on the Project tab for full data.

See [docs/content-editor.md](../../docs/content-editor.md) and
[PACK_README.md](PACK_README.md).

## Offline gifts and Gen 2 decorations

In **Events → Gifts** (Gen 1/2) or **Events → Offline gifts** (FireRed), create
an item or Pokémon reward. Gen 2 also supports bedroom decorations. Set the
title, reward, quantity or level, and collection/full/already-collected dialogue.
Click **Build delivery script**, then attach the displayed script to a delivery
NPC on Maps. For Gen 1, enter the map ID and the NPC's `TEXT_` identifier before
building. Save the mod before playtesting.

Each gift can be collected once per save, tracked separately for each mod and
gift ID. Item rewards respect bag capacity and stack limits. Pokémon require a
free party slot. Failed delivery leaves the gift available. Disable/re-enable
keeps claim history; creating a new gift creates a new reward identity. FireRed
dialogue changes need **Build delivery script** again. Rebuilding preserves
manual script/dialogue changes and reports a conflict instead of overwriting them.

**Events → Decorations** in Gen 2 edits existing collectible decoration names
and their sprite/block references, with **Revert decoration** to remove an
override. Categories and ownership flags stay intact. Give decorations through
the gift builder; players place them using the bedroom PC. Artwork changes
appear after the bedroom map reloads.

These are offline NPC rewards. They do not implement infrared/wireless transfer,
native Wonder Card menus/imports, or event-ticket destination unlocks. An item
gift alone does not unlock its associated event; author that event separately.

Run gift checks with `tests/content-editor/run-gift-checks.ps1 -Runtime <recomp>`.
The integration harness needs an extracted FireRed cache and uses disposable test
projects, without loading or changing player saves.

## Safari Zone and Trainer House

**Rules → Safari** in Gen 1 edits the entry price, Safari Ball allowance, steps
inside the zone, and timeout/out-of-balls exit map and cell. Entry dialogue shows
the configured price and allowance. The original early-exit event remains in
place. Yellow has an optional discounted-entry setting, including its eventual
one-ball admission for a player with no money.

**Rules → Safari Zone** in FireRed edits balls and steps. Its native entrance
script still controls the fee and exit. Allowance changes apply to new visits;
saved visits retain their remaining balls and steps.

**Events → Trainer House** in Gen 2 edits the visiting opponent's name and a team
of one to six Pokémon, including levels, held items and up to four explicit
moves per member. Leave moves empty to use the species' normal level moves.
Choose the normal once-per-day restriction or allow repeat battles. The repeat
option applies only to the Trainer House daily check and still records that a
battle happened, so returning to daily mode respects that day's visit.

Both forms have a Revert control. Save and restart the playtest after changes.
The Trainer House override does not rewrite native trainer records or Mystery
Gift save data; disabling the mod restores the original opponent behavior.

The gift-check runner also tests these features and renders their panels.

## FireRed / Gen 3

Map events show actions in everyday language. Select an action to edit its
settings: choose Pokémon, moves, trainers, characters, screen transitions,
directions, and built-in game actions by name. A saved switch remembers yes or
no; a saved number can remember a count or quest stage. Use the same number
when another action needs to check it.

Legendary and other prepared battles expose their Pokémon, level, and held item
on the battle action itself, even when an earlier command sets those values.
Editing a prepared opponent keeps the original battle type and event behavior.
If no fixed opponent can be found, choose one and use **Apply battle opponent**.
Other supported actions expose prepared inputs such as the team Pokémon to
check, the Day Care Pokémon to return, and the price to charge.

Movement routes describe individual steps, turns, jumps, and effects. Hover
over shortened labels to read the full description. Unrecognized values remain
visible and are preserved when you open an event. **All actions / details**
provides access to the underlying commands when needed.

Use a Gen1Recomp checkout with FireRed and Gen 3 content schemas. On Windows,
`ContentEditor-FireRed.bat` launches against
`%USERPROFILE%\Downloads\gen1recomp-dev\gen1recomp-dev`; pass another checkout
folder as its first argument to override that location. The linked runtime is
preferred over a bundled runtime at startup. Restart after changing runtime versions.

Select FireRed and create or open a mod. The launcher can reuse the game's
existing `firered/` extract in the shared `pokemon-love2d` save directory.
Otherwise import a FireRed USA 1.0 `.gba` ROM from Project. No ROM is bundled.

The FireRed workspaces include:

- **Pokemon / Moves / Items:** use the existing editors with FireRed adapters.
  Pokémon has six stats, abilities, growth, held items, native sprites/icons,
  learnsets, evolutions, trees, TM/HM compatibility, and native dex measurements.
  Items expose native pockets, prices, usage/held-effect fields and 24×24 icon imports.
  Moves expose native effects, chance, target, priority, flags, and an animation link.
  Existing partial Gen 3 edits migrate when these workspaces open. New records,
  edits, empty lists, and reverting edits are tested through the native loader.
  **Remove edit** restores the original record; it does not delete a ROM species/item.
- **Trainers / AI:** the existing trainer browser, native portraits, six-member parties,
  held items and move pickers, battle items, double battles, and AI script flags.
- **Encounters:** native grass, surf, Rock Smash, and fishing tables, with species
  pickers, encounter rates, and minimum/maximum levels. Slot order stays intact.
- **Player:** new-game position, money, player/rival names, bag/PC items, starter
  replacement rules, and native player/trainer image assets.
- **Shops:** the existing stock editor reads native mart lists and exports numeric
  item IDs. Empty inventories and reverting overrides are supported.
- **Trades:** editor-authored, one-time NPC trades with generated confirmation scripts.
  Attach the generated script to an NPC on Maps. The first matching non-egg party
  member is exchanged at its current level; the replacement gets the configured OT
  and nickname. When the original ROM is configured, the nine original trade
  records are available as starting points. Editing one does not automatically
  replace its original NPC script; generate and attach the script on Maps.
- **Types / Rules / Effects:** native matchup/category/name overrides, critical and
  residual damage/trapping rules, and remapping existing status/setup handlers.
  These hooks are removed when the mod is disabled. Custom type IDs and arbitrary
  new effect implementations are not provided by these forms.
- **Breeding:** native species gender, egg groups, egg cycles and ROM egg-move lists,
  plus an exported two-parent Day-Care service assigned to a map NPC.
- **GFX:** Pokemon battle sprite imports plus categorized overworld, trainer,
  tileset, and field-effect image replacement.
- **Maps:** uses the existing `MapsWorkspace` / `MapBuilder` layout, including
  the map browser, native metatile palette, paint tools, layers, PNG sources,
  stencil, stamps, zoom/pan, resize, and doors/exits drawer. FireRed elevation
  and collision bytes survive conversion and resize. Export assembles layers
  against the player's native atlases; extracted atlas pixels are not bundled.
  New maps receive an `FR_` prefix. Objects, signs, warps, and triggers use native
  records in the event drawer. Native scripts and movement sequences are edited
  on Events. The event drawer includes a searchable script assignment picker.
- **Events / Dialog:** native command lists with a selected-step argument editor,
  insert/copy/delete/reorder actions, and the existing map/dialog/text workspace.
  Dialog preserves native controls, displaying unfamiliar tokens as `{CONTROL:n}`. **+ Custom field** adds command
  arguments using Lua data values. Placed events get an `EDITOR_...` script to
  edit here. Commands and field names follow the linked runtime's Gen 3 VM.
  Inline `applymovement` commands offer named walking, facing, waiting, visibility
  and emote actions, an actor selector, and a cell-by-cell path preview. Add a
  `waitmovement` command when the following script must wait for movement to finish.
  Unrecognized native movement bytes are preserved; Raw arguments remains available.
  **Quest builder** creates one-time item rewards, optionally requiring an item
  in the bag (kept) or a defeated trainer. Configure the offer, unmet requirement,
  success, completed and bag-full dialogue, then **Build scripts** and **Save**.
  Attach the displayed main script to an NPC using the map event script picker.
  Completion flags are checked against extracted flags, scripts, maps and other
  quests. A full bag or declined offer does not mark the quest completed.
  Recipes persist separately from their generated native scripts; manual script
  or dialogue changes are preserved unless **Replace manual edits** is selected.
  Multi-stage quest graphs and item turn-in quests are not implemented by this builder.
- **Anims:** move, status, general/special scripts, labels, sprite tags, and
  background metadata. Native commands can be added, reordered, and edited.
  **Play draft** runs the native battle VM and renderer in the editor, with species
  selection, attack direction, pause/resume and frame stepping. The preview is
  silent and uses a temporary battle; use UI to replace animation image sheets.
  Playback stops at 60 seconds to catch unfinished tasks or command loops.
- **UI:** categorized title/intro, menus, battle, fonts, Pokedex, trainer-card,
  naming and help assets, plus an all-assets browser. Export PNG, edit externally, then import a same-size PNG replacement.
  RGBA assets are converted back to native bytes. Known font/frame dimensions
  are filled in; other raw sheets require their original width.
- **Audio:** uses the existing Audio workspace with music/SFX/cry remaps,
  map-song assignments, file imports, and native/imported previews. Replacements use
  the runtime's stop, pause/resume, fade, and fanfare controls.

Most forms commit edits immediately; use **Apply animation** and **Apply rules**
for animation/starter drafts before switching selections, then **Save**.
Applied edits participate in undo/redo and persist in `editor_project.lua`.
Structured fields are the default; record forms also offer a Lua-value view.
Empty event lists are exported as empty lists instead of silently preserving
the original events.

Opening an existing handwritten mod preserves its original entry source.
Save adds `editor_apply.lua` and an `editor_entry.lua` wrapper, and updates the
manifest entry so both the original code and editor changes run. Existing game
compatibility declarations are preserved. New projects target FireRed only.
Native map/animation/asset/audio exports declare `engine_internals` because the
linked runtime does not expose these systems through public Gen 3 registries.
Asset overrides are read through mod-owned hooks; extracted cache files are
not overwritten. Editor changes are excluded when loading the original mod's
base records so Revert can restore the original data.

Pokémon and move expansion mods use the linked runtime's content registries;
there is no fixed species roster or mod-name whitelist. Successfully loaded
records are available immediately in the editors and content pickers. Edits
to an authored mod run after its original entry point, preserving its scripts
and assets. New species allocate native slots and National Dex numbers
independently. Large exports split record constructors into separate functions
to stay within LuaJIT's limits.

Project > Mod Content shows available and added Pokémon/move counts, rejected
registrations (including failures the mod catches itself), and runtime messages.
Expand the details or copy the complete report to diagnose partial imports.
This does not translate incompatible record formats or implement custom battle
effects: those still need support in the selected game's runtime. In particular,
1025Dex 1.1.18 exposes its 1025 species with the tested FireRed runtime, but its
Gen 1-shaped additional moves are rejected by the FireRed move schema.

Pokémon previews also recognize DBK/g9 sprite components using
`data/dbk_data.lua` and `data/icon_data.lua`, either at the mod root or in a
component subfolder. Front/back and shiny sheets animate as individual frames;
party icons use the pack's atlas mapping. These are preview-only mappings, so
the mod's rendering hooks and saved sprite paths stay intact. Explicit editor
sprite imports take priority. Other custom rendering formats need an adapter.

Pokémon > Positions adjusts each species' opponent/front and player/back
vertical battle offsets (-64 to 64 pixels). The animated singles preview shows
both sides, supports shiny art, and includes the mod's existing vertical lift.
Reset removes the editor offsets. Saved offsets apply in battle only, after
the original mod, and leave health bars and substitute sprites unchanged.

The custom ability/effect builder supports healing, percentage HP loss, stat
changes/resets, weather, curing status, sleep/poison/toxic/burn/paralysis/freeze,
confusion and flinching. Move actions can individually target the user or the
opponent and can be reordered. Activation can require low/full HP or the presence
or absence of a status condition. Custom abilities can trigger on entry, at turn
end, or on switch-out. Status actions use native secondary-effect checks,
including substitute, Safeguard and Shield Dust handling.

The builder now offers seven ability triggers, 25 conditions and 21 actions.
Hit triggers cover receiving damage, receiving contact, dealing damage and
knocking out an opponent. These run per successful damaging hit; substitute
hits do not activate them, and a fainted holder cannot activate a reaction.
Abilities also support opponent targeting and per-action target overrides.
Conditions include adjustable HP thresholds, specific statuses, weather,
boosted/lowered stats and the triggering hit's category or contact flag.
Additional actions copy, swap, invert, set or clear stat stages, remove confusion,
flinching or trapping, clear weather, and heal or recoil based on hit damage.
Damage-based HP actions require a damaging move or a hit/knockout trigger.
Five replaceable presets provide regeneration, contact retaliation, a knockout
boost, rain on entry and status cleanup on exit. Each behavior supports up to
eight ordered actions.

**Full Gen 1/2 feature parity is still incomplete.** All tabs are available with
FireRed-specific editing paths, but multi-stage quest graphs are not adapted,
and the other limitations listed above
remain. Rendering panels does not establish complete authoring or gameplay parity.

This targets the supplied FireRed runtime. Ruby, Sapphire, Emerald, and LeafGreen
need runtime support before they can be selected. Gen 1/2 project conversion,
Gen 1/2 quest builders, and unrelated generation-gated registries are not
available in FireRed merely by showing their tabs.

Checks (set `POKEPORT_RECOMP` to the runtime checkout first; the real-cache
```powershell
.\tools\tooling\luajit\luajit.exe tests/content-editor/test_gen3.lua
$env:POKEPORT_GEN3_CACHE = "$env:APPDATA\LOVE\pokemon-love2d\firered"
.\tools\tooling\luajit\luajit.exe tests/content-editor/test_gen3_native.lua
$env:POKEPORT_GEN3_MOD = "$env:POKEPORT_RECOMP\mods\example_mew_starter"
.\tools\tooling\luajit\luajit.exe tests/content-editor/test_gen3_real.lua
$env:EDITOR_TEST_ROOT = (Get-Location).Path
$env:POKEPORT_VERSION = 'firered'
.\love\love.exe tests/content-editor/gen3-smoke
```

The hidden LÖVE harness checks real-cache startup, renders 31 panel paths, loads
generated exports through the runtime mod loader, and exercises silent imported
audio playback. `test_gen3_workspace.lua` also checks layer and event persistence,
native elevation after resizing, new maps, and the generated native atlas path.
`test_gen3_content.lua` edits species/items/moves/trainers/encounters/player/rules
and event-command forms. It checks migration, native reloads, preserved text controls,
shop consumers, type calculations, effect handlers, trade cancellation/full-party/
one-time behavior, and restoration after disabling the mod.
`test_gen3_anim_preview.lua` exercises native animation playback, background effects,
reversed attacks, pause/step and renderer restoration. `test_gen3_movement.lua`
checks named movement authoring and native action decoding. `test_gen3_quests.lua`
runs generated quests through the native VM, checks failure/completion branches,
manual-edit protection, NPC assignment and save/reopen persistence.
Results and screenshots stay in its ignored output directory.
`test_gen3_roundtrip.lua` additionally tests a disposable copy of the example mod;
set `POKEPORT_GEN3_TEST_MOD` to that copy, never the original. These checks do not
replace a full in-game walkthrough of your authored events and animations.

### FireRed preview and label corrections

Encounter lists resolve native bank/map IDs to map names and combine unedited
aliases. Shops display their consuming maps. Trainer and audio lists use numeric
ordering; music and sound effects are separate, named catalogs. Trainer parties
show automatic level-up moves and explicitly show absent held items as None.
Overworld previews use the extracted frame dimensions, with frame stepping and
playback. Badge sheets use all eight 16-pixel badges. UI > Animation preview plays
the native intro or title scene with imported image overrides, pause and stepping.

Shiny front/back previews and original trade records need an unmodified FireRed
USA 1.0 ROM. Set `POKEPORT_GEN3_ROM` or put its full path in the local, ignored
`gen3-rom-path.txt` beside the launcher. The ROM is read-only and verified by SHA-1
before fixed offsets are used. Shiny preview does not provide shiny palette editing
or add shiny rendering to the linked game runtime.

The supplemental table layout and music IDs follow
[pret/pokefirered](https://github.com/pret/pokefirered):
[src/data/ingame_trades.h](https://github.com/pret/pokefirered/blob/master/src/data/ingame_trades.h),
[src/trade_scene.c](https://github.com/pret/pokefirered/blob/master/src/trade_scene.c), and
[include/constants/songs.h](https://github.com/pret/pokefirered/blob/master/include/constants/songs.h).
`test_gen3_reported_ui.lua` runs inside the LÖVE harness and requires this ROM for
trade/shiny checks; it also renders the corrected panels and intro/title playback.

### FireRed UI content controls

Dialog previews use the FireRed font and two-line paging. Battle image widths
come from their native layouts (including the 320 x 24 health-bar element sheet).
Unknown raw widths are selectable from valid dimensions in a dropdown.
UI > Pokedex previews entry, habitat and size screens; Edit Pokemon opens the
species data editor. UI > Help edits the extracted questions/answers, previews
text, and exports overrides that reset when the mod is disabled.
UI > Town Map reads the original 240 x 160 Kanto artwork directly from the
verified FireRed ROM, including compressed tiles, tilemap flips and palette banks.
An imported PNG can replace it; Revert restores the ROM artwork.
This does not add Sevii map authoring. Pokédex screen previews show runtime data, not unsaved species drafts.
Items offers named held-effect, battle-use, registration and importance choices,
with a picker to copy an existing item's settings. Numeric amounts remain editable.
Copying settings does not reproduce behaviors hardcoded to particular native item
IDs in the linked runtime. Custom item logic still needs runtime scripting.

Town Map ROM pointer locations follow [HexManiacAdvance tableReference](https://github.com/haven1433/HexManiacAdvance/blob/master/src/HexManiac.Core/Models/Code/tableReference.txt). Animation move rows/headings resolve the native move number to its actual name; search accepts names and IDs.

New FireRed moves now start from a searchable existing move and retain a copy of
its animation. New items offer medicine, held-item, collectible and key-item
starting points, copying their icon and assigning an unused item number.
Move type, effect, target and turn order use named dropdowns. Individual flag
choices preserve unrelated bits. Power, accuracy, PP and effect amounts remain
numeric fields. Native item pack overrides include newly created records so the
runtime's item-use code receives their values; disabling the mod resets the pack.

### FireRed breeding, abilities, and trainer controls

Breeding and Pokemon Basics offer named gender distributions and egg groups.
Breeding estimates hatch steps from egg cycles and edits ROM-derived egg-move
lists with named dropdowns. Day-Care service assigns a two-parent attendant to a
map NPC. Parents gain experience while walking; compatible pairs produce Eggs
with inherited IVs, paternal egg/TM moves and shared level-up moves. Deposit,
withdrawal fees, collection, full-party handling and save persistence run from
code included in exported mods. Withdraw parents before disabling the mod.

Effects > Abilities lists existing abilities, shows their species, and assigns
either ability slot with Pokemon dropdowns. Move effects names replacement
behaviors and identifies affected moves. Create abilities/effects builds custom
abilities triggered on battle entry or turn end, and custom move behaviors.
Named actions restore HP, cure status, change stats or set weather, with configurable
chances and targets. Actions can be combined. Assign abilities to Pokemon or
behaviors to moves. Choose Status move for actions only, or Damage, then extra
actions for an attack with configurable power. Damaging moves retain native
accuracy, type effectiveness, damage and PP handling; the extra actions run once
per successfully damaged target, and skip misses, immunity and Substitute.
Extra actions can affect the user or opponent. Assigning a behavior replaces the
move's original effect. Unrestricted Lua battle scripting is outside this builder.

Trainer Basics includes named classes, gender, sprite previews, and encounter
music. AI offers named behavior toggles and retains an advanced numeric override.
Music changes are per trainer and revert to original behavior when disabled.


### Oak's introduction and tile rotation

FireRed **UI > Oak intro** edits each speech stage by name, including the player
and rival prompts. The preview supports page navigation. Keep `{PLAYER}` and
`{RIVAL}` for name substitution; use `\n` for a line break and `\f` for a page.
Restore this original line removes only that stage's override. Exported mods
apply the text to the native new-game scene and disabling the mod restores it.

In **Maps > Paint map > Select**, click a placed tile (or drag a selection), then
choose Rotate left/right. Each selected tile turns 90 degrees in place on the
active layer. Other cells, the paint brush, and passage settings remain unchanged.
Undo/redo restores the tiles and their generated graphics. Rotation uses static
artwork; animation sequences are not rotated.


### Full FireRed opening preview

**UI > Oak intro > Full intro** plays the native new-game scene. Choose the
professor's demonstration Pokemon, text speed, and whether to show the opening
help pages. Restart after changing settings, and use A/B, arrows, Start and Select
to play through the scene and naming screens. The preview is silent and never
starts a game or changes your save. **Dialogue** edits the speech and **Artwork**
imports/exports its portraits, backgrounds and other intro graphics. The selected
Pokemon and its cry are applied to exported mods.

Pokemon **Learnset** now uses searchable move dropdowns. **TM/HM** uses named
machine dropdowns showing both the machine number and move name.

### FireRed Pokemon forms

Open **Pokemon > Forms**, enable multiple forms, then add named variants. Each
variant has a separate editable Pokemon record for sprites, stats, types,
abilities and moves, while retaining its parent's Pokedex number. Named forms
are available in the species pickers used by gifts, encounters and trainers.
Import 64 x 64 front/back PNGs or start with the parent's artwork and party icon.

Choose a fixed default form, a permanent personality-based form, Unown's letter
selection, or Forecast weather changes. Unown's template extracts all 28 letter
sprites from the verified FireRed ROM; Castform's template extracts Normal,
Sunny, Rainy and Snowy sprites and assigns their weather and types. Weather
changes affect battle appearance and types only: stats, moves and the saved
Pokemon's identity stay unchanged, and no transformation animation is played.
Fixed default forms given as gifts use the selected form's learnset.

Deoxys templates are editable starting points, **not finished alternate-version
assets**: they copy the parent's artwork and stats. Import the desired artwork
and edit each form's stats and moves. Forms do not currently include an in-game
item or event action for manually switching an existing Pokemon between forms.
Save exports the form records and runtime hooks together; editor-only names and
selection settings survive reopening the project.

### FireRed roaming Pokemon

Open **Encounters > Roaming Pokemon**. Start with the FireRed legendary preset
or add custom roamers. Species and map fields use named searchable dropdowns.
The preset is level 50: Entei for the Bulbasaur choice, Suicune for Charmander,
and Raikou for Squirtle. It unlocks after Celio's Ruby/Sapphire network quest
(`FLAG_SYS_CAN_LINK_WITH_RS`). Starter-dependent choices use the original lab
choice slot even when the starter's species has been replaced.

Each roamer has an editable level, encounter chance, allowed maps, unlock rule,
battle behavior and defeated behavior. Catching always retires it. Personality,
IVs, location, remaining HP/status and caught/defeated state persist in the game
save's mod data. Species/level changes affect new roamers; existing individuals
retain their identity. These are mod-owned roamers, not imports of an existing
cartridge's roamer state.

Movement chooses another allowed map on player map changes and after the roamer's
battle. This is a configurable movement system, not the cartridge's adjacency
and location-history algorithm. The encounter percentage replaces a successful
normal grass encounter only when the roamer is on that map; multiple eligible
roamers share that roll. Repel blocks a lower-level roamer. Fishing and surfing
do not trigger these roamers, and maps need working grass encounters.

“Fight, then flee after a turn unless trapped” uses the native escape restrictions
for trapping moves and abilities. “Stay and fight” disables automatic fleeing.
The preset does not reproduce the cartridge's first-turn flee timing or its
Roar disappearance bug. The native battle engine remains responsible for damage,
status, catching and rewards.

### Additional FireRed Town Maps

UI > Town Map > Town Map artwork includes Kanto and Sevii Islands 1-3, 4-5, and 6-7. Each preview decodes its original 240 x 160 artwork from the imported FireRed ROM. Import, export, and revert operate on the selected region independently. Sevii image overrides are saved with the mod, but the linked runtime currently supports navigation and Fly destinations only on Kanto.

### Fame Checker (FireRed)

UI > Fame Checker reads all 16 people and 96 facts from the verified FireRed USA 1.0 ROM. Use the character and fact dropdowns to edit names, fact headings, text pages, source/location labels, personal messages, and portraits. Text wraps in the preview; custom portraits must be 64 x 64 PNGs. Availability can follow original story events, be immediate, or depend on a story flag. Editing or pressing Enable Fame Checker in mod exports a working Bag-item viewer with your mod. Save, then restart playtest.

The viewer uses the original yellow ROM background, a scrolling five-name character list, six source icons, and the original character portraits. Up/Down selects a person; Right or A selects facts; directions move between the six facts; A turns text pages; Select switches to the personal portrait/message; B returns to the list or closes the viewer. The original story specials unlock the same six fact slots; all six unlock the personal message. Discovery progress persists in mod save data from when the mod is enabled. Earlier discoveries are not reconstructed from an existing save. Source/location text is descriptive and does not relocate the NPC or change its script. Character slots stay fixed so original events keep their identity.

Imported Title / Intro PNGs are applied directly to the native boot screen as well as the editor preview, including the title border background. Previously saved mods must be saved again to regenerate this runtime support.
