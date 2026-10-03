# Content editor

LÖVE app that authors Gen1Recomp mods: maps, dialog, trainers, items,
Pokémon, and simple quest scripts.

The contextual **Maps** workspace provides standalone 16×16 layered map authoring,
custom PNG tilesets, collision, animations, safe resizing, and guided warps.
Editable layers stay in `<mod>.editor_project.lua` beside the runtime mod folder; Save generates the normal map
and tileset records plus a legal asset-transform recipe inside the same
shareable mod.

The former Map Builder and Maps workflows are unified here. The left column
contains maps and tile sources, the center switches between **Terrain** and
**Events**, and the right drawer contains **Map**, **Layers**, **Animate**, and
**Warps**. Existing maps are prepared for the 16×16 grid when selected; use
**+ New Map** for a new layered map and **World View** for connected neighbors.

## GUIDES tab

The first tab. Step-by-step guides by topic -- Getting started, Gen 3
features, Maps and events, Pokemon and data -- each a few numbered steps,
most with **Take me there** (switches to the right tab and mode). Guides for
FireRed / LeafGreen features say so, and only link there in a Gen 3 mod.
Content is plain data in `Guides.lua`: add a guide as a table of steps.

## Update editor

Portable editors and source checkouts follow the Content Editor repository's `main` source commits.
The editor checks on startup and every 15 minutes, downloads changes automatically,
and installs the staged update when you close it normally. **Restart to update**
can apply it sooner. No GitHub release or manual update check is needed.

Portable updates replace only an explicit list of application files and folders. `mods/`,
project files, ROM caches, saves, settings, and the installed LÖVE binaries are
untouched. Replaced files are backed up, with rollback if copying fails.

Git checkouts read their installed commit from Git and update by fast-forward
on `main`. Local editor changes, divergent history, or incoming changes to mods
and generated data pause the update. Git never resets, cleans, stashes, or forces
your checkout. Unfinished mods remain in place. The Gen1Recomp runtime follows
the revision pinned by the editor commit,
not upstream's latest branch.

Downloads and backups live in the save folder's `update/`. Offline failures retry
after 15 minutes. Source staging requires `tar` plus PowerShell on Windows, or
`tar` and `zip` on Linux/macOS. Packages record `content-editor-commit.txt`.
`POKEPORT_NO_UPDATE_CHECK=1` disables startup and periodic automatic checks.

## Editor settings

**Settings** (top bar) holds the editor's own settings, kept in the save
folder's `editor-settings.lua`: mods, updates and the editor folder never
touch them. **Theme** picks the editor's colours: Fire Red, Leaf Green, Omega
Ruby, Alpha Sapphire (the original look), Gamma Emerald, Heart Gold or Soul
Silver, or any colour from the hue bar. The chosen look
applies straight away. `Theme.lua` recolours the chrome in place (`Theme.apply`);
every non-stock look is the Purple palette turned to another hue with each
colour's saturation and lightness kept, so text stays as readable (checked
at every hue in `tests/content-editor/test_editor_theme.lua`). Green, yellow
and red keep their meaning, and the game colours on the top stripe stay.

**Updates** turns automatic updates off (`autoUpdate = false`): no checks at
start or every 15 minutes, no background download and no install on close,
so local changes to the editor's own files stay. The top bar then says
**Updates off**; its pop-up can still **Check now** and download / install by
hand. `POKEPORT_NO_UPDATE_CHECK=1` also turns them off (`Updater.autoEnabled`).

## Cutscene maker and viewer (Gen 3)

**Playtest event** launches the linked Gen1Recomp game on the selected event's
map and runs the script through the real game interpreter. It saves/syncs editor
changes using the normal playtest workflow, then uses an in-memory copy of the
current game save (or a new session if none exists). Saving is disabled in this
test process. Map-entry scripts are suppressed during setup so the selected
event can start directly. Normal game controls handle dialogue, movement and
battles; the save's party, flags and inventory still determine event behavior.
This requires a linked source runtime with `POKEPORT_DRIVER` support.

Open **Events → Cutscenes**, or select a map event and choose **Cutscene maker /
viewer**. **New cutscene** creates a normal event script with dialogue and
character locking. Use the maker to add, edit, copy, reorder or delete dialogue,
waits and movement routes. Save uses the existing mod script export. Assign the
script using **Map events → Edit appearance / conditions → Event / cutscene
script** to trigger it in game.

**Open viewer** provides Play/Pause, Step and Restart. Attached events load their
map automatically, including project terrain edits and NPC sprites. The camera
starts at 3x zoom centered on the event and follows the moving actor. Use **- / +**
to adjust zoom and **Full map / Focus event** to switch views. The location
picker shows only maps whose events reference the script, including linked calls.
Scripts without map-event references show an empty location list. Player placement is approximate; movement
is shown at route endpoints.

Flag checks ask for ON/OFF; unknown variable comparisons ask for a preview value.
Branches and linked calls/returns follow those choices using isolated state.
Restart clears the choices. Sound and text-color commands continue with a note;
audio and text-color changes are not reproduced. Built-in game routines are
noted as omitted; unsupported effects and unavailable actors continue automatically
with a visible note. This keeps playback usable without claiming those effects
were simulated. Dialogue and story-state choices still wait for input; loop
protection remains in place for repeating scripts.
Use game playtest for accurate game effects, menus, collision and animation.
Scripts may be shared by multiple events; use **Make unique copy** before
changing only one event.

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

