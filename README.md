# Gen1Recomp Content Editor

Author **mods** for Gen1Recomp: maps, Pokémon, trainers, dialog, items, moves,
palettes, and talk scripts. Edits live under `mods/<id>/` — never the ROM cache.

Deep reference: [docs/content-editor.md](docs/content-editor.md)

---

## Launch

**From a source checkout**

```sh
git submodule update --init --recursive
./ContentEditor.sh
./ContentEditor.sh --mod mods/my_content
```

Windows:

```powershell
.\ContentEditor.bat
.\ContentEditor.bat --mod mods/my_content
```

Source launchers assemble the ignored `.content-editor-runtime/` workspace
from the pin and overlay editor-owned tools. Portable packages are already
assembled and launch directly.

**Portable pack (share with others)**

```powershell
.\scripts\pack_content_editor.ps1              # windows + linux
.\scripts\pack_content_editor.ps1 -Platform linux
.\scripts\pack_content_editor.ps1 -Platform windows
```

Outputs (no ROM cache or user saves):

- `dist/win/gen1recomp-content-editor-win64.zip` → `ContentEditor.bat`
- `dist/linux/gen1recomp-content-editor-linux64.tar.gz` → `./ContentEditor.sh`
  (after `chmod +x ContentEditor.sh love/love-11.5-x86_64.AppImage`)
- macOS: `dist/macos/gen1recomp-content-editor-macos-universal.tar.gz` →
  `./ContentEditor.command`

Portable packages include `love/portable.txt`. ROM caches, saves, options,
derived assets, and Playtest mods created after extraction stay under the
package's `love/` directory. A dedicated LÖVE identity prevents mods from a
normal `%APPDATA%`/XDG/macOS Gen1Recomp installation from leaking into the
portable editor. Source checkouts retain the normal platform save directory.

On **Project → GAME DATA** they can **Link Recomp** (reuse an existing
install’s cache), **Import ROM** (cache in the active portable/save root), or
**Use fixtures** (stub data).

**Playtest is standalone; linking Recomp is not required.** Release packages include the exact Gen1Recomp
submodule revision under `runtime/gen1recomp` and the LÖVE runtime; the same
revision is recorded by `.github/runtime-upstream.json`. Playtest
saves/synchronizes the open project, enables only that mod, and boots the ROM
version selected in the editor. A linked Recomp checkout is used only as an
fallback when a source clone has not initialized its pinned submodule.
Selecting a ROM does not change the mod's authored `games`, `gen2compat`, or
`game_version` manifest compatibility.

---

## Quick start

1. **Project → GAME DATA** — Link Gen1Recomp, Import a ROM, or stay on fixtures.
2. **Project** — Create a new mod id, or Open an existing `mods/<id>/` folder.
3. Edit on the other tabs (Maps, Pokémon, Trainers, …).
4. **Save** (Ctrl+S) writes:
   - `editor_project.lua` — editor source of truth
   - `main.lua` — loadable mod the game runs
5. **Playtest**, or enable the mod in the Gen1Recomp launcher / validate:

```sh
python tools/modkit.py validate <id>
```

Hand-written example mods are protected: Save will not overwrite their
`main.lua`. Use a **new mod id** for editor work.

### Share your mod

Zip and send the `mods/<your_mod>/` folder (include `assets/` if you added
sprites). Do **not** ship ROM files (`.gb`) or `data/generated` /
`assets/generated`.

---

## Tabs

| Tab | Purpose |
|-----|---------|
| **Project** | Create / open / save; game data source; boot & constants; Validate / Playtest |
| **Manifest** | `manifest.json` (name, version, deps) |
| **Code** | Browse / edit Lua under `mods/` |
| **Maps** | One contextual workspace for layered/classic terrain, NPCs, signs, encounters, connections, and optional TMX import |
| **Dialog** | NPC / sign text (`TEXT_*`) |
| **Trainers** | Parties, money, battle pics, palette |
| **AI** | Trainer AI classes |
| **Items** | Items + heal / status / ball / key templates |
| **Pokémon** | Stats, types, sprites, icons, cry, palette |
| **Moves** | Power, accuracy, effects, flags |
| **Effects** | Move-effect templates |
| **Types** | Type chart |
| **Audio** | Music, cries, SFX, map songs |
| **GFX** | SGB palettes, overworld sprites, tilesets |
| **Events** | Talk scripts, offline gifts, Gen 2 decorations / Trainer House, and save-flag tester |

