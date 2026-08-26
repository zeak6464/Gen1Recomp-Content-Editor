-- Drive tools/cartkit.py from the linked Gen1Recomp (scaffold / pin / validate / pack).

local Json = require("src.link.Json")
local ModIO = require("ModIO")
local DataSource = require("DataSource")

local Cartkit = {}

Cartkit.BASES = { "red", "blue", "yellow", "gold", "silver", "crystal" }
Cartkit.SEALS = { "sealed", "sealed+", "open" }
Cartkit.FINISHES = { "", "sparkle", "holo", "sparkle+holo" }

local CART_KEYS = {
  "schema", "id", "title", "version", "author", "repo", "summary",
  "shell", "finish", "label", "base", "engine", "seal", "speeds",
  "mods", "load_order",
}
local MOD_KEYS = {
  "id", "source", "repo", "version", "sha256", "mod", "file", "md5",
  "enabled", "options",
}

local function join(a, b)
  if not a or a == "" then return b end
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a .. b end
  return a .. package.config:sub(1, 1) .. b
end

local function quote(s)
  s = tostring(s or "")
  if package.config:sub(1, 1) == "\\" then
    return '"' .. s:gsub('"', '""') .. '"'
  end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function fileOk(path)
  if not path or path == "" then return false end
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

function Cartkit.engineRoot(S)
  local prefs = (S and S.dataPrefs) or DataSource.loadPrefs()
  local recomp = (prefs and prefs.recompRoot) or DataSource.mountedRecompRoot()
  if recomp and recomp ~= "" then
    recomp = recomp:gsub("[/\\]+$", "")
    if fileOk(join(recomp, join("tools", "cartkit.py"))) then return recomp end
  end
  local src = ModIO.repoRoot()
  if fileOk(join(src, join("tools", "cartkit.py"))) then return src end
  return nil
end

function Cartkit.scriptPath(S)
  local root = Cartkit.engineRoot(S)
  if not root then return nil end
  return join(root, join("tools", "cartkit.py"))
end

function Cartkit.cartsRoot(S)
  local root = Cartkit.engineRoot(S)
  if not root then return nil end
  return join(root, "carts")
end

function Cartkit.cartPath(dir)
  return join(dir, "cart.json")
end

function Cartkit.encodeCart(cart)
  local ordered = {}
  for _, key in ipairs(CART_KEYS) do
    local val = cart[key]
    if val ~= nil and val ~= "" then
      if key == "mods" and type(val) == "table" then
        local mods = {}
        for i, row in ipairs(val) do
          if type(row) == "table" then
            local rec = {}
            for _, mk in ipairs(MOD_KEYS) do
              local mv = row[mk]
              if mv ~= nil and mv ~= "" and not (mk == "enabled" and mv == true) then
                rec[mk] = mv
              end
            end
            mods[i] = rec
          end
        end
        ordered.mods = mods
      elseif key == "speeds" and type(val) == "table" and #val == 0 then
        -- omit
      elseif key == "load_order" and type(val) == "table" and #val == 0 then
        -- omit
      else
        ordered[key] = val
      end
    end
  end
  return Json.encode(ordered)
end

function Cartkit.readCart(dir)
  local body, err = ModIO.readText(Cartkit.cartPath(dir))
  if not body then return nil, err end
  local data, derr = Json.decode(body)
  if type(data) ~= "table" then return nil, derr or "cart.json is not an object" end
  data.mods = type(data.mods) == "table" and data.mods or {}
  data.load_order = type(data.load_order) == "table" and data.load_order or nil
  return data
end

function Cartkit.writeCart(dir, cart)
  return ModIO.writeText(Cartkit.cartPath(dir), Cartkit.encodeCart(cart) .. "\n")
end

Cartkit.LABEL_MAX = 1024 * 1024
Cartkit.LABEL_WARN = 256 * 1024

function Cartkit.fileSize(path)
  if type(path) ~= "string" or path == "" then return nil end
  local f = io.open(path, "rb")
  if not f then return nil end
  local n = f:seek("end")
  f:close()
  return n
end

