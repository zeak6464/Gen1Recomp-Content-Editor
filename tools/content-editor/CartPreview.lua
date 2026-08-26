-- Launcher-style cartridge preview for the CART tab (shell, finish, label).

local Kit = require("Kit")
local Theme = require("Theme")
local PAL = Theme.PAL

local CartPreview = {}

local TAU = math.pi * 2
local FINISH_NONE, FINISH_SPARKLE, FINISH_HOLO = 0, 1, 2

local FINISH_SHADER = [[
#ifdef PIXEL
extern float finish;
extern float finish_time;
extern float finish_spin;

float sparkHash(vec2 p) {
  return fract(sin(dot(p, vec2(41.7321, 289.113))) * 43758.5453);
}

vec3 sparkle(vec2 screen_coords) {
  vec2 cell = screen_coords / 19.0;
  vec2 id = floor(cell);
  vec2 f = fract(cell);
  float peak = 0.0;
  for (int oy = -1; oy <= 1; oy++) {
    for (int ox = -1; ox <= 1; ox++) {
      vec2 n = vec2(float(ox), float(oy));
      vec2 h = vec2(sparkHash(id + n), sparkHash(id + n + 17.0));
      float phase = sparkHash(id + n + 71.0) * 6.2831;
      float tw = sin(finish_time * 2.6 + phase + finish_spin * 3.0) * 0.5 + 0.5;
      float d = length(f - (n + h));
      peak = max(peak, smoothstep(0.13, 0.0, d) * pow(tw, 16.0));
    }
  }
  return vec3(peak);
}

vec3 holo(vec2 uv) {
  float band = uv.x * 0.9 + uv.y * 0.6 + finish_spin * 0.55 + finish_time * 0.06;
  vec3 hue = 0.5 + 0.5 * cos(6.2831 * (band + vec3(0.0, 0.33, 0.67)));
  float interference = 0.5 + 0.5 * sin((uv.x - uv.y) * 62.0 + finish_time * 0.9);
  return hue * (0.55 + 0.45 * interference);
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
  vec4 px = Texel(tex, texture_coords) * color;
  if (finish > 1.5) {
    vec3 sheen = holo(texture_coords);
    float lum = dot(px.rgb, vec3(0.299, 0.587, 0.114));
    px.rgb = mix(px.rgb, px.rgb * (0.65 + sheen), 0.30 * (0.35 + 0.65 * lum));
    px.rgb += sheen * 0.05 * px.a;
  } else if (finish > 0.5) {
    px.rgb += sparkle(screen_coords) * 0.70 * px.a;
  }
  return px;
}
#endif
]]

local shaderCache = false

local function clamp(n, lo, hi)
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

