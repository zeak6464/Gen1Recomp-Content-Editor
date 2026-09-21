local M={}
function M.draw(S,x,y,w,h,App)
  local K=require("Kit");local L=require("RegList");local s=K.scale
  if not S.project then return end
  require("Gen3ContentAdapter").prepare(S)
  L.modeChips(S,"g3EffectsMode",{{id="effects",label="Move effects"},{id="abilities",label="Abilities"},{id="custom",label="Create abilities / effects"}},x,y,s)
  y=y+36*s;h=h-36*s
  if S.g3EffectsMode=="abilities" then return require("Gen3Abilities").draw(S,x,y,w,h,App) end
  if S.g3EffectsMode=="custom" then return require("Gen3Behaviors").draw(S,x,y,w,h,App) end
  local native=require("src.core.game3.battle.effects")
  local ids=native.ids()
  local labels={};for _,id in ipairs(ids) do labels[id]=require("Gen3Abilities").name(id) end
  S.g3EffectId=S.g3EffectId or ids[1]
  local fx,fw=L.drawList(S,App,x,y,w,h,"NATIVE MOVE EFFECTS",ids,{selKey="g3EffectId",queryKey="g3EffectQuery",offsetKey="g3EffectOffset",label=function(id) return labels[id] end})
  local id=S.g3EffectId;if not id then return end
  local edits=S.project.gen3Effects or {}
  K.caption(fx,y,labels[id])
  K.caption(fx,y+30*s,"Change what ALL moves using this effect do")
  require("ChoicePicker").field(S,{x=fx,y=y+64*s,w=fw,h=28*s,ids=ids,labels=labels,current=edits[id] or id,title="CHOOSE REPLACEMENT BEHAVIOR",
    onPick=function(target) S.project.gen3Effects=S.project.gen3Effects or {};S.project.gen3Effects[id]=target;App.markDirty() end})
  if K.button(fx,y+104*s,150*s,28*s,"Restore original behavior",{}) then
    if S.project.gen3Effects then S.project.gen3Effects[id]=nil end;App.markDirty()
  end
  K.caption(fx,y+150*s,"Moves using this effect (damage effects are edited on Moves)")
  local map=require("src.core.game3.battle.effect_ids").STATUS_SETUP
  local top,view=require("FormPane").begin(S,"g3EffectMoves",fx,y+180*s,fw,h-180*s)
  local yy=top
  for _,mid in ipairs(L.mergeIds(S.project.moves,S.data.moves)) do
    local move=S.project.moves[mid] or S.data.moves[mid]
    if map[move.effect]==id then
      if K.button(fx,yy,view.contentW,28*s,mid,{}) then S.moveId=mid;S.tab="moves" end
      yy=yy+34*s
    end
  end
  require("FormPane").finish(S,"g3EffectMoves",top,yy,view)
end
function M.emit(p,encode,out)
  if not next(p.gen3Effects or {}) then return end
  local effects=require("src.core.game3.battle.effects")
  for id,target in pairs(p.gen3Effects) do assert(effects.get(id) and effects.get(target),"Unknown native effect handler") end
  out[#out+1]="  local effectHandlers="..encode(p.gen3Effects)
  out[#out+1]=[=[
  local Effects=require("src.core.game3.battle.effects")
  local Runtime=require("src.mods.Runtime")
  if not Effects._editorEffectBridge then
    Effects._editorEffectBridge=true
    for _,method in ipairs({"get","run"}) do
      local base=Effects[method]
      Effects[method]=function(...) return Runtime.call("editor.gen3.effects."..method,base,...) end
    end
  end
  for _,method in ipairs({"get","run"}) do
    mod.hooks:wrap("editor.gen3.effects."..method,function(proceed,id,...)
      return proceed(effectHandlers[id] or id,...)
    end)
  end
]=]
end
return M