-- cartkit treats CK004 local pins as fatal for a published cart.  This editor
-- allows them for a this-PC cart, so interpret() splits those from real errors.
function Cartkit.interpret(out)
  local info = { hardFail = false, localPins = false, labelTooBig = false }
  for line in tostring(out or ""):gmatch("[^\r\n]+") do
    if line:find("ERROR", 1, true) then
      if line:find("pinned to one install", 1, true) then
        info.localPins = true
      elseif line:find("CK003", 1, true) then
        info.labelTooBig = true
        info.hardFail = true
      else
        info.hardFail = true
      end
    end
  end
  return info
end

local function encodePng(imageData)
  if not (imageData and imageData.encode) then return nil end
  local ok, fd = pcall(imageData.encode, imageData, "png")
  if not (ok and fd) then return nil end
  if fd.getString then return fd:getString() end
  return nil
end

local function scaleImage(src, nw, nh)
  local dst = love.image.newImageData(nw, nh)
  local sw, sh = src:getWidth(), src:getHeight()
  dst:mapPixel(function(x, y)
    local sx = math.min(sw - 1, math.floor((x + 0.5) / nw * sw))
    local sy = math.min(sh - 1, math.floor((y + 0.5) / nh * sh))
    return src:getPixel(sx, sy)
  end)
  return dst
end

