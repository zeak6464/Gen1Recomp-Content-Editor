-- FireRed metatile behaviours (MB_*), the value held in bits 0-8 of a
-- metatile's attribute word.
--
-- Only names this codebase itself pins down are listed. Every one below is
-- corroborated by src/core/game3/scripting/collision.lua (the surfable,
-- ledge, warp and sign tables, each carrying its pokefirered line reference)
-- or by scripting/interaction_scripts.lua's FLAVOR / CODE tables. Anything
-- else is deliberately absent rather than guessed: M.label falls back to the
-- effect the engine's own classifier gives it, which is accurate whatever the
-- pret constant happens to be called.

local M = {}

M.NAMES = {
  -- Ground -----------------------------------------------------------------
  [0x00] = "Normal ground",
  [0x02] = "Tall grass",                 -- collision.lua:classify
  [0x08] = "Cave floor",                 -- classify: beh == 0x08 -> CAVE
  [0x0C] = "Mountain top",               -- MOUNTAIN_TOP_BEH
  [0x21] = "Sand",                       -- classify: 0x21 / 0x2B -> SAND
  [0x2B] = "Deep sand",
  [0xD1] = "Tall grass (2)",             -- classify pairs it with 0x02

  -- Water ------------------------------------------------------------------
  [0x10] = "Pond water",                 -- sBehaviorSurfable
  [0x11] = "Semi-deep water",
  [0x12] = "Deep water",
  [0x13] = "Waterfall",
  [0x15] = "Ocean water",
  [0x1A] = "Water (unused variant)",
  [0x1B] = "Water by the abandoned ship",
  [0x50] = "Water (50)",
  [0x51] = "Water (51)",
  [0x52] = "Water (52)",
  [0x53] = "Water (53)",
  [0x16] = "Puddle",                     -- WALK_ON_WATER_BEH
  [0x17] = "Shallow water",

  -- Ledges -----------------------------------------------------------------
  [0x38] = "Ledge: jump east",           -- JUMP_DIR
  [0x39] = "Ledge: jump west",
  [0x3A] = "Ledge: jump north",
  [0x3B] = "Ledge: jump south",

  -- Stairs and warps -------------------------------------------------------
  [0x2A] = "Rock stairs",                -- STAIR_BEH, walkable tiers
  [0x60] = "Cave door",                  -- DOOR_BEH / isWarpMetatileBehavior
  [0x61] = "Ladder",                     -- WARP_STAIR_BEH
  [0x62] = "Arrow warp: east",
  [0x63] = "Arrow warp: west",
  [0x64] = "Arrow warp: north",
  [0x65] = "Arrow warp: south",
  [0x66] = "Fall warp",                  -- KEEP_FACING_WARP_BEH
  [0x67] = "Regular warp",
  [0x68] = "Lavaridge 1F warp",
  [0x69] = "Warp door",
  [0x6A] = "Escalator up",
  [0x6B] = "Escalator down",
  [0x6C] = "Stair warp: up east",
  [0x6D] = "Stair warp: up west",
  [0x6E] = "Stair warp: down east",
  [0x6F] = "Stair warp: down west",
  [0x71] = "Union Room warp",

  -- Things you face and read ----------------------------------------------
  [0x80] = "Shop counter",               -- COUNTER_BEH
  [0x81] = "Bookshelf",                  -- interaction_scripts FLAVOR
  [0x82] = "Poke Mart shelf",
  [0x83] = "PC",                         -- PC_BEH
  [0x84] = "Sign",                       -- SIGN_BEH
  [0x85] = "Town map on the wall",
  [0x86] = "Television",
  [0x87] = "Poke Center sign",
  [0x88] = "Poke Mart sign",
  [0x89] = "Cabinet",
  [0x8A] = "Kitchen",
  [0x8B] = "Dresser",
  [0x8C] = "Snacks",
  [0x8D] = "Wireless communication screen",
  [0x8E] = "Battle records",
  [0x8F] = "Questionnaire",
  [0x90] = "Food",
  [0x91] = "Indigo: ultimate goal sign",
  [0x92] = "Indigo: highest authority sign",
  [0x93] = "Blueprints",
  [0x94] = "Painting",
  [0x95] = "Power plant machine",
  [0x96] = "Telephone",
  [0x97] = "Computer",
  [0x98] = "Advertising poster",
  [0x99] = "Tasty food",
  [0x9A] = "Trash bin",
  [0x9B] = "Cup",
  [0x9C] = "Polished window",
  [0x9D] = "Beautiful sky window",
  [0x9E] = "Blinking lights",
  [0x9F] = "Neatly lined up tools",
  [0xA0] = "Impressive machine",
  [0xA1] = "Video game",
  [0xA2] = "Burglary",
  [0xA3] = "Trainer Tower clock",
}

-- Plain-language names for the classifier's own categories, used to describe
-- a behaviour we have no pret name for.
local EFFECTS = {
  WATER = "surfable water", TALL_GRASS = "tall grass", TREE = "a tree",
  CLIFF = "a cliff face", COAST_CLIFF = "a coastal cliff",
  BLOCKED = "a wall", BUILDING = "a building wall", DOOR = "a doorway",
  SIGN = "a sign", PC = "a PC", COUNTER = "a counter", CAVE = "cave floor",
  STAIR = "stairs", SAND = "sand", PATH = "walkable ground",
  PIER = "a pier", SHORT_GRASS = "short grass", TOWN_PATH = "town ground",
  ROCK_DECK = "a rock deck", LEDGE = "a ledge",
  WARP_KEEP_FACING = "a warp that keeps your facing",
}

--- What the engine's classifier makes of a behaviour, as a short phrase.
-- mid and kind matter for a handful of id-based special cases, so pass them
-- when you have them.
function M.effect(behavior, mid, raw, kind)
  local ok, Script = pcall(require, "src.core.game3.scripting.collision")
  if not ok or not Script then return nil end
  local category, ledge = Script.classify(mid or 0, raw or 0, behavior or 0, kind)
  local text = EFFECTS[category] or (category and category:lower())
  if category == "LEDGE" and ledge then
    local dirs = { E = "east", W = "west", N = "north", S = "south" }
    text = "a ledge you hop " .. (dirs[ledge] or ledge)
  end
  return text, category
end

--- Display label for a behaviour byte, never nil.
function M.label(behavior, mid, raw, kind)
  if behavior == nil then return "Not set" end
  local name = M.NAMES[behavior]
  if name then return string.format("%s  (0x%02X)", name, behavior) end
  local effect = M.effect(behavior, mid, raw, kind)
  if effect then
    return string.format("Behavior 0x%02X  - acts as %s", behavior, effect)
  end
  return string.format("Behavior 0x%02X", behavior)
end

--- ids/labels for ChoicePicker, current value always included.
function M.choices(current, mid, kind)
  local ids, labels, seen = {}, {}, {}
  for value in pairs(M.NAMES) do
    local key = tostring(value)
    ids[#ids + 1] = key
    labels[key] = M.label(value, mid, 0, kind)
    seen[value] = true
  end
  if current ~= nil and not seen[current] then
    local key = tostring(current)
    ids[#ids + 1] = key
    labels[key] = M.label(current, mid, 0, kind)
  end
  table.sort(ids, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
  return ids, labels
end

return M
