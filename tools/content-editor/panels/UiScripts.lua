-- UI tab "Scripts" mode: list every UI screen Lua so people can open
-- the engine file or copy it into the mod and edit it.

local Kit = require("Kit")
local Theme = require("Theme")
local State = require("State")
local Generation = require("Generation")
local ModIO = require("ModIO")
local Code = require("Code")
local PAL = Theme.PAL

local UiScripts = {}

-- One row per screen people already edit on the UI tab (plus Theme).
-- gen1 / gen2 hold the engine module + repo-relative path.
local CATALOG = {
  { id = "title", group = "Title", label = "Title screen",
    tip = "CONTINUE / NEW GAME / OPTION loop",
    gen1 = { module = "src.ui.TitleState", rel = "src/ui/TitleState.lua" },
    gen2 = { module = "src.ui.gen2.TitleState", rel = "src/ui/gen2/TitleState.lua" } },
  { id = "intro", group = "Intro", label = "Intro movie",
    tip = "Studio splash and cinema before the title",
    gen1 = { module = "src.ui.IntroMovie", rel = "src/ui/IntroMovie.lua" },
    gen2 = { module = "src.ui.gen2.GoldSilverIntro",
      rel = "src/ui/gen2/GoldSilverIntro.lua" } },
  { id = "yellowIntro", group = "Intro", label = "Yellow intro",
    tip = "Yellow cinema (Pikachu / Game Freak)",
    gen1 = { module = "src.ui.YellowIntro", rel = "src/ui/YellowIntro.lua" } },
  { id = "crystalIntro", group = "Intro", label = "Crystal intro",
    tip = "Unown / Suicune cinema",
    gen2 = { module = "src.ui.gen2.CrystalIntro",
      rel = "src/ui/gen2/CrystalIntro.lua" } },
  { id = "oak", group = "Oak", label = "Oak speech",
    tip = "New-game lab intro",
    gen1 = { module = "src.ui.OakSpeech", rel = "src/ui/OakSpeech.lua" },
    gen2 = { module = "src.ui.gen2.OakSpeech", rel = "src/ui/gen2/OakSpeech.lua" } },
  { id = "credits", group = "Credits", label = "Credits",
    tip = "End-roll screens",
    gen1 = { module = "src.ui.Credits", rel = "src/ui/Credits.lua" },
    gen2 = { module = "src.ui.gen2.Credits", rel = "src/ui/gen2/Credits.lua" } },
  { id = "theme", group = "Theme", label = "Theme / boxes",
    tip = "Text box, choice box, cursors",
    gen1 = { module = "src.ui.Theme", rel = "src/ui/Theme.lua" },
    gen2 = { module = "src.ui.Theme", rel = "src/ui/Theme.lua" } },
  { id = "townmap", group = "Town map", label = "Town map",
    tip = "Kanto town map pins and background",
    gen1 = { module = "src.ui.TownMap", rel = "src/ui/TownMap.lua" } },
  { id = "pokegear", group = "Town map", label = "Pokégear",
    tip = "Johto / Kanto map, phone, radio",
    gen2 = { module = "src.ui.gen2.Pokegear", rel = "src/ui/gen2/Pokegear.lua" } },
  { id = "trainerCard", group = "Menus", label = "Trainer card",
    tip = "ID card and badges",
    gen1 = { module = "src.ui.TrainerCard", rel = "src/ui/TrainerCard.lua" },
    gen2 = { module = "src.ui.gen2.TrainerCard",
      rel = "src/ui/gen2/TrainerCard.lua" } },
  { id = "pokedex", group = "Menus", label = "Pokédex",
    tip = "Dex list and entry pages",
    gen1 = { module = "src.ui.PokedexMenu", rel = "src/ui/PokedexMenu.lua" },
    gen2 = { module = "src.ui.gen2.PokedexMenu",
      rel = "src/ui/gen2/PokedexMenu.lua" } },
  { id = "pack", group = "Menus", label = "Pack",
    tip = "Bag / pack pockets",
    gen2 = { module = "src.ui.gen2.PackMenu", rel = "src/ui/gen2/PackMenu.lua" } },
  { id = "naming", group = "Menus", label = "Naming screen",
    tip = "Player / Pokémon / box names",
    gen1 = { module = "src.ui.NamingScreen", rel = "src/ui/NamingScreen.lua" },
    gen2 = { module = "src.ui.gen2.NamingScreen",
      rel = "src/ui/gen2/NamingScreen.lua" } },
  { id = "pc", group = "Menus", label = "PC",
    tip = "Bill's PC / storage",
    gen2 = { module = "src.ui.gen2.PcMenu", rel = "src/ui/gen2/PcMenu.lua" } },
  { id = "stats", group = "Menus", label = "Stats / summary",
    tip = "Party summary pages",
    gen1 = { module = "src.ui.SummaryMenu", rel = "src/ui/SummaryMenu.lua" },
    gen2 = { module = "src.ui.gen2.SummaryMenu",
      rel = "src/ui/gen2/SummaryMenu.lua" } },
  { id = "diploma", group = "Menus", label = "Diploma",
    tip = "Hall of Fame diploma",
    gen1 = { module = "src.ui.Diploma", rel = "src/ui/Diploma.lua" },
    gen2 = { module = "src.ui.gen2.Diploma", rel = "src/ui/gen2/Diploma.lua" } },
  { id = "battle", group = "Battle", label = "Battle state",
    tip = "Battle flow and HUD host",
    gen1 = { module = "src.ui.BattleState", rel = "src/ui/BattleState.lua" },
    gen2 = { module = "src.ui.gen2.BattleState",
      rel = "src/ui/gen2/BattleState.lua" } },
  { id = "battleHud", group = "Battle", label = "Battle HUD",
    tip = "HP bars and battle chrome",
    gen2 = { module = "src.ui.gen2.BattleHud", rel = "src/ui/gen2/BattleHud.lua" } },
  { id = "slots", group = "Minigames", label = "Slot machine",
    tip = "Game Corner slots",
    gen1 = { module = "src.ui.SlotMachine", rel = "src/ui/SlotMachine.lua" },
    gen2 = { module = "src.ui.gen2.SlotMachine",
      rel = "src/ui/gen2/SlotMachine.lua" } },
  { id = "surf", group = "Minigames", label = "Surfing Pikachu",
    tip = "Yellow Pikachu's Beach",
    gen1 = { module = "src.ui.SurfingMinigame",
      rel = "src/ui/SurfingMinigame.lua" } },
  { id = "cardflip", group = "Minigames", label = "Card flip",
    tip = "Game Corner card flip",
    gen2 = { module = "src.ui.gen2.CardFlip", rel = "src/ui/gen2/CardFlip.lua" } },
  { id = "unown", group = "Minigames", label = "Unown puzzle",
    tip = "Ruins of Alph puzzle",
    gen2 = { module = "src.ui.gen2.UnownPuzzle",
      rel = "src/ui/gen2/UnownPuzzle.lua" } },
  { id = "egg", group = "Menus", label = "Egg hatch",
    tip = "Egg hatch animation",
    gen2 = { module = "src.ui.gen2.EggHatchAnim",
      rel = "src/ui/gen2/EggHatchAnim.lua" } },
  { id = "trade", group = "Menus", label = "Trade animation",
    tip = "Link-trade cinema",
    gen1 = { module = "src.ui.TradeAnim", rel = "src/ui/TradeAnim.lua" } },
}

