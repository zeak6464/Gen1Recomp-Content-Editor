return function(S, game, IO, mount, cryCheck)
  assert(mount(S.path, "mods/new_species_check", 0) ~= 0)
  local fs = {}
  for _,key in ipairs({"read","load","getInfo"}) do fs[key] = love.filesystem[key] end
  fs.write = function() return true end
  fs.getDirectoryItems = function(path)
    if path == "mods" then return {"new_species_check"} end
    return love.filesystem.getDirectoryItems(path)
  end
  local gen2 = require("Generation").isGen2(S)
  -- App already seeded engine-owned registries. A fresh runtime loader
  -- expects the ROM dataset before that seeding step.
  for key in pairs(require("src.mods.Builtins").namespaceRoots(gen2 and 2 or 1)) do
    if key ~= "type_chart" then S.data[key] = nil end
  end
  local loader = require("src.mods.Loader").new({fs=fs,generation=gen2 and 2 or 1,version=game})
  function loader:_loadState()
    self.disabled,self.gen2Forced,self.modOptions = {},{},{}
    self.safeMode = false
  end
  loader:load(S.data)
  local status=loader:status()
  assert(#(status.errors or {}) == 0, table.concat(status.errors or {},"; "))
  assert(S.data.pokemon.NEW_MON, "runtime registration lost species")
  if cryCheck then cryCheck.verify(S,S.data) end
  local save = {version=game,party={},player={name="TEST",id=1},flags={},
    pokedex={seen={},owned={},caught={}},options={}}
  local g = {data=S.data,save=save}
  require("src.render.Font").load(S.data)
  local screen
  if gen2 then
    local mon = require("src.battle.gen2.Mon").new(S.data,"NEW_MON",5)
    local B = require("src.ui.gen2.BattleState")
    local queued = {}
    local b = setmetatable({save=save,game=g,battle={},
      push=function(_,row) queued[#queued+1]=row end,
      name=function() return "NEW_MON" end,
      hasPokedex=function() return true end,pushPayDay=function() end}, {__index=B})
    b:pushCaught(mon,"POKE_BALL")
    assert(save.party[1].species=="NEW_MON" and save.pokedex.caught.NEW_MON)
    local opened=false
    for _,row in ipairs(queued) do if row.kind=="dex-entry" then opened=true end end
    assert(opened,"capture did not queue new-entry screen")
    screen=require("src.ui.gen2.PokedexMenu").new(g,{entrySpecies="NEW_MON",newEntry=true})
    assert(screen.view=="entry","new species missing from dex list")
    assert(S.data.gen2Pokedex.entries.NEW_MON,"new species entry not merged")
  else
    local mon = require("src.pokemon.Pokemon").new(S.data,"NEW_MON",5)
    local B = require("src.battle.BattleState")
    local queued
    local b = setmetatable({game=g,data=S.data,enemy={mon=mon,name="NEW_MON"},
      restoreMimicked=function() end,sayNextWaitSfx=function() end,
      uiNext=function(_,fn) queued=fn end,actNext=function() end,
      offerNickname=function() end,
      buildScreen=function(_,_,species) return require("src.ui.DexEntryMenu").new(g,species) end}, {__index=B})
    b:storeCaughtMon()
    assert(save.party[1].species=="NEW_MON" and save.pokedex.owned.NEW_MON)
    screen=assert(queued,"capture did not queue new-entry screen")()
    if cryCheck then screen.picDelay=1;screen:update(1/60) else screen.picDelay=0 end
  end
  return function() screen:draw() end
end
