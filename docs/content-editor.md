# Content editor (maps, dialog, trainers, items, Pokémon, events)

In-game LÖVE editor that authors **mod folders** — never the ROM cache under
`data/generated/`. Launch:

```sh
git submodule update --init --recursive
./ContentEditor.sh
./ContentEditor.sh --mod mods/my_content
# or
ContentEditor.bat --mod mods/my_content
```

On Windows with the bundled runtime:

```powershell
.\love\love-11.5-win64\love.exe . --content-editor
```

Game data (tilesets, species, maps) comes from, in order of an explicit
Project choice or auto-detect:

1. **Local** `data/generated` (dev checkout)
2. **Linked Gen1Recomp** folder (Project → Link Recomp)
3. **Imported ROM** cache in the LÖVE save directory (Project → Import ROM)
4. **Fixtures** — `tests/fixture_data` (ROM-free stub data)

The shareable pack from `scripts/pack_content_editor.ps1` never includes
`data/generated` or `assets/generated`. Prefs are stored as
`content_editor_data.json` in the save directory.

## Tabs

| Tab | What it authors |
|-----|-----------------|
| **Project** | Create / open / save; game data source; `field.boot` + `constants`; Validate / Playtest |
| **Manifest** | Edit `mods/<id>/manifest.json` |
| **Code** | Browse/edit Lua under `mods/` (paste multi-line; Ctrl+Z undoes code) |
| **Maps** | One contextual workspace for layered/classic terrain and all map events/settings |
| **Dialog** | NPC/sign `TEXT_*` bindings and string table text |
| **Trainers** | `OPP_*` parties / money / name + trainer headers |
| **AI** | `ai_classes` (uses / item / switch behavior) |
| **Items** | Items + effect templates (heal / status / ball / key) |
| **Pokémon** | Species stats, types, sprites, icons, scales, cry/palette |
| **Moves** | Move stats + advanced fields (multi-hit, fixed damage, charge…) |
| **Effects** | Author `move_effects` from templates (status, recoil, drain, OHKO…) |
| **Types** | Type chart entries / matchups |
| **Audio** | Music, cries, SFX, map songs |
| **GFX** | Palettes (preview), overworld sprites, tileset walk/door/warp |
| **Events** | Talk script steps (incl. labels/jumps) + save-flag tester |

## Workflow

1. **Project** — Create a mod id or Open an existing folder.
2. Author content on the other tabs.
3. **Save** — writes:
   - `editor_project.lua` — structured editor state (source of truth)
   - `main.lua` — regenerated loadable mod
4. Enable the mod in the launcher, or validate:

```sh
python tools/modkit.py validate <id>
python tools/modkit.py pack mods/<id>
```

Hand-written mods (e.g. `example_mew_starter`) are protected: Save will refuse
to overwrite their `main.lua`. Create a **new mod id** for editor work.

## Dialog

1. Place an **object** or **sign** on Maps (auto-assigns a `TEXT_*` id).
2. Open **Dialog**, select the map and pin, edit the string (`\n` / `\f` /
   `{PLAYER}`).
3. Save emits `mod.content.text:override` and `text_pointers:patch` keyed by
   the map **label**.

## Trainers

1. On **Trainers**, patch a vanilla `OPP_*` or create a new class (party,
   money, base pic).
2. On **Maps**, choose the **TRAINER** tool and click a cell — places an
   object with `trainerClass` / `trainerParty` and seeds a
   `trainer_headers` entry (sight range, battle/won/after text, beat flag).
3. Save emits `trainers` + `trainer_headers` (new registry) + text strings.

## Events

**Scripts** mode builds linear talk scripts for a `MAP/TEXT_*` key:

| Step | Emits |
|------|--------|
| Show text | `show_text` |
| Label / Jump | `label` / `jump` / `jump_if_true` / `jump_if_false` |
| Set / clear flag | `set_flag` / `clear_flag` (`MOD_<modId>_…`) |
| Skip if flag | `check_flag` + `jump_if_true end` |
| Give / take item | `give_item` / `take_item` |
| One-shot gift | check done flag → give item once |

Use **From Dialog selection** after picking an NPC on the Dialog tab.

