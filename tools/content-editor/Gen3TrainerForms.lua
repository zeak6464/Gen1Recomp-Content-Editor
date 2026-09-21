local M={}
local Kit=require("Kit")
local List=require("RegList")
local PAL=require("Theme").PAL
function M.moves(S,mon)
  if mon.moves then return mon.moves end
  local rec=S.project.pokemon[mon.species] or S.data.pokemon[mon.species] or {}
  local result={}
  for _,entry in ipairs(rec.learnset or rec.levelMoves or {}) do
    local level=entry.level or entry[1] or 0
    local move=entry.move or entry[2]
    if level<=(mon.level or 1) and move and move~="0" then
      if #result==4 then table.remove(result,1) end
      result[#result+1]=move
    end
  end
  return result
end
function M.draw(S,tr,mutate,App,x,y,w,section)
  local s=Kit.scale;local rh=28*s
  local function number(key,label,lo,hi)
    Kit.caption(x,y,label)
    local old=tonumber(tr[key]) or lo
    local n=math.floor(math.max(lo,math.min(hi,List.num(App,"g3_tr_"..key,x+150*s,y,w-150*s,rh,old))))
    if n~=old then tr=mutate();tr[key]=n;App.markDirty() end
    y=y+36*s
  end
  local function choice(key,label,labels,after)
    local current=tostring(tr[key] or 0)
    if not labels[current] then labels[current]="Keep current ("..current..")" end
    local ids={};for id in pairs(labels) do ids[#ids+1]=id end
    table.sort(ids,require("Gen3Labels").natural)
    Kit.caption(x,y,label)
    require("ChoicePicker").field(S,{x=x+150*s,y=y,w=w-150*s,h=rh,current=current,ids=ids,labels=labels,title=label,
      onPick=function(id) tr=mutate();tr[key]=tonumber(id);if after then after(tr,id) end;App.markDirty() end})
    y=y+36*s
  end
  if section=="basics" then
    local Preview=require("Preview")
    Preview.draw(S,Preview.trainerPicPath(S,tr),x,y,128*s,128*s,false)
    Kit.caption(x+144*s,y,"Trainer battle sprite")
    local ids,labels={},{}
    for path in pairs(require("Gen3Resources").assets(S.data)) do
      local id=path:match("/trainers/front/(%d+)%.rgba$")
      if id then ids[#ids+1]=id;labels[id]="Trainer sprite "..id end
    end
    table.sort(ids,function(a,b) return tonumber(a)<tonumber(b) end)
    require("ChoicePicker").field(S,{x=x+144*s,y=y+30*s,w=math.max(100*s,w-144*s),h=rh,
      ids=ids,labels=labels,current=tostring(tr.pic or 0),title="CHOOSE TRAINER SPRITE",
      onPick=function(id) tr=mutate();tr.pic=tonumber(id);App.markDirty() end})
    y=y+144*s
    Kit.caption(x,y,"Name")
    local name=Kit.textfield("g3_tr_name",x+150*s,y,w-150*s,rh,tr.name or "","")
    if name~=tr.name then tr=mutate();tr.name=name;App.markDirty() end
    y=y+36*s
    local classes={}
    local pack=require("Gen3Resources").readTable(S.data,"data/generated/gba/trainers.lua")
    for id,name in pairs(pack.classNames or {}) do classes[tostring(id)]=name:gsub("_"," ") end
    choice("class","Trainer class",classes,function(rec,id) rec.className=pack.classNames[tonumber(id)] or rec.className end)
    choice("gender","Gender",{["0"]="Male",["1"]="Female"})
    Kit.caption(x,y,"Encounter music")
    local musicLabels={original="Original game setting"}
    for id,label in pairs(require("Gen3TrainerMusic").labels) do musicLabels[id]=label end
    require("ChoicePicker").field(S,{x=x+150*s,y=y,w=w-150*s,h=rh,
      current=tostring((S.project.gen3TrainerMusic or {})[tr.id] or "original"),ids={"original","283","284","285"},labels=musicLabels,
      onPick=function(id) S.project.gen3TrainerMusic=S.project.gen3TrainerMusic or {};S.project.gen3TrainerMusic[tr.id]=tonumber(id);App.markDirty() end})
    y=y+36*s
    Kit.caption(x,y,"Battle decisions: choose behaviors on the AI tab.");y=y+36*s
    if Kit.chip(x,y,180*s,rh,"Double battle",tr.doubleBattle,PAL.blue) then
      tr=mutate();tr.doubleBattle=not tr.doubleBattle;App.markDirty()
    end
    y=y+40*s
    for i=1,4 do
      local old=(tr.items or {})[i] or 0
      local current="0"
      for id,item in pairs(S.data.items or {}) do if item.index==old then current=id;break end end
      Kit.caption(x,y,"Battle item "..i)
      require("ItemPicker").field(S,{x=x+150*s,y=y,w=w-150*s,h=rh,current=current,allowClear=true,
        onPick=function(id)
          local item=(S.project.items or {})[id] or (S.data.items or {})[id]
          tr=mutate();tr.items=tr.items or {0,0,0,0};tr.items[i]=item and item.index or 0;App.markDirty()
        end})
      y=y+36*s
    end
  elseif section=="ai" then
    Kit.caption(x,y,"Choose how this trainer selects moves.");y=y+32*s
    local pack=require("Gen3Resources").readTable(S.data,"data/generated/gba/battle_ai/pack.lua")
    for i=0,31 do
      local bit=2^i;local enabled=math.floor((tr.aiFlags or 0)/bit)%2==1
      local friendly={ [0]="Avoid ineffective moves",[1]="Use more tactical decisions",[2]="Try to knock out the opponent",
        [3]="Prefer setting up on the first turn",[4]="Take more risks",[5]="Prefer the strongest move",[6]="Use Baton Pass",
        [7]="Consider a double-battle partner",[8]="Consider remaining HP",[9]="Unknown native behavior",[29]="Roaming Pokemon behavior",[30]="Safari behavior",[31]="First rival battle behavior" }
      local raw=(pack.table or {})[i+1]
      local label=friendly[i] or (raw and raw:gsub("_"," ")) or ("Unused behavior "..i)
      if i<=8 or enabled then
        if Kit.chip(x,y,math.min(w,460*s),28*s,label,enabled,PAL.blue) then
          tr=mutate();tr.aiFlags=(tr.aiFlags or 0)+(enabled and -bit or bit);App.markDirty()
        end
        y=y+34*s
      end
    end
    if Kit.chip(x,y,240*s,28*s,"Advanced AI settings",S.g3TrainerAdvancedAi,PAL.blue) then S.g3TrainerAdvancedAi=not S.g3TrainerAdvancedAi end
    y=y+36*s
    if S.g3TrainerAdvancedAi then number("aiFlags","Native behavior flags",0,4294967295) end
  elseif section=="parties" then
    Kit.caption(x,y,"Battle party (up to six Pokemon)");y=y+28*s
    for i,mon in ipairs(tr.party or {}) do
      Kit.caption(x,y,"Pokemon "..i)
      if Kit.button(x+w-80*s,y,80*s,rh,"Remove",{}) then
        tr=mutate();table.remove(tr.party,i);App.markDirty();break
      end
      y=y+34*s
      require("SpeciesPicker").field(S,{x=x,y=y,w=w*.6,h=rh,current=mon.species,
        onPick=function(id) tr=mutate();tr.party[i].species=id;App.markDirty() end})
      local lv=List.num(App,"g3_tr_level_"..i,x+w*.65,y,w*.35,rh,mon.level or 1)
      lv=math.max(1,math.min(100,math.floor(lv)))
      if lv~=mon.level then tr=mutate();tr.party[i].level=lv;App.markDirty() end
      y=y+36*s
      Kit.caption(x,y,"Held item");y=y+22*s
      require("ItemPicker").field(S,{x=x,y=y,w=w,h=rh,current=mon.heldItem,emptyLabel="None",allowClear=true,
        onPick=function(id) tr=mutate();tr.party[i].heldItem=(id and id~="") and id or nil;App.markDirty() end})
      y=y+36*s
      local moves=List.mergeIds(S.project.moves,S.data.moves)
      local effective=M.moves(S,mon)
      Kit.caption(x,y,mon.moves and "Custom moves" or "Level-up moves (automatic)");y=y+22*s
      for slot=1,4 do
        require("ChoicePicker").field(S,{x=x,y=y,w=w,h=rh,current=effective[slot],emptyLabel="Empty move slot",ids=moves,
          title="Move "..slot,allowClear=true,onPick=function(id)
            tr=mutate();local m=tr.party[i];m.moves=m.moves or {effective[1] or "0",effective[2] or "0",effective[3] or "0",effective[4] or "0"}
            m.moves[slot]=(id and id~="") and id or "0";App.markDirty()
          end})
        y=y+34*s
      end
      if Kit.button(x,y,180*s,rh,"Use level-up moves",{}) then
        tr=mutate();tr.party[i].moves=nil;App.markDirty()
      end
      y=y+48*s
    end
    if #(tr.party or {})<6 and Kit.button(x,y,180*s,rh,"Add Pokemon",{kind="good"}) then
      tr=mutate();tr.party=tr.party or {};tr.party[#tr.party+1]={species="PIDGEY",level=5};App.markDirty()
    end
    y=y+40*s
  end
  return y
end
return M