## Map event templates (FireRed and LeafGreen)

In **Maps → Events**, choose the **Event** tool. Its template picker offers
**Talking NPC**, **Item pickup**, **One-time reward**, and **Empty event**.
Set dialogue or the reward item and quantity in the toolbar, then click an
empty map tile. Each pickup/reward receives a separate persistent completion
flag. A full Bag leaves the reward available. Item pickups use the Poké Ball
graphic and disappear after successful collection.

Click an existing event to select it in the sidebar; drag it to move it.
**Quick event edit** exposes recognized dialogue, item, trainer, and wild-battle
actions. Choose an action, change its fields, and use **Apply text** for dialogue.
**Open event window** still provides the complete command editor. Save the mod
before playtesting. Placement templates configure new events; selecting a
different template does not replace an existing event's behavior.

## Custom Pokemon, forms, and types (Gen 3)

See [form support and remaining mechanics](FORM_SUPPORT.md) for the coverage
report, limits, and a move-triggered transformation walkthrough.

Create additional species in **Pokemon**, or open a species' **Forms** section
and choose **Enable multiple forms → Add custom form**. Fixed forms can represent
regional variants. Each form can have its own artwork, stats, typing and learnset.
Import the desired sprites and configure those records; later-generation species
and their assets are not automatically included.

**Change form while holding an item** assigns an item to each alternate form.
Giving/taking held items through the party menu updates the form immediately;
stats calculation and battle entry also check the rule. Without a matching item,
the Pokemon returns to the original form. This supports an Origin-style form
rule. It does not implement every later-generation battle transformation or
mid-battle item-loss transition. Moves, PP, personality and persistent identity
are retained; HP changes preserve damage, and fainted Pokemon stay fainted.

**Choose form by gender** assigns alternate forms to Male, Female or Genderless.
Unmatched genders use the original form. Eggs are not transformed.

**Fuse with a partner using a key item** supports reversible, two-Pokemon fusion.
For Kyurem-style recipes, create Kyurem, Reshiram and Zekrom species, then add
White and Black forms to Kyurem. Select fusion mode, create a DNA Splicers key
item, and assign Reshiram as White's partner and Zekrom as Black's partner.
Configure each form's artwork, stats, typing and ability separately.
Give the player the key item through an event. In the Bag, use it on the base
Pokemon, then select the partner. Use it on the fused Pokemon to separate them;
one party slot must be free. Canceling before partner selection changes nothing.

Fusion retains the base's experience, moves and PP; it applies the resulting
species' stats and ability while preserving HP damage. The partner's complete
record is stored inside the fused Pokemon and survives saves and PC storage.
Trading, releasing, daycare deposit and evolution are blocked while fused.
Eggs cannot fuse, and the base must not be fainted. The key item is reusable.
Add **form-specific move changes** for signature-move substitutions. A fused
form can be the starting form for an additional transformation such as Ultra
Burst. Later-generation assets and a one-fusion-per-key-item restriction are
not supplied automatically.

**Transform using move, item or battle rules** adds configurable move-use and
move-hit changes, known-move selection, persistent item-use changes, HP and
minimum-level conditions, weather, battle-held-item selection, switch-out,
end-of-turn, damage-taken and knockout triggers. Add rules to each target form,
choose the required source form, and choose reversion on switching or battle end.
Only one rule fires per event. Battle rules preserve the individual's maximum
HP and moves; they do not implement unrelated ability effects or giant-form
mechanics. Optional ability IDs restrict a rule to a particular ability.

**Special form mechanic** adds Mega Evolution, Primal Reversion, Ultra Burst,
Dynamax/Gigantamax, Terastallization (including Stellar), Disguise, Ice Face,
Gulp Missile and HP-changing Power Construct/boss phases. Configure the source
form and prerequisites. Press **SELECT** in the battle move menu to choose a
manual transformation, then choose a move. Primal and reactive mechanics activate
automatically. G-Max signature effects use a move configured in the project.

**Field / individual form selection** supports maps, hours, monthly seasons,
nature, personality rarity, story flags, inherited tags and timed grooming items.
**Form-specific move changes** supplies reversible signature substitutions and
variable move typing. Species indices now extend through 65535 in exported
local runtime mods. See [coverage and fidelity boundaries](FORM_SUPPORT.md)
before relying on a particular later-generation ability or battle interaction.

**Types → + New type** allocates a custom type index (18–63). Set its ID, display
name, physical/special category and matchups, then assign it to Pokemon or moves.
New matchups default to neutral. Fairy can be authored this way; its matchup
chart is not filled automatically. The summary screen displays a text badge
for custom types. These features target Gen1Recomp mods, not a GBA ROM patch.

## Gen 3 bridges

