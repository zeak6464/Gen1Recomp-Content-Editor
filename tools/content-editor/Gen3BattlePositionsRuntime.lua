local M={}
function M.install(mod,positions)
  local Ui=require("src.core.game3.battle.ui")
  local Runtime=require("src.mods.Runtime")
  local P=require("src.core.game3.pokemon")
  local byIndex={}
  for id,value in pairs(positions) do
    local rec=mod.content.pokemon:get(id)
    if rec then byIndex[rec.index]=value end
  end
  if not Ui._editorPositionDispatch then
    Ui._editorPositionDispatch=true
    local original=Ui.bounceOffset
    Ui.bounceOffset=function(...) return Runtime.call("editor.gen3.battle.positions",original,...) end
  end
  mod.hooks:wrap("editor.gen3.battle.positions",function(proceed,kind,id)
    local original=proceed(kind,id)
    if kind~="mon" then return original end
    local battle=package.loaded["src.core.game3.battle"]
    local st=battle and battle._st
    local back=id=="player" or type(id)=="number" and id%2==0
    local b=st and ((id==0 or id=="player") and st.player or (id==1 or id=="enemy") and st.enemy or (st.battlers or {})[id])
    local Anim=package.loaded["src.core.game3.battle.anim"]
    if Anim and Anim.shownBattler then b=Anim.shownBattler(id,b) end
    if not b then return original end
    local species=b.species or (b.mon and P.speciesOf(b.mon))
    local pres=Anim and Anim.present and Anim.present(id)
    if pres and pres.substitute then return original end
    if pres and pres.transformSpecies then species=pres.transformSpecies
    elseif b.expTransform and not (pres and pres.pendingTransform) then species=b.expTransform.species or species end
    local rec=type(species)=="string" and positions[species] or byIndex[species]
    return original+(rec and (back and rec.backY or rec.frontY) or 0)
  end)
end
return M
