-- Run against a disposable copy of the user's project, never its source folder.
return function(data,root)
 local IO,G=require("ModIO"),require("Gen3")
 local path=root.."/tests/content-editor/gen3-smoke/audit-project"
 if not IO.readText(path.."/manifest.json") then return end
 local project=assert(IO.load(path));local original=assert(IO.readText(path.."/editor_project.lua"))
 local function load()
  local fresh={};G.load(fresh,data._gen3Read)
  local loader,err=require("Gen3Mod").load(fresh,path);assert(loader,err)
  return loader
 end
 local function starters(loader)
  for _,rule in ipairs(project.gen3Starters or {}) do
   if rule.onlyFirst then
    local source=assert(loader.content.pokemon:get(rule.matchSpecies[1]))
    local target=assert(loader.content.pokemon:get(rule.species))
    local ctx={overworld={map={id=rule.map}},save={party={},flags={}}}
    local row=loader.hooks:call("script.command",function(_,_,r) return r end,ctx,"setvar",{var=rule.variable or 0x4002,value=source.index})
    assert(row.value==target.index,"Saved starter selection did not change")
    local gift={ctx=ctx,species=rule.species,level=5};loader.events:emit("pokemon.before_give",gift)
    assert(gift.species==rule.species and gift.level==rule.level,"Saved starter gift mismatch")
   end
  end
 end
 local function forms(loader)
  local P=require("src.core.game3.pokemon")
  P.install(P._cache)
  local E=require("src.core.game3.encounters")
  -- Run the live encounter reader against this project's merged tables.
  E._tables={};E._loaded=false;E.ensureLoaded()
  loader.content.encounters.spec.write(E,loader.content.encounters)
  E.ensureLoaded()
  for id in pairs(project.encounters or {}) do
   local source=loader.content.encounters:get(id)
   for _,kind in ipairs({"land","water","rocks","fishing"}) do
    for i,slot in ipairs(source[kind] and source[kind].slots or {}) do
     local rec=assert(loader.content.pokemon:get(slot.species))
     local actual=E._tables[id][kind].slots[i].species
     assert(actual==rec.index,"Live encounter has wrong species: "..slot.species.." -> "..tostring(actual))
     assert(P.name(actual)~="?????","Wild encounter has unknown name")
    end
   end
  end
  for _,family in pairs(project.gen3Forms or {}) do
   for _,row in ipairs(family.forms) do
    local rec=assert(loader.content.pokemon:get(row.species))
    assert(P.name(rec.index)==rec.name,"Saved form lost its name after game startup: "..row.species)
    assert(P.frontPic(rec.index) and P.backPic(rec.index),"Saved form lost its battle sprites: "..row.species)
   end
  end
 end
 starters(load());require("src.mods.Runtime").reset()
 assert(IO.save(path,project));assert(IO.load(path));local loader=load();starters(loader);forms(loader)
 require("src.mods.Runtime").reset()
 assert(IO.readText(root.."/mods/FireRed-Test/editor_project.lua")==original,"Audit changed the user's project")
end
