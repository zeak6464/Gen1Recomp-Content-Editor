-- GAME PATCHES tab: switches for features a mod adds on top of the game
-- (nothing in the engine is changed; each one is generated into main.lua).
-- FireRed / LeafGreen / Emerald: the real time clock (day and night,
-- Gen3DayNight); on FireRed / LeafGreen with its encounter tables as a
-- setting of it, Emerald Maps (Gen3EmLink) and Kanto Region
-- (Gen3KantoRegion). Emerald: FireRed Maps (Gen3FrLink), Hoenn Region
-- (Gen3HoennRegion), the Physical/Special split (Gen3Split) and the System
-- Clock (Gen3SystemClock).
--
-- Each patch is a title, one line under it and an Off / On switch; what it
-- does in detail opens in a pop-up (Description).

local Kit = require("Kit")
local Theme = require("Theme")
local PAL = Theme.PAL

local M = {}

-- A two-way switch: "Off" | "On" (smaller for a sub setting). Returns the
-- new value when clicked.
local function switch(x, y, on, s, small)
  local w, h = (small and 64 or 90) * s, (small and 24 or 34) * s
  local picked
  if Kit.chip(x, y, w, h, "Off", not on, PAL.red, nil, "Turn it off") and on then picked = false end
  if Kit.chip(x + w + 6 * s, y, w, h, "On", on, PAL.green, nil, "Turn it on") and not on then picked = true end
  return picked
end

-- What the pop-ups say ---------------------------------------------------------

