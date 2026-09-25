-- Run from the repository root with LuaJIT.
package.path = 'tools/save-editor/?.lua;' .. package.path
local held, touching = false, false
love = {
  mouse = {isDown = function() return held end},
  touch = {getTouches = function() return touching and {1} or {} end},
}
local Kit = require('Kit')
for _, kind in ipairs({'rows', 'pixels'}) do
  local function scroll()
    if kind == 'rows' then return Kit.scroll(0, 0, 200, 100, 0, 100, 10, 1, kind) end
    return Kit.scrollPixels(0, 0, 200, 100, 0, 1000, kind)
  end
  local function reset()
    held, touching = false, false
    Kit.beginFrame(0, 0, false, 0)
    Kit._scrollState = {}
  end
  reset()
  held = true
  Kit.beginFrame(50, 80, true, 0)
  assert(scroll() == 0)
  Kit.beginFrame(50, 20, false, 0)
  assert(scroll() == 0, kind .. ': mouse body drag scrolled')
  assert(Kit.mouseDown, 'painting must still see the held mouse')
  Kit.beginFrame(50, 20, false, -1)
  assert(scroll() > 0, kind .. ': wheel stopped working')
  reset()
  held = true
  Kit.beginFrame(195, 5, true, 0)
  scroll()
  Kit.beginFrame(195, 70, false, 0)
  assert(scroll() > 0, kind .. ': scrollbar drag stopped working')
  reset()
  held, touching = true, true
  Kit.beginFrame(50, 80, true, 0)
  scroll()
  Kit.beginFrame(50, 20, false, 0)
  assert(scroll() > 0, kind .. ': touch swipe stopped working')
  reset()
end
print('PASS: mouse selection, wheel, scrollbar dragging, and touch swipes')
