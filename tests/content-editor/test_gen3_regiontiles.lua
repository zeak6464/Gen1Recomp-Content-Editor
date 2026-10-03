-- Hoenn tile behaviours (Gen3RegionTilesRuntime): which step callback an
-- Emerald map's onResume script sets. Plain LuaJIT. From the repository root:
--   luajit tests/content-editor/test_gen3_regiontiles.lua
package.path = "tools/content-editor/?.lua;" .. package.path
local T = require("Gen3RegionTilesRuntime")
local E, F = T.NAMES.emerald, T.NAMES.firered
local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name) else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

run("scan: the callbacks that belong to maps", function()
  local scripts = {
    ash = { { op = "setstepcallback", 1 }, { op = "end" } },
    fortree = { { op = "setstepcallback", 2 }, { op = "end" } },
    log = { { op = "setstepcallback", 3 }, { op = "end" } },
    crack = { { op = "setstepcallback", 7 }, { op = "end" } },
  }
  assert(T.scan(scripts, "ash", E) == "ash" and T.scan(scripts, "fortree", E) == "fortreeBridge")
  assert(T.scan(scripts, "log", E) == "pacifidlogBridge" and T.scan(scripts, "crack", E) == "crackedFloor")
end)

run("scan: story callbacks stay out (truck, secret base, Sootopolis gym)", function()
  local scripts = { truck = { { op = "setstepcallback", 5 } }, base = { { op = "setstepcallback", 6 } }, ice = { { op = "setstepcallback", 4 } } }
  assert(T.scan(scripts, "truck", E) == nil and T.scan(scripts, "base", E) == nil and T.scan(scripts, "ice", E) == nil)
end)

run("scan: follows calls, ignores loops, missing scripts and bad keys", function()
  local scripts = { a = { { op = "call", target = "b" } }, b = { { op = "goto", target = "a" }, { op = "call", target = "c" } },
    c = { { op = "setstepcallback", 2 } } }
  assert(T.scan(scripts, "a", E) == "fortreeBridge")
  assert(T.scan(scripts, "nope", E) == nil and T.scan(scripts, nil, E) == nil and T.scan(nil, "a", E) == nil)
  assert(T.scan({ x = { { op = "goto", target = "x" } } }, "x", E) == nil)
end)

run("scan: FireRed's Icefall Cave ice, and only FireRed's", function()
  local scripts = { ice = { { op = "setstepcallback", 4 } }, ash = { { op = "setstepcallback", 1 } } }
  assert(T.scan(scripts, "ice", F) == "ice" and T.scan(scripts, "ash", F) == nil)
end)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
