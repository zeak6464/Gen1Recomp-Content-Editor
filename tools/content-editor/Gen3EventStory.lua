-- A bounded, read-only expansion of control flow. Each text row retains its source.
local M={}
local A=require("Gen3EventActions")
local quiet={lock=true,lockall=true,release=true,releaseall=true,waitmessage=true,
  waitbuttonpress=true,closemessage=true,waitmovement=true}
local labels={faceplayer="Turn toward the player",playse="Play a sound",playfanfare="Play a fanfare",
  copyobjectxytoperm="Remember the character's new position"}
local relations={[0]="is less than",[1]="equals",[2]="is greater than",[3]="is at most",[4]="is at least",[5]="does not equal"}
function M.itemPickup(steps)
  if type(steps)~="table" then return end
  for i=1,#steps-2 do
    local a,b,c=steps[i],steps[i+1],steps[i+2]
    if a.op=="setorcopyvar" and (a[1] or a.var)==0x8000
      and b.op=="setorcopyvar" and (b[1] or b.var)==0x8001
      and c.op=="callstd" and (c.std or c[1])==1 then
      return {first=i,item=tonumber(a[2] or a.value),quantity=tonumber(b[2] or b.value) or 1}
    end
  end
end
function M.itemName(S,index)
  local id
  for _,bucket in ipairs({(S.project or {}).items or {},(S.data or {}).items or {}}) do
    for key,rec in pairs(bucket) do if type(rec)=="table" and rec.index==index then id=key;break end end
    if id then break end
  end
  if id then return id:gsub("^ITEM_",""):gsub("_"," "),id end
  return "Unknown item "..tostring(index),nil
