-- Bind visible actions to the commands which actually prepare their inputs.
-- State belongs to one control-flow path; conditional branches get a copy.
local M={}
local copy=require("src.mods.Merge").deepCopy
local battles={[0x138]=true,[0x137]=true,[0x139]=true,[0x143]=true,[0x156]=true}
local opponent={{0x8004,"Pokémon","species",1,65535},{0x8005,"Level",nil,1,100},{0x8006,"Held item","item",0,65535}}
M.specials={
  -- pret/pokefirered src/cable_club.c: EnterColosseumPlayerSpot and its tasks.
  [32]={{0x8004,"Battle format","linkBattleFormat",1,5},{0x8005,"Player's battle spot","linkBattleSpot",0,3}},
  [0x1BB]=opponent,
  [0xF003]={{0x8000,"Pokémon","species",1,65535}},
  [0x7C]={{0x8004,"Pokémon on the team","teamSlot",0,5}},
  [0x7D]={{0x8004,"Pokémon on the team","teamSlot",0,5}},
  [0x9E]={{0x8004,"Pokémon on the team","teamSlot",0,5}},
  [0x147]={{0x8004,"Pokémon on the team","teamSlot",0,5}},
  [0x148]={{0x8004,"Pokémon on the team","teamSlot",0,5}},
  [0x150]={{0x8004,"Pokémon on the team","teamSlot",0,5}},
  [0x17C]={{0x8004,"Species to look for","species",1,65535}},
  [0xC5]={{0x8005,"Price to check",nil,0,65535}},
  [0xC6]={{0x8005,"Price to charge",nil,0,65535}},
  [0x163]={{0x8004,"Pokémon to mark as seen","species",1,65535}},
  [0x1B4]={{0x8004,"Species to look for","species",1,65535}},
  [0x7B]={{0x8004,"Pokémon on the team","teamSlot",0,5}},
  [0xBA]={{0x8004,"Pokémon on the team","teamSlot",0,5}},
  [0x85]={{0x8004,"Do not count this team Pokémon","teamSlot",0,5}},
  [0x96]={{0x8004,"Saved switch for this hidden item",nil,32,4095}},
  [0xD4]={{0x8004,"Pokédex to count","pokedex",0,1}},
  [0xBB]={{0x8004,"Pokémon to leave at the Day Care","teamSlot",0,5}},
  [0x176]={{0x8004,"Pokémon to leave at the Day Care","teamSlot",0,5}},
  [0xC0]={{0x8004,"Pokémon to return","daycareSlot",0,1}},
  [0xBF]={{0x8004,"Day Care Pokémon to check","daycareSlot",0,1}},
  [0xBE]={{0x8004,"Day Care Pokémon to check","daycareSlot",0,1}},
  [0xFF]={{0x8005,"Pokémon offered by the player","teamSlot",0,5}},
  [0x197]={{0x8004,"Pokémon to massage","teamSlot",0,5}},
  [0x13A]={{0x800F,"Character to move","character",1,65535}},
  [0x17D]={{0x8004,"Help topic number",nil,0,65535}},
  [0x5F]={{0x8004,"Phrase editor type",nil,0,65535}},
  [0x1B2]={{0x8004,"Cursor column",nil,0,65535},{0x8005,"Cursor row",nil,0,65535},{0x8006,"Hide the cursor","yesno",0,1}},
  [0x132]={{0x8005,"Floor to display","elevatorFloor",0,15}},
  [0x111]={{0x8005,"Starting floor","elevatorFloor",0,15},{0x8006,"Destination floor","elevatorFloor",0,15}},
  [0x158]={{0x8004,"Choice-list number",nil,0,65535}},
}
function M.new() return {vars={}} end
function M.clone(state) return copy(state) end
local function variableInputs(state,definitions,script,index)
  local fields={}
  for _,d in ipairs(definitions) do
    local known=state.vars[d[1]]
    fields[#fields+1]={label=d[2],choices=d[3],min=d[4],max=d[5],value=known and known.value,
      binding=known and copy(known.binding) or {script=script,index=index,insertVar=d[1]}}
  end
  return fields