In the map editor, paint the lower ground first and set its passage to Walk,
Water or Solid as appropriate. Select a bridge tile from the palette, choose
**Bridge**, and paint **Deck east/west** or **Deck north/south**. The deck uses
the selected tile above the untouched lower terrain. Select different tiles
to paint the deck's edges and middle; this tool does not supply bridge artwork.

Choose the matching **Entrance** mode and mark the approach cell immediately
beyond each end of the deck. These approach cells should be walkable paths.
Use one entrance per lane for a bridge more than one cell wide. Entrances are
marked in green while the Bridge tool is selected; deck cells are yellow.

Approaching an entrance along the bridge's axis selects the upper walking level.
The player can cross the deck, cannot walk off its sides, and returns to normal
height after leaving the far entrance. The lower route keeps its own passage:
walking ground stays walkable and water still requires Surf. The deck is drawn
above the lower player and below the upper player. No elevation numbers need
editing. **Remove bridge** removes only the deck/entrance metadata and leaves
the lower terrain intact. Save and restart the playtest after changes.

These presets support straight player-traversable bridges; they are not a
multi-floor navigation system for NPCs or stacked bridges. NPC placement and
scripted movement still require their own elevation setup.

## Gen 3 blocks (FireRed)

**GFX → Blocks** edits FireRed metatiles the way the Gen 1/2 block editor
does: pick a block, click one of its eight slots (bottom layer and top layer,
2×2 each), then click a tile in the sheet. Each slot has its own palette
(0–12) and H/V flip; each block has a layer type (Normal, Covered, Split) and
a behaviour. **+ New block** adds blocks after the tileset's own (up to id
1023); **Duplicate**, **Revert** and **Delete block** do what they say.

No ROM is needed — not by the modder, not by players. Tiles come from the
block pictures the game saved when FireRed was imported (the same data the
maps are drawn from): the sheet shows every distinct tile found in the
tileset's blocks, each in its own colours, and every existing block is shown
as those tiles, drawing back exactly as in the game.

**Your own tiles.** *Paint on a copy* turns the selected slot's tile into one
of your own tiles (Y1, Y2, …) and opens an 8×8 pixel editor beside the
preview: left button paints, right button (or **Pick**) picks a colour, colour
0 is see-through. *+ New blank tile* under the sheet starts from scratch.
Only the pixels you paint are saved; unpainted pixels of a copy come from the
player's game.

New and edited blocks appear in the map editor's tile picker (after the
saved ones) and draw as edited on the map. On save, `main.lua` gets only
definitions — which tile (by where it sits in the saved blocks), palette and
flips — plus your painted pixels; no game graphics. In game the blocks are
rebuilt from the player's own saved data and written into that tileset's
atlas, so ROM maps and maps built in the editor both show them.

**Merge a tile on top** (under a selected slot) combines two tiles in one
slot: click it, then click tiles in the sheet (optionally flipped). The
merged tile keeps its own colours wherever the hardware allows:

1. the same corner of the other layer is free: it goes there, in its own
   palette (the block becomes *Covered*, both layers under the player);
2. otherwise the two tiles become one of yours in a palette that has every
   colour of both, putting missing colours into colour numbers of that
   palette no block uses (dots under the swatches mark them; the game gets
   them for this tileset only, so nothing it already shows changes);
3. only when no palette has room, the nearest colours of the slot's palette.

See-through pixels keep what's there, and the water (or sand, flowers)
still showing around a merged tile keeps animating in game -- also when the
merge moved the slot to another palette, and when the water is in the top
layer of a *Covered* block.

**Swap layers** (under the slot grids) swaps the bottom and top layers
corner for corner. **Merge top into bottom** draws each top-layer tile onto
the bottom tile in the same corner (the same way as *Merge a tile on top*,
keeping colours where a palette has room) and empties the top layer, ready
for more edits.

**Import PNG...** (above the block strip) turns a picture into blocks: one
PNG, or a strip of animation frames side by side (the way the game keeps its
own animated tiles). Choose how many blocks it covers (bigger pictures are
shrunk to fit), a block to show behind it (select it in the strip first; e.g.
the sea), under or over the player, and a palette (*Auto* picks the closest;
the background's own colours are kept out so the picture doesn't melt into
it). *Create blocks* makes the blocks and your tiles, and for several frames
a tile animation per block, then shows which first-frame blocks to paint on
the map. Importing again under the same name replaces it and keeps its block
numbers; *Remove* deletes an import's blocks, tiles and animation.

**Whirlpools.** In the map editor, the Collision tool has a **Whirlpool**
brush (FireRed projects). Painted cells can't be surfed into; facing one
while surfing and pressing A asks to use WHIRLPOOL when a party Pokémon
knows the move (and the chosen badge is owned), then carries the player
across in the direction they face to the first water past it, still
surfing, with the whirlpool sound, like Waterfall. Otherwise it says the
currents are too strong. **Crossing settings** (next to the brush) sets the
move, badge, messages and sound for every whirlpool in the project. The
cells get behaviour 0x1F0, the editor's own; `Gen3WhirlpoolRuntime` adds the
crossing in game.

Animated ground keeps animating: where a block's bottom layer uses tiles of
an animated game block (water, sand, flowers) and nothing covers them, those
pixels follow the game's animation frames; everything else stays as you
built it. An edited block with nothing animated left under it drops out of
the animation, so your edit stays.