**Save flags** mode opens a real `save.lua` and toggles `MOD_*` / scraped
`EVENT_*` flags for playtesting. That edits save state, not mod content (same
idea as `love . --editor` Events).

## Items and effects

| Template     | Emits |
|--------------|--------|
| Heal HP      | `item_effects` heal + `items.effect` |
| Status cure  | `item_effects` status clear |
| Ball         | `balls:register` + `items.ball` |
| Key item     | noop effect, not tossable |
| Data only    | item record only |

## Project validate / playtest

On **Project**, **Validate** / **Playtest** sit under Overview.

**Validate** runs `python tools/modkit.py validate <id>` against the ROM
version currently selected in the editor. The Windows pack includes its
validator-only LuaJIT under `tools/tooling/luajit`; if LuaJIT is missing, the
editor installs it via the OS package manager
(`winget` on Windows, `brew install luajit` on macOS, `apt`/`dnf`/`pacman`
on Linux when passwordless sudo works) and sets `MODKIT_LUAJIT`. It does **not**
drop `luajit.exe` into the LÖVE save folder — Windows Defender treats that as
`Behavior:Win32/SuspLua.A`.

**Playtest does not require Link Recomp.** It runs the exact upstream checkout
at `runtime/gen1recomp`, whose Git submodule commit is mirrored in
`.github/runtime-upstream.json`. Release archives contain a minimal immutable
runtime archive (fused into the Windows Playtest executable), so players need
neither Git nor network access. No duplicate game-runtime snapshot is tracked
in the editor repository.

On each launch, Playtest:

1. saves the open project and synchronizes it to the pinned runtime's mod root;
2. disables previously enabled mods and enables only the open editor mod;
3. boots the ROM version currently selected in the editor with `--game`.

Selecting Red, Blue, Yellow, or Gold controls that Playtest launch. It does not
rewrite `manifest.json` compatibility fields: `games`, `gen2compat`, and
`game_version` remain the mod author's declaration. The open editor project
remains the authoring source of truth.

Link Recomp remains optional for reusing an existing imported ROM cache. It is
also a development fallback if `git submodule update --init --recursive` has
not populated the pin. Normal release packages always include the pin.

### Portable release storage

Release packages include `love/portable.txt`. Both the editor and bundled
Playtest runtime therefore use the package's `love/` directory for imported
ROM caches, saves, options, derived assets, and the synchronized Playtest mod.
The launchers select the dedicated identity
`gen1recomp-content-editor-portable`, preventing mods from the user's normal
Gen1Recomp AppData/XDG/macOS save directory from appearing in a portable run.
The distributable archive itself remains clean: it contains the marker but no
ROM-derived data, personal saves, options, or user mods.

The scheduled `Sync Gen1Recomp runtime` workflow checks `bryanthaboi/gen1recomp`
`main` daily. It advances only the submodule and recorded commit on
`sync/gen1recomp-runtime`, then creates or refreshes a ready-for-review PR.
Runtime and package checks must pass before that update is merged into `main`
and becomes the pin used by later releases.

## Pack for sharing

```powershell
.\scripts\pack_content_editor.ps1              # windows + linux + macOS
.\scripts\pack_content_editor.ps1 -Platform linux
```

Builds cache-free packs:

- `dist/win/gen1recomp-content-editor-win64.zip`
- `dist/linux/gen1recomp-content-editor-linux64.tar.gz` (LÖVE AppImage)
- `dist/macos/gen1recomp-content-editor-macos-universal.tar.gz` (LÖVE app)

See `tools/content-editor/PACK_README.md`.

## Maps

The Map Builder header walks through four steps: **Choose a map**, **Make it
editable**, **Paint or add events**, and **Save your mod**. Existing classic or
imported maps open in a read-only preview. Click **Edit this map** to create an editable 16×16
layered copy. Selecting a map, opening World View, scrolling, or using keyboard
navigation never changes the mod. The layered editor is portable and does not
require Tiled.

The left column contains the map list and tile sources, the center switches
between **Paint map** and **Add events**, and the right drawer contains
**Map setup**, **Layers**, **Tile animation**, and **Doors & exits**.
**World View** shows connected neighbors.
Potentially destructive commands are kept under **More actions**.

