local M={}
function M.install(mod,configs,typeIds)
  local Runtime=require("src.mods.Runtime");local P=require("src.core.game3.pokemon");local Moves=require("src.core.game3.battle.moves")
  local rules={};local contexts={}
  for _,f in ipairs(configs) do for _,row in ipairs(f.forms) do
    local index=assert(mod.content.pokemon:get(row.species)).index;rules[index]={}
    for _,r in ipairs(row.moveChanges or {}) do
      local source=assert(mod.content.moves:get(r.move)).index
      rules[index][source]={replacement=r.replacement and assert(mod.content.moves:get(r.replacement)).index,type=r.type and assert(typeIds[r.type])}
      if r.replacement and r.type then rules[index][assert(mod.content.moves:get(r.replacement)).index]={type=assert(typeIds[r.type])} end
    end
  end end
  local function bridge(object,name,fn)
    local key="editor.gen3.formmoves."..name
    if not object[key] then object[key]=true;local original=object[name];object[name]=function(...) return Runtime.call(key,original,...) end end
    mod.hooks:wrap(key,fn)
  end
  local function apply(mon,species)
    if not mon or mon.isEgg or mon.egg then return end
    local stored=mon._editorFormMoves
    if stored and stored.species==species then return end
    if stored then
      for slot,swap in pairs(stored.slots) do if mon.moves and mon.moves[slot]==swap.to then mon.moves[slot]=swap.from end end
      mon._editorFormMoves=nil
    end
    local selected=rules[species];if not selected then return end
    local slots={}
    for slot,id in ipairs(mon.moves or {}) do local r=selected[tonumber(id)]
      if r and r.replacement then slots[slot]={from=id,to=r.replacement};mon.moves[slot]=r.replacement end
    end
    if next(slots) then mon._editorFormMoves={species=species,slots=slots} end
  end
  mod.hooks:wrap("editor.gen3.formmoves.battler",function(_,b) if b then apply(b.mon,b.species) end end)
  bridge(P,"applyStats",function(proceed,mon,...)
    local result=proceed(mon,...);apply(mon,mon and mon.species);return result
  end)
  local Engine=require("src.core.game3.battle.engine")
  bridge(Engine,"resolveMove",function(proceed,user,target,id,slot,ad,st,out,opts)
    local State=require("src.core.game3.battle.state");user=State.occupant(st,user)
    local num=tonumber(id) or Moves.numForName(id);local r=rules[user and user.species] and rules[user.species][num]
    contexts[#contexts+1]={num=num,type=r and r.type}
    local ok,result=pcall(proceed,user,target,id,slot,ad,st,out,opts);contexts[#contexts]=nil
    if not ok then error(result,0) end;return result
  end)
  bridge(Moves,"get",function(proceed,id)
    local result=proceed(id);local c=contexts[#contexts]
    if c and c.type and result.numId==c.num then local out={};for k,v in pairs(result) do out[k]=v end;out.type=c.type;return out end
    return result
  end)
end
return M
