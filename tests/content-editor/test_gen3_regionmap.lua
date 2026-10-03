-- Town Map and Fly in imported regions (Gen3RegionMapRuntime): which "visited"
-- flags a map's script sets. Plain LuaJIT. From the repository root:
--   luajit tests/content-editor/test_gen3_regionmap.lua
package.path = "tools/content-editor/?.lua;" .. package.path
local T = require("Gen3RegionMapRuntime")
local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name) else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local any = function() return true end

run("scanFlags: Emerald setflag and FireRed setworldmapflag", function()
  local scripts = { a = { { op = "setflag", 2153 }, { op = "end" } }, b = { { op = "setworldmapflag", 2192 }, { op = "end" } } }
  assert(T.scanFlags(scripts, "a", any)[1] == 2153 and T.scanFlags(scripts, "b", any)[1] == 2192)
end)

run("scanFlags: only the flags the caller accepts", function()
  local scripts = { a = { { op = "setflag", 5 }, { op = "setflag", 2153 }, { op = "setflag", 9000 } } }
  local got = T.scanFlags(scripts, "a", function(_, id) return id >= 2152 and id < 2168 end)
  assert(#got == 1 and got[1] == 2153)
end)

run("scanFlags: follows calls, ignores loops, missing scripts and bad keys", function()
  local scripts = { a = { { op = "call", target = "b" } }, b = { { op = "goto", target = "a" }, { op = "call", target = "c" } },
    c = { { op = "setflag", 2160 } } }
  local got = T.scanFlags(scripts, "a", any)
  assert(#got == 1 and got[1] == 2160)
  assert(#T.scanFlags(scripts, "nope", any) == 0 and #T.scanFlags(scripts, nil, any) == 0 and #T.scanFlags(nil, "a", any) == 0)
  assert(#T.scanFlags({ x = { { op = "goto", target = "x" } } }, "x", any) == 0)
end)

run("scanFlags: other ops are left alone", function()
  local scripts = { a = { { op = "setvar", 1, 2 }, { op = "clearflag", 2153 }, { op = "end" } } }
  assert(#T.scanFlags(scripts, "a", any) == 0)
end)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