Limits: tiles that no saved block uses aren't available; a behaviour change
doesn't alter collision already baked into vanilla maps; palettes can't be
edited yet. Tests: `tests/content-editor/run-block-checks.ps1 -Runtime <runtime>`.

## GAME PATCHES (FireRed / LeafGreen)

The **GAME PATCHES** tab (between CODE and MAPS) lists features a mod adds
on top of the game; each patch has its own box, its sub settings share it
with smaller switches, and **Description** explains it. Patches only change
the base game; maps you add are set up with the editor's own tools.

- **Clean Project** -- **Apply** (asks first, with a warning: only at the
  start of a project; every change made so far is gone) wipes the open
  project, saves it and reopens it with one blank starter map
  (`FR_STARTER_MAP`, set as the start map in PLAYER). A new game starts
  there with no story flags or variables; the intro only asks boy or girl
  and the player's name (no professor, no rival -- `Gen3CleanIntro.lua`);
  the title screen and menu are unchanged. FireRed's own maps and scripts
  are hidden in the editor and can't be reached in game. **MAPS → Import
  template map** copies a FireRed map's layout (tiles, collision, heights,
  border) into a new map, never its events or story. Pokemon, moves, items,
  types, tilesets, graphics and trainers stay. **Emerald** has it too: the
  starter map is `EM_STARTER_MAP` (grass, Petalburg's tileset), the intro is
  Birch's scene cut the same way (no professor, no Lotad) and the game
  starts on your map, not in the truck. **FireRed Maps** stays as it was:
  with it on, FireRed's tilesets and template maps are still there for a
  hand-made region (the imported Kanto region is wiped with the rest).
- **Real Time Clock** with **Encounter tables** -- see below.

## Gen 3 day and night (FireRed)

The **GAME PATCHES** tab (between CODE and MAPS) switches the real time
clock on or off; **GFX → Day & night** holds its settings. With it on, a
Crystal-style clock runs: outdoor maps (map types Town, City, Route and
Ocean route) follow the device's own time. Buildings, caves and battles
look the same all day. Turning it off keeps every setting, night look and
time-of-day encounter list for when it's turned on again.

- **Parts of the day.** Morning, day and night start at the hours you set
  (Crystal's 4, 10 and 18 by default). A new part fades in over the fade
  minutes.
- **Looks.** Day is drawn as the game draws it. Morning and night multiply
  every colour by a tint, in the GBA's 5-bit colours. Menus and text boxes
  are not tinted.
- **Night look.** In GFX → Blocks, open a block and turn on **Night look**
  (next to the palette). Select pixels (drag; right-drag unselects; *Select a
  colour* picks every pixel of one colour), then **Use this colour** gives them
  their own night colour, or **Keep day colour** keeps them as they are by
  day. Those pixels skip the night tint; everything else darkens.
  **Find similar blocks** uses the block as an example: it learns which day
  colours became which night colours and which colour framed them, then finds
  blocks (this tileset, or every tileset outdoor maps use) where those colours
  sit inside that frame -- windows, not blue roofs or water -- and shows them
  day and night to tick before **Give … this look**. For a window it
  missed, open that block, select its window pixels and press **Light like
  <example>**: its colours, darkest to brightest, take the example's night
  colours. Then search with **All lit blocks** as the examples to find more of
  that kind too; **Looser match** accepts patches with frame on 40% of their
  edge (from 2 pixels). **Hide already lit** hides blocks that already have a
  night look. Right-click a result to fix it right there: the same pixel grid
  and tools (plus **Remove night look** and **Give it this look**) -- before
  it's given its look, edits change what it gets; after, they save straight
  into the block. **Remove night look** takes one block's look away and
  **Remove all night looks** (click twice) every block's; Undo brings them
  back. The Day & night tab lists the blocks with a night look, each with
  **Remove**.
- **Wild encounters by time of day.** In Encounters, pick a map and a kind
  (Grass, Surf, Rock Smash, Fishing), then **Morning**, **Day** or **Night**
  and **Give morning, day and night their own lists**: each starts as a
  copy of the all-day list, and the all-day list is off from then on (like
  Crystal's grass). **Back to one all-day list** removes them. The Day &
  night tab lists them. They follow the same clock and test hour and only
  apply while day and night is on; with it off the all-day list is used.
- **Encounter tables.** GAME PATCHES → Real time clock → **Encounter
  tables**, a setting of the clock: Off while the clock is off, and turned
  On when the clock is turned on. On: FireRed's own Kanto routes and caves
  (31 tables, keeping their encounter rate) get Pokemon Crystal's morning /
  day / night lists (`Gen3CrystalEncounters.lua`, from pret/pokecrystal, a
  placeholder mix) straight away, as their own lists -- edit them in
  Encounters like any other. Crystal's seven slots are spread over
  FireRed's twelve with the same chances. Maps added in a mod are never
  touched. Off: Crystal's lists come back out and every table uses its
  all-day list; tables you've edited, and lists you made yourself, are
  kept. **Back to one all-day list** or **Keep the all-day list at every
  time** (Encounters → All day) takes one table out while the rest still
  change.
- **Telling the time in events.** The game action (special) **Read the
  clock** (`0xE100`, `Gen3Clock.lua`) puts the day, date and time into
  `{STR_VAR_1}` (Tuesday), `{STR_VAR_2}` (29 September) and `{STR_VAR_3}`
  (10:42 PM) for dialogue after it, and numbers into the script's own
  variables: `0x8004` day (0 Sunday - 6 Saturday), `0x8005` hour, `0x8006`
  minute, `0x8007` part of the day (0 morning, 1 day, 2 night) for checks.
  Same clock as the looks (device time; the test hour while the clock is on).
  In the event window (and EVENTS > Map events), **Add action...** has
  **Read the clock** (put at the top of the event) and **Check the time or
  day...** (`Gen3ClockEvents.lua`): It's morning / day / night, a day of the
  week, before or from an hour. A check is `compare_var_to_value` +
  `goto_if` to its own `EditorBranch_*` event, which says its line and ends;
  when it doesn't match the event carries on below, so several checks read
  as "if ... else if ... otherwise". Pick an **If** line to change the check
  or **Remove this check**. GUIDES > An NPC who tells the time walks through
  it.
- **Default night looks.** The editor ships night looks for FireRed's own
  outdoor blocks (455 blocks: windows, lamps, signs), in
  `Gen3DayNightDefaults.lua`. Turning day and night on in a project with no
  night looks starts from them; edit or remove any as usual. **Add default
  night looks** in the Day & night tab gives the missing ones to blocks that
  have no look of their own (yours are kept). (Colours marked lit in older
  projects are still honoured and listed there.)
- **Preview.** The **Time of day** button over the map (and the Day & night
  tab) previews any time: Play runs a day in 36 seconds; the Blocks previews
  follow the same time.
- **Test hour.** Playtests use this hour instead of the clock; clear it
  before sharing the mod.

In game, `Gen3DayNightRuntime` wraps `Renderer.endWorldPass`: on an outdoor
map the finished world canvas is redrawn once through a shader
(`Gen3DayNightCore.SHADER`) before the menus are drawn. At night the night
look's pixels are written into the tileset pictures (and put back at dawn or
indoors); their colours are nudged one 5-bit step if a palette already uses
them, so exactly those pixels skip the tint. No engine files change.

## Gen 3 map connections

The map connections viewer defaults to **Full region**, following all edge
connections from the selected map. **Nearby** shows immediate neighbors;
**All maps** includes disconnected regions and interiors in separate areas.
Use **Fit**, the mouse wheel to zoom, and drag empty space or hold WASD to pan.
Click a map to select it, then **Open in Editor** to edit it. Placement uses
existing connection offsets; the viewer does not create connections between
unconnected maps or infer geographical placement from door warps.

**Map setup → Map connections** supports multiple connections on each side.
Use **+ Add** under North, South, East or West, then set the destination and
offset in 16-pixel cells. Editing or removing one connection updates only its
matching return link. Offsets run horizontally for North/South and vertically
for East/West. Gaps between destination spans remain blocked.

Legacy stock caches that lost Water Path's additional west connections are
repaired to Green Path (0), Six Island (40) and Ruin Valley (80). Explicit edits
made with this connection editor are preserved, including deleted links.
Save the project and restart its playtest to use the exported runtime support.

## LeafGreen edition support

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

## Outside the map (FireRed / LeafGreen)

**Maps → Border → Around the map** shows a map, the maps connected to it (blue
outlines, named) and the tiles around them, as the game draws them. Space
outside every map belongs to the **nearest** map, which decides its fill and
keeps the tiles painted there, so the space around connected maps joins up
the same from either side:

- **Game border** — the game's repeating border pattern (**Pattern** view).
- **Extrude** — the map's last 2 rows and columns carried on outward, so 2×2
  things like trees stay whole.

**This map** picks one for the open map, or follows the **Mod default**, which
covers outdoor maps (Town, City, Route, Ocean route); indoor maps keep the game
border unless they choose Extrude themselves.

Any cell outside the maps, within the nearest map's **Margin** (0–64 tiles, 16 by default) can be painted
by hand from any tileset (**Paint tileset**): **Paint** sets a tile (click or
drag), **Revert** clears it back to the fill, **Pick** copies any cell's tile
and tileset. Right-click any tile (on the map or around it) to pick it without
changing tools, like the map builder's Pencil. Zoom with **-** / **+** or the mouse wheel over the map (50% to
800%, around the pointer); Shift+wheel scrolls up/down, Ctrl+wheel left/right. Move around with the
**Pan** tool (drag), or with any tool by dragging with the middle mouse button
or with Space held. The **Map** tool switches to another map: click a connected
map (or the space nearest to it) to edit its border instead.
Painted tiles win over the fill and are only for looks; nobody can
walk outside a map. The game uses them from `main.lua` (the engine isn't
changed), and they replace the player's VOID FILL option on those cells.

## FireRed maps and tilesets in Emerald

**GAME PATCHES → FireRed Maps** (Emerald) gives the mod FireRed's maps and
tilesets, read from a FireRed or LeafGreen import (the editor's or the linked
Gen1Recomp folder's). With it on:

- Every FireRed tileset (`FireRed: …`) can be painted with: the map builder's
  tileset list and **Create new map**, **Create / resize → Tileset**, and
  **Border → Around the map → Paint tileset**.
- **Maps → Import template map** lists FireRed's maps too (type "FireRed" in
  its search): one comes in as a new map builder map with that map's blocks,
  collision, heights, border and map type.
- **Import region** (on the patch) brings in every FireRed map at once, Kanto
  and the Sevii Islands, as `EM_KANTO_<name>`: FireRed's blocks, borders,
  connections, warps, name signs, signs and wild Pokemon (edit them in
  Encounters like any other list). Add a warp from a Hoenn map to reach them.
  **Edit this map** turns one into a map builder map like any other. Running
  it again on a project imported before signs came across gives those maps
  their signs.
- **Wild Pokemon** (a setting on the patch, on to start with): FireRed's wild
  Pokemon on the Kanto maps. Off: they have none until you make some. Wild
  Pokemon only appear once the player has a Pokemon.
- **People, marts & nurses** (a setting on the patch, on to start with):
  FireRed's everyday people -- the ones that just talk, Poke Mart clerks
  with FireRed's shop lists, and Pokemon Center nurses (Emerald's healing).
  In game they use FireRed's own sprites from the import; the editor shows
  Emerald look-alikes. Trainers, item balls and story people (anyone FireRed
  shows or hides with a flag) stay out. Off takes them back out; Import
  region again adds them to maps brought in earlier.