local function joinPath(root, rel)
  local sep = package.config:sub(1, 1)
  rel = tostring(rel or ""):gsub("\\", "/")
  if tostring(root or ""):sub(-1) == "/" or tostring(root or ""):sub(-1) == "\\" then
    return root .. rel:gsub("/", sep)
  end
  return root .. sep .. rel:gsub("/", sep)
end

local function openModId(S)
  if S.path then return S.path:match("[/\\]([^/\\]+)$") end
  return S.browseModId
end

local function destRel(rel)
  return tostring(rel or ""):gsub("^src/", "")
end

function UiScripts.list(S)
  local gen2 = Generation.isGen2(S)
  local items = {}
  for _, row in ipairs(CATALOG) do
    local spec = gen2 and row.gen2 or row.gen1
    if spec then
      items[#items + 1] = {
        id = row.id,
        group = row.group,
        label = row.label,
        tip = row.tip,
        module = spec.module,
        rel = spec.rel,
      }
    end
  end
  return items
end

local function copyRec(S, row)
  local bag = S.project and S.project.uiScripts
  local rec = bag and bag[row.id]
  if type(rec) == "table" and type(rec.rel) == "string" and rec.rel ~= "" then
    return rec
  end
  return nil
end

local function revealPath(path)
  if type(path) ~= "string" or path == "" then return false end
  local osName = love and love.system and love.system.getOS and love.system.getOS()
  if osName == "Windows" then
    local win = path:gsub("/", "\\")
    os.execute('explorer /select,"' .. win:gsub('"', "") .. '"')
    return true
  end
  if osName == "OS X" then
    os.execute('open -R "' .. path:gsub('"', "") .. '"')
    return true
  end
  if osName == "Linux" then
    local dir = path:match("^(.*)[/\\]") or path
    os.execute('xdg-open "' .. dir:gsub('"', "") .. '"')
    return true
  end
  return false
