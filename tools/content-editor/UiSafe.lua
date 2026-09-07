-- Shared size-safe UI helpers for the editor (preview + import warnings).
-- Runtime copies of load/fitted live in the generated mod (ModWriter.emitCustomUi).

local Preview = require("Preview")

local UiSafe = {}

function UiSafe.pathOf(v)
  if type(v) == "table" then return tostring(v.path or v.sheet or v.image or "") end
  if type(v) == "string" then return v end
  return ""
end

function UiSafe.imageSize(S, path)
  path = UiSafe.pathOf(path)
  if path == "" then return nil end
  local image = Preview.image(S, path)
  if not image then return nil end
  local ok, iw, ih = pcall(function()
    return image:getWidth(), image:getHeight()
  end)
  if ok and type(iw) == "number" and iw > 0 then return iw, ih end
  return nil
end

function UiSafe.sizesMatch(ew, eh, aw, ah)
  return ew and aw and ew == aw and eh == ah
end

function UiSafe.fieldKey(specId, keys)
  local parts = { tostring(specId or "") }
  for i = 1, #(keys or {}) do
    parts[#parts + 1] = tostring(keys[i])
  end
  return table.concat(parts, ".")
end

function UiSafe.ensure(S)
  if not S or not S.project then return end
  S.project.uiMismatch = S.project.uiMismatch or {}
  S.project.uiFitted = S.project.uiFitted or {}
end

function UiSafe.noteMismatch(S, key, expectedPath, actualPath)
  if not S or not S.project or type(key) ~= "string" or key == "" then return end
  UiSafe.ensure(S)
  local ew, eh = UiSafe.imageSize(S, expectedPath)
  local aw, ah = UiSafe.imageSize(S, actualPath)
  if ew and aw and not UiSafe.sizesMatch(ew, eh, aw, ah) then
    S.project.uiMismatch[key] = { ew, eh, aw, ah }
  else
    S.project.uiMismatch[key] = nil
    if S.project.uiFitted then S.project.uiFitted[key] = nil end
  end
end

function UiSafe.mismatch(S, key)
  local m = S and S.project and S.project.uiMismatch
  return m and m[key] or nil
end

function UiSafe.fitted(S, key)
  local f = S and S.project and S.project.uiFitted
  return f and f[key] and true or false
end

function UiSafe.setFitted(S, key, on)
  if not S or not S.project or type(key) ~= "string" then return end
  UiSafe.ensure(S)
  if on then
    S.project.uiFitted[key] = true
  else
    S.project.uiFitted[key] = nil
  end
end

function UiSafe.drawFitted(image, x, y, w, h)
  if not image then return false end
  local ok, iw, ih = pcall(function() return image:getDimensions() end)
  if not (ok and iw and ih and iw > 0 and ih > 0) then return false end
  local sc = math.min(w / iw, h / ih)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, x + (w - iw * sc) / 2, y + (h - ih * sc) / 2, 0, sc, sc)
  return true
end

function UiSafe.stills(intro)
  local out = {}
  if type(intro) ~= "table" or type(intro.stills) ~= "table" then return out end
  for i, row in ipairs(intro.stills) do
    local path = UiSafe.pathOf(row)
    if path ~= "" then
      out[#out + 1] = {
        path = path,
        frames = tonumber(type(row) == "table" and row.frames) or 180,
        index = i,
      }
    end
  end
  return out
end

function UiSafe.isCustom(bucket)
  return type(bucket) == "table" and tostring(bucket.layout or "") == "custom"
end

return UiSafe