Signs read what they say in FireRed -- messages, braille and Pokemon
pictures -- rebuilt as Emerald scripts. They and the people show up in
Dialog and Events like any other, with FireRed's words read from your
import: edit them there. Only what you change is saved in the mod (as your
own text or script); everything else still comes from the player's import.
Signs that are machines or menus in FireRed (slot machines, vending
machines) are left out. People are rebuilt the same way (what they say,
their shop, their healing). Story people, trainers and other scripts don't
come across (FireRed's scripts don't run in Emerald), and each map keeps
its own FireRed music, played from the player's FireRed import (see
[Music from the other game](#music-from-the-other-game)). FireRed's shelves, dressers, trash bins,
signs and the like show their FireRed text when read. With People, marts &
nurses on, walking into a Kanto Pokemon Center makes it the place a blackout returns to: the player
wakes up healed in front of its nurse, as in FireRed (Hoenn's centers keep
working as they do). FireRed's tiles animate and its doors open as in FireRed;
spinner tiles spin and the Icefall Cave ice cracks, as in FireRed.

On these maps the Town Map (Emerald's PokeNav MAP) and the Fly move show FireRed's Kanto map, with the towns the player has walked into marked visited, and flying to a Kanto town lands on its imported copy. FireRed's own map screen is run by the game from the player's FireRed import; the mod carries no map art. Flying between regions is not possible: each region's Fly list is its own.

The PokeNav's map entry reads **REGION MAP** on these Kanto maps, with "Check the map of the region." under it, instead of Hoenn's. Change both in UI > Town Map > **PokeNav text** (the entry, up to 10 letters, and the description under it, up to 40; empty or **Default** restores the wording above).

The mod carries names only (`frlg__pallet_outdoor`, `frlg:FR_PALLET_TOWN`,
`EM_KANTO_…`), never FireRed's graphics or lists. In game `main.lua` reads
them from the player's own FireRed or LeafGreen import; without one the mod
doesn't turn on and says to import FireRed or LeafGreen first. Turning the
patch off hides FireRed from the pickers; maps already using it keep it.

## Emerald maps and tilesets in FireRed / LeafGreen

**GAME PATCHES → Emerald Maps** (FireRed and LeafGreen) is the same idea the
other way round: Emerald's maps and tilesets in a Kanto mod -- Hoenn in a
FireRed game -- read from an Emerald import. With it on:

- Every Emerald tileset (`Emerald: …`) can be painted with, wherever FireRed's
  are offered (map builder, **Create / resize → Tileset**, **Border**).
- **Maps → Import template map** lists Emerald's maps (type "Emerald" in its
  search).
- **Import region** brings in every Emerald map at once as
  `FR_HOENN_<name>`: Emerald's blocks, borders, connections, warps, signs,
  map names and wild Pokemon. Add a warp from a Kanto map to reach them.
- **Wild Pokemon** and **People, marts & nurses** (settings on the patch, on
  to start with) work as in FireRed Maps: Emerald's talkers, Poke Mart clerks
  with Emerald's shop lists, and Pokemon Center nurses (FireRed's healing);
  walking into a Hoenn Pokemon Center makes it the place a blackout returns
  to. People are drawn with Emerald's own sprites in the game (the editor
  shows FireRed look-alikes). Trainers, item balls, story people, map scripts
  and step triggers stay out.