-- Write path under maxBytes (default: cartkit's 256 KB warning). Returns ok, bytes, shrunk?
function Cartkit.fitLabel(path, maxBytes)
  maxBytes = tonumber(maxBytes) or Cartkit.LABEL_WARN
  local size = Cartkit.fileSize(path)
  if not size then return false, "label.png is missing" end
  if size <= maxBytes then return true, size, false end
  if not (love and love.image and love.image.newImageData
      and love.filesystem and love.filesystem.newFileData) then
    return false, "cannot shrink label without LÖVE"
  end
  local body, err = ModIO.readText(path)
  if not body then return false, err or "cannot read label.png" end
  local okFd, fd = pcall(love.filesystem.newFileData, body, "label.png")
  if not (okFd and fd) then return false, "cannot load label.png" end
  local okImg, img = pcall(love.image.newImageData, fd)
  if not (okImg and img) then return false, "label.png is not a PNG" end
  local encoded = encodePng(img)
  if encoded and #encoded <= maxBytes then
    local wok, werr = ModIO.writeText(path, encoded)
    if not wok then return false, werr end
    return true, #encoded, true
  end
  local w, h = img:getWidth(), img:getHeight()
  local scale = math.sqrt(maxBytes / math.max(1, size)) * 0.85
  for _ = 1, 10 do
    local nw = math.max(16, math.floor(w * scale))
    local nh = math.max(16, math.floor(h * scale))
    local okDst, dst = pcall(scaleImage, img, nw, nh)
    if not okDst then return false, tostring(dst) end
    encoded = encodePng(dst)
    if encoded and #encoded <= maxBytes then
      local wok, werr = ModIO.writeText(path, encoded)
      if not wok then return false, werr end
      return true, #encoded, true
    end
    img, w, h = dst, nw, nh
    scale = 0.7
  end
  return false, "label is still over " .. tostring(maxBytes) .. " bytes after shrink"
end

-- Drop cartkit FAIL / local-pin ERRORs when the editor accepts this-PC pins.
function Cartkit.displayLog(out, info)
  info = info or Cartkit.interpret(out)
  local lines = {}
  for line in tostring(out or ""):gmatch("[^\r\n]+") do
    if line:find("pinned to one install", 1, true) then
      lines[#lines + 1] = "note local pin — OK on this PC"
    elseif line:match("^FAIL ") and not info.hardFail then
      -- cartkit fails the cart for local pins; the editor does not
    else
      lines[#lines + 1] = line
    end
  end
  if not info.hardFail and info.localPins then
    lines[#lines + 1] = "ok valid on this PC"
  end
  if #lines == 0 then return tostring(out or "") end
  return table.concat(lines, "\n")
end

function Cartkit.listCarts(S)
  local root = Cartkit.cartsRoot(S)
  local out = {}
  if not root then return out end
  for _, name in ipairs(ModIO.listSubdirs(root)) do
    if ModIO.exists(Cartkit.cartPath(join(root, name))) then
      out[#out + 1] = name
    end
  end
  return out
end

local function runCmd(cmd)
  local ok, handle = pcall(io.popen, cmd .. " 2>&1")
  if not ok or not handle then
    return false, "shell unavailable: " .. tostring(handle)
  end
  local out = handle:read("*a") or ""
  local okClose, _, code = handle:close()
  local exit = (type(code) == "number" and code) or (okClose and 0 or 1)
  return exit == 0, out
end

function Cartkit.run(S, argv)
  local root = Cartkit.engineRoot(S)
  local script = Cartkit.scriptPath(S)
  if not root or not script then
    return false, "Link a Gen1Recomp folder that includes tools/cartkit.py"
  end
  local function cmdFor(py)
    local parts = { py, quote(script), "--repo", quote(root) }
    for i = 1, #argv do
      parts[#parts + 1] = quote(argv[i])
    end
    return table.concat(parts, " ")
  end
  local ok, out = runCmd(cmdFor("python"))
  if (not ok and (out or ""):find("python")) or (out or ""):find("not recognized") then
    ok, out = runCmd(cmdFor("python3"))
  end
  local info = Cartkit.interpret(out)
  if info.hardFail then return false, out end
  if info.localPins then return true, out end
  if tostring(out):find("FAIL ", 1, true) then return false, out end
  return ok, out
end

function Cartkit.hasLocalPins(cart)
  for _, row in ipairs((cart and cart.mods) or {}) do
    if type(row) == "table" and row.source == "local" then return true end
  end
  return false
end

local function blank(v)
  if v == nil or v == "" then return nil end
  return v
end

-- Pack a .g1rcart with the engine encoder so local pins are legal.
-- cartkit pack refuses those (CK004); GitHub is only for --online index checks.
function Cartkit.packBundle(dir, cart, outPath)
  local okM, Manifest = pcall(require, "src.carts.CartManifest")
  if not okM then return false, "engine CartManifest is not on the path" end
  local okB, Base64 = pcall(require, "src.core.Base64")
  if not okB then return false, "engine Base64 is not on the path" end

  local mods = {}
  for i, row in ipairs(cart.mods or {}) do
    if type(row) == "table" then
      local rec = { id = row.id, source = row.source, version = row.version }
      if row.source == "github" then
        rec.repo, rec.sha256 = row.repo, row.sha256
      elseif row.source == "gamebanana" then
        rec.mod, rec.file, rec.md5 = row.mod, row.file, row.md5
      end
      if row.enabled == false then rec.enabled = false end
      rec.options = row.options
      mods[i] = rec
    end
  end
  local payload = {
    id = cart.id,
    title = cart.title,
    version = cart.version,
    author = cart.author,
    repo = blank(cart.repo),
    summary = blank(cart.summary),
    shell = cart.shell,
    finish = blank(cart.finish),
    speeds = (type(cart.speeds) == "table" and #cart.speeds > 0) and cart.speeds or nil,
    label = blank(cart.label),
    base = cart.base,
    engine = blank(cart.engine),
    seal = cart.seal,
    mods = mods,
    load_order = cart.load_order,
  }
  local labelName = payload.label
  if labelName then
    local bytes = ModIO.readText(join(dir, labelName))
    if bytes and #bytes > 0 then
      payload.labelArt = {
        name = labelName:match("[^/\\]+$") or labelName,
        encoding = "base64",
        bytes = #bytes,
        data = Base64.encode(bytes),
      }
    end
  end
  local parsed, err = Manifest.parse(payload)
  if not parsed then return false, err end
  if payload.labelArt then
    local art, aerr = Manifest.parseLabelArt(payload.labelArt)
    if not art then return false, aerr end
    parsed.labelArt = art
  end
  local body = Manifest.encode(parsed)
  local wok, werr = ModIO.writeText(outPath, body)
  if not wok then return false, werr end
  return true, outPath
end

return Cartkit
