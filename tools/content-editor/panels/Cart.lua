-- CART tab: author cart.json through cartkit (scaffold, pin, validate, pack).

local Kit = require("Kit")
local Theme = require("Theme")
local FormPane = require("FormPane")
local RegList = require("RegList")
local ModIO = require("ModIO")
local Cartkit = require("Cartkit")
local Json = require("src.link.Json")
local ColorWheel = require("ColorWheel")
local CartPreview = require("CartPreview")
local PAL = Theme.PAL

local Cart = {}

local BASES = Cartkit.BASES
local SEALS = Cartkit.SEALS
local FINISHES = Cartkit.FINISHES
local PIN_SOURCES = { "github", "gamebanana", "local" }
local PLACEHOLDER_REPO = "owner/example-mod"
local PLACEHOLDER_SHA = string.rep("0", 64)
local SHELL_PRESETS = {
  { "R", PAL.railRed, "Red" },
  { "B", PAL.railBlue, "Blue" },
  { "Y", PAL.railGold or PAL.railYellow, "Yellow" },
  { "G", { 218, 145, 32 }, "Gold" },
  { "S", PAL.railSilver, "Silver" },
  { "C", PAL.railCrystal, "Crystal" },
}

local function join(a, b)
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a .. b end
  return a .. package.config:sub(1, 1) .. b
end

