local runtime=assert(os.getenv("POKEPORT_RECOMP"))
local cache=assert(os.getenv("POKEPORT_GEN3_CACHE"))
package.path="tools/content-editor/?.lua;tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local G,IO,Writer=require("Gen3"),require("ModIO"),require("ModWriter")
local Adapter=require("Gen3ContentAdapter")
local copy=require("src.mods.Merge").deepCopy
require("src.core.GameVersion").set("firered")
love=love or {filesystem={read=function(path) return IO.readText(path) end}}
local function fresh()
  local data={}
  G.load(data,function(path) return IO.readText(cache.."/"..path) end)
  return data
end
local data=fresh()
local mon=copy(G.catalog(data,"pokemon").BULBASAUR)
mon.id,mon.name,mon.index,mon.dex="CUSTOM_MON","CUSTOM MON",800,600
local move=copy(G.catalog(data,"moves").TACKLE)
move.id,move.name,move.index,move.power="CUSTOM_MOVE","CUSTOM MOVE",1000,77
mon.learnset={{level=1,move="CUSTOM_MOVE"}}
local dir=(os.getenv("TEMP") or "/tmp").."/editor_mod_content_"..os.time()
assert(IO.ensureDirectory(dir))
local original="return function(mod)\nmod.content.moves:register('CUSTOM_MOVE',"..Writer.encodeLua(move)..")\n"
  .."mod.content.pokemon:register('CUSTOM_MON',"..Writer.encodeLua(mon)..")\n"
  .."pcall(function() mod.content.moves:register('BROKEN_MOVE',{power='invalid'}) end)\nend"
assert(IO.writeText(dir.."/manifest.json",'{"id":"custom_content","name":"Custom content","version":"1.0.0","api":2,"profile":"content","games":["firered"],"entry":"main.lua","permissions":["engine_internals"]}'))
assert(IO.writeText(dir.."/main.lua",original))
local ok,err=pcall(function()
  local loader=assert(require("Gen3Mod").load(data,dir,{baseOnly=true}))
  local report=data._editorGen3Report
  assert(report.loaded and report.counts.pokemon.added==1 and report.counts.moves.added==1)
  assert(#report.rejected==1 and report.rejected[1].id=="BROKEN_MOVE")
  local p=assert(IO.load(dir))
  assert(p._protectMain and p.game=="firered")
  local S={data=data,project=p,version="firered"}
  Adapter.prepare(S)
  assert(data.pokemon.CUSTOM_MON.learnset[1].move=="CUSTOM_MOVE")
  assert(data.moves.CUSTOM_MOVE.power==77)
  local newMon=Adapter.newRecord(S,"pokemon","NEXT_MON")
  assert(newMon.index==801 and newMon.dex==601,"Native slot and National Dex allocations must be independent")
  p.pokemon.CUSTOM_MON=copy(data.pokemon.CUSTOM_MON)
  p.pokemon.CUSTOM_MON.baseStats.hp=123
  p.moves.CUSTOM_MOVE=copy(data.moves.CUSTOM_MOVE)
  p.moves.CUSTOM_MOVE.power=99
  p.gen3BattlePositions={CUSTOM_MON={frontY=-5,backY=8}}
  p.gen3Behaviors={DEPARTURE={kind="ability",index=78,name="Departure",trigger="switchOut",target="self",chance=100,condition="status",actions={{kind="cure"}}}}
  assert(IO.save(dir,p))
  assert(IO.readText(dir.."/main.lua")==original,"Original custom code was overwritten")
  assert(loadfile(dir.."/editor_apply.lua"))
  p=assert(IO.load(dir))
  assert(p.gen3BattlePositions.CUSTOM_MON.frontY==-5 and p.gen3BattlePositions.CUSTOM_MON.backY==8)
  assert(p.gen3Behaviors.DEPARTURE.trigger=="switchOut" and p.gen3Behaviors.DEPARTURE.condition=="status")
  assert(p.pokemon.CUSTOM_MON.baseStats.hp==123 and p.moves.CUSTOM_MOVE.power==99)
  data=fresh()
  assert(require("Gen3Mod").load(data,dir))
  assert(G.catalog(data,"pokemon").CUSTOM_MON.baseStats.hp==123)
  assert(G.catalog(data,"moves").CUSTOM_MOVE.power==99)
  data=fresh()
  assert(require("Gen3Mod").load(data,dir,{baseOnly=true}))
  assert(G.catalog(data,"moves").CUSTOM_MOVE.power==77,"Base import reapplied the saved editor overlay")
end)
for _,file in ipairs({"main.lua","manifest.json","editor_project.lua","editor_entry.lua","editor_apply.lua"}) do os.remove(dir.."/"..file) end
assert(ok,err)
print("PASS: custom Pokemon/moves load, selectors, independent IDs, rejected-record diagnostics and protected save/reload")

local external=os.getenv("POKEPORT_CONTENT_MOD")
if external then
  data=fresh()
  assert(require("Gen3Mod").load(data,external,{baseOnly=true}))
  local report=data._editorGen3Report
  local state={data=data,project=assert(IO.load(external)),version="firered"}
  Adapter.prepare(state)
  assert(report.loaded and report.counts.pokemon.added>0)
  assert(data.pokemon.PECHARUNT,"Expansion species missing from the editor")
  assert(#report.rejected>0,"Caught registration errors must remain visible")
  print(string.format("AUDIT: %d Pokemon (%d added), %d moves (%d added), %d rejected registrations, %d runtime messages",
    report.counts.pokemon.total,report.counts.pokemon.added,report.counts.moves.total,report.counts.moves.added,
    #report.rejected,#report.messages))
end