local function clockText(S)
  local DN = require("Gen3DayNight")
  local on, cfg = DN.enabled(S.project), DN.settings(S.project)
  local lines = {
    "The game follows the player's own clock. Outdoor maps (Town, City, Route, Ocean route) look like morning, day or night; buildings, caves, battles and menus look the same all day.",
    ("Morning from %d:00, day from %d:00, night from %d:00, with a %d-minute fade (Settings)."):format(
      cfg.morning, cfg.day, cfg.night, cfg.blend),
    ("%d blocks have a night look: lit windows, lamps and signs."):format(#DN.paintedBlocks(S.project)),
    DN.encountersEnabled(S.project) and "Wild encounters change with the time of day (Encounter tables)."
      or "Wild encounters use the all-day lists (Encounter tables is off).",
    "Turning it off keeps every setting and night look for when it's turned on again. Encounter tables go off with it, and on again with it.",
    on and "It is on." or "It is off: the game has no clock.",
  }
  if cfg.testHour then
    lines[#lines + 1] = ("Test hour %d:00 is pinned -- clear it in Settings before you share the mod."):format(cfg.testHour)
  end
  return "Real Time Clock", lines
end

local function encounterText(S)
  local DN = require("Gen3DayNight")
  local lines = {
    ("On: FireRed's own routes and caves (%d Kanto tables) get Pokemon Crystal's morning, day and night lists straight away, as their own lists. Maps added in a mod aren't touched."):format(#DN.crystalTargets(S.project)),
    "Edit them in Encounters (pick a map, then Morning, Day or Night) like any other list. Back to one all-day list or Keep the all-day list at every time takes one table out.",
    "Off: Crystal's lists come back out and every table uses its all-day list. Tables you've edited are kept, and so are lists you made yourself.",
    "It's a setting of the real time clock: off while the clock is off, and on again when the clock is turned on.",
  }
  return "Encounter tables", lines
end

local function wrappedLines(f, text, width)
  if f and f.getWrap then
    local _, wrapped = f:getWrap(text, width)
    return math.max(1, #wrapped)
  end
  return 1
end

-- The pop-up, over the tab: a description, or (for an action) a warning
-- with Cancel and a confirm button.
local function popup(S, App, x, y, w, h)
  local s = Kit.scale
  local confirm = S._gamePatchConfirm and M.confirms[S._gamePatchConfirm]
  local title, lines
  if confirm then title, lines = confirm.title, confirm.lines(S)
  else title, lines = M.describe[S._gamePatchPopup](S) end
  local G = love.graphics
  local f = Kit.fonts and Kit.fonts.small
  local bw = math.min(w - 40 * s, 640 * s)
  local textW = bw - 40 * s
  local lineH = f and f:getHeight() * 1.25 or 18 * s
  local total = 0
  for _, line in ipairs(lines) do total = total + wrappedLines(f, line, textW) * lineH + 8 * s end
  local bh = total + 110 * s
  local bx, by = x + (w - bw) / 2, y + 40 * s
  Theme.col(PAL.bgBot, 0.75)
  G.rectangle("fill", x, y, w, h)
  -- solid underneath: the card itself is see-through
  Theme.col(PAL.bgMid, 1)
  G.rectangle("fill", bx, by, bw, bh, 16 * s, 16 * s)
  Kit.card(bx, by, bw, bh)
  Kit.text("button", title, bx + 20 * s, by + 18 * s, PAL.heading)
  local ty = by + 54 * s
  for i, line in ipairs(lines) do
    Theme.col(confirm and i == 1 and PAL.red or PAL.text, 1)
    if f then G.setFont(f) end
    G.printf(line, bx + 20 * s, ty, textW, "left")
    ty = ty + wrappedLines(f, line, textW) * lineH + 8 * s
  end
  G.setColor(1, 1, 1, 1)
  if confirm then
    if Kit.button(bx + bw - 140 * s, by + bh - 46 * s, 120 * s, 30 * s, "Cancel", { kind = "ghost", font = "micro" })
        or (Kit.mouseClicked and not Kit.hit(bx, by, bw, bh)) then
      S._gamePatchConfirm = nil
    elseif Kit.button(bx + 20 * s, by + bh - 46 * s, 240 * s, 30 * s, confirm.button, { kind = "danger", font = "micro" }) then
      S._gamePatchConfirm = nil
      confirm.run(S, App)
    end
    return
  end
  local close = Kit.button(bx + bw - 140 * s, by + bh - 46 * s, 120 * s, 30 * s, "Close", { kind = "ghost", font = "micro" })
  if close or (Kit.mouseClicked and not Kit.hit(bx, by, bw, bh)) then S._gamePatchPopup = nil end
end

-- The patches ---------------------------------------------------------------
-- Each patch gets its own box. Its sub settings share that box, below a
-- line, with smaller text and switches.

local function cleanText(S)
  local applied = require("Gen3Clean").enabled(S.project)
  return "Clean Project", {
    "Start a mod from scratch. Apply wipes the open project and leaves one blank starter map.",
    "A new game starts on the starter map (PLAYER tab > start map) with no story flags, variables or events.",
    "The intro only asks boy or girl and the player's name: no professor, no rival. The title screen and menu stay.",
    S and require("Generation").id(S) == "emerald"
      and "Emerald's own maps and scripts are hidden and can't be reached in game; the game starts on your map, not in the truck. MAPS > Import template map brings an Emerald map's layout in under a new name -- never its events or story -- and Hoenn Region > Import region brings them all in at once, without the story. FireRed Maps stays as it is: with it on, FireRed's tilesets and template maps are there too (the imported region is removed with everything else)."
      or "FireRed's own maps and scripts are hidden and can't be reached in game. MAPS > Import template map brings a FireRed map's layout in under a new name -- never its events or story. Emerald Maps stays as it is: with it on, Emerald's tilesets and template maps are there too (the imported region is removed with everything else).",
    "Pokemon, moves, items, types, tilesets, graphics and trainers stay available.",
    applied and "This project is clean." or "Only do this at the start of a project.",
  }
end

local function splitText(S)
  local on = require("Gen3Split").enabled(S.project)
  return "Physical/Special Split", {
    "Each move is Physical or Special by itself, as in Gen 4, instead of by its type. Fire Punch hits with Attack, Shadow Ball with Special Attack.",
    "Every original move starts at its official Gen 4 category. Change one in MOVES > Category.",
    "Hidden Power and Weather Ball stay Special whatever type they become.",
    on and "It is on." or "It is off: moves are Physical or Special by their type.",
  }
end

local function systemClockText(S)
  local on = require("Gen3SystemClock").enabled(S.project)
  return "System Clock", {
    "On a new game, checking the bedroom clock sets the game's clock to the PC's clock. No clock screen opens and the story goes on as normal.",
    "From then on the game's time is the PC's time: berries, tides and daily events follow it.",
    "Saves that already set their clock keep their own time.",
    on and "It is on." or "It is off: the player sets the bedroom clock by hand.",
  }
end

local function fireRedText(S)
  local FrLink = require("Gen3FrLink")
  local link = FrLink.editor()
  return "FireRed Maps", {
    "Use FireRed's maps and tilesets in this Emerald mod. They're read from a FireRed or LeafGreen import -- yours in the editor, the player's in the game. The mod itself holds no FireRed graphics.",
    "On: every FireRed tileset can be painted with (map builder, Create / resize, Around the map), and MAPS > Import template map lists FireRed's maps (type FireRed in its search).",
    "Import region brings in every FireRed map at once as EM_KANTO_<name>, joined by FireRed's own connections and warps, with its signs. Story people, trainers and other scripts don't come across (FireRed's scripts don't run in Emerald) -- add them in the editor, and a warp from Hoenn to reach Kanto. Music is Emerald's. Spinner tiles and the Icefall Cave ice work as in FireRed. On these maps the Town Map (via the PokeNav) and Fly show FireRed's Kanto map, with the towns the player has walked into.",
    "People, marts & nurses (a setting, on to start with): FireRed's everyday people come too -- the ones that talk, Poke Mart clerks with FireRed's shop lists, and Pokemon Center nurses that heal. Walking into a Kanto Pokemon Center also makes it where a blackout returns to. They look like FireRed's people in the game (the editor shows Emerald look-alikes).",
    "Wild Pokemon (a setting of FireRed Maps, on to start with): the Kanto maps get FireRed's own wild Pokemon, editable in Encounters. Off: they have none until you make some. (Wild Pokemon only appear once the player has a Pokemon.)",
    "The PokeNav's map entry on the Kanto maps reads REGION MAP; its wording is in UI > Town Map > PokeNav text.",
    "Players need FireRed or LeafGreen imported: without one the mod doesn't turn on and says so.",
    link and ("Found your " .. (link.game == "leafgreen" and "LeafGreen" or "FireRed") .. " import.")
      or "No FireRed or LeafGreen import found: import one in PROJECT first.",
  }
end

local function emeraldMapsText(S)
  local EmLink = require("Gen3EmLink")
  local link = EmLink.editor()
  return "Emerald Maps", {
    "Use Emerald's maps and tilesets in this FireRed / LeafGreen mod -- Hoenn in a Kanto game. They're read from an Emerald import: yours in the editor, the player's in the game. The mod itself holds no Emerald graphics, maps or lists, only their names.",
    "On: every Emerald tileset can be painted with (map builder, Create / resize, Around the map), and MAPS > Import template map lists Emerald's maps (type Emerald in its search).",
    "Import region brings in every Emerald map at once as FR_HOENN_<name>, joined by Emerald's own connections and warps, with its signs and map names. Story people, trainers, item balls and map scripts don't come across (Emerald's scripts don't run in FireRed) -- add them in the editor, and a warp from Kanto to reach Hoenn. Music is FireRed's. On these maps the Town Map and Fly show Emerald's Hoenn map, with the towns the player has walked into.",
    "People, marts & nurses (a setting, on to start with): Emerald's everyday people come too -- the ones that only talk, Poke Mart clerks with Emerald's shop lists, and Pokemon Center nurses that heal. Walking into a Hoenn Pokemon Center also makes it where a blackout returns to. They look like Emerald's people in the game (the editor shows FireRed look-alikes).",
    "Wild Pokemon (a setting of Emerald Maps, on to start with): the Hoenn maps get Emerald's own wild Pokemon, editable in Encounters. Off: they have none until you make some. (Wild Pokemon only appear once the player has a Pokemon.)",
    "Long grass and deep sand act as FireRed's tall grass and sand, and Emerald's shelves, vases, trash cans and shop shelves show their text. Muddy slopes, the Fortree and Pacifidlog bridges, cracked floors and ash grass work as in Emerald. Rails for the Acro / Mach Bike, bumpy slopes, berry soil and secret bases look right but behave as plain ground or walls in FireRed.",
    "Players need Emerald imported: without it the mod doesn't turn on and says so.",
    link and "Found your Emerald import." or "No Emerald import found: import one in PROJECT first.",
  }
end

local function kantoText(S)
  local Kanto = require("Gen3KantoRegion")
  return "Kanto Region", {
    "Bring the game's own maps (Kanto and the Sevii Islands) into this mod without the story. It's for a Clean Project mod, where the game's maps are hidden and can't be reached: with it, Kanto can be joined to your own maps (and to Hoenn, from Emerald Maps).",
    "Kanto is already in the game, so this is only needed if you deleted or changed the originals (a Clean Project hides them). Re-import region adds every map again at once as FR_KANTO_<name>, joined by the game's own connections and warps, with its music and signs. They are the mod's own maps: paint, resize and connect them like any other. Add a warp or a connection from one of your maps to reach Kanto. The Town Map and Fly work on them, and Fly lands on the copies once the originals are removed.",
    "People, marts & nurses (a setting, on to start with): the everyday people come too -- the ones that only talk, Poke Mart clerks and Pokemon Center nurses. Walking into a Kanto Pokemon Center makes its town where a blackout returns to. Story people, trainers, item balls, map scripts and step triggers stay out -- add your own in the editor.",
    "Wild Pokemon (a setting, on to start with): the Kanto maps get the game's own wild Pokemon, editable in Encounters. Off: they have none until you make some.",
    "The mod holds names only: the maps, scripts and lists are the game's own.",
    Kanto.imported(S.project) and "The region is imported." or "The region isn't imported yet.",
  }
end

local function hoennText(S)
  local Hoenn = require("Gen3HoennRegion")
  return "Hoenn Region", {
    "Bring Emerald's own maps into this mod without the story. It's for a Clean Project mod, where Emerald's maps are hidden and can't be reached: with it, Hoenn can be joined to your own maps (and to Kanto, from FireRed Maps).",
    "Hoenn is already in the game, so this is only needed if you deleted or changed the originals (a Clean Project hides them). Re-import region adds every Emerald map again at once as EM_HOENN_<name>, joined by Emerald's own connections and warps, with its music and signs. They are the mod's own maps: paint, resize and connect them like any other. Add a warp or a connection from one of your maps to reach Hoenn. The Town Map and Fly work on them, and Fly lands on the copies once the originals are removed.",
    "People, marts & nurses (a setting, on to start with): Emerald's everyday people come too -- the ones that only talk, Poke Mart clerks and Pokemon Center nurses. Walking into a Hoenn Pokemon Center makes its town where a blackout returns to. Story people, trainers, item balls, map scripts and step triggers stay out -- add your own in the editor.",
    "Wild Pokemon (a setting, on to start with): the Hoenn maps get Emerald's own wild Pokemon, editable in Encounters. Off: they have none until you make some.",
    "The mod holds names only: the maps, scripts and lists are the game's own.",
    Hoenn.imported(S.project) and "The region is imported." or "The region isn't imported yet.",
  }
end

M.describe = { clock = clockText, encounters = encounterText, clean = cleanText, split = splitText,
  systemClock = systemClockText, firered = fireRedText, frwild = fireRedText, frpeople = fireRedText,
  hoenn = hoennText, hoennwild = hoennText, hoennpeople = hoennText,
  kanto = kantoText, kantowild = kantoText, kantopeople = kantoText,
  emmaps = emeraldMapsText, emwild = emeraldMapsText, empeople = emeraldMapsText }

M.confirms = {
  region = {
    title = "Import region -- add every FireRed map?",
    button = "Import the FireRed region",
    lines = function(S)
      local n = #(require("Gen3FrLink").maps())
      return {
        ("Adds %d FireRed maps to this mod as EM_KANTO_<name> maps (Kanto and the Sevii Islands). Maps it already has are left alone."):format(n),
        "They keep FireRed's blocks, borders, connections, warps and signs, read from the FireRed or LeafGreen import"
          .. (require("Gen3FrLink").wildEnabled(S.project) and ", and its wild Pokemon (Wild Pokemon is on)." or ". Wild Pokemon is off: turn it on for Kanto's wild Pokemon.")
          .. (require("Gen3FrLink").peopleEnabled(S.project) and " Everyday people, mart clerks and nurses come too; story people, trainers and other scripts don't." or " People aren't copied (People, marts & nurses is off).") ,
        "Maps already brought in by an earlier Import region get their signs and people. Add a warp from a Hoenn map to reach Kanto. Undo removes them again.",
      }
    end,
    run = function(S, App)
      local ok, added, skipped, signs, left, people = pcall(require("Gen3FrLink").importRegion, S)
      if not ok then S.status = "Import region failed: " .. tostring(added); return end
      if not added then S.status = tostring(skipped); return end
      App.markDirty()
      S.status = ("Imported %d FireRed maps (EM_KANTO_...)%s, %d signs%s, %d people"):format(added,
        skipped > 0 and (", " .. skipped .. " already there") or "", signs or 0,
        (left or 0) > 0 and (" (" .. left .. " machines and menus left out)") or "", people or 0)
    end,
  },
  emregion = {
    title = "Import region -- add every Emerald map?",
    button = "Import the Hoenn region",
    lines = function(S)
      local EmLink = require("Gen3EmLink")
      return {
        ("Adds %d Emerald maps to this mod as FR_HOENN_<name> maps (Hoenn). Maps it already has are left alone."):format(#EmLink.maps()),
        "They keep Emerald's blocks, borders, connections, warps and signs, read from the Emerald import"
          .. (EmLink.wildEnabled(S.project) and ", and its wild Pokemon (Wild Pokemon is on)." or ". Wild Pokemon is off: turn it on for Hoenn's wild Pokemon.")
          .. (EmLink.peopleEnabled(S.project) and " Everyday people, mart clerks and nurses come too; story people, trainers and other scripts don't." or " People aren't copied (People, marts & nurses is off)."),
        "Maps already brought in by an earlier Import region get their signs and people. Add a warp from a Kanto map to reach Hoenn. Undo removes them again.",
      }
    end,
    run = function(S, App)
      local ok, added, skipped, signs, left, people = pcall(require("Gen3EmLink").importRegion, S)
      if not ok then S.status = "Import region failed: " .. tostring(added); return end
      if not added then S.status = tostring(skipped); return end
      App.markDirty()
      S.status = ("Imported %d Emerald maps (FR_HOENN_...)%s, %d signs%s, %d people"):format(added,
        skipped > 0 and (", " .. skipped .. " already there") or "", signs or 0,
        (left or 0) > 0 and (" (" .. left .. " machines and menus left out)") or "", people or 0)
    end,
  },
  kanto = {
    title = "Re-import region -- add every Kanto map again?",
    button = "Re-import the Kanto region",
    lines = function(S)
      local Kanto = require("Gen3KantoRegion")
      return {
        ("Adds %d maps to this mod as FR_KANTO_<name> maps (Kanto and the Sevii Islands). Maps it already has are left alone."):format(Kanto.pending(S)),
        "They keep the game's blocks, borders, connections, warps, music and signs"
          .. (Kanto.wildEnabled(S.project) and ", and its wild Pokemon (Wild Pokemon is on)." or ". Wild Pokemon is off: turn it on for Kanto's wild Pokemon.")
          .. (Kanto.peopleEnabled(S.project) and " Everyday people, mart clerks and nurses come too; story people, trainers and map scripts don't." or " People aren't copied (People, marts & nurses is off)."),
        "Add a warp or a connection from one of your maps to reach Kanto. Undo removes them again.",
      }
    end,
    run = function(S, App)
      local ok, added, skipped, signs, people = pcall(require("Gen3KantoRegion").importRegion, S)
      if not ok then S.status = "Re-import region failed: " .. tostring(added); return end
      if not added then S.status = tostring(skipped); return end
      App.markDirty()
      S.status = ("Imported %d Kanto maps (FR_KANTO_...)%s, %d signs, %d people"):format(added,
        skipped > 0 and (", " .. skipped .. " already there") or "", signs or 0, people or 0)
    end,
  },
  hoenn = {
    title = "Re-import region -- add every Hoenn map again?",
    button = "Re-import the Hoenn region",
    lines = function(S)
      local Hoenn = require("Gen3HoennRegion")
      return {
        ("Adds %d Emerald maps to this mod as EM_HOENN_<name> maps. Maps it already has are left alone."):format(#Hoenn.maps(S)),
        "They keep Emerald's blocks, borders, connections, warps, music and signs"
          .. (Hoenn.wildEnabled(S.project) and ", and its wild Pokemon (Wild Pokemon is on)." or ". Wild Pokemon is off: turn it on for Hoenn's wild Pokemon.")
          .. (Hoenn.peopleEnabled(S.project) and " Everyday people, mart clerks and nurses come too; story people, trainers and map scripts don't." or " People aren't copied (People, marts & nurses is off)."),
        "Add a warp or a connection from one of your maps to reach Hoenn. Undo removes them again.",
      }
    end,
    run = function(S, App)
      local ok, added, skipped, signs, people = pcall(require("Gen3HoennRegion").importRegion, S)
      if not ok then S.status = "Re-import region failed: " .. tostring(added); return end
      if not added then S.status = tostring(skipped); return end
      App.markDirty()
      S.status = ("Imported %d Hoenn maps (EM_HOENN_...)%s, %d signs, %d people"):format(added,
        skipped > 0 and (", " .. skipped .. " already there") or "", signs or 0, people or 0)
    end,
  },
  clean = {
    title = "Clean Project -- wipe this project?",
    button = "Wipe and start clean",
    lines = function(S)
      return {
        "This should only be done at the start of a project. All changes made up until this point will be gone.",
        ("Everything in %s -- maps, events, scripts, Pokemon, items, trainers, graphics and settings edits -- is removed, and the mod is saved straight away. It can't be undone."):format(
          tostring((S.project or {}).name or (S.project or {}).id or "this mod")),
        "What's left: one blank starter map, a new game that starts there with no story, and the short intro (boy or girl, and a name).",
      }
    end,
    run = function(S, App)
      local ok, result = pcall(require("Gen3Clean").apply, S)
      if not ok then S.status = "Clean Project failed: " .. tostring(result); return end
      App.markDirty()
      local path = S.path
      if path and App.save() then
        if App.openMod then App.openMod(path) end
        S.status = "Clean Project applied: starting from " .. tostring(result)
      else
        S.status = "Clean Project applied (not saved yet): starting from " .. tostring(result)
      end
      S.tab = "patches"
    end,
  },
}

local function dayNight() return require("Gen3DayNight") end

local function kanto(S)
  local game = require("Generation").id(S)
  return game == "firered" or game == "leafgreen"
end

local function emerald(S) return require("Generation").id(S) == "emerald" end

-- `kanto` patches and subs are FireRed / LeafGreen only; `emerald` ones Emerald only.
M.PATCHES = {
  {
    id = "clean", title = "Clean Project", subtitle = "Start from scratch: no story, events or maps",
    action = { label = "Apply", confirm = "clean",
      tooltip = "Wipe this project and start clean -- asks first" },
    note = function(S)
      return require("Gen3Clean").enabled(S.project) and "This project is clean" or nil
    end,
  },
  {
    id = "clock", title = "Real Time Clock", subtitle = "Day and night cycles",
    isOn = function(S) return dayNight().enabled(S.project) end,
    setOn = function(S, on)
      local changed = dayNight().setEnabled(S.project, on, kanto(S))
      if changed then dayNight().syncCrystalPopulation(S) end -- Encounter tables follow the clock
      return changed
    end,
    status = { on = "Real time clock on", off = "Real time clock off (settings kept)" },
    note = function(S)
      local h = dayNight().settings(S.project).testHour
      return h and ("Test hour %d:00 is pinned"):format(h) or nil
    end,
    settings = { tooltip = "Hours, tints, night looks and the preview (GFX > Day & night)",
      open = function(S) S.tab, S.g3GfxMode = "gfx", "daynight" end },
    subs = {
      {
        id = "encounters", kanto = true, title = "Encounter tables", subtitle = "Pre-configured Day/ night encounters that can be edited",
        isOn = function(S) return dayNight().encountersEnabled(S.project) end,
        setOn = function(S, on)
          if on and not dayNight().enabled(S.project) then
            S.status = "Turn the Real Time Clock on first: Encounter tables come on with it"
            return false
          end
          local changed = dayNight().setEncounters(S.project, on)
          if changed then dayNight().syncCrystalPopulation(S) end
          return changed
        end,
        status = { on = "Encounter tables on: Crystal's lists filled in, ready to edit",
          off = "Encounter tables off: Crystal's lists taken back out, all-day lists used" },
      },
    },
  },
  {
    id = "systemClock", emerald = true, title = "System Clock", subtitle = "The bedroom clock is set from the PC's clock",
    isOn = function(S) return require("Gen3SystemClock").enabled(S.project) end,
    setOn = function(S, on) return require("Gen3SystemClock").setEnabled(S.project, on) end,
    status = { on = "System clock on", off = "System clock off" },
  },
  {
    id = "firered", emerald = true, title = "FireRed Maps", subtitle = "FireRed's maps and tilesets, from a FireRed or LeafGreen import",
    isOn = function(S) return require("Gen3FrLink").enabled(S.project) end,
    setOn = function(S, on)
      local changed = require("Gen3FrLink").setEnabled(S.project, on)
      -- the tileset lists are rebuilt with (or without) FireRed's
      if changed then require("Gen3FrLink").refresh(S) end
      return changed
    end,
    status = { on = "FireRed Maps on: FireRed's tilesets and maps are in the pickers",
      off = "FireRed Maps off (maps already using FireRed keep it)" },
    note = function(S)
      local FrLink = require("Gen3FrLink")
      if not FrLink.enabled(S.project) then return nil end
      if not FrLink.editor() then return "No FireRed or LeafGreen import found" end
      if S.project.gen3FrRegion then return "Region imported (EM_KANTO_ maps)" end
      return nil
    end,
    settings = { label = "Import region", tooltip = "Add every FireRed map at once, connected, as EM_KANTO_ maps",
      enabled = function(S) local FrLink = require("Gen3FrLink") return FrLink.enabled(S.project) and FrLink.editor() ~= nil end,
      open = function(S) S._gamePatchConfirm = "region" end },
    subs = {
      {
        id = "frwild", title = "Wild Pokemon", subtitle = "Kanto's wild Pokemon on the Import region maps",
        isOn = function(S) return require("Gen3FrLink").wildEnabled(S.project) end,
        setOn = function(S, on) return require("Gen3FrLink").setWild(S, on) end,
        status = { on = "Wild Pokemon on: Kanto maps use FireRed's encounter tables (Encounters tab)",
          off = "Wild Pokemon off: Kanto maps have only the lists you make" },
      },
      {
        id = "frpeople", title = "People, marts & nurses", subtitle = "FireRed's everyday people on the Import region maps",
        isOn = function(S) return require("Gen3FrLink").peopleEnabled(S.project) end,
        setOn = function(S, on) return require("Gen3FrLink").setPeople(S, on) end,
        status = { on = "People on: Kanto maps get FireRed's talkers, mart clerks and nurses",
          off = "People off: Kanto maps have only the people you make" },
      },
    },
  },
  {
    id = "emmaps", kanto = true, title = "Emerald Maps", subtitle = "Emerald's maps and tilesets, from an Emerald import",
    isOn = function(S) return require("Gen3EmLink").enabled(S.project) end,
    setOn = function(S, on)
      local changed = require("Gen3EmLink").setEnabled(S.project, on)
      -- the tileset lists are rebuilt with (or without) Emerald's
      if changed then require("Gen3EmLink").refresh(S) end
      return changed
    end,
    status = { on = "Emerald Maps on: Emerald's tilesets and maps are in the pickers",
      off = "Emerald Maps off (maps already using Emerald keep it)" },
    note = function(S)
      local EmLink = require("Gen3EmLink")
      if not EmLink.enabled(S.project) then return nil end
      if not EmLink.editor() then return "No Emerald import found" end
      if S.project.gen3EmRegion then return "Region imported (FR_HOENN_ maps)" end
      return nil
    end,
    settings = { label = "Import region", tooltip = "Add every Emerald map at once, connected, as FR_HOENN_ maps",
      enabled = function(S) local EmLink = require("Gen3EmLink") return EmLink.enabled(S.project) and EmLink.editor() ~= nil end,
      open = function(S) S._gamePatchConfirm = "emregion" end },
    subs = {
      {
        id = "emwild", title = "Wild Pokemon", subtitle = "Hoenn's wild Pokemon on the Import region maps",
        isOn = function(S) return require("Gen3EmLink").wildEnabled(S.project) end,
        setOn = function(S, on) return require("Gen3EmLink").setWild(S, on) end,
        status = { on = "Wild Pokemon on: Hoenn maps use Emerald's encounter tables (Encounters tab)",
          off = "Wild Pokemon off: Hoenn maps have only the lists you make" },
      },
      {
        id = "empeople", title = "People, marts & nurses", subtitle = "Emerald's everyday people on the Import region maps",
        isOn = function(S) return require("Gen3EmLink").peopleEnabled(S.project) end,
        setOn = function(S, on) return require("Gen3EmLink").setPeople(S, on) end,
        status = { on = "People on: Hoenn maps get Emerald's talkers, mart clerks and nurses",
          off = "People off: Hoenn maps have only the people you make" },
      },
    },
  },
  {
    id = "kanto", kanto = true, title = "Kanto Region", subtitle = "The game's own maps in the mod, without the story",
    action = { label = "Re-import region", confirm = "kanto", kind = "ghost",
      tooltip = "Kanto is already in the game. Only needed if you deleted or changed the originals: adds every Kanto and Sevii map again, connected, as FR_KANTO_ maps -- asks first" },
    note = function(S)
      return require("Gen3KantoRegion").imported(S.project) and "Region imported (FR_KANTO_ maps)" or nil
    end,
    subs = {
      {
        id = "kantowild", title = "Wild Pokemon", subtitle = "Kanto's wild Pokemon on the re-imported maps",
        isOn = function(S) return require("Gen3KantoRegion").wildEnabled(S.project) end,
        setOn = function(S, on) return require("Gen3KantoRegion").setWild(S, on) end,
        status = { on = "Wild Pokemon on: Kanto maps use the game's encounter tables (Encounters tab)",
          off = "Wild Pokemon off: Kanto maps have only the lists you make" },
      },
      {
        id = "kantopeople", title = "People, marts & nurses", subtitle = "The game's everyday people on the re-imported maps",
        isOn = function(S) return require("Gen3KantoRegion").peopleEnabled(S.project) end,
        setOn = function(S, on) return require("Gen3KantoRegion").setPeople(S, on) end,
        status = { on = "People on: Kanto maps get the game's talkers, mart clerks and nurses",
          off = "People off: Kanto maps have only the people you make" },
      },
    },
  },
  {
    id = "hoenn", emerald = true, title = "Hoenn Region", subtitle = "Emerald's own maps in the mod, without the story",
    action = { label = "Re-import region", confirm = "hoenn", kind = "ghost",
      tooltip = "Hoenn is already in the game. Only needed if you deleted or changed the originals: adds every Emerald map again, connected, as EM_HOENN_ maps -- asks first" },
    note = function(S)
      return require("Gen3HoennRegion").imported(S.project) and "Region imported (EM_HOENN_ maps)" or nil
    end,
    subs = {
      {
        id = "hoennwild", title = "Wild Pokemon", subtitle = "Hoenn's wild Pokemon on the re-imported maps",
        isOn = function(S) return require("Gen3HoennRegion").wildEnabled(S.project) end,
        setOn = function(S, on) return require("Gen3HoennRegion").setWild(S, on) end,
        status = { on = "Wild Pokemon on: Hoenn maps use Emerald's encounter tables (Encounters tab)",
          off = "Wild Pokemon off: Hoenn maps have only the lists you make" },
      },
      {
        id = "hoennpeople", title = "People, marts & nurses", subtitle = "Emerald's everyday people on the re-imported maps",
        isOn = function(S) return require("Gen3HoennRegion").peopleEnabled(S.project) end,
        setOn = function(S, on) return require("Gen3HoennRegion").setPeople(S, on) end,
        status = { on = "People on: Hoenn maps get Emerald's talkers, mart clerks and nurses",
          off = "People off: Hoenn maps have only the people you make" },
      },
    },
  },
  {
    id = "split", emerald = true, title = "Physical/Special Split", subtitle = "Moves are Physical or Special by themselves, as in Gen 4",
    isOn = function(S) return require("Gen3Split").enabled(S.project) end,
    setOn = function(S, on) return require("Gen3Split").setEnabled(S.project, on) end,
    status = { on = "Physical/Special split on", off = "Physical/Special split off" },
    settings = { tooltip = "Each move's Category (MOVES tab)", open = function(S) S.tab = "moves" end },
  },
}

local function flip(S, App, patch, picked)
  if picked ~= nil and patch.setOn(S, picked) then
    App.markDirty()
    S.status = picked and patch.status.on or patch.status.off
  end
end

-- One patch's box. Returns the next y.
local function patchCard(S, App, patch, x, y, w)
  local s = Kit.scale
  local colW = 186 * s
  local rx = x + w - colW - 16 * s
  local subs = {}
  for _, sub in ipairs(patch.subs or {}) do
    if kanto(S) or not sub.kanto then subs[#subs + 1] = sub end
  end
  local mainH = patch.settings and 132 or 96
  local subH = 62
  local cardH = (mainH + #subs * subH + (#subs > 0 and 10 or 0)) * s
  Kit.card(x, y, w, cardH)
  local cx, cy = x + 18 * s, y + 16 * s
  local on = patch.isOn and patch.isOn(S) or false

  Kit.text("button", patch.title, cx, cy, PAL.heading)
  Kit.text("small", patch.subtitle, cx, cy + 26 * s, PAL.muted)
  local note = patch.note and patch.note(S)
  if note then Kit.text("small", note, cx, cy + 50 * s, patch.action and PAL.green or PAL.yellow) end
  if patch.action then
    if Kit.button(rx, cy, colW, 34 * s, patch.action.label, { kind = patch.action.kind or "danger", font = "micro",
        tooltip = patch.action.tooltip }) then
      S._gamePatchConfirm = patch.action.confirm
    end
    on = true
  else
    flip(S, App, patch, switch(rx, cy, on, s))
    on = patch.isOn(S)
  end
  if Kit.button(rx, cy + 44 * s, colW, 28 * s, "Description", { kind = "ghost", font = "micro",
      tooltip = "What " .. patch.title .. " does" }) then
    S._gamePatchPopup = patch.id
  end
  if patch.settings and Kit.button(rx, cy + 78 * s, colW, 28 * s, patch.settings.label or "Settings", { kind = "ghost", font = "micro",
      tooltip = patch.settings.tooltip, enabled = not patch.settings.enabled or patch.settings.enabled(S) }) then
    patch.settings.open(S)
  end

  -- sub settings: same box, smaller
  local sy = y + mainH * s
  local subColW = 134 * s
  local srx = x + w - subColW - 16 * s
  for _, sub in ipairs(subs) do
    Theme.col(PAL.cardBorder, 0.3)
    love.graphics.line(cx, sy, x + w - 16 * s, sy)
    love.graphics.setColor(1, 1, 1, 1)
    local ty = sy + 10 * s
    local ex = cx + 18 * s
    Kit.text("small", sub.title, ex, ty, on and PAL.heading or PAL.faint)
    Kit.text("micro", sub.subtitle, ex, ty + 20 * s, on and PAL.muted or PAL.faint)
    flip(S, App, sub, switch(srx, ty, sub.isOn(S), s, true))
    if Kit.button(srx, ty + 28 * s, subColW, 20 * s, "Description", { kind = "ghost", font = "micro",
        tooltip = "What " .. sub.title .. " does" }) then
      S._gamePatchPopup = sub.id
    end
    sy = sy + subH * s
  end
  return y + cardH + 12 * s
end

function M.draw(S, x, y, w, h, App)
  local s = Kit.scale
  local top = y
  Kit.caption(x, y, "GAME PATCHES")
  y = y + 24 * s
  Kit.text("small", "Features this mod adds on top of the game. The game itself isn't changed; each one is written into the mod.",
    x, y, PAL.muted)
  y = y + 32 * s
  local cw = math.min(w, 760 * s)
  if not (kanto(S) or require("Generation").id(S) == "emerald") or not S.project then
    Kit.emptyBox(x, y, cw, 120 * s, "No game patches for " .. require("Generation").label(S) .. " yet.")
    return
  end
  -- Encounter tables: Crystal's lists filled in / taken out to match the switch
  if dayNight().syncCrystalPopulation(S) then App.markDirty() end
  -- While a pop-up is open, the cards underneath don't take clicks.
  local open = S._gamePatchPopup ~= nil or S._gamePatchConfirm ~= nil
  local blocked = Kit.blockClicks
  if open then Kit.blockClicks = true end
  -- The cards scroll (mouse wheel / scrollbar) when they don't all fit.
  local Pane = require("FormPane")
  local first, view = Pane.begin(S, "gamePatchesScroll", x, y, cw + Kit.scrollbarSize() + 4 * s, top + h - y)
  local cy = first
  for _, patch in ipairs(M.PATCHES) do
    if (kanto(S) or not patch.kanto) and (emerald(S) or not patch.emerald) then cy = patchCard(S, App, patch, x, cy, cw) end
  end
  Pane.finish(S, "gamePatchesScroll", first, cy, view)
  Kit.blockClicks = blocked
  if open then popup(S, App, x, top, w, h) end
end

return M