To keep the workspace approachable, only the everyday painting/event tools are
shown initially. **More tools** reveals selection, collision, warps, trainers,
and other specialized actions. The settings drawer uses four task names:
**Map setup**, **Layers**, **Tile animation**, and **Doors & exits**, each with a
short explanation. Map setup initially shows Map options, People & objects,
Signs & messages, and Wild Pokemon; **More settings** reveals hidden items and
badge gates. Tile-source importing, replacement, TMX, and export commands live
under **More options** below the tile palette.

### Create or open

- **Create new map** opens a guided form with **Small room**, **Town**, and
  **Large area** size presets. A custom size and starting visual style remain
  available. Create assigns an index starting at 1000 and opens the new map.
- Selecting an existing game or classic-editor map is navigation-only. Click
  **Edit Map** when ready; the explicit conversion retains the original map
  record, objects, signs, encounters, and connections.
- Width and height are entered in 16×16 walk cells. Both values must be even
  because one game block contains 2×2 cells.
- Growing a map keeps existing content at the top left. Shrinking removes only
  warp endpoints, NPCs, and signs outside the new bounds.

### Custom tilesets and colors

The tile-source list labels every source as either **RUNTIME REFERENCE** or
**CUSTOM MOD SOURCE**. Runtime references are read-only blocks and pixels from
the selected ROM; opening one in GFX and choosing **Replace in mod** creates a
mod-owned replacement without modifying the imported cache. Custom sources
and replacements are stored with the project and can be edited or removed.

**+ Custom PNG** copies a sheet into `assets/mapbuilder/sources/`. Its width and
height must be multiples of 16 pixels. Use the arrow buttons to switch between
the original game block source and any number of imported sheets; maps may
paint tiles from all of them.

Imported sources have a **Color mode** enum:

- `True color` is the default and keeps every PNG color.
- `Palette` treats the source as four-shade artwork and applies the map's
  effective palette when it must be composed with true-color layers.

The canvas follows the same rule as Save: true-color sources keep their pixels
and palette sources use the effective map palette, including animated frames
and transparent layers. **Export PNG** copies one original source without
quantization; **Export All** writes every available source. Both write to the
open mod's `exports/tilesets/` folder. This is an editor workspace folder:
validation and packaging ignore it. Move an original or appropriately
transformed asset into the mod's `assets/` tree when it is ready to ship.

Do not place ROM-derived graphics in a shared mod. Referencing the player's
game tileset is safe; only artwork imported into the mod is redistributed.

### Layers and paint tools

Ground always exists. Add, rename, reorder, show/hide, and adjust the opacity
of other layers. **Out** controls compilation: it is on by default, and turning
it off leaves the layer editable in `editor_project.lua` but excludes it from
the game map.

The tools are:

| Tool | Behavior |
|------|----------|
| Pencil | Paint the chosen 16×16 source tile |
| Eraser | Drag to clear a rectangular range on the active layer |
| Fill | Flood-fill matching cells |
| Rectangle | Drag a filled rectangle with the current tile |
| Picker | Pick the top visible tile and its layer |
| Select | Drag a range; Shift-drag adds another range |
| Collision | Paint solid, walk, grass, water, or shore behavior |
| Warp | Create coordinate-based map transfers |
| Pan | Move around the canvas without editing |

With Select active, **Clear tiles** or Delete erases all selected ranges from
every layer and resets passage to `solid`. Copy and paste preserve all layers
and passage values; the arrow actions nudge the copied selection by one cell.

Use **Terrain** mode for these tools. **Grid** toggles cell boundaries and
**Passage** shows collision without changing the active tool. Use **Events**
mode to place an object, sign, trainer, or fixed wild encounter directly on the
same canvas. Existing markers can be dragged; Ctrl+C / Ctrl+V copies the
selected event and Delete removes it. The **Dialog** action opens its text.

### Tile animation

Select a tile from an imported PNG and click **Animate tile** below the tile
palette. In **Tile animation**, choose a starting frame count. Each frame
can then use any tile from that PNG, have its own duration in milliseconds,
and be reordered, added, or deleted. Animated starting tiles are marked **A**
in the palette. New animations initially use consecutive tiles from left to
right in sheet order, beginning at the selected tile. A composed map
cell may stack one animated tile with any number of static layers. Save emits
the transform instructions and `animatedTiles` record used by the renderer;
the frame PNGs are built in the player's derived-asset cache at game startup.