end
function M.rows(S,id,catalog)
  local out,active={},{}
  if S.data._g3StoryMovements==nil then
    local bytes=S.data._gen3Read and S.data._gen3Read("data/generated/gba/scripts/movements.lua")
    S.data._g3StoryMovements=bytes and require("Gen3Decode").decode(bytes,{allowArray=true,allowComments=true,maxBytes=16777216,maxNodes=1000000}) or {}
  end
  local function add(label,depth,script,index,text)
    out[#out+1]={label=label,depth=depth,script=script,index=index,text=text}
  end
  local function walk(key,depth)
    if #out>=240 or depth>8 then add("More behavior is available in Advanced commands",depth);return end
    if active[key] then add("Repeat earlier behavior",depth);return end
    local steps=(((S.project.gen3 or {}).map_scripts or {})[key] or catalog[key])
    if not steps then add("Linked behavior is unavailable in this project",depth);return end
    active[key]=true
    local i=1
    while i<=#steps and #out<240 do
      local row,nextRow=steps[i],steps[i+1];local op=row.op
      local pickup=M.itemPickup({steps[i],steps[i+1],steps[i+2]})
      if pickup and pickup.first==1 then
        local name,itemId=M.itemName(S,pickup.item)
        out[#out+1]={label="Pick up "..(pickup.quantity>1 and pickup.quantity.." × " or "")..name,
          depth=depth,script=key,index=i,kind="item",item=pickup.item,itemId=itemId,quantity=pickup.quantity}
        i=i+3
      elseif (op=="compare_var_to_value" or op=="checkflag") and nextRow and (nextRow.op=="goto_if" or nextRow.op=="call_if") then
        local cond=nextRow.cond or nextRow[1]
        local condition
        if op=="checkflag" and (cond==1 or cond==5) then
          condition="saved switch "..tostring(row.flag or row[1])..(cond==1 and " is ON" or " is OFF")
        elseif op=="compare_var_to_value" and relations[cond] then
          condition="saved value "..tostring(row.var or row[1]).." "..relations[cond].." "..tostring(row.value or row[2])
        else condition="an unnamed game condition is met" end
        add("If "..condition,depth,key,i)
        walk(nextRow.target or nextRow[2],depth+1)
        add(nextRow.op=="goto_if" and "Otherwise, continue below" or "Then continue below",depth)
        i=i+2
      elseif op=="loadword" and (row.dest or row[1])==0 and nextRow and (nextRow.op=="callstd" or nextRow.op=="gotostd")
        and (nextRow.std or nextRow[1] or -1)>=2 and (nextRow.std or nextRow[1] or 99)<=6 and A.text(S,row) then
        add((nextRow.std or nextRow[1])==5 and "Ask the player: Yes / No" or "Show dialogue",depth,key,i,A.text(S,row))
        i=i+2;if nextRow.op=="gotostd" then break end
      elseif op=="message" and A.text(S,row) then
        add("Show dialogue",depth,key,i,A.text(S,row));i=i+1
      elseif op=="goto" or op=="call" then
        walk(row.target or row[1],depth);i=i+1;if op=="goto" then break end
      elseif op=="end" or op=="return" then break
      else
        if op=="applymovement" then
          local actor=row.localId or row[1]
          local who=actor==255 and "Player" or "Character "..tostring(actor)
          local route=row.movement or row[2]
          local bytes=type(route)=="table" and route or (S.data._g3StoryMovements or {})[route]
          local parts={}
          if bytes then
            local previous,count
            local function flush() if previous then parts[#parts+1]=previous..(count>1 and " x"..count or "") end end
            for _,byte in ipairs(bytes) do
              if byte==254 or byte==255 then break end
              local label=({[74]="Face the player",[75]="Face away from the player",[76]="Keep facing this direction",[77]="Allow turning"})[byte]
                or require("Gen3MovementEditor").label(byte)
              if label:find("^Native action") then label="Special movement (see Advanced commands)" end
              if label==previous then count=count+1 else flush();previous=label;count=1 end
            end
            flush()
          end
          add(who..": "..(#parts>0 and table.concat(parts,", ") or "follow a movement route"),depth,key,i)
        elseif op=="delay" then add("Wait "..tostring((row.frames or row[1] or 0)/60).." seconds",depth,key,i)
        elseif op=="setflag" or op=="clearflag" then add("Remember: switch "..tostring(row.flag or row[1])..(op=="setflag" and " is ON" or " is OFF"),depth,key,i)
        elseif not quiet[op] then add(labels[op] or "Game-specific action (inspect in Advanced commands)",depth,key,i) end
        i=i+1
      end
    end
    active[key]=nil
  end
  walk(id,0);return out
end
function M.draw(S,id,catalog,x,y,w,h,App)
  local K=require("Kit");local P=require("FormPane");local s=K.scale;local color=require("Theme").PAL.text
  K.caption(x,y,"WHAT HAPPENS")
  K.text("small","Read from top to bottom. Indented actions happen only inside that condition.",x,y+26*s,color)
  K.text("small","Saved values and switches have no story names in the imported game.",x,y+49*s,color)
  local rows=M.rows(S,id,catalog);local pane="g3Story/"..id
  local top,view=P.begin(S,pane,x,y+82*s,w,h-82*s);local yy=top
  local selected=S._g3StoryEdit
  for n,row in ipairs(rows) do
    local xx=x+math.min(row.depth,4)*18*s;local width=view.contentW-(xx-x)
    K.text("small",K.ellipsize("small",row.label,width),xx,yy,color);K.offerTooltip(xx,yy,width,24*s,row.label);yy=yy+28*s
    if row.kind=="item" then
      K.text("small","The Poké Ball disappears after a successful pickup. If the Bag is full, it stays here.",xx+8*s,yy,color);yy=yy+29*s
      K.caption(xx,yy,"ITEM");yy=yy+25*s
      require("ItemPicker").field(S,{x=xx,y=yy,w=width,h=29*s,current=row.itemId or "",emptyLabel="Unknown item "..tostring(row.item),title="CHOOSE PICKUP ITEM",onPick=function(itemId)
        local index=require("ItemPicker").indexForId(S,itemId);if not index then return end
        local source=((S.project.gen3 or {}).map_scripts or {})[row.script] or catalog[row.script]
        local copy=require("src.mods.Merge").deepCopy(source);local step=copy[row.index];step[2]=index;if step.value~=nil then step.value=index end
        S.project.gen3.map_scripts[row.script]=copy;S._g3ScriptSource=nil;App.markDirty()
      end});yy=yy+40*s
      K.caption(xx,yy,"QUANTITY");yy=yy+25*s
      local value=K.textfield(pane.."/item/"..n,xx,yy,math.min(width,180*s),29*s,tostring(row.quantity),"")
      local quantity=tonumber(value)
      if quantity and quantity==math.floor(quantity) and quantity>=1 and quantity<=999 and quantity~=row.quantity then
        local source=((S.project.gen3 or {}).map_scripts or {})[row.script] or catalog[row.script]
        local copy=require("src.mods.Merge").deepCopy(source);local step=copy[row.index+1];step[2]=quantity;if step.value~=nil then step.value=quantity end
        S.project.gen3.map_scripts[row.script]=copy;S._g3ScriptSource=nil;App.markDirty()
      end
      yy=yy+42*s
    elseif row.text then
      local text=row.text:gsub("\n","  ")
      local font=K.fonts.small
      local _,lines=font:getWrap(text,math.max(80,width-12*s))
      for _,line in ipairs(lines) do K.text("small",line,xx+8*s,yy,color);yy=yy+23*s end
      if K.button(xx,yy,120*s,27*s,"Edit dialogue",{}) then
        S._g3MessageDraft=nil
        S._g3StoryEdit={root=id,script=row.script,index=row.index}
      end
      yy=yy+37*s
      if selected and selected.root==id and selected.script==row.script and selected.index==row.index then
        local source=S.project.gen3.map_scripts[row.script] or catalog[row.script]
        if S._g3ScriptSource~=source or S._g3ScriptId~=row.script then
          S._g3ScriptSource=source;S._g3ScriptId=row.script;S._g3ScriptDraft=require("src.mods.Merge").deepCopy(source)
        end
        local _,bottom=require("Gen3EventCommands").drawText(S,pane.."/"..n,S._g3ScriptDraft[row.index],xx,yy,width,function()
          S.project.gen3.map_scripts[row.script]=require("src.mods.Merge").deepCopy(S._g3ScriptDraft)
          S._g3ScriptSource=S.project.gen3.map_scripts[row.script];App.markDirty()
        end)
        yy=bottom or yy
      end
    end
    yy=yy+10*s
  end
  if #rows==0 then K.caption(x,yy,"This event has no visible actions yet.");yy=yy+30*s end
  P.finish(S,pane,top,yy,view)
end
return M