Emerald's tiles, tile animations and door animations all play. Long grass
and deep sand act as FireRed's tall grass and sand, and Emerald's shelves,
vases, trash cans, shop shelves and blueprints show their Emerald text when
read. Muddy slopes slide you down, the Fortree and Pacifidlog bridges and
cracked floors react to your steps, and ash grass turns to ash, all run by the
game's own Emerald code (the ash puff and Soot Sack, though, are left out).

On these maps the Town Map and the Fly move show Emerald's Hoenn map, run by the game from the player's Emerald import, with the towns the player has walked into marked visited; flying to a Hoenn town lands on its imported copy. Fly stays within the region the player is in.
Hoenn's Acro / Mach Bike rails, bumpy slopes, berry soil and secret bases still
look right but act as plain ground or walls, and deep sand leaves no
footprints. Each map keeps its own Emerald music, played from the player's Emerald
import (see [Music from the other game](#music-from-the-other-game)).

The mod carries names only (`em__general__petalburg`, `em:EM_ROUTE101`,
`FR_HOENN_…`), never Emerald's graphics, maps or lists. In game `main.lua`
reads them from the player's own Emerald import; without one the mod doesn't
turn on and says to import Emerald first. Turning the patch off hides Emerald
from the pickers; maps already using it keep it. Clean Project keeps the patch
as it was (without the imported region).

## Kanto and Hoenn Region in a Clean Project

Clean Project hides the game's own maps. **GAME PATCHES → Kanto Region**
(FireRed and LeafGreen) and **Hoenn Region** (Emerald) bring them back,
without the story. The region is already in the game, so the button is only
needed if you deleted or changed the originals (Clean Project hides them).
They work the same way (Hoenn's maps are `EM_HOENN_<name>`, Kanto's
`FR_KANTO_<name>`); Kanto's, as an example:

- **Re-import region** adds every map -- Kanto and the Sevii Islands -- at once as
  `FR_KANTO_<name>`, joined by the game's own connections and warps, with its
  blocks, borders, music, map names and signs. They are the mod's own maps:
  paint, resize and connect them like any other. Add a warp or a connection
  from one of your maps to reach them. Maps it already has are left alone, so
  running it again only adds what is missing.
- **Wild Pokemon** (on to start with): each map gets the game's own wild
  Pokemon, editable in Encounters.
- **People, marts & nurses** (on to start with): the everyday people come
  too -- talkers, Poke Mart clerks with the game's shop lists, and Pokemon
  Center nurses (walking into a Kanto Pokemon Center makes it the place a
  blackout returns to). Trainers, item balls, story people, map scripts and
  step triggers stay out; add your own in the editor.
- **Town Map and Fly** work on the imported maps with no setting: the game's
  own map screen opens for the player's region, the towns the player walks
  into are marked visited, and Fly lands on the imported copy of the town (the
  original is hidden after Clean Project).

The mod carries names only (`FR_KANTO_…` / `EM_HOENN_…` maps naming the
game's own), never the game's graphics or lists.

## Regions

**UI > Town Map > Regions** defines regions of your own, with nothing imported
or linked behind them -- Kanto and Hoenn side by side, say. A region is a
name, a colour and the maps in it:

- **Maps by name:** list the map-name beginnings it owns (`EM_HOENN_, FR_HOENN_`).
  The longest match wins, and a map is in at most one region.
- **By hand:** type a map id and **Put in region** to add any map whatever it is
  called; **Remove** takes it out again. A map a prefix would have given the
  region can be taken out the same way.
- **Add the regions in use** offers the regions the maps already in the mod
  suggest (`EM_HOENN_`, `FR_KANTO_`...).
- **In the editor:** MAPS > the map list shows a colour bar per region, and
  searching `@hoenn` lists a region's maps (`@` every map that is in a region,
  `@-` the ones in none).
- **Preview the maps:** **Preview the maps** (or MAPS > World view > **Region**,
  with a region picker) lays out just that region's towns, cities and routes
  (not the buildings and caves in them) by their connections, outlined in the
  region's colour. Exits to maps outside the region show as
  yellow stubs.
- **In an Emerald game:** a region's **PokeNav** entry (up to 10 letters) and
  description (up to 40) replace "HOENN MAP" and its line on that region's maps.
  They are redrawn from the game's own label at run time, so the mod carries
  only the words. This wins over the Kanto wording above on a map both name.

A region's own Town Map picture, Fly list and cursor grid are not part of this
yet: the Town Map and Fly still show the screen of the game (or import) the
maps belong to.

## Music from the other game

Any map in an Emerald project can play FireRed / LeafGreen music, and any map in a
FireRed / LeafGreen project can play Emerald music (the other game's import has to
be there, like for the map imports).

- **Pick it:** AUDIO > **Map songs** > pick a map > the **Song** list has this
  game's songs, then the other game's ("FireRed: Pallet", "Emerald: Petalburg").
  **Play** previews either.
- **Imported maps keep their own song:** the maps Emerald Maps / FireRed Maps bring
  in play the song they have in their own game (before this they got a stand-in
  by map type). Without that game's audio in the import the stand-in is still used.
- **In the game:** the mod carries only a song number (the other game's number plus
  16384). The game reads the song from the player's own import of that game and
  plays it with its own music player, so volume, pausing, fades and jingles work as
  for any song. If the other game isn't imported the map is silent.
- Only map music is covered: battle music, jingles and the Pokemon Center / bike /
  surf songs the game picks itself stay the host game's.

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

Gen 3 layered maps refresh native water, sand, and flower animations on the
current map and visible connected maps using the runtime's shared animation
counter. Newly painted water without an explicit elevation uses elevation 0,
so surfing can cross into new routes from native water. Explicit elevations
are preserved.

Import a 16×16-tile PNG with **+ New PNG**, select the animated starting tile,
and click **Animate tile**. Choose an initial frame count in the **Animate**
drawer, then set every frame's source tile and duration independently. Frames
can be reordered, added, or deleted; **Static** removes the animation. Animated
starting tiles are marked **A** in the palette.

Save emits `tileset.animatedTiles` plus `mapbuilder_transforms.lua`. Gen1Recomp
builds the derived frame images on first load. Playback therefore requires a
Gen1Recomp runtime with `animatedTiles` support; the pinned runtime in
`runtime/gen1recomp` provides it (`src/render/TileRenderer.lua`).

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

**UI → Location banners** edits the arrival name plate for each map. Choose a
map and turn **Show banner on arrival** on or off (including for new custom
maps). Enter its banner text; leave the text blank to use the original region
name. **Export template** saves a 128×24 PNG without text. Edit that image and
use **Import artwork** to give this map a separate banner background. Other
windows retain their original artwork. **Use original artwork** removes the
image override. Save and restart Playtest; existing arrival/suppression rules
still apply. This changes the arrival banner, not Town Map or save-menu names.

To add a trainer battle sprite, use **Trainers → + Import new sprite** with a
64×64 PNG, or **+ New trainer sprite** in the native image asset browser.
The editor assigns a new sprite number and adds it to the trainer sprite
picker; existing sprites remain available. Other native UI image imports
still replace the selected image.

For additional overworld characters, open **GFX → Overworld**, select a sprite
with the frame layout you want, and use **Import as new sprite**. Import a PNG
with the same dimensions and vertically stacked frame order; **Export PNG**
provides a template. The new sprite gets its own ID, image, and frame metadata.
Select that ID in a map character's **Appearance** picker. Standing and walking
frames, frame size, and inanimate status follow the selected template. Save and
restart Playtest. IDs 240–255 remain reserved for script variables; this runtime
supports additional ordinary overworld sprites in the unused slots below 240.

Use **Audio → Music → + New**, then **Browse**, to import a new song. The new
numeric ID is available in **Map songs**; sound effects also support **+ New**.
Name the track to identify it in the audio list. Ordinary file imports choose
a unique filename if that filename already exists in the mod. Save and restart
Playtest to load the changes.

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
  New species are numbered from 440 up. They can be evolved into from the
  start: FireRed's rule that evolutions into species above #151 wait for the
  National Pokédex still applies to the game's own species, not to the mod's
  new ones, and evolutions into a new species keep their target however the
  game loads the records (`Gen3NewPokemon.lua`, run from main.lua).
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
  In a Gen 3 project the Map songs list also offers the other Gen 3 game's
  music when its import is there (see [Music from the other game](#music-from-the-other-game)).

Most forms commit edits immediately; use **Apply animation** and **Apply rules**
for animation/starter drafts before switching selections, then **Save**.
Applied edits participate in undo/redo and persist in `<mod>.editor_project.lua` beside the mod folder.
Existing in-folder projects remain readable and migrate on Save. Keep the sibling
source file when backing up editable projects; distribute only the runtime mod folder.
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
and edit each form's stats and moves. Use an item-use rule to switch an existing
Pokemon in the field, or a special mechanic for manual battle activation.
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

The picker also previews the other game's pictures when its import is there: Kanto and Sevii in an Emerald project (from your FireRed import), Hoenn in a FireRed / LeafGreen project (from your Emerald import). Those are view only (and can be exported as PNG), because in the game they are that game's own Town Map; nothing of them is stored in the mod.

### Fame Checker (FireRed)

UI > Fame Checker reads all 16 people and 96 facts from the verified FireRed USA 1.0 ROM. Use the character and fact dropdowns to edit names, fact headings, text pages, source/location labels, personal messages, and portraits. Text wraps in the preview; custom portraits must be 64 x 64 PNGs. Availability can follow original story events, be immediate, or depend on a story flag. Editing or pressing Enable Fame Checker in mod exports a working Bag-item viewer with your mod. Save, then restart playtest.

The viewer uses the original yellow ROM background, a scrolling five-name character list, six source icons, and the original character portraits. Up/Down selects a person; Right or A selects facts; directions move between the six facts; A turns text pages; Select switches to the personal portrait/message; B returns to the list or closes the viewer. The original story specials unlock the same six fact slots; all six unlock the personal message. Discovery progress persists in mod save data from when the mod is enabled. Earlier discoveries are not reconstructed from an existing save. Source/location text is descriptive and does not relocate the NPC or change its script. Character slots stay fixed so original events keep their identity.

Imported Title / Intro PNGs are applied directly to the native boot screen as well as the editor preview, including the title border background. Previously saved mods must be saved again to regenerate this runtime support.
