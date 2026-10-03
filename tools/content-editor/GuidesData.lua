-- GUIDES tab content; see Guides.lua for the format.
return {
  categories = {
    { id = "start", label = "Getting started" },
    { id = "gen3", label = "Game features" },
    { id = "maps", label = "Maps and events" },
    { id = "data", label = "Pokemon and data" },
  },
  guides = {
    {
      id = "first_mod", category = "start",
      title = "Start your first mod",
      summary = "Make a mod, point the editor at your game, save it and play it.",
      steps = {
        { "PROJECT tab, 1 PROJECT: type a name in New mod id and press Create. Your mods show as buttons there too -- click one to open it.", go = { tab = "project" } },
        { "2 TARGET GAME: pick the one game the mod is for.", go = { tab = "project" } },
        { "3 GAME DATA: Link Recomp to your Gen1Recomp folder (Playtest needs it), or Import ROM so the editor can read the game. Nothing from the ROM is copied into your mod.", go = { tab = "project" } },
        { "Change something in any tab, then press Save at the top right (Ctrl+S). Save writes your mod into mods/<your mod id>." },
        { "4 CHECK & RUN: Validate mod finds mistakes, Scan mod checks for ripped game files, and Playtest mod starts the game with your mod.", go = { tab = "project" } },
      },
    },
    {
      id = "basics", category = "start",
      title = "Saving, undo and sharing",
      summary = "The keys and buttons you'll use every time.",
      steps = {
        { "Save: Ctrl+S or the Save button. A * after the mod name (top left) means there are unsaved changes." },
        { "Undo: Ctrl+Z. Redo: Ctrl+Y. The Undo / Redo buttons at the top do the same." },
        { "The bar along the bottom says what just happened -- look there if something didn't seem to work." },
        { "Open (top right) opens another mod. Close quits; it asks twice if you haven't saved." },
        { "To share a mod, share its mods/<your mod id> folder only -- never a ROM or the data/generated folder." },
      },
    },
    {
      id = "update", category = "start",
      title = "Keep the editor up to date",
      summary = "New versions come out often. The Updates button installs them for you.",
      steps = {
        { "The editor checks for a new version when it opens. When there is one, the button at the top right says Update to v0.1.x." },
        { "Press it, then Download update. " },
        { "Press Restart to update. The editor closes, copies the new files in and opens again. Your mods, game data, saves and settings aren't touched." },
      },
    },
    {
      id = "clock", category = "gen3", gen3 = true,
      title = "Real Time Clock (day and night)",
      summary = "Outdoor maps follow the player's clock: morning, day and night, like Pokemon Crystal. FireRed and LeafGreen only.",
      steps = {
        { "GAME PATCHES: turn Real Time Clock On. Encounter tables come on with it.", go = { tab = "patches" } },
        { "Press Settings (or go to GFX > Day & night) to set when morning, day and night start, the fade, and the colours.", go = { tab = "gfx", set = { g3GfxMode = "daynight" } } },
        { "Use the time bar (Play runs a whole day in 36 seconds) to preview maps at any time of day." },
        { "Test hour pins one hour for playtests. Clear it before you share the mod.", go = { tab = "gfx", set = { g3GfxMode = "daynight" } } },
        { "Towns, cities, routes and ocean routes change with the time; buildings, caves, battles and menus don't. A map's type (Map setup) decides." },
      },
    },
    {
      id = "clock_npc", category = "gen3", gen3 = true,
      title = "An NPC who tells the time",
      summary = "A person who reads the day, date and time, then says something different in the morning, the day and at night. FireRed and LeafGreen only.",
      steps = {
        { "GAME PATCHES: turn Real Time Clock On. Morning, day and night start at the hours set in GFX > Day & night.", go = { tab = "patches" } },
        { "MAPS: open the map (Pallet Town, say) and press Edit this map if it isn't editable yet.", go = { tab = "maps" } },
        { "Add events > Event > Talking NPC. Type his first line in the box next to it -- \\n is a new line, \\p a new text box: Let me check my\\nwatch...\\pIt's {STR_VAR_1},\\n{STR_VAR_2}.\\pThe time is\\n{STR_VAR_3}. Then click a free tile on the map.", go = { tab = "maps" } },
        { "Press Open event window. Appearance > CHOOSE GRAPHIC: type old and pick 32 Old man." },
        { "What happens > Add action... > Read the clock (day, date and time). It goes at the top, so his line can say {STR_VAR_1} (the day, e.g. Tuesday), {STR_VAR_2} (the date, e.g. 29 September) and {STR_VAR_3} (the time, e.g. 10:42 PM)." },
        { "Add action... > Check the time or day... > It's night. Pick the Show dialogue line under If it's night, change the text (Yawn... I'm getting\\nsleepy. Good night!) and press Apply text." },
        { "Do the same with It's day, then It's before 6 AM (for early morning). Checks run from the top: the first one that matches is said and the event ends there." },
        { "Add action... > Show dialogue for the morning line. It comes after the checks, so it's said when none of them match." },
        { "Pick an If line to change its check or Remove this check. Other checks: a day of the week (It's Tuesday) or an hour (It's 6 PM or later)." },
        { "Save, then Playtest. To hear each line, set Test hour in GFX > Day & night, and clear it before you share the mod.", go = { tab = "gfx", set = { g3GfxMode = "daynight" } } },
      },
    },
    {
      id = "night_looks", category = "gen3", gen3 = true,
      title = "Lit windows and lamps at night",
      summary = "Give blocks their own night colours so windows and lamps glow in the dark. FireRed and LeafGreen only.",
      steps = {
        { "GFX > Blocks: pick a tileset and a block (a window, say).", go = { tab = "gfx", set = { g3GfxMode = "blocks" } } },
        { "Press Night look, select the pixels that should light up, choose a colour and press Use this colour." },
        { "Find similar blocks finds the same kind of window across the other outdoor tilesets -- apply the ones that look right." },
        { "FireRed's own outdoor blocks already have night looks. GFX > Day & night > Add default night looks puts back any that are missing.", go = { tab = "gfx", set = { g3GfxMode = "daynight" } } },
      },
    },
    {
      id = "time_encounters", category = "gen3", gen3 = true,
      title = "Wild Pokemon by time of day",
      summary = "Different wild Pokemon in the morning, by day and at night. FireRed and LeafGreen only.",
      steps = {
        { "GAME PATCHES: Real Time Clock On, and Encounter tables On. FireRed's own routes and caves get Pokemon Crystal's morning / day / night lists straight away.", go = { tab = "patches" } },
        { "ENCOUNTERS: pick a map, then Grass and Morning, Day or Night. Change any slot like a normal list.", go = { tab = "encounters", set = { g3EncounterKind = "land", g3EncounterSection = "wild", g3EncounterTime = "night" } } },
        { "On a map you've added, pick Morning, Day or Night and press Give morning, day and night their own lists." },
        { "All day > Keep the all-day list at every time stops one table changing with the time; Back to one all-day list removes its morning / day / night lists.", go = { tab = "encounters", set = { g3EncounterTime = "all" } } },
      },
    },
    {
      id = "clean", category = "gen3", gen3 = true,
      title = "Start from scratch (Clean Project)",
      summary = "A blank game: no story, events or game maps. Only do this at the start of a project. FireRed, LeafGreen and Emerald.",
      steps = {
        { "GAME PATCHES > Clean Project > Apply, read the warning, then Wipe and start clean. Everything in the open mod is wiped -- it can't be undone.", go = { tab = "patches" } },
        { "You get one blank starter map; a new game starts there. The intro only asks boy or girl and the player's name." },
        { "MAPS > Import template map copies any of the game's maps' layouts into a new map, without its events or story. In Emerald with GAME PATCHES > FireRed Maps on, FireRed's maps and tilesets are there too; in FireRed and LeafGreen, GAME PATCHES > Emerald Maps does the same with Emerald's.", go = { tab = "maps" } },
        { "To get the game's own maps back after cleaning, use GAME PATCHES > Kanto Region (FireRed, LeafGreen) or Hoenn Region (Emerald) > Re-import region: every map comes back as FR_KANTO_ / EM_HOENN_ maps, with its connections, signs, wild Pokemon and everyday people, but no story.", go = { tab = "patches" } },
      },
    },
    {
      id = "png_maps", category = "gen3", gen3 = true,
      title = "Make a map from a picture",
      summary = "Draw a map in any art program, then turn the PNG into real FireRed tiles.",
      steps = {
        { "MAPS: open or create the map, and press Edit this map if it isn't editable yet.", go = { tab = "maps" } },
        { "In the Map Builder, Use PNG loads your picture as a stencil over the map. Size makes the map fit the picture (screenshots scaled up 2x-8x are shrunk back)." },
        { "Use as map turns the picture into FireRed blocks, in a copy of the closest tileset -- the game's own tilesets are never changed." },
        { "The new blocks can be edited in GFX > Blocks like any other.", go = { tab = "gfx", set = { g3GfxMode = "blocks" } } },
      },
    },
    {
      id = "blocks", category = "gen3", gen3 = true,
      title = "Edit tiles and blocks",
      summary = "Blocks are the 16x16 squares maps are painted with: two layers of 8x8 tiles.",
      steps = {
        { "GFX > Blocks: pick a tileset, then a block.", go = { tab = "gfx", set = { g3GfxMode = "blocks" } } },
        { "Paint on a copy edits a tile without changing it everywhere else it's used. Swap layers puts a tile on top of or under the player." },
        { "Behaviour sets what the block does in game: grass, water, a door and so on." },
        { "Save the mod to keep your changes." },
      },
    },
    {
      id = "new_map", category = "maps",
      title = "Make a new map",
      summary = "Create a map, paint it and set how it's walked on.",
      steps = {
        { "MAPS > Create new map: give it a name, pick a size, a visual style and a map type (Town, Route, Indoor...), then Create map.", go = { tab = "maps" } },
        { "Map Builder tools: Pencil, Fill and Rectangle paint the chosen block; Eraser clears; Picker takes a block from the map." },
        { "Collision paints where the player can walk: walls, grass (wild Pokemon), water (Surf) and ledges." },
        { "Press Save changes (or Ctrl+S) when you're done." },
      },
    },
    {
      id = "edit_map", category = "maps",
      title = "Change one of the game's maps",
      summary = "Edit an existing town or route.",
      steps = {
        { "MAPS: pick the map in the list and press Edit this map. This makes the mod's own copy; the game's map isn't changed.", go = { tab = "maps" } },
        { "Paint, add events and save as usual. World View shows the map with its neighbours." },
        { "Changed your mind? More actions > Reset original puts the game's version back." },
      },
    },
    {
      id = "warps", category = "maps",
      title = "Doors, stairs and caves (warps)",
      summary = "Connect maps so the player can walk between them.",
      steps = {
        { "In the Map Builder, choose Warp and click the door cell. Two-way links both ends at once; One-way and Custom return only go one way.", go = { tab = "maps" } },
        { "Exit type paints what kind of exit a cell is: Door, Stairs, Cave, Pad or Carpet. It decides the sound and the walk-out." },
        { "For caves: the cave mouth outside is Cave, and the tile you land on inside is Carpet facing down." },
      },
    },
    {
      id = "people", category = "maps",
      title = "People, signs and trainers",
      summary = "Put NPCs, signs, trainers and Pokemon on a map.",
      steps = {
        { "In the Map Builder's event tools: Event places a person or object, Sign a sign, Trainer a trainer (pick the class first), Wild a Pokemon you can battle.", go = { tab = "maps" } },
        { "Trigger places a step tile that stops the player and runs a script." },
        { "Select picks an event to change what it says or does." },
      },
    },
    {
      id = "cutscenes", category = "maps",
      title = "Cutscenes",
      summary = "Dialogue and movement played out on a map.",
      steps = {
        { "EVENTS > Cutscenes > New cutscene.", go = { tab = "events", set = { g3EventMode = "cutscenes" } } },
        { "Add dialogue, waits and movement routes; copy, reorder or delete them." },
        { "Open viewer plays it on its map. Playtest event runs it in the real game (needs a linked Recomp)." },
        { "To trigger it in game: Map events > Edit appearance / conditions > Event / cutscene script.", go = { tab = "events", set = { g3EventMode = "map" } } },
      },
    },
    {
      id = "pokemon", category = "data",
      title = "Change a Pokemon",
      summary = "Stats, types, moves learned and pictures.",
      steps = {
        { "POKEMON: pick a Pokemon from the list; the form on the right changes it.", go = { tab = "pokemon" } },
        { "Its pictures are in GFX > Pokemon.", go = { tab = "gfx", set = { g3GfxMode = "pokemon" } } },
        { "Save, then Playtest mod to try it." },
      },
    },
    {
      id = "moves_items", category = "data",
      title = "Moves and items",
      summary = "Power, accuracy, prices and what items do.",
      steps = {
        { "MOVES: pick a move to change its power, accuracy and the rest of its details.", go = { tab = "moves" } },
        { "ITEMS: pick an item to change its details.", go = { tab = "items" } },
      },
    },
    {
      id = "trainers", category = "data",
      title = "Trainers",
      summary = "Who they are and which Pokemon they use.",
      steps = {
        { "TRAINERS: pick a trainer and change their party.", go = { tab = "trainers" } },
        { "To add one to a map, use the Trainer tool in the Map Builder.", go = { tab = "maps" } },
      },
    },
    {
      id = "wild", category = "data",
      title = "Wild encounters",
      summary = "Which wild Pokemon appear, and how often.",
      steps = {
        { "ENCOUNTERS: pick a map, then Grass, Surf, Rock Smash or Fishing.", go = { tab = "encounters", set = { g3EncounterSection = "wild", g3EncounterTime = "all" } } },
        { "Encounter rate is how often they appear. Each slot has a Pokemon and a level range; the first slots are the most common." },
        { "Disable table turns one off; Revert map puts the game's list back." },
      },
    },
  },
}
