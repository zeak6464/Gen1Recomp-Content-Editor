-- Names for overworld sprites. Emerald, Ruby, and Sapphire use that game's
-- OBJ_EVENT_GFX list. The table below is only the FireRed / LeafGreen list.
local M = {}

M.NAMES = {
  [0] = "Red", [1] = "Red (bike)", [2] = "Red (surfing)", [3] = "Red (field move)", [4] = "Red (fishing)",
  [5] = "Red (VS Seeker)", [6] = "Red (VS Seeker, bike)",
  [7] = "Leaf", [8] = "Leaf (bike)", [9] = "Leaf (surfing)", [10] = "Leaf (field move)", [11] = "Leaf (fishing)",
  [12] = "Leaf (VS Seeker)", [13] = "Leaf (VS Seeker, bike)",
  [14] = "Brendan (R/S)", [15] = "May (R/S)",
  [16] = "Little boy", [17] = "Little girl", [18] = "Youngster", [19] = "Boy", [20] = "Bug Catcher",
  [21] = "Sitting boy", [22] = "Lass", [23] = "Woman", [24] = "Battle Girl", [25] = "Man", [26] = "Rocker",
  [27] = "Fat man", [28] = "Woman 2", [29] = "Beauty", [30] = "Balding man", [31] = "Woman 3",
  [32] = "Old man", [33] = "Old man 2", [34] = "Old man (lying down)", [35] = "Old woman",
  [36] = "Tuber (boy, water)", [37] = "Tuber (girl)", [38] = "Tuber (boy, sand)",
  [39] = "Camper", [40] = "Picnicker", [41] = "Cooltrainer (male)", [42] = "Cooltrainer (female)",
  [43] = "Swimmer (male, water)", [44] = "Swimmer (female, water)", [45] = "Swimmer (male, land)",
  [46] = "Swimmer (female, land)", [47] = "Worker (male)", [48] = "Worker (female)",
  [49] = "Team Rocket (male)", [50] = "Team Rocket (female)", [51] = "Game Boy kid", [52] = "Super Nerd",
  [53] = "Biker", [54] = "Black Belt", [55] = "Scientist", [56] = "Hiker", [57] = "Fisherman",
  [58] = "Channeler", [59] = "Chef", [60] = "Policeman", [61] = "Gentleman", [62] = "Sailor",
  [63] = "Captain", [64] = "Nurse", [65] = "Cable Club receptionist", [66] = "Union Room receptionist",
  [67] = "Receptionist (male)", [68] = "Clerk", [69] = "Mystery Gift deliveryman", [70] = "Trainer Tower dude",
  [71] = "Prof. Oak", [72] = "Blue (rival)", [73] = "Bill", [74] = "Lance", [75] = "Agatha", [76] = "Daisy",
  [77] = "Lorelei", [78] = "Mr. Fuji", [79] = "Bruno", [80] = "Brock", [81] = "Misty", [82] = "Lt. Surge",
  [83] = "Erika", [84] = "Koga", [85] = "Sabrina", [86] = "Blaine", [87] = "Giovanni", [88] = "Mom",
  [89] = "Celio", [90] = "Teachy TV host", [91] = "Gym guy", [92] = "Item ball",
  [93] = "Town map", [94] = "Pokedex", [95] = "Cut tree", [96] = "Rock Smash rock", [97] = "Strength boulder",
  [98] = "Fossil", [99] = "Ruby", [100] = "Sapphire", [101] = "Old Amber", [102] = "Gym sign", [103] = "Sign",
  [104] = "Trainer tips sign", [105] = "Clipboard", [106] = "Meteorite", [107] = "Lapras doll", [108] = "Seagallop ferry",
  [109] = "Snorlax", [110] = "Spearow", [111] = "Cubone", [112] = "Poliwrath", [113] = "Clefairy", [114] = "Pidgeot",
  [115] = "Jigglypuff", [116] = "Pidgey", [117] = "Chansey", [118] = "Omanyte", [120] = "Pikachu", [121] = "Psyduck",
  [122] = "Nidoran (female)", [123] = "Nidoran (male)", [124] = "Nidorino", [125] = "Meowth", [126] = "Seel",
  [127] = "Voltorb", [128] = "Slowpoke", [129] = "Slowbro", [130] = "Machop", [131] = "Wigglytuff", [132] = "Doduo",
  [133] = "Fearow", [136] = "Zapdos", [137] = "Moltres", [138] = "Articuno", [139] = "Mewtwo", [140] = "Mew",
  [144] = "Lugia", [145] = "Ho-Oh", [148] = "Deoxys", [149] = "Deoxys", [150] = "Deoxys", [151] = "S.S. Anne",
}

--- "0  Brendan Normal" for the pickers. Pass the editor state so Emerald
-- does not reuse the FireRed list. label(id) still reads the FireRed list.
function M.label(S, id)
  if type(S) ~= "table" then id, S = S, nil end
  local n = tonumber(id)
  -- Custom sprites imported into this mod show the name given at import.
  local custom = n and S and S.project and S.project.gen3Assets
    and S.project.gen3Assets["data/generated/gba/ow/" .. n .. ".rgba"]
  if custom and custom.ow and custom.metaFile and custom.name then
    return tostring(n) .. "  " .. custom.name .. " (custom)"
  end
  local game = S and require("Generation").id(S)
  if n and game and game ~= "firered" and game ~= "leafgreen" then
    local name = require("Gen3Labels").constant(S, "event_objects", "OBJ_EVENT_GFX_", n)
    return name and (tostring(n) .. "  " .. name) or ("Sprite " .. tostring(id))
  end
  local name = n and M.NAMES[n]
  return name and (tostring(id) .. "  " .. name) or ("Sprite " .. tostring(id))
end

return M