end
local function unpreparedBattle(script,index)
  local fields={newBattle={script=script,index=index}}
  for _,d in ipairs(opponent) do fields[#fields+1]={label=d[2],choices=d[3],min=d[4],max=d[5]} end
  return fields
end
function M.observe(state,row,script,index)
  local op=row.op;local result
  if op=="setvar" or op=="setorcopyvar" or op=="copyvar" then
    local var=row.var or row[1];local raw=row.value or row[2];local value=raw
    if op=="copyvar" or (op=="setorcopyvar" and type(raw)=="number" and raw>=0x4000) then
      value=state.vars[raw] and state.vars[raw].value
    end
    if var then state.vars[var]={value=value,binding={script=script,index=index,var=var}} end
  elseif op=="addvar" or op=="subvar" then
    state.vars[row.var or row[1]]=nil
  elseif op=="setwildbattle" then
    local fields={}
    for i,d in ipairs(opponent) do
      local alias=({"species","level","item"})[i]
      fields[i]={label=d[2],choices=d[3],min=d[4],max=d[5],value=row[i] or row[alias] or (i==3 and 0 or nil),
        binding={script=script,index=index,position=i,alias=alias}}
    end
    state.pending=fields;result=copy(fields)
  elseif op=="special" or op=="specialvar" then
    local id=op=="special" and (row.id or row[1]) or row[2]
    if M.specials[id] then
      result=variableInputs(state,M.specials[id],script,index)
      result.help=require("Gen3ActionLanguage").specialHelp[id]
    end
    if id==0x1BB then state.pending=copy(result)
    elseif battles[id] then result=copy(state.pending) or unpreparedBattle(script,index);state.pending=nil end
    if result and not result.newBattle and op=="specialvar" then
      result[#result+1]={label="Store the answer in saved number",min=0x4000,max=65535,value=row[1],
        binding={script=script,index=index,position=1,expectedOp="specialvar"}}
    end
    -- Built-in actions may change temporary values. Never claim stale values
    -- are known; a prepared opponent is independent of those later changes.
    state.vars={}
  elseif op=="dowildbattle" then result=copy(state.pending) or unpreparedBattle(script,index);state.pending=nil
  elseif op=="callnative" or op=="gotonative" or op=="callstd" or op=="gotostd" then
    state.vars={};state.pending=nil
  end
  return result
end
function M.prepareBattle(S,catalog,target,values)
  if not values.species or values.species%1~=0 or values.species<1 or values.species>65535
    or not values.level or values.level%1~=0 or values.level<1 or values.level>100
    or not values.item or values.item%1~=0 or values.item<0 or values.item>65535 then return false end
  local source=((S.project.gen3 or {}).map_scripts or {})[target.script] or catalog[target.script]
  local step=source and source[target.index]
  if not step or not (step.op=="dowildbattle" or (step.op=="special" and battles[step.id or step[1]])
    or (step.op=="specialvar" and battles[step[2]])) then return false end
  local rows=copy(source)
  table.insert(rows,target.index,{op="setwildbattle",species=values.species,level=values.level,item=values.item})
  S.project.gen3=S.project.gen3 or {};S.project.gen3.map_scripts=S.project.gen3.map_scripts or {}
  S.project.gen3.map_scripts[target.script]=rows;S._g3ScriptSource=nil
  return true
end
function M.edit(S,catalog,field,value)
  if type(value)~="number" or value%1~=0 or value<(field.min or 0) or value>(field.max or 65535) then return false end
  local b=field.binding
  local source=((S.project.gen3 or {}).map_scripts or {})[b.script] or catalog[b.script]
  if not source or not source[b.index] then return false end
  local rows=copy(source);local step=rows[b.index]
  if b.insertVar then
    table.insert(rows,b.index,{op="setvar",var=b.insertVar,value=value})
  elseif b.var then
    if (step.var or step[1])~=b.var then return false end
    if step.op~="setvar" and step.op~="copyvar" and step.op~="setorcopyvar" then return false end
    -- A chosen constant replaces a copied/dynamic value for this input only.
    step.op="setvar";if step.opcode then step.opcode=0x16 end
    if step.var~=nil or step[1]==nil then step.var=b.var end
    if step.value~=nil or step[2]==nil then step.value=value end
    if step[2]~=nil then step[2]=value end
  else
    if step.op~=(b.expectedOp or "setwildbattle") then return false end
    if step[b.position]~=nil then step[b.position]=value end
    if b.alias and (step[b.alias]~=nil or step[b.position]==nil) then step[b.alias]=value end
  end
  S.project.gen3=S.project.gen3 or {};S.project.gen3.map_scripts=S.project.gen3.map_scripts or {}
  S.project.gen3.map_scripts[b.script]=rows;S._g3ScriptSource=nil
  return true
end
function M.draw(S,key,fields,catalog,x,y,w,changed)
  local K=require("Kit");local s=K.scale;local color=require("Theme").PAL.text
  local draft
  if fields.newBattle then
    S._g3BattleInputs=S._g3BattleInputs or {}
    draft=S._g3BattleInputs[key] or {level=5,item=0};S._g3BattleInputs[key]=draft
    fields=copy(fields)
    for i,name in ipairs({"species","level","item"}) do fields[i].value=draft[name] end
  end
  local help=draft and "No fixed opponent was found. Choose an opponent, then apply it to this battle." or "Edit what this action uses, including settings prepared earlier."
  help=fields.help or help
  K.text("small",K.ellipsize("small",help,w),x,y,color);K.offerTooltip(x,y,w,24*s,help);y=y+30*s
  for i,field in ipairs(fields) do
    K.caption(x,y,field.label);y=y+24*s
    local function pick(value)
      if draft then
        if value>=field.min and value<=field.max and value%1==0 then draft[({"species","level","item"})[i]]=value end
      elseif value~=field.value and M.edit(S,catalog,field,value) then changed() end
    end
    if field.choices=="species" then
      local P=require("SpeciesPicker")
      P.field(S,{x=x,y=y,w=w,h=29*s,current=P.idForIndex(S,field.value) or "",emptyLabel=field.value and "Pokémon "..field.value or "Chosen while playing — select a Pokémon",title="CHOOSE POKÉMON",onPick=function(id) local n=P.indexForId(S,id);if n then pick(n) end end})
    elseif field.choices=="item" then
      local P=require("ItemPicker")
      P.field(S,{x=x,y=y,w=w-110*s,h=29*s,current=P.idForIndex(S,field.value) or "",emptyLabel=field.value==0 and "No held item" or "Choose held item",title="HELD ITEM",onPick=function(id) local n=P.indexForId(S,id);if n then pick(n) end end})
      if K.button(x+w-102*s,y,102*s,29*s,"No item",{}) then pick(0) end
    elseif field.choices then
      local ids,labels=require("Gen3ActionLanguage").choiceData(S,field.choices,field.value or "dynamic")
      labels.dynamic="Chosen while playing"
      require("ChoicePicker").field(S,{x=x,y=y,w=w,h=29*s,current=tostring(field.value or "dynamic"),ids=ids,labels=labels,title=field.label,onPick=function(id) local n=tonumber(id);if n then pick(n) end end})
    else
      local value=K.textfield(key.."/input/"..i,x,y,w,29*s,field.value~=nil and tostring(field.value) or "","Chosen while playing")
      local n=tonumber(value);if n then pick(n) end
    end
    y=y+40*s
  end
  if draft then
    if K.button(x,y,220*s,29*s,"Apply battle opponent",{enabled=draft.species~=nil,kind="good"})
      and M.prepareBattle(S,catalog,fields.newBattle,draft) then S._g3BattleInputs[key]=nil;changed() end
    y=y+40*s
  end
  return y
end
return M