Choose **Static** to remove an animation. Frame durations are quantized to the
game's 60 Hz update clock with a minimum editor duration of 16 ms. Playback
requires a Gen1Recomp runtime with `tileset.animatedTiles` support; the runtime
checkout used with this editor implements it in `src/render/TileRenderer.lua`.

### Guided warps

The editor stores stable endpoints and generates array indices during Save.
Authors never need to edit `destWarp` or maintain a separate map index file.

- **Two-way:** click A, choose another map, click B. A and B link both ways.
- **One-way:** A links to B; B is an inactive arrival endpoint.
- **Custom return:** A links to B, then B links to a separately chosen C.

The map list shows the actual registry IDs while placing a destination. Warp
markers are red for active endpoints and blue for arrival-only endpoints.
Deleting an endpoint safely disables links that targeted it.

### What Save produces

The non-flattened source remains in `editor_project.lua`, including layers,
source-tile references, opacity/export settings, collision, animations, and
stable warp links. Save also writes:

- `mapbuilder_transforms.lua`, and wires it into `manifest.json`
- a generated tileset record with blocks and collision lists
- a normal map patch/register record with resolved warps

Save immediately runs the transform recipe so Map Editor and World Viewer can
show the flattened atlas without restarting. Playtest runs the same recipe as
needed and stores the flattened atlas and animation frames under
`save/mod-derived/<mod-id>/mapbuilder/`. A missing selected-ROM tileset input
now fails Save explicitly instead of stamping an empty transform as complete.
Base-game
pixels are sampled from that player's imported cache; they are never copied
into the shared mod. Imported custom PNGs remain normal mod assets.

That output is an ordinary self-contained mod. No runtime companion mod or
engine workspace modification is required. Because Gen1Recomp manifests can
name one asset-transform file, Save stops with a clear error if the mod already
uses a different `assets_transforms` recipe; move that work into the Maps workspace's
generated recipe before saving again.

The generated format retains Gen I limits of 256 unique 8×8 tiles and 256
unique blocks per composed map. One grass collision graphic carries tall-
grass encounter behavior; additional grass-marked graphics remain walkable.

### Classic maps and events

Legacy block maps are adapted only after **Edit Map** is clicked. NPCs, signs, trainers,
encounters, connections, palettes, hidden items, and badge gates are embedded
in the same right-hand **Map** drawer used beside layered terrain. The map list
and property drawer stay put, and Save compiles the source back into the
runtime's normal 32×32 metatile block representation.

Warp endpoints and links live only in **Doors & exits**. **Map setup** retains
connections, which describe neighboring-map seams rather than coordinate
transfer events.

### Terrain and character colors

Terrain and overworld characters have independent color settings:

- **Map tiles TrueColor** belongs to the active tileset. It affects every map
  that uses that tileset slot. Create a map-local tileset slot first when only
  one map should use the raw PNG colors.
- **Sprite TrueColor** and the sprite palette belong to the sprite definition
  and follow that character everywhere it is used.
- On Gold, **NPC palette on this map** is a native per-object override. Choose
  `DEFAULT` to follow the sprite definition, or choose a named OBJ palette for
  only that NPC placement. `TRUE COLOR` creates an object-specific sprite
  definition because Gold's native object byte contains palette slots but no
  TrueColor bit; selecting `DEFAULT` again removes that generated definition.

The editor preview uses the same precedence as the pinned runtime: a Gold map
object override wins over its sprite default, while TrueColor art bypasses the
palette shader only for that individual terrain or sprite draw.

### Optional Pokemonium / Pokenet TMX import

```sh
python tools/tmx_import.py path/to/res/maps --mod mods/my_content
```

Or **Import TMX** on the Maps tab. Converts 32×32 layers into Gen1 blocks + a
new tileset; scripts/MMO AI do not convert. Do not redistribute Nintendo/fan
tilesets in packed mods. This is a legacy migration path; the Maps workspace has no
Tiled dependency.

## Related

- [Tiled map editing](tiled-map-editing.md)
- [Content Editor quick start](../README.md)
- Save editor: `love . --editor` (player saves, not content)