---

## Maps workspace

The old **Map Builder** and **Maps** split has been replaced by one contextual
**Maps** workspace. The selected map controls what the workspace shows; map
terrain, events, settings, layers, tilesets, animations, and warps no longer
require switching between two tabs.

The workspace is arranged as follows:

- **Top bar** — the four-step guide, World View / Back to Editor,
  **Edit this map**, **Create new map**, and **More actions**.
- **Left column** — map list followed by the active tileset-source palette.
- **Center** — the 16×16 canvas, switching between **Paint map** and
  **Add events**.
- **Right drawer** — **Map setup**, **Layers**, **Tile animation**, and
  **Doors & exits**.

Selecting an existing or imported map opens a read-only preview. This is safe
navigation and never adds data to the mod. Click **Edit this map** only when you
want an editable project copy; the conversion retains the map record, objects,
signs, encounters, connections, and other metadata. New maps always use the
layered 16×16 workflow. Save compiles editable sources back to Gen1Recomp's
normal 32×32 block representation. Tiled and manual runtime-data editing are
not required.

### Create and navigate maps

1. Select an existing map and click **Edit this map**, or click
   **Create new map** and choose an ID, size preset, and starting visual style.
2. Open **More options** and click **+ New PNG** to add a source arranged as 16×16
   tiles. A map can paint from several imported PNG sources and game tilesets.
3. Add and reorder layers. Layers are exported by default; turn **Out** off to
   keep a reference layer in the project without putting it in the game.
4. Paint collision and warps, then Save.

**World View** shows the selected map together with connected neighbors; use
**Back to Editor** to resume editing. **More actions** contains destructive and
legacy commands. **Clear Events** removes objects, signs, transfers, and layered
warp endpoints without erasing terrain. **Delete Map** deletes a project-owned
map; source-game maps revert to their original data.

Only common tools and settings are shown initially. **More tools** reveals
selection, collision, warp, trainer, and other specialized tools.
**More settings** reveals hidden items and badge gates, while **More options**
contains tileset import, replacement, TMX, and export actions.