local function cycle(list, cur)
  local idx = 1
  for i, v in ipairs(list) do
    if v == cur then idx = i; break end
  end
  return list[(idx % #list) + 1]
end

local function csv(list)
  if type(list) ~= "table" then return "" end
  return table.concat(list, ", ")
end

local function splitCsv(s)
  local out = {}
  for part in tostring(s or ""):gmatch("[^,]+") do
    part = part:match("^%s*(.-)%s*$")
    if part and part ~= "" then out[#out + 1] = part end
  end
  return out
end

local function markDirty(S)
  S.cartDirty = true
  S._quitArmed = nil
end

local function isPlaceholder(row)
  return type(row) == "table"
    and tostring(row.repo or ""):lower() == PLACEHOLDER_REPO
    and row.sha256 == PLACEHOLDER_SHA
end

local function dropPlaceholders(mods)
  local i = 1
  while i <= #mods do
    if isPlaceholder(mods[i]) then
      table.remove(mods, i)
    else
      i = i + 1
    end
  end
end

local function clearPinSourceFields(row)
  row.repo, row.sha256, row.mod, row.file, row.md5 = nil, nil, nil, nil, nil
end

-- CartManifest local pins need semver; 0.0.0 is CartStore.UNPINNED_VERSION.
local function pinVersion(raw)
  local v = tostring(raw or ""):match("^%s*(.-)%s*$")
  if v ~= "" and v:match("^%d+%.%d+%.%d+") then return v end
  return "0.0.0"
end

local function readFolderManifest(dir)
  if type(dir) ~= "string" or dir == "" then
    return nil, "no folder"
  end
  local body, err = ModIO.readText(join(dir, "manifest.json"))
  if not body then return nil, "that folder has no manifest.json" end
  local data, derr = Json.decode(body)
  if type(data) ~= "table" then
    return nil, derr or "manifest.json is not an object"
  end
  return data
end

local function pinLocalFromDir(S, dir)
  local d = S.cartDraft
  if not d then return end
  local man, err = readFolderManifest(dir)
  if not man then
    S.status = tostring(err)
    return
  end
  local id = tostring(man.id or ""):match("^[%w_%-]+$")
  if not id then
    S.status = "That manifest has no valid id"
    return
  end
  local version = pinVersion(man.version)
  local mods = d.mods
  dropPlaceholders(mods)
  for _, row in ipairs(mods) do
    if row.id == id then
      row.source = "local"
      row.version = version
      clearPinSourceFields(row)
      markDirty(S)
      S.status = "Updated local pin " .. id .. " " .. version
      return
    end
  end
  if #mods >= 64 then
    S.status = "Cart already has 64 pins"
    return
  end
  mods[#mods + 1] = { id = id, source = "local", version = version }
  markDirty(S)
  S.status = "Pinned local " .. id .. " " .. version
end

local function field(S, id, x, y, w, h, value, ph, tip)
  local v = Kit.textfield(id, x, y, w, h, value, ph, tip)
  if v ~= tostring(value or "") then markDirty(S) end
  return v
end

local function plain(id, x, y, w, h, value, ph, tip)
  return Kit.textfield(id, x, y, w, h, value, ph, tip)
end

local function defaultDraft(id)
  return {
    schema = 1,
    id = id or "my_cart",
    title = (id or "my_cart"):gsub("[_%-]", " "),
    version = "0.1.0",
    author = "",
    repo = "",
    summary = "",
    shell = "#8b1a1a",
    finish = "",
    label = "label.png",
    base = "red",
    engine = "",
    seal = "sealed",
    speeds = {},
    mods = {},
    load_order = {},
  }
end

local function loadDraft(S, dir)
  local data, err = Cartkit.readCart(dir)
  if not data then
    S.cartDraft = defaultDraft(dir:match("[^/\\]+$"))
    S.cartLoadError = tostring(err)
    S.cartDirty = false
    CartPreview.invalidate(S)
    return
  end
  local d = defaultDraft(data.id)
  for k, v in pairs(data) do d[k] = v end
  if type(d.mods) ~= "table" then d.mods = {} end
  if type(d.speeds) ~= "table" then d.speeds = {} end
  if type(d.load_order) ~= "table" then d.load_order = {} end
  d.finish = d.finish or ""
  d.repo = d.repo or ""
  d.summary = d.summary or ""
  S.cartDraft = d
  S.cartLoadError = nil
  S.cartDirty = false
  CartPreview.invalidate(S)
end

local function selectCart(S, dir)
  S.cartDir = dir
  S.cartId = dir and dir:match("[^/\\]+$") or nil
  S._cartFor = dir
  S.cartPinIndex = 1
  S.cartScroll = 0
  if dir then loadDraft(S, dir) else S.cartDraft = nil end
end

local function cartDirFor(S, id)
  local root = Cartkit.cartsRoot(S)
  if not root or not id then return nil end
  return join(root, id)
end

local function ensureList(S)
  local ids = Cartkit.listCarts(S)
  if S.cartDir then
    local name = S.cartId
    local found = false
    for _, id in ipairs(ids) do
      if id == name then found = true; break end
    end
    if not found and name then
      ids[#ids + 1] = name
      table.sort(ids)
    end
  end
  if S.cartId and S._cartFor ~= S.cartDir then
    selectCart(S, S.cartDir)
  elseif not S.cartId and ids[1] then
    selectCart(S, cartDirFor(S, ids[1]))
  end
  return ids
end

function Cart.save(S, App)
  if not (S.cartDraft and S.cartDir) then
    S.status = "No cart selected"
    return false
  end
  local ok, err = Cartkit.writeCart(S.cartDir, S.cartDraft)
  if not ok then
    S.status = "Write failed: " .. tostring(err)
    return false
  end
  S.cartDirty = false
  S.status = "Wrote " .. Cartkit.cartPath(S.cartDir)
  if App and App.markDirty then
    -- cart is its own file; do not dirty the content project
  end
  return true
end

local function runKit(S, App, argv, okMsg)
  if S.cartDirty and S.cartDir then
    if not Cart.save(S, App) then return end
  end
  local cmd = argv and argv[1]
  if cmd == "validate" and S.cartDir and S.cartDraft then
    local name = tostring(S.cartDraft.label or "label.png")
    if name ~= "" then
      Cartkit.fitLabel(join(S.cartDir, name))
      CartPreview.invalidate(S)
    end
  end
  local ok, out = Cartkit.run(S, argv)
  local info = Cartkit.interpret(out)
  S.cartLog = Cartkit.displayLog(out, info)
  if info.hardFail then
    if info.labelTooBig then
      S.status = "Label over 1 MB — Shrink on the label row"
    else
      S.status = "cartkit failed — see log"
    end
  elseif info.localPins then
    S.status = (okMsg or "OK") .. " for this PC (local pins)"
  elseif ok then
    S.status = okMsg or "cartkit OK"
  else
    S.status = "cartkit failed — see log"
  end
  if S.cartDir then loadDraft(S, S.cartDir) end
  return ok
end

function Cart.draw(S, x, y, w, h, App)
  local s = Kit.scale
  local script = Cartkit.scriptPath(S)
  if not script then
    Kit.emptyBox(x, y, w, h,
      "Link Gen1Recomp on Project (needs tools/cartkit.py)")
    return
  end

  local ids = ensureList(S)
  local listW = math.min(200 * s, w * 0.24)
  local gap = 12 * s
  local mainX = x + listW + gap
  local mainW = w - listW - gap

  Kit.caption(x, y, "CARTS/")
  local listY = y + 22 * s
  local listH = h - 22 * s - 40 * s
  Kit.card(x, listY, listW, listH, 12 * s)

  local rowH = 30 * s
  local perPage = math.max(1, math.floor((listH - 16 * s) / rowH))
  local scrollX, scrollY = x + 4 * s, listY + 8 * s
  local scrollW, scrollH = listW - 8 * s, listH - 16 * s
  local rowW = Kit.scrollInnerWidth(scrollW)
  S.cartListOffset = Kit.scroll(scrollX, scrollY, scrollW, scrollH,
    S.cartListOffset or 0, #ids, perPage)
  local dirtyGuard = (S.cartDirty and S.cartId) or nil
  local nav = RegList.bindNav(S, ids, {
    selKey = "cartId", offsetKey = "cartListOffset", perPage = perPage,
    onSelect = function(id)
      if dirtyGuard and id ~= dirtyGuard then
        S.cartId = dirtyGuard
        S.status = "Unsaved cart — Write or Reload before switching"
        return
      end
      selectCart(S, cartDirFor(S, id) or S.cartDir)
    end,
  })
  for i = 1, perPage do
    local idx = (S.cartListOffset or 0) + i
    local cid = ids[idx]
    if not cid then break end
    local ry = scrollY + (i - 1) * rowH
    local on = S.cartId == cid
    Kit.offerTooltip(x + 6 * s, ry, rowW - 2 * s, rowH - 4 * s,
      "Open carts/" .. cid .. "/cart.json")
    if Kit.row(x + 6 * s, ry, rowW - 2 * s, rowH - 4 * s, on, PAL.blue) then
      nav.activate()
      if dirtyGuard and cid ~= dirtyGuard then
        S.status = "Unsaved cart — Write or Reload before switching"
      else
        selectCart(S, cartDirFor(S, cid) or S.cartDir)
      end
    end
    Kit.text("small", Kit.ellipsize("small", cid, math.max(8, rowW - 20 * s)),
      x + 14 * s, ry + 6 * s, on and PAL.heading or PAL.text)
  end
  S.cartListOffset = Kit.scrollbar(scrollX, scrollY, scrollW, scrollH,
    S.cartListOffset or 0, #ids, perPage)

  local newY = listY + listH + 8 * s
  S.cartNewId = plain("cart_new_id", x, newY, listW - 72 * s, 32 * s,
    S.cartNewId or "", "new_id", "New cart id (letters, numbers, _ or -)")
  if Kit.button(x + listW - 68 * s, newY, 68 * s, 32 * s, "New", {
      kind = "good", tooltip = "Create a cart folder under the linked engine carts/",
    }) then
    local nid = tostring(S.cartNewId or ""):gsub("%s+", "")
    if nid == "" then
      S.status = "Enter a cart id first"
    else
      local argv = { "scaffold", nid, "--into", Cartkit.cartsRoot(S) }
      if S.version and S.version ~= "" then
        argv[#argv + 1] = "--base"
        argv[#argv + 1] = S.version
      end
      local ok, out = Cartkit.run(S, argv)
      S.cartLog = tostring(out or "")
      if ok then
        S.cartNewId = ""
        selectCart(S, cartDirFor(S, nid))
        S.status = "Scaffolded " .. nid
      else
        S.status = "Scaffold failed — see log"
      end
    end
  end

  if not S.cartDraft or not S.cartDir then
    Kit.emptyBox(mainX, listY, mainW, listH + 40 * s,
      "Scaffold a cart or pick one under carts/")
    return
  end

  local d = S.cartDraft
  local title = (S.cartDirty and "* " or "") .. (S.cartId or "?") .. " / cart.json"
  Kit.caption(mainX, y, Kit.ellipsize("caption", title, mainW))

  local barY = listY
  local btnH = 30 * s
  local bw = 78 * s
  local bx = mainX
  if Kit.button(bx, barY, bw, btnH, "Write", {
      kind = "primary", tooltip = "Save cart.json (does not pack a .g1rcart)",
    }) then
    Cart.save(S, App)
  end
  bx = bx + bw + 6 * s
  if Kit.button(bx, barY, bw, btnH, "Reload", {
      kind = "ghost", tooltip = "Discard unsaved edits and reload cart.json",
    }) then
    loadDraft(S, S.cartDir)
    S.status = "Reloaded cart.json"
  end
  bx = bx + bw + 6 * s
  local online = S.cartOnline == true
  if Kit.chip(bx, barY, 72 * s, btnH, online and "ONLINE" or "OFFLINE",
      online, PAL.yellow, nil,
      "ONLINE checks GitHub/GameBanana indexability. Off = not required.") then
    S.cartOnline = not online
  end
  bx = bx + 78 * s
  if Kit.button(bx, barY, bw, btnH, "Validate", {
      kind = "accent",
      tooltip = "Check cart.json. ONLINE also checks the published index.",
    }) then
    local argv = { "validate", S.cartDir }
    if S.cartOnline then argv[#argv + 1] = "--online" end
    runKit(S, App, argv, "Validate OK")
  end
  bx = bx + bw + 6 * s
  if Kit.button(bx, barY, bw, btnH, "Pack", {
      kind = "accent",
      tooltip = "Write id-version.g1rcart. Local pins are fine; GitHub is not required.",
    }) then
    local outName = string.format("%s-%s.g1rcart",
      tostring(d.id or S.cartId), tostring(d.version or "0.0.0"))
    local outPath = join(S.cartDir, outName)
    if S.cartDirty then Cart.save(S, App) end
    local labelName = tostring(d.label or "label.png")
    if labelName ~= "" then
      Cartkit.fitLabel(join(S.cartDir, labelName))
      CartPreview.invalidate(S)
    end
    local ok, msg = Cartkit.packBundle(S.cartDir, d, outPath)
    if ok then
      S.cartLog = "wrote " .. outName
      S.status = "Packed " .. outName
    else
      S.cartLog = tostring(msg or "")
      S.status = "Pack failed: " .. tostring(msg)
    end
  end
  bx = bx + bw + 6 * s
  if Kit.button(bx, barY, 100 * s, btnH, "Workflow", {
      kind = "ghost",
      tooltip = "Add a GitHub release workflow (only needed to publish on GitHub)",
    }) then
    runKit(S, App, { "add-release-workflow", S.cartDir }, "Wrote release.yml")
  end

  local formY = barY + btnH + 10 * s
  local logH = 96 * s
  local formH = (listY + listH + 40 * s) - formY - logH - 8 * s
  local gapPreview = 8 * s
  local wantPreview = math.min(230 * s, math.max(160 * s, mainW * 0.30))
  local formW, previewW
  if mainW - wantPreview - gapPreview >= 240 * s then
    previewW = wantPreview
    formW = mainW - previewW - gapPreview
  else
    previewW = math.max(132 * s, mainW * 0.32)
    formW = mainW - previewW - gapPreview
    if formW < 200 * s then
      formW, previewW = mainW, 0
    end
  end
  Kit.card(mainX, formY, formW, formH, 12 * s)
  if previewW > 0 then
    Kit.card(mainX + formW + gapPreview, formY, previewW, formH, 12 * s)
  end

  FormPane.track(S, "cartScroll", S.cartDir)
  local py, view = FormPane.begin(S, "cartScroll",
    mainX + 10 * s, formY + 10 * s, formW - 20 * s, formH - 20 * s)
  local px = mainX + 10 * s
  local propW = view.contentW or (formW - 20 * s)
  local fh = 28 * s
  local labelW = 110 * s
  local top = py

  local function row(label, body)
    Kit.text("micro", label, px, py + 6 * s, PAL.caption)
    body(px + labelW, py, propW - labelW, fh)
    py = py + fh + 8 * s
  end

  if S.cartLoadError then
    Kit.text("micro", "Load note: " .. S.cartLoadError, px, py, PAL.yellow)
    py = py + 18 * s
  end

  Kit.caption(px, py, "IDENTITY")
  py = py + 22 * s
  row("id", function(fx, fy, fw, fh_)
    d.id = field(S, "ct_id", fx, fy, fw, fh_, d.id, "my_cart",
      "Cart id: letters, numbers, _ or -")
  end)
  row("title", function(fx, fy, fw, fh_)
    d.title = field(S, "ct_title", fx, fy, fw, fh_, d.title, "My Cart",
      "Name shown on the launcher cartridge")
  end)
  row("version", function(fx, fy, fw, fh_)
    d.version = field(S, "ct_ver", fx, fy, fw, fh_, d.version, "0.1.0",
      "Semantic version, e.g. 0.1.0")
  end)
  row("author", function(fx, fy, fw, fh_)
    d.author = field(S, "ct_author", fx, fy, fw, fh_, d.author, "you",
      "Who made this cart (required to pack)")
  end)
  row("github", function(fx, fy, fw, fh_)
    d.repo = field(S, "ct_repo", fx, fy, fw, fh_, d.repo, "owner/my-cart",
      "Optional owner/repo. Not required to pack. ONLINE uses it for index checks.")
  end)
  row("summary", function(fx, fy, fw, fh_)
    d.summary = field(S, "ct_sum", fx, fy, fw, fh_, d.summary, "one line",
      "One-line blurb on the launcher")
  end)
  row("base", function(fx, fy, fw, fh_)
    if Kit.button(fx, fy, fw, fh_, tostring(d.base or "red"), {
        kind = "ghost", tooltip = "Which game this cart plays as (click to cycle)",
      }) then
      d.base = cycle(BASES, d.base or "red")
      markDirty(S)
    end
  end)
  row("seal", function(fx, fy, fw, fh_)
    if Kit.button(fx, fy, fw, fh_, tostring(d.seal or "sealed"), {
        kind = "ghost",
        tooltip = "sealed: exact pin set\nsealed+: player may toggle pins\nopen: player can add more mods",
      }) then
      d.seal = cycle(SEALS, d.seal or "sealed")
      markDirty(S)
    end
  end)
  row("shell", function(fx, fy, fw, fh_)
    local rgb = CartPreview.parseShell(d.shell) or { 139, 26, 26 }
    love.graphics.setColor((rgb[1] or 0) / 255, (rgb[2] or 0) / 255,
      (rgb[3] or 0) / 255, 1)
    love.graphics.rectangle("fill", fx, fy, fh_, fh_, 6 * s, 6 * s)
    love.graphics.setColor(1, 1, 1, 0.4)
    love.graphics.rectangle("line", fx, fy, fh_, fh_, 6 * s, 6 * s)
    love.graphics.setColor(1, 1, 1, 1)
    Kit.offerTooltip(fx, fy, fh_, fh_, "Pick shell color")
    if Kit.press(fx, fy, fh_, fh_) then
      ColorWheel.open(S, {
        title = "SHELL",
        color = rgb,
        onChange = function(c)
          d.shell = CartPreview.hex(c)
          markDirty(S)
        end,
        onApply = function(c)
          d.shell = CartPreview.hex(c)
          markDirty(S)
        end,
      })
    end
    local hx = fx + fh_ + 8 * s
    local hexW = 90 * s
    local typed = field(S, "ct_shell", hx, fy, hexW, fh_, d.shell, "#8b1a1a",
      "#RRGGBB cartridge plastic color")
    if typed:match("^#%x%x%x%x%x%x$") then typed = typed:lower() end
    d.shell = typed
    local chipX = hx + hexW + 8 * s
    local chip, gap = 22 * s, 4 * s
    for i, preset in ipairs(SHELL_PRESETS) do
      local cx = chipX + (i - 1) * (chip + gap)
      if cx + chip <= fx + fw + 1 then
        local c = preset[2]
        love.graphics.setColor((c[1] or 0) / 255, (c[2] or 0) / 255,
          (c[3] or 0) / 255, 1)
        love.graphics.rectangle("fill", cx, fy + 3 * s, chip, fh_ - 6 * s,
          4 * s, 4 * s)
        love.graphics.setColor(1, 1, 1, 0.35)
        love.graphics.rectangle("line", cx, fy + 3 * s, chip, fh_ - 6 * s,
          4 * s, 4 * s)
        love.graphics.setColor(1, 1, 1, 1)
        Kit.offerTooltip(cx, fy + 3 * s, chip, fh_ - 6 * s, preset[3])
        if Kit.press(cx, fy + 3 * s, chip, fh_ - 6 * s) then
          d.shell = CartPreview.hex(c)
          markDirty(S)
        end
      end
    end
  end)
  row("finish", function(fx, fy, fw, fh_)
    local shown = (d.finish and d.finish ~= "") and d.finish or "(none)"
    if Kit.button(fx, fy, fw, fh_, shown, {
        kind = "ghost",
        tooltip = "plain, sparkle (glitter), holo (foil), or sparkle+holo",
      }) then
      d.finish = cycle(FINISHES, d.finish or "")
      markDirty(S)
    end
  end)
  row("speeds", function(fx, fy, fw, fh_)
    local cur = csv(d.speeds)
    local v = field(S, "ct_spd", fx, fy, fw, fh_, cur, "1, 2",
      "GameSpeed multipliers this cart allows, comma-separated")
    if v ~= cur then
      local nums = {}
      for _, part in ipairs(splitCsv(v)) do
        nums[#nums + 1] = tonumber(part) or part
      end
      d.speeds = nums
    end
  end)
  row("engine", function(fx, fy, fw, fh_)
    d.engine = field(S, "ct_eng", fx, fy, fw, fh_, d.engine, ">=0.2.0 <1.0.0",
      "Optional engine version range this cart needs")
  end)
  row("label", function(fx, fy, fw, fh_)
    d.label = field(S, "ct_lab", fx, fy, math.max(40 * s, fw - 100 * s),
      fh_, d.label, "label.png", "PNG sticker on the cartridge (keep under 256 KB)")
    if Kit.button(fx + fw - 96 * s, fy, 96 * s, fh_, "Browse", {
        kind = "ghost", tooltip = "Copy a PNG next to cart.json (auto-shrinks if over 256 KB)",
      }) then
      App.pickFile("Cart label PNG", "PNG (*.png)|*.png|All|*.*", function(picked)
        local dest = join(S.cartDir, "label.png")
        local ok, err = ModIO.copyFile(picked, dest)
        if ok then
          d.label = "label.png"
          markDirty(S)
          local fitOk, bytes, shrunk = Cartkit.fitLabel(dest)
          CartPreview.invalidate(S)
          Cart.save(S, App)
          if fitOk and shrunk then
            S.status = string.format("Copied and shrunk label.png (%d KB)",
              math.floor((tonumber(bytes) or 0) / 1024))
          elseif fitOk then
            S.status = "Copied label.png"
          else
            S.status = "Copied label.png — " .. tostring(bytes)
          end
        else
          S.status = "Label copy failed: " .. tostring(err)
        end
      end)
    end
  end)
  do
    local labelPath = join(S.cartDir, tostring(d.label ~= "" and d.label or "label.png"))
    local nbytes = Cartkit.fileSize(labelPath)
    if nbytes and nbytes > Cartkit.LABEL_WARN then
      local overMax = nbytes > Cartkit.LABEL_MAX
      Kit.text("micro",
        overMax
          and string.format("label is %.2f MB (max 1.00) — Shrink",
            nbytes / Cartkit.LABEL_MAX)
          or string.format("label is %d KB — Shrink under 256 KB",
            math.floor(nbytes / 1024)),
        px, py + 4 * s, overMax and PAL.red or PAL.yellow)
      if Kit.button(px + propW - 84 * s, py, 84 * s, 22 * s, "Shrink", {
          kind = "accent", tooltip = "Scale label.png under 256 KB",
        }) then
        local fitOk, bytes, shrunk = Cartkit.fitLabel(labelPath)
        CartPreview.invalidate(S)
        if fitOk then
          S.status = shrunk
            and string.format("Shrunk label.png to %d KB", math.floor(bytes / 1024))
            or "Label already under 256 KB"
        else
          S.status = "Shrink failed: " .. tostring(bytes)
        end
      end
      py = py + 28 * s
    end
  end

  py = py + 8 * s
  Kit.caption(px, py, "PINS  (1–64)")
  py = py + 22 * s
  Kit.text("micro",
    "Published pin (optional). ONLINE checks the GitHub/GameBanana index.",
    px, py, PAL.muted)
  py = py + 18 * s

  S.cartPinSpec = plain("ct_pin_spec", px, py, propW - 90 * s, fh,
    S.cartPinSpec or "", "owner/repo@1.2.3 or gamebanana URL",
    "Published pin only. Leave blank and use Add/Browse for a local mod.")
  if Kit.button(px + propW - 84 * s, py, 84 * s, fh, "Pin", {
      kind = "accent",
      tooltip = "Pin a published GitHub release or GameBanana file (fills the hash).\nNot required for local mods.",
    }) then
    local spec = tostring(S.cartPinSpec or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if spec == "" then
      S.status = "Enter owner/repo@1.2.3 or a GameBanana URL"
    else
      local argv = { "pin", S.cartDir, spec }
      local pinId = tostring(S.cartPinId or ""):gsub("%s+", "")
      if pinId ~= "" then
        argv[#argv + 1] = "--id"
        argv[#argv + 1] = pinId
      end
      local fileId = tonumber(S.cartPinFile)
      if fileId then
        argv[#argv + 1] = "--file"
        argv[#argv + 1] = tostring(fileId)
      end
      for _, opt in ipairs(splitCsv(S.cartPinOpts or "")) do
        argv[#argv + 1] = "--option"
        argv[#argv + 1] = opt
      end
      if runKit(S, App, argv, "Pinned " .. spec) then
        S.cartPinSpec = ""
      end
    end
  end
  py = py + fh + 6 * s
  Kit.text("micro", "id override", px, py + 6 * s, PAL.caption)
  S.cartPinId = plain("ct_pin_id", px + labelW, py, 140 * s, fh,
    S.cartPinId or "", "mod-id", "Optional id override for a published pin")
  Kit.text("micro", "GB file", px + labelW + 150 * s, py + 6 * s, PAL.caption)
  S.cartPinFile = plain("ct_pin_file", px + labelW + 210 * s, py, 80 * s, fh,
    S.cartPinFile or "", "id", "GameBanana file id when a mod has several files")
  py = py + fh + 6 * s
  Kit.text("micro", "options", px, py + 6 * s, PAL.caption)
  S.cartPinOpts = plain("ct_pin_opts", px + labelW, py, propW - labelW, fh,
    S.cartPinOpts or "", "difficulty=hard", "Freeze option values on the pin, e.g. difficulty=hard")
  py = py + fh + 10 * s

  Kit.text("micro",
    "Local mods on this PC. GitHub/GameBanana are only for ONLINE index checks.",
    px, py, PAL.muted)
  py = py + 18 * s
  local localMods = ModIO.listMods()
  if S.cartLocalPick then
    local found = false
    for _, name in ipairs(localMods) do
      if name == S.cartLocalPick then found = true; break end
    end
    if not found then S.cartLocalPick = localMods[1] end
  elseif S.path then
    local openId = S.path:match("[^/\\]+$")
    for _, name in ipairs(localMods) do
      if name == openId then S.cartLocalPick = name; break end
    end
    if not S.cartLocalPick then S.cartLocalPick = localMods[1] end
  else
    S.cartLocalPick = localMods[1]
  end
  local thisW = 64 * s
  local addW = 56 * s
  local browseW = 72 * s
  local gapW = 6 * s
  local pickW = math.max(80 * s, propW - addW - browseW - thisW - gapW * 3)
  local pickLabel = S.cartLocalPick or "(none)"
  if Kit.button(px, py, pickW, fh, Kit.ellipsize("small", pickLabel, pickW - 12 * s), {
      kind = "ghost", tooltip = "Cycle mods in the editor mods/ folder",
    }) then
    if #localMods == 0 then
      S.status = "No mods in the editor mods/ folder — use Browse"
    else
      S.cartLocalPick = cycle(localMods, S.cartLocalPick)
    end
  end
  if Kit.button(px + pickW + gapW, py, addW, fh, "Add", {
      kind = "accent", tooltip = "Pin the selected editor mod as source=local",
    }) then
    local pick = S.cartLocalPick
    if not pick then
      S.status = "Pick a local mod or Browse a folder"
    else
      pinLocalFromDir(S, ModIO.modDir(pick))
    end
  end
  if Kit.button(px + pickW + gapW + addW + gapW, py, browseW, fh, "Browse", {
      kind = "ghost", tooltip = "Pick any folder that has manifest.json",
    }) then
    App.pickFolder("Choose a mod folder", function(path)
      pinLocalFromDir(S, path)
    end, S.path or ModIO.modsRoot())
  end
  if Kit.button(px + pickW + gapW + addW + gapW + browseW + gapW, py, thisW, fh,
      "This", {
        kind = "ghost", tooltip = "Pin the open content project",
      }) then
    if S.path then
      pinLocalFromDir(S, S.path)
    else
      S.status = "Open a mod project first"
    end
  end
  py = py + fh + 12 * s

  local mods = d.mods
  if #mods == 0 then
    Kit.text("micro", "No pins yet. Pin a published release or add a local mod.",
      px, py, PAL.faint)
    py = py + 20 * s
  end
  for i, row in ipairs(mods) do
    Kit.card(px, py, propW, 64 * s, 8 * s)
    local idv = field(S, "ct_m_id_" .. i, px + 8 * s, py + 6 * s, 140 * s, 24 * s,
      tostring(row.id or ""), "id", "Mod id this pin names")
    row.id = idv
    local src = tostring(row.source or "github")
    if Kit.button(px + 156 * s, py + 6 * s, 90 * s, 24 * s, src, {
        kind = "ghost",
        tooltip = "github: published release (index)\ngamebanana: GameBanana file\nlocal: a copy already on this PC",
      }) then
      row.source = cycle(PIN_SOURCES, src)
      if row.source == "local" then
        clearPinSourceFields(row)
        if not row.version or row.version == "" then row.version = "0.0.0" end
      elseif row.source == "gamebanana" then
        row.repo, row.sha256 = nil, nil
      else
        row.mod, row.file, row.md5 = nil, nil, nil
      end
      markDirty(S)
    end
    local on = row.enabled ~= false
    if Kit.chip(px + 254 * s, py + 6 * s, 70 * s, 24 * s,
        on and "ON" or "OFF", on, PAL.green, nil,
        "Whether this pin runs. OFF still installs it.") then
      row.enabled = not on
      if row.enabled then row.enabled = nil end
      markDirty(S)
    end
    if Kit.button(px + propW - 120 * s, py + 6 * s, 36 * s, 24 * s, "^",
        { kind = "ghost", tooltip = "Move this pin earlier in load order" }) and i > 1 then
      mods[i], mods[i - 1] = mods[i - 1], mods[i]
      markDirty(S)
    end
    if Kit.button(px + propW - 80 * s, py + 6 * s, 36 * s, 24 * s, "v",
        { kind = "ghost", tooltip = "Move this pin later in load order" }) and i < #mods then
      mods[i], mods[i + 1] = mods[i + 1], mods[i]
      markDirty(S)
    end
    if Kit.button(px + propW - 40 * s, py + 6 * s, 32 * s, 24 * s, "X",
        { kind = "danger", tooltip = "Remove this pin" }) then
      table.remove(mods, i)
      markDirty(S)
      break
    end
    if row.source == "local" then
      row.version = field(S, "ct_m_ver_" .. i, px + 8 * s, py + 34 * s,
        100 * s, 24 * s, tostring(row.version or ""), "1.0.0",
        "Installed version on this PC")
      Kit.text("micro", "this PC only — launcher cannot download it",
        px + 116 * s, py + 38 * s, PAL.faint)
    elseif row.source == "gamebanana" then
      row.mod = tonumber(field(S, "ct_m_mod_" .. i, px + 8 * s, py + 34 * s,
        100 * s, 24 * s, tostring(row.mod or ""), "mod id",
        "GameBanana mod id")) or row.mod
      row.file = tonumber(field(S, "ct_m_file_" .. i, px + 116 * s, py + 34 * s,
        100 * s, 24 * s, tostring(row.file or ""), "file id",
        "GameBanana file id")) or row.file
      row.md5 = field(S, "ct_m_md5_" .. i, px + 224 * s, py + 34 * s,
        math.max(80 * s, propW - 240 * s), 24 * s, tostring(row.md5 or ""), "md5",
        "Published file md5 — Pin fills this")
    else
      row.repo = field(S, "ct_m_repo_" .. i, px + 8 * s, py + 34 * s,
        180 * s, 24 * s, tostring(row.repo or ""), "owner/repo",
        "GitHub owner/repo — needed for ONLINE index checks")
      row.version = field(S, "ct_m_ver_" .. i, px + 196 * s, py + 34 * s,
        80 * s, 24 * s, tostring(row.version or ""), "1.0.0",
        "Release tag / semver")
      row.sha256 = field(S, "ct_m_sha_" .. i, px + 284 * s, py + 34 * s,
        math.max(80 * s, propW - 300 * s), 24 * s, tostring(row.sha256 or ""), "sha256",
        "Archive sha256 — Pin fills this")
    end
    py = py + 72 * s
  end

  local order = {}
  for _, row in ipairs(mods) do
    if type(row.id) == "string" and row.id ~= "" then
      order[#order + 1] = row.id
    end
  end
  d.load_order = order

  FormPane.finish(S, "cartScroll", top, py, view)

  if previewW > 0 then
    Kit.offerTooltip(mainX + formW + gapPreview, formY, previewW, formH,
      "Launcher cartridge preview. Drag to spin.")
    CartPreview.draw(S, mainX + formW + gapPreview, formY, previewW, formH, {
      id = d.id,
      title = d.title,
      base = d.base,
      shell = d.shell,
      finish = d.finish,
      labelPath = join(S.cartDir, tostring(d.label ~= "" and d.label or "label.png")),
    })
  end

  local logY = formY + formH + 8 * s
  Kit.card(mainX, logY, mainW, logH, 8 * s)
  local log = S.cartLog or ""
  if log == "" then
    Kit.text("micro", "cartkit output appears here.", mainX + 10 * s, logY + 10 * s, PAL.faint)
  else
    local ly = logY + 8 * s
    local n = 0
    for line in log:gmatch("[^\r\n]+") do
      n = n + 1
      if n > 6 then break end
      local col = PAL.muted
      local u = line:upper()
      if line:find("^note ", 1) or line:find("note local", 1, true) then col = PAL.yellow
      elseif u:find("ERROR", 1, true) or u:find("FAIL", 1, true) then col = PAL.red
      elseif u:find("WARN", 1, true) then col = PAL.yellow
      elseif u:find("OK ", 1, true) or u:find("WROTE", 1, true) then col = PAL.green
      end
      Kit.text("micro", Kit.ellipsize("micro", line, mainW - 20 * s),
        mainX + 10 * s, ly, col)
      ly = ly + 14 * s
    end
  end
end

return Cart
