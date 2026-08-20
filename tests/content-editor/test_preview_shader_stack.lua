package.path = "tools/content-editor/?.lua;" .. package.path

local active
love = {
  graphics = {
    getShader = function() return active end,
    setShader = function(shader) active = shader end,
  },
}

package.preload.Theme = function()
  return { PAL = {} }
end
package.preload.WorldPaletteOverrides = function()
  return {}
end

local paletteShader = { id = "palette" }
package.preload["src.render.PaletteFX"] = function()
  return {
    shader = function() return paletteShader end,
    sendColors = function() end,
    usesGbcPack = function() return false end,
  }
end

local Preview = require("Preview")
local Generation = require("Generation")
local colors = {
  { 255, 255, 255 }, { 170, 170, 170 },
  { 85, 85, 85 }, { 0, 0, 0 },
}

local mapShader = { id = "map" }
active = mapShader
local spriteScope = Preview.pushPaletteShader({}, colors)
assert(active == paletteShader, "sprite palette must become active")
Preview.popPaletteShader(spriteScope)
assert(active == mapShader, "sprite palette must restore enclosing map shader")

active = mapShader
local rawScope = Preview.pushUnshaded()
assert(active == nil, "true-color sprite must suspend enclosing palette")
Preview.popPaletteShader(rawScope)
assert(active == mapShader, "true-color sprite must restore enclosing map shader")

active = nil
assert(Preview.pushUnshaded() == false, "unshaded draw without an outer shader is a no-op")

-- Gold uses a map object's non-zero PAL_NPC_* byte before the sprite's
-- PAL_OW_* default. The editor preview must resolve the same precedence.
assert(Preview.gen2ObjectPaletteRef({ paletteId = 3 }, nil) == 3,
  "sprite paletteId must be the default")
assert(Preview.gen2ObjectPaletteRef({ paletteId = 3 }, { palette = 0 }) == 3,
  "zero object palette must retain the sprite default")
assert(Preview.gen2ObjectPaletteRef({ paletteId = 3 }, { palette = 9 }) == 1,
  "PAL_NPC_BLUE must override the sprite with OBJ slot 1")
assert(Preview.gen2ObjectPaletteRef({ palette = "PAL_OW_PINK" }, {})
    == "PAL_OW_PINK", "named sprite palette must remain supported")

assert(not Generation.isGen2({ version = "red" }))
assert(not Generation.isGen2({ version = "blue" }))
assert(not Generation.isGen2({ version = "yellow" }))
assert(Generation.isGen2({ version = "gold" }),
  "Gold controls must follow the Project tab target game")

print("ok preview shader stack")