function CartPreview.parseShell(hex)
  local r, g, b = tostring(hex or ""):match("#(%x%x)(%x%x)(%x%x)")
  if not r then return nil end
  return { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
end

function CartPreview.hex(rgb)
  local r = math.floor(clamp(tonumber(rgb and rgb[1]) or 0, 0, 255) + 0.5)
  local g = math.floor(clamp(tonumber(rgb and rgb[2]) or 0, 0, 255) + 0.5)
  local b = math.floor(clamp(tonumber(rgb and rgb[3]) or 0, 0, 255) + 0.5)
  return string.format("#%02x%02x%02x", r, g, b)
end

function CartPreview.invalidate(S)
  if S then S._cartPreview = nil end
end

local function finishFlags(name)
  name = tostring(name or "")
  return name:find("sparkle", 1, true) ~= nil, name:find("holo", 1, true) ~= nil
end

local function getShader()
  if shaderCache ~= false then return shaderCache end
  if not (love and love.graphics and love.graphics.newShader) then
    shaderCache = nil
    return nil
  end
  local ok, sh = pcall(love.graphics.newShader, FINISH_SHADER)
  shaderCache = (ok and sh) or nil
  return shaderCache
end

local function sendFinish(shader, mode, spin)
  if not (shader and shader.send) then return end
  pcall(function()
    shader:send("finish", mode)
    shader:send("finish_time", Kit.time or 0)
    shader:send("finish_spin", spin or 0)
  end)
end

local function fileSize(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:close()
  return size
end

local function loadLabel(path)
  if type(path) ~= "string" or path == "" then return nil end
  if not (love and love.graphics and love.graphics.newImage
      and love.filesystem and love.filesystem.newFileData) then
    return nil
  end
  local f = io.open(path, "rb")
  if not f then return nil end
  local bytes = f:read("*a")
  f:close()
  if not bytes or bytes == "" then return nil end
  local name = path:match("[^/\\]+$") or "label.png"
  local okFd, fd = pcall(love.filesystem.newFileData, bytes, name)
  if not (okFd and fd) then return nil end
  local ok, image = pcall(love.graphics.newImage, fd)
  if not ok or not image then return nil end
  local sized, iw, ih = pcall(image.getDimensions, image)
  if not (sized and iw and ih and iw > 0 and ih > 0) then return nil end
  return { image = image, width = iw, height = ih }
end

local function project(cx, cy, yaw, pitch, x, y, z)
  local cyaw, syaw = math.cos(yaw), math.sin(yaw)
  local cpitch, spitch = math.cos(pitch), math.sin(pitch)
  local rx = x * cyaw + z * syaw
  local rz = -x * syaw + z * cyaw
  local ry = y * cpitch - rz * spitch
  rz = y * spitch + rz * cpitch
  local perspective = 620 / (620 - rz)
  return cx + rx * perspective, cy + ry * perspective
end

local function polygon(points, color, alpha)
  if not (love and love.graphics and love.graphics.polygon) then return end
  local flat = {}
  for i = 1, #points do
    flat[#flat + 1], flat[#flat + 2] = points[i][1], points[i][2]
  end
  Theme.col(color, alpha or 1)
  love.graphics.polygon("fill", flat)
end

local function quad(proj, x, y, w, h, z)
  return {
    { proj(x, y, z) }, { proj(x + w, y, z) },
    { proj(x + w, y + h, z) }, { proj(x, y + h, z) },
  }
end

local function facing(points)
  local area = 0
  for i = 1, #points do
    local a, b = points[i], points[i % #points + 1]
    area = area + a[1] * b[2] - b[1] * a[2]
  end
  return area > 0
end

local function pill(proj, x, y, w, h, z, color, alpha)
  local points, radius = {}, h / 2
  for i = 0, 10 do
    local a = -math.pi / 2 + math.pi * i / 10
    points[#points + 1] = { proj(x + w - radius + math.cos(a) * radius,
      y + radius + math.sin(a) * radius, z) }
  end
  for i = 0, 10 do
    local a = math.pi / 2 + math.pi * i / 10
    points[#points + 1] = { proj(x + radius + math.cos(a) * radius,
      y + radius + math.sin(a) * radius, z) }
  end
  polygon(points, color, alpha)
end

local function labelMesh(state, label, points)
  if not (love and love.graphics and love.graphics.newMesh) then return nil end
  local mesh = state.mesh
  if not mesh then
    mesh = love.graphics.newMesh({
      { 0, 0, 0, 0, 255, 255, 255, 255 },
      { 0, 0, 1, 0, 255, 255, 255, 255 },
      { 0, 0, 1, 1, 255, 255, 255, 255 },
      { 0, 0, 0, 1, 255, 255, 255, 255 },
    }, "fan", "dynamic")
    state.mesh = mesh
  end
  mesh:setTexture(label.image)
  mesh:setVertices({
    { points[1][1], points[1][2], 0, 0, 255, 255, 255, 255 },
    { points[2][1], points[2][2], 1, 0, 255, 255, 255, 255 },
    { points[3][1], points[3][2], 1, 1, 255, 255, 255, 255 },
    { points[4][1], points[4][2], 0, 1, 255, 255, 255, 255 },
  })
  return mesh
end

local function stateOf(S)
  S._cartPreview = S._cartPreview or { spin = 0, lastTime = Kit.time or 0 }
  return S._cartPreview
end

local function drawCart(S, x, y, w, h, skin)
  local st = stateOf(S)
  local cx, cy = x + w / 2, y + h / 2
  local hot = Kit.hover(x, y, w, h)

  if Kit.mouseClicked and Kit.hit(x, y, w, h) and not Kit.blockClicks then
    if Kit.mouseDown then
      st.drag = true
      st.lastX, st.lastY = Kit.mouseX, Kit.mouseY
    end
  end
  if st.drag then
    if Kit.mouseDown then
      st.spin = (st.spin or 0) + (Kit.mouseX - (st.lastX or Kit.mouseX)) * 0.018
      st.pitch = clamp((st.pitch or 0)
        + (Kit.mouseY - (st.lastY or Kit.mouseY)) * 0.010, -1.20, 1.20)
      st.lastX, st.lastY = Kit.mouseX, Kit.mouseY
    else
      st.drag = nil
    end
  end

  local dt = math.min(0.08, math.max(0, (Kit.time or 0) - (st.lastTime or Kit.time or 0)))
  st.lastTime = Kit.time or 0
  if not st.drag then
    local upright = math.floor((st.spin or 0) / TAU + 0.5) * TAU
    st.spin = (st.spin or 0) + (upright - (st.spin or 0)) * math.min(1, dt * 4)
    st.pitch = (st.pitch or 0) * (1 - math.min(1, dt * 4))
  end

  local yaw = -0.42 + (st.spin or 0)
  local pitch = 0.14 + (st.pitch or 0)
  if hot and not st.drag then
    yaw = yaw + clamp((Kit.mouseX - cx) / math.max(1, w / 2), -1, 1) * 0.08
    pitch = pitch + clamp((Kit.mouseY - cy) / math.max(1, h / 2), -1, 1) * 0.05
  end

  local halfW, halfH = w / 2, h / 2
  local depth = math.max(6, w * 0.10)
  local proj = function(px, py, pz)
    return project(cx, cy, yaw, pitch, px, py, pz)
  end

  local shader = getShader()
  local sparkle, holo = finishFlags(skin.finish)
  if love and love.graphics and love.graphics.push then
    love.graphics.push("all")
  end
  if shader then
    love.graphics.setShader(shader)
    sendFinish(shader, sparkle and FINISH_SPARKLE or FINISH_NONE, st.spin)
  end

  local capH = h * 3 / 65
  local mainTop = -halfH + capH
  local capRight = halfW - w * 5 / 57
  local mainFront = quad(proj, -halfW, mainTop, w, h - capH, depth)
  local mainBack = quad(proj, -halfW, mainTop, w, h - capH, -depth)
  local capFront = quad(proj, -halfW, -halfH, capRight + halfW, capH, depth)
  local capBack = quad(proj, -halfW, -halfH, capRight + halfW, capH, -depth)
  local shell = skin.color
  local side = {
    math.floor(shell[1] * 0.54), math.floor(shell[2] * 0.54),
    math.floor(shell[3] * 0.54),
  }

  local frontFacing = facing(mainFront)
  if frontFacing then
    polygon(mainBack, side, 1)
    polygon(capBack, side, 1)
  else
    polygon(mainFront, shell, 1)
    polygon(capFront, shell, 1)
  end
  polygon({ mainFront[2], mainFront[3], mainBack[3], mainBack[2] }, side, 1)
  polygon({ mainFront[3], mainFront[4], mainBack[4], mainBack[3] }, side, 1)
  polygon({ mainFront[1], mainFront[2], mainBack[2], mainBack[1] }, side, 1)
  polygon({ mainFront[4], mainFront[1], mainBack[1], mainBack[4] }, side, 1)
  polygon({ capFront[2], capFront[3], capBack[3], capBack[2] }, side, 1)
  polygon({ capFront[1], capFront[2], capBack[2], capBack[1] }, side, 1)
  polygon({ capFront[4], capFront[1], capBack[1], capBack[4] }, side, 1)
  if frontFacing then
    polygon(mainFront, shell, 1)
    polygon(capFront, shell, 1)
  else
    polygon(mainBack, side, 1)
    polygon(capBack, side, 1)
    local backZ = -(depth + 0.8)
    local sd = math.min(w, h) * 0.11
    pill(proj, -sd * 0.62, -sd * 0.62, sd * 1.24, sd * 1.24, backZ,
      { math.floor(shell[1] * 0.4), math.floor(shell[2] * 0.4),
        math.floor(shell[3] * 0.4) }, 0.9)
    pill(proj, -sd / 2, -sd / 2, sd, sd, backZ - 0.4, { 196, 186, 148 }, 1)
    pill(proj, -sd * 0.32, -sd * 0.32, sd * 0.64, sd * 0.64,
      backZ - 0.6, { 220, 212, 178 }, 0.8)
    local r = sd / 2
    for k = 0, 2 do
      local a = -math.pi / 2 + k * (2 * math.pi / 3)
      local ux, uy = math.cos(a), math.sin(a)
      local vx, vy = -uy, ux
      local r0, r1, w0, w1 = r * 0.16, r * 0.82, r * 0.13, r * 0.3
      polygon({
        { proj(ux * r0 + vx * w0, uy * r0 + vy * w0, backZ - 0.8) },
        { proj(ux * r0 - vx * w0, uy * r0 - vy * w0, backZ - 0.8) },
        { proj(ux * r1 - vx * w1, uy * r1 - vy * w1, backZ - 0.8) },
        { proj(ux * r1 + vx * w1, uy * r1 + vy * w1, backZ - 0.8) },
      }, { 112, 104, 76 }, 1)
    end
  end

  if frontFacing then
    local faceZ = depth + 0.8
    local grooveW = w * 0.115
    local grooveH = math.max(1, h * 0.009)
    local grooveScale = { 1.22, 1.10, 1.00, 1.00, 1.10, 1.22 }
    local grooveInset = w * 0.02
    for i = 0, 5 do
      local ry = mainTop + h * 0.014 + i * h * 0.021
      local gw = grooveW * grooveScale[i + 1]
      polygon(quad(proj, -halfW + grooveInset, ry, gw, grooveH, faceZ), side, 0.7)
      polygon(quad(proj, halfW - gw - grooveInset, ry, gw, grooveH, faceZ), side, 0.7)
    end
    local pillX, pillW = -halfW + w * 0.19, w * 0.62
    local pillY, pillH = mainTop + h * 0.015, h * 0.115
    pill(proj, pillX, pillY, pillW, pillH, faceZ + 0.5, side, 0.55)
    local inX, inY = w * 0.008, h * 0.008
    pill(proj, pillX + inX, pillY + inY, pillW - 2 * inX, pillH - 2 * inY,
      faceZ + 0.8, {
        math.floor(shell[1] * 0.92), math.floor(shell[2] * 0.92),
        math.floor(shell[3] * 0.92),
      }, 1)

    local labelX, labelY = -w * 0.33, -h * 0.20
    local labelW, labelH = w * 0.66, h * 0.55
    polygon(quad(proj, labelX - 2, labelY - 2, labelW + 4, labelH + 4, faceZ + 0.8),
      side, 0.95)
    local labelPoints = quad(proj, labelX, labelY, labelW, labelH, faceZ + 1.2)
    local label = skin.label
    if shader and holo then sendFinish(shader, FINISH_HOLO, st.spin) end
    local mesh = label and labelMesh(st, label, labelPoints)
    if mesh and love.graphics.draw then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(mesh)
    elseif not label then
      polygon(labelPoints, {
        math.floor(shell[1] * 0.78 + 255 * 0.22),
        math.floor(shell[2] * 0.78 + 255 * 0.22),
        math.floor(shell[3] * 0.78 + 255 * 0.22),
      }, 1)
    end
    if shader and holo then
      sendFinish(shader, sparkle and FINISH_SPARKLE or FINISH_NONE, st.spin)
    end
    polygon({
      { proj(-w * 0.07, h * 0.37, faceZ + 1) },
      { proj(w * 0.07, h * 0.37, faceZ + 1) },
      { proj(0, h * 0.43, faceZ + 1) },
    }, side, 0.70)
  end

  if love and love.graphics and love.graphics.pop then
    love.graphics.pop()
  end
  if love and love.graphics and love.graphics.setColor then
    love.graphics.setColor(1, 1, 1, 1)
  end
end

function CartPreview.draw(S, x, y, w, h, info)
  info = info or {}
  local s = Kit.scale
  Kit.caption(x + 10 * s, y + 8 * s, "PREVIEW")
  local st = stateOf(S)
  local path = info.labelPath
  local size = path and fileSize(path) or nil
  if st.labelPath ~= path or st.labelSize ~= size then
    st.labelPath, st.labelSize = path, size
    st.label = path and loadLabel(path) or nil
    st.mesh = nil
  end

  local pad = 10 * s
  local headH = 26 * s
  local footH = 44 * s
  local areaX = x + pad
  local areaY = y + headH
  local areaW = w - pad * 2
  local areaH = h - headH - footH
  if areaW < 8 or areaH < 8 then return end

  local cartW = math.min(areaW, areaH * 0.72)
  local cartH = cartW / 0.72
  if cartH > areaH then
    cartH = areaH
    cartW = cartH * 0.72
  end
  local cartX = areaX + (areaW - cartW) / 2
  local cartY = areaY + (areaH - cartH) / 2
  drawCart(S, cartX, cartY, cartW, cartH, {
    color = CartPreview.parseShell(info.shell) or st.lastColor or { 139, 26, 26 },
    finish = info.finish,
    label = st.label,
  })
  st.lastColor = CartPreview.parseShell(info.shell) or st.lastColor

  local fy = y + h - footH + 4 * s
  local title = tostring(info.title or info.id or "cart")
  Kit.text("small", Kit.ellipsize("small", title, areaW), areaX, fy, PAL.heading)
  local finish = (info.finish and info.finish ~= "") and info.finish or "plain"
  Kit.text("micro",
    Kit.ellipsize("micro", tostring(info.base or "red") .. " · " .. finish, areaW),
    areaX, fy + 16 * s, PAL.muted)
  Kit.text("micro", "drag to spin", areaX, fy + 28 * s, PAL.faint)
end

return CartPreview
