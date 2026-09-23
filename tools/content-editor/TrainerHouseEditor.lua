local M={}
function M.defaults()
  return {name="CAL",daily=true,party={{species="MEGANIUM",level=50},{species="TYPHLOSION",level=50},{species="FERALIGATR",level=50}}}
end
function M.validate(row,generation)
  if not row then return end
  assert(generation==2,"Trainer House settings require Gen 2")
  assert(type(row.name)=="string" and row.name:match("%S"),"Enter a Trainer House opponent name")
  assert(type(row.daily)=="boolean","Choose the Trainer House daily battle setting")
  assert(type(row.party)=="table" and #row.party>=1 and #row.party<=6,"Trainer House needs 1 to 6 Pokemon")
  for _,mon in ipairs(row.party) do
    assert(type(mon.species)=="string" and mon.species~="","Choose a Trainer House Pokemon")
    assert(type(mon.level)=="number" and mon.level%1==0 and mon.level>=1 and mon.level<=100,"Trainer House levels must be 1 to 100")
    assert(mon.item==nil or type(mon.item)=="string","Choose a held item")
    if mon.moves then
      assert(type(mon.moves)=="table" and #mon.moves<=4,"Choose at most four moves")
      local used={}
      for _,move in ipairs(mon.moves) do assert(type(move)=="string" and move~="" and not used[move],"Trainer House moves must be unique");used[move]=true end
    end
  end
end
function M.emit(p,encode,out)
  if not p.trainerHouse then return end;M.validate(p.trainerHouse,2)
  out[#out+1]="local trainerHouse=(function()\n"..assert(love.filesystem.read("tools/content-editor/TrainerHouseRuntime.lua")).."\nend)()"
  out[#out+1]="trainerHouse.install(mod,"..encode(p.trainerHouse)..")"
end
function M.draw(S,x,y,w,h,App)
  local K,L,C=require("Kit"),require("RegList"),require("ChoicePicker");local s=K.scale
  local row=S.project.trainerHouse
  K.caption(x,y,"VIRIDIAN TRAINER HOUSE");y=y+40*s;h=h-40*s
  if not row then
    K.caption(x,y,"Create a visiting opponent for the existing Trainer House event.")
    if K.button(x,y+42*s,260*s,30*s,"Customize Trainer House",{kind="good"}) then S.project.trainerHouse=M.defaults();App.markDirty() end
    return
  end
  local Pane=require("FormPane");local first,view=Pane.begin(S,"trainerHouseForm",x,y,w,h);y=first;w=view.contentW
  K.caption(x,y,"Opponent name")
  local name=K.textfield("trainerHouseName",x+200*s,y,w-210*s,30*s,row.name,"")
  if name~=row.name then row.name=name;App.markDirty() end;y=y+44*s
  if K.button(x,y,240*s,30*s,row.daily and "One battle per day" or "Repeat battles allowed",{}) then row.daily=not row.daily;App.markDirty() end;y=y+44*s
  K.caption(x,y,"Empty move lists use the Pokemon's moves at its level.");y=y+36*s
  local moves=L.mergeIds(S.project.moves or {},S.data.moves or {})
  for i,mon in ipairs(row.party) do
    K.caption(x,y,"Pokemon "..i)
    require("SpeciesPicker").field(S,{x=x+130*s,y=y,w=w-430*s,h=30*s,current=mon.species,onPick=function(id) mon.species=id;App.markDirty() end})
    K.caption(x+w-290*s,y,"Level")
    local level=L.num(App,"trainerHouse/"..i.."/level",x+w-210*s,y,90*s,30*s,mon.level)
    if level~=mon.level then mon.level=level;App.markDirty() end
    if #row.party>1 and K.button(x+w-110*s,y,100*s,30*s,"Remove",{}) then table.remove(row.party,i);App.markDirty();break end;y=y+40*s
    K.caption(x,y,"Held item")
    require("ItemPicker").field(S,{x=x+130*s,y=y,w=w-260*s,h=30*s,current=mon.item or "",onPick=function(id) mon.item=id;App.markDirty() end})
    if mon.item and K.button(x+w-120*s,y,110*s,30*s,"No item",{}) then mon.item=nil;App.markDirty() end;y=y+40*s
    for j,move in ipairs(mon.moves or {}) do
      C.field(S,{x=x+130*s,y=y,w=w-260*s,h=30*s,current=move,ids=moves,title="Battle move",onPick=function(id) mon.moves[j]=id;App.markDirty() end})
      if K.button(x+w-120*s,y,110*s,30*s,"Remove move",{}) then table.remove(mon.moves,j);App.markDirty();break end;y=y+38*s
    end
    if #(mon.moves or {})<4 then
      C.field(S,{x=x+130*s,y=y,w=w-140*s,h=30*s,current="",ids=moves,title="Add battle move",emptyLabel="Add a move",onPick=function(id)
        mon.moves=mon.moves or {};for _,m in ipairs(mon.moves) do if m==id then S.status="That move is already included";return end end
        mon.moves[#mon.moves+1]=id;App.markDirty()
      end});y=y+42*s
    end
    y=y+12*s
  end
  if #row.party<6 and K.button(x,y,170*s,30*s,"Add Pokemon",{}) then row.party[#row.party+1]={species="PIKACHU",level=50};App.markDirty() end;y=y+44*s
  K.caption(x,y,"The existing receptionist and battle event use this opponent. No gift transfer is needed.");y=y+35*s
  if K.button(x,y,190*s,30*s,"Revert Trainer House",{}) then S.project.trainerHouse=nil;App.markDirty() end;y=y+45*s
  Pane.finish(S,"trainerHouseForm",first,y,view)
end
return M
