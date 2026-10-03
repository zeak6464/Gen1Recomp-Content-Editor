-- Newer engines read tileset images through a texture stream built from the cache
-- given to tileset_native.install. The runtimes that redirect tileset folders
-- (FireRed Maps, Emerald Maps, tileset copies) must put their cache proxy in
-- before that, and rebuild a stream that was already built (the save editor
-- installs the cache before it loads mods). Plain LuaJIT. From the repository root:
--   luajit tests/content-editor/test_gen3_streamcache.lua
local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name) else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function read(p) return assert(io.open(p)):read("*a") end

local checks = {
  { "Gen3FrLinkRuntime.lua", "frlink" },
  { "Gen3EmLinkRuntime.lua", "emlink" },
}
for _, c in ipairs(checks) do
  local src = read("tools/content-editor/" .. c[1])
  run(c[1] .. ": proxy goes in before install builds the stream", function()
    assert(src:find('wrap%("editor%.gen3%.' .. c[2] .. '%.tiles",function%(proceed,cache,%.%.%.%)\n%s*local a,b=proceed%(proxy%(cache%),%.%.%.%)'),
      "the install hook must hand the proxy to install")
  end)
  run(c[1] .. ": a stream built before the mod loaded is rebuilt", function()
    assert(src:find("if T%._cache and T%._stream and T%.invalidate then pcall%(T%.invalidate%) end"))
  end)
end
run("Gen3BlocksRuntime.lua: tileset copies rebuild an existing stream", function()
  local src = read("tools/content-editor/Gen3BlocksRuntime.lua")
  assert(src:find("if T%._cache and T%._stream and T%.invalidate then pcall%(T%.invalidate%) end"))
  assert(src:find('wrap%("editor%.gen3%.copies%.install",function%(proceed,cache,%.%.%.%)\n%s*return proceed%(proxy%(cache%)'))
end)

print(("%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