The editor keeps the original layer data in `editor_project.lua`. Save also
generates runtime blocks, collision lists, map records, and a
`mapbuilder_transforms.lua` recipe. On first game load, that recipe composes
the map atlas and animation frames from the player's own imported game art
plus the custom PNGs in the mod. The shareable mod is self-contained and
carries no copied game graphics. Tile animations require a Gen1Recomp runtime
that supports the generated `tileset.animatedTiles` records; use the linked
runtime described under [Tile animations](#tile-animations).

### Paint map mode

Choose **Paint map** above the canvas for tile and passage editing. Its tools are:

- **Pencil**, **Eraser**, **Fill**, and **Rectangle** for painting.
- **Picker** to take a tile and layer from the canvas.
- **Select** for rectangular multi-range operations.
- **Collision** to paint `solid`, `walk`, `grass`, `water`, or `shore` passage.
- **Warp** for coordinate transfers.
- **Pan** to move the camera without editing.

Hold Shift while dragging **Select** to add ranges. Selection actions can copy,
paste, nudge, select all, or clear. **Clear tiles** and Delete clear every layer
and reset passage to `solid` inside the selected ranges. **Grid** toggles cell
lines; **Passage** overlays collision without changing the active tool. Zoom
with **− / +**, **Fit**, or the mouse wheel; pan with the Pan tool, middle mouse,
Space/Alt drag, WASD, or horizontal/modified wheel input.

### Add events mode

Choose **Add events** above the canvas to place and edit map events in the same
16×16 coordinate system:

- **Event** — NPC or scripted object.
- **Sign** — sign/background event.
- **Trainer** — trainer class and party.
- **Wild** — fixed species and level encounter.
- **Select** — select the nearest event without creating one.

Click an empty cell to place the chosen event. Click and drag an existing marker
to move it. Ctrl+C / Ctrl+V copy and paste the selected event; Delete removes
it. **Dialog** opens the text associated with the current map or selected event.

### Property drawers

- **Map setup** contains the selected map's gameplay settings and event details.
- **Layers** creates, names, reorders, hides, exports, and changes opacity for
  terrain layers. **Eye** affects editor visibility; **Out** controls Save output.
  It also contains safe map resizing. Growth adds space on the right/bottom;
  shrinking reports and removes out-of-bounds terrain and events.
- **Tile animation** controls imported-PNG color mode and animation frames.
- **Doors & exits** creates links and lists/deletes stable endpoints on the
  current map.

Tileset color mode is an enum:

- **True color** preserves all PNG colors and is the default for imported art.
- **Palette** treats the PNG as four-shade graphics and applies the map palette.

The canvas uses the same color rule as Save, including animated frames and
transparent layers. **Export PNG** copies the selected original source without
quantization; **Export All** writes every available source. Both export to the
open mod's `exports/tilesets/` folder.

### Tile animations

Tile animations are authored from imported PNG sources; game tileset sources
remain available for painting but cannot define custom animation frames.

1. Select the tile that should act as the animated tile.
2. Click **Animate tile** below the tile palette, or open the
   **Tile animation** drawer.
3. Choose **2**, **3**, **4**, **6**, or **8** to create an initial sequence.
   New sequences begin with consecutive tiles in sheet order.
4. Edit each frame independently:
   - **Tile** selects any 16×16 tile in the same PNG source.
   - **ms** sets that frame's duration (minimum 16 ms).
   - **↑ / ↓** reorder the frame.
   - **Delete** removes it; **+ Add frame** appends another frame.
5. Paint the animated starting tile onto the map. Animated starting tiles are
   marked **A** in the palette. Choose **Static** to remove its animation.

A composed cell may contain one animated source tile plus any number of static
layers. Save converts the per-frame durations to a 60 Hz runtime sequence,
writes `animatedTiles` into the generated tileset, and writes frame-composition
jobs to `mapbuilder_transforms.lua`. On first game load, Gen1Recomp builds the
frame PNGs under `save/mod-derived/<mod-id>/mapbuilder/`; they are derived output
and should not be included when sharing the mod.

The linked Gen1Recomp checkout at `D:\decomp\gen1recomp` contains the required
runtime handling in `src/render/TileRenderer.lua`. If the mod is shared with
another player, their Gen1Recomp build must also support `animatedTiles` frame
records. If terrain appears but stays static, update/rebuild that runtime and
launch the mod again so its derived assets can be generated.

### Warps without indices

Choose **Doors & exits** and select a link type:

- **Two-way** — source and destination return to each other.
- **One-way** — the destination is arrival-only and does not immediately fire.
- **Custom return** — the destination returns to a third map or cell.

Click the source cell, select the destination map from the left list, and
click the arrival cell. Custom return asks for one final cell. The editor owns
map IDs and destination indices and rebuilds them safely when endpoints move.

Map dimensions are 16×16 cells and must be even because the game stores maps
as 2×2-cell blocks. Resizing preserves the top-left area and removes only
warps, NPCs, or signs that end up outside the smaller map.

The **Map** drawer also exposes encounters, connections, palettes, hidden items,
badge gates, and other classic map metadata. Connections remain in **Map**
because they describe neighboring-map seams; coordinate transfers belong in
**Doors & exits**.

### Optional TMX import

**Import TMX** on the Maps tab, or:

```sh
python tools/tmx_import.py path/to/maps --mod mods/my_content
```

TMX is retained as a legacy migration action in **Maps**; it is not needed by
the layered terrain editor.

---

## Pokémon / Trainers / palettes

- **Pokémon** — set types (must exist on the type chart; use `FLYING` not
  `BIRD`), sprites, icon class, and an **SGB palette**. Click the front /
  back / icon preview or the Palette row to open the picker.
- Display **names** must use Gen1 font characters (no `_` — e.g. `NEWMON`
  not `NEW_MON`). The species **id** can still use underscores.
- **Trainers** — click the battle pic or Palette row to pick a portrait
  palette (default MEWMON).

---

## Dialog & trainers on the map

1. Place an object or sign on **Maps** (gets a `TEXT_*` id).
2. Edit the string on **Dialog** (`\n`, `\f`, `{PLAYER}`).
3. For battles: author an `OPP_*` on **Trainers**, then use the **TRAINER**
   tool on Maps to place them.

---

## Shortcuts

| Key | Action |
|-----|--------|
| Ctrl+S | Save |
| Ctrl+Z / Ctrl+Y | Undo / redo |
| Esc | Close picker / quit editor |
| [ / ] or Tab | Previous / next tab |
| Space or Alt + drag | Pan map while painting |
| WASD over the map | Pan the map camera |
| Ctrl+C / Ctrl+V | Copy / paste selected terrain ranges or events |
| Delete / Backspace | Clear selected terrain ranges or delete selected event |
| Mouse wheel over a list | Scroll maps, tilesets, layers, or warps |
| Mouse wheel over the classic map | Zoom map or scroll the block dock |

---

## Requirements

- LÖVE **11.5** (bundled in the portable pack / `love/` in this checkout).
- Full tilesets/species/playtest need either a linked Gen1Recomp install, an
  imported ROM (save-dir cache), or a local `data/generated` in a dev
  checkout. Otherwise the editor uses `tests/fixture_data`.
- Custom tile-animation playback requires the `animatedTiles` renderer support
  documented above. Editor preview alone does not guarantee an older game
  runtime can play the generated frames.

---

## Pack for sharing (maintainers)

```powershell
.\scripts\pack_content_editor.ps1 -Platform all
```

Outputs:

- `dist/win/gen1recomp-content-editor-win64.zip`
- `dist/linux/gen1recomp-content-editor-linux64.tar.gz`
- `dist/macos/gen1recomp-content-editor-macos-universal.tar.gz`

Editor + LÖVE runtime + fixtures + sample mods, **no ROM cache**.


FireRed Fly destinations: open **UI → Town Map → Fly destinations**, then choose
**Set up FireRed Fly destinations**. The starter list contains Kanto's 13 outdoor
arrival points. Add or rename destinations, choose a landing map, set the zero-based
landing tile and Town Map marker, and choose **After visiting**, **Always available**,
or a named story flag. Save the mod to activate these settings. In-game, choose Fly
from a Pokémon's menu, use the direction buttons to select a destination, and press
A to travel or B to cancel. Normal Fly badge and outdoor-use checks still apply.
Visit tracking starts when the mod is enabled; existing saves can use Always available
or an existing story flag. Arrival uses the map's normal loading behavior, without a
Fly takeoff/landing animation.


### FireRed end credits and area previews

UI → **End credits** reads all 42 original credit text pages plus the closing page from the verified FireRed USA 1.0 ROM. Edit headings and credit lines, choose original artwork or import a 240 × 160 PNG, set duration, and add/delete/reorder pages. The default **Original cinematic sequence** follows the original scene order with scrolling maps, animated player/rival sprites, four Pokémon pose transitions, white-circle and Poké Ball backgrounds, credits music, cries, and closing artwork. **Simple timed pages** remains available as an alternative. Play preview uses the same sequence player as the exported mod. Enable in game and Save to play it after Hall of Fame, before its normal completion callback.

The cinematic presentation uses baked map images, so water, weather, and map objects do not animate. Transition timing and text layout approximate the cartridge presentation; this is not a frame-exact emulation. Edited credit text, page durations, replacement images, and additional pages are retained when building the cinematic sequence.

UI → **Area previews** contains all 21 original area illustrations, composed from their ROM tiles, palettes, and tilemaps. Choose the arrival map, area name, duration, and first-arrival/every-arrival/disabled behavior. Import a 240 × 160 replacement or export the preview. The first-arrival history is stored per mod in the save; it starts when this feature is enabled and does not reconstruct visits from older saves. Loading an existing save inside an area does not itself trigger a preview. A, B, or Start advances/skips a screen. Disable in game preserves the editor's settings and artwork.

Both features export their data and images into the mod; the game does not need access to the source ROM. Restart the editor after updating its code, enable the desired sequence, Save, and relaunch playtest.