end

local function previewLines(S, row, maxLines)
  maxLines = maxLines or 12
  local rec = copyRec(S, row)
  local body
  if rec then
    local modId = openModId(S)
    if modId then body = select(1, ModIO.readModFile(modId, rec.rel)) end
  end
  if not body then
    local full = Code.engineFilePath(S, row.rel)
    if full then body = select(1, ModIO.readText(full)) end
  end
  if not body and love and love.filesystem and love.filesystem.read then
    local ok, data = pcall(love.filesystem.read, row.rel)
    if ok then body = data end
  end
  if type(body) ~= "string" or body == "" then
    return { "(engine file not found — link Gen1Recomp on the Project tab)" }
  end
  body = body:gsub("\r\n", "\n"):gsub("\r", "\n")
  local lines = {}
  for line in (body .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
    if #lines >= maxLines then break end
  end
  return lines
end

local function makeEditable(S, App, row)
  local modId = openModId(S)
  if not modId then
    S.status = "Open a mod on the Project tab first"
    return
  end
  local existing = copyRec(S, row)
  if existing then
    Code.openModFile(S, modId, existing.rel)
    return
  end
  local src = Code.engineFilePath(S, row.rel)
  local rel = destRel(row.rel)
  local ok, err
  if src then
    ok, err = ModIO.copyFile(src, joinPath(ModIO.modDir(modId), rel))
  else
    local body
    if love and love.filesystem and love.filesystem.read then
      local readOk, data = pcall(love.filesystem.read, row.rel)
      if readOk then body = data end
    end
    if type(body) ~= "string" then
      S.status = "Cannot copy " .. row.rel .. " — engine file not found"
      return
    end
    ok, err = ModIO.writeModFile(modId, rel, body)
  end
  if not ok then
    S.status = "Copy failed: " .. tostring(err)
    return
  end
  State.ensureProjectFields(S.project)
  S.project.uiScripts[row.id] = { module = row.module, rel = rel }
  if App and App.markDirty then App.markDirty() end
  Code.openModFile(S, modId, rel)
  S.status = "Editing mods/" .. modId .. "/" .. rel .. " — Save to load it in playtest"
end

function UiScripts.draw(S, x, y, w, h, App)
  local s = Kit.scale
  State.ensureProjectFields(S.project)
  local items = UiScripts.list(S)
  if #items == 0 then
    Kit.emptyBox(x, y, w, h, "No UI scripts for this game")
    return
  end
  if not S.uiScriptId then S.uiScriptId = items[1].id end
  local sel
  for i = 1, #items do
    if items[i].id == S.uiScriptId then sel = i; break end
  end
  if not sel then
    sel = 1
    S.uiScriptId = items[1].id
  end

  Theme.col(PAL.rowBg, 0.55)
  love.graphics.rectangle("fill", x, y, w, h, 8 * s, 8 * s)

  local pad = 10 * s
  Kit.caption(x + pad, y + 6 * s, "UI SCRIPTS")
  Kit.text("micro",
    "Open the engine Lua for each screen. Edit in mod copies it here; Save loads that copy.",
    x + pad, y + 22 * s, PAL.muted)

  local btnH = 24 * s
  local btnY = y + h - btnH - 8 * s
  local listY = y + 40 * s
  local listX = x + 4 * s
  local listW = w - 8 * s
  local listH = math.max(48 * s, math.floor((btnY - listY - 8 * s) * 0.55))
  local rowH = 20 * s
  local per = math.max(1, math.floor(listH / rowH))
  local innerW = Kit.scrollInnerWidth(listW)
  S.uiScriptOffset = Kit.scroll(listX, listY, listW, listH,
    S.uiScriptOffset or 0, #items, per, 1, "uiScripts")
  local lastGroup = nil
  Kit.pushClip(listX, listY, innerW, listH)
  for i = 1, per do
    local li = (S.uiScriptOffset or 0) + i
    local row = items[li]
    if not row then break end
    local ry = listY + (i - 1) * rowH
    local on = li == sel
    if Kit.press(listX + 2 * s, ry, innerW - 4 * s, rowH) then
      S.uiScriptId = row.id
      sel = li
    end
    if on then
      Theme.col(PAL.yellow, 0.14)
      love.graphics.rectangle("fill", listX + 2 * s, ry, innerW - 4 * s, rowH)
    end
    local prefix = ""
    if row.group ~= lastGroup then
      prefix = row.group .. " · "
      lastGroup = row.group
    end
    local mark = copyRec(S, row) and "● " or "  "
    Kit.text("micro",
      Kit.ellipsize("micro", mark .. prefix .. row.label, innerW - 10 * s),
      listX + 6 * s, ry + 3 * s, on and PAL.heading or PAL.muted)
  end
  Kit.popClip()
  S.uiScriptOffset = Kit.scrollbar(listX, listY, listW, listH,
    S.uiScriptOffset or 0, #items, per, "uiScripts")

  local row = items[sel]
  local rec = copyRec(S, row)
  local prevY = listY + listH + 6 * s
  local prevH = math.max(24 * s, btnY - prevY - 6 * s)
  Kit.text("small", row.label, x + pad, prevY, PAL.heading)
  Kit.text("micro", rec and ("mods/" .. tostring(openModId(S)) .. "/" .. rec.rel)
      or row.rel,
    x + pad, prevY + 16 * s, rec and PAL.yellow or PAL.caption)
  Kit.text("micro", row.tip, x + pad, prevY + 30 * s, PAL.muted)

  local textY = prevY + 46 * s
  Kit.pushClip(x + pad, textY, w - 2 * pad, math.max(8 * s, prevY + prevH - textY))
  local py = textY
  for _, line in ipairs(previewLines(S, row, 10)) do
    Kit.text("micro", Kit.ellipsize("micro", line, w - 2 * pad),
      x + pad, py, PAL.text)
    py = py + 13 * s
    if py > prevY + prevH then break end
  end
  Kit.popClip()

  local bx = x + pad
  if Kit.button(bx, btnY, 110 * s, btnH, rec and "Open edit" or "Open source", {
        kind = "accent", font = "small",
        tooltip = rec and "Open the mod copy on the Code tab"
          or "Open the engine file on the Code tab (read-only)",
      }) then
    if rec then
      local modId = openModId(S)
      if modId then Code.openModFile(S, modId, rec.rel) end
    else
      Code.openRepoFile(S, row.rel)
    end
  end
  bx = bx + 116 * s
  if Kit.button(bx, btnY, 100 * s, btnH, rec and "Re-open" or "Edit in mod", {
        kind = "primary", font = "small",
        tooltip = rec and "Open the existing mod copy"
          or "Copy this script into the mod and edit it",
      }) then
    makeEditable(S, App, row)
  end
  bx = bx + 106 * s
  if rec and Kit.button(bx, btnY, 90 * s, btnH, "Use vanilla", {
        kind = "ghost", font = "small",
        tooltip = "Stop loading the mod copy (file stays on disk)",
      }) then
    S.project.uiScripts[row.id] = nil
    if App and App.markDirty then App.markDirty() end
    S.status = "Will use vanilla " .. row.rel .. " after Save"
  end
  if rec then bx = bx + 96 * s end
  if Kit.button(bx, btnY, 80 * s, btnH, "Copy path", {
        kind = "ghost", font = "small",
      }) then
    local full
    if rec then
      local modId = openModId(S)
      if modId then full = joinPath(ModIO.modDir(modId), rec.rel) end
    else
      full = Code.engineFilePath(S, row.rel) or row.rel
    end
    if love and love.system and love.system.setClipboardText then
      love.system.setClipboardText(full)
    end
    S.status = "Copied " .. tostring(full)
  end
  bx = bx + 86 * s
  if Kit.button(bx, btnY, 70 * s, btnH, "Reveal", {
        kind = "ghost", font = "small",
      }) then
    local full
    if rec then
      local modId = openModId(S)
      if modId then full = joinPath(ModIO.modDir(modId), rec.rel) end
    else
      full = Code.engineFilePath(S, row.rel)
    end
    if full and revealPath(full) then
      S.status = "Revealed " .. tostring(full)
    else
      S.status = full or ("No disk path for " .. row.rel)
    end
  end
end

return UiScripts
