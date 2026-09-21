local M={}
function M.prepare(p)
  for id,rec in pairs(p.gen3Trades or {}) do
    local key="EditorTrade_"..p.id:gsub("[^%w_]","_").."_"..id.."_Prompt"
    local prompt="Trade the first "..rec.give.." in your party for "..rec.get.."?"
    if rec._prompt and p.text and p.text[key]==rec._prompt then p.text[key]=prompt;rec._prompt=prompt end
  end
end
function M.draw(S,x,y,w,h,App)
  local K=require("Kit");local L=require("RegList");local s=K.scale
  if not S.project then return end
  require("Gen3ContentAdapter").prepare(S)
  local originals=require("Gen3Rom").trades(S)
  local records={};for id,rec in pairs(originals) do records[id]=rec end
  for id,rec in pairs(S.project.gen3Trades or {}) do records[id]=rec end
  local ids=L.sortedKeys(records)
  S.g3TradeId=S.g3TradeId or ids[1]
  local fx,fw=L.drawList(S,App,x,y,w,h,"SCRIPTED TRADES",ids,{selKey="g3TradeId",queryKey="g3TradeQuery",offsetKey="g3TradeOffset",
    label=function(id) local r=records[id];return r and (r.give.." → "..r.get) or id end,
    footerLabel="New trade",onFooter=function()
      local n=1;while records["TRADE_"..n] do n=n+1 end
      local id="TRADE_"..n
      S.project.gen3Trades=S.project.gen3Trades or {};records=S.project.gen3Trades
      records[id]={give="ABRA",get="MR_MIME",nickname="MARCEL",otName="NPC",otId=12345}
      S.g3TradeId=id;App.markDirty()
    end})
  local id=S.g3TradeId;local rec=id and records[id]
  if not rec then
    K.caption(fx,y,"Create a trade, then attach its script to an NPC on Maps.")
    K.caption(fx,y+30*s,"The linked runtime does not expose the original ROM trade table.")
    return
  end
  local function mutate()
    S.project.gen3Trades=S.project.gen3Trades or {}
    if not S.project.gen3Trades[id] then S.project.gen3Trades[id]=require("src.mods.Merge").deepCopy(rec) end
    rec=S.project.gen3Trades[id];return rec
  end
  K.caption(fx,y,id.." — first matching party Pokemon, once per save")
  local yy=y+38*s
  for _,row in ipairs({{"give","Player gives"},{"get","Player receives"}}) do
    K.caption(fx,yy,row[2])
    require("SpeciesPicker").field(S,{x=fx+170*s,y=yy,w=fw-170*s,h=28*s,current=rec[row[1]],
      onPick=function(value) rec=mutate();rec[row[1]]=value;App.markDirty() end})
    yy=yy+38*s
  end
  for _,row in ipairs({{"nickname","Nickname"},{"otName","Original trainer"}}) do
    K.caption(fx,yy,row[2])
    local v=K.textfield("g3_trade_"..row[1],fx+170*s,yy,fw-170*s,28*s,rec[row[1]] or "","")
    if v~=rec[row[1]] then rec=mutate();rec[row[1]]=v;App.markDirty() end
    yy=yy+38*s
  end
  K.caption(fx,yy,"Trainer ID")
  local ot=L.num(App,"g3_trade_ot",fx+170*s,yy,120*s,28*s,rec.otId or 12345)
  ot=math.max(0,math.min(65535,math.floor(ot)))
  if ot~=rec.otId then rec=mutate();rec.otId=ot;App.markDirty() end
  yy=yy+46*s
  local script="EditorTrade_"..S.project.id:gsub("[^%w_]","_").."_"..id
  K.caption(fx,yy,"Script: "..script);yy=yy+30*s
  if K.button(fx,yy,210*s,28*s,"Create / open NPC script",{kind="good"}) then
    rec=mutate()
    local p=S.project;p.gen3=p.gen3 or {};p.gen3.map_scripts=p.gen3.map_scripts or {}
    if not p.gen3.map_scripts[script] then
      local text=script.."_Prompt"
      rec._prompt="Trade the first "..rec.give.." in your party for "..rec.get.."?"
      p.text[text]=rec._prompt
      p.gen3.map_scripts[script]={{op="lock"},{op="faceplayer"},{op="message",ptr=text},{op="waitmessage"},
        {op="yesnobox",x=20,y=8},{op="editor_trade",owner=p.id,trade=id},{op="closemessage"},{op="release"},{op="end"}}
      p.gen3Modes=p.gen3Modes or {};p.gen3Modes.map_scripts=p.gen3Modes.map_scripts or {}
      p.gen3Modes.map_scripts[script]="register";App.markDirty()
    end
    S.gen3Id=script;S.tab="events";S.g3EventMode="scripts"
  end
  yy=yy+40*s
  K.caption(fx,yy,"Attach this script to an NPC on Maps to use this trade in game.")
  yy=yy+26*s
  K.caption(fx,yy,"Receives the offered Pokemon's level. Canceling leaves the party unchanged.")
  yy=yy+30*s
  if K.button(fx,yy,140*s,28*s,originals[id] and "Revert trade" or "Delete trade",{kind="danger"}) then
    if S.project.gen3Trades then S.project.gen3Trades[id]=nil end
    S.g3TradeId=nil;App.markDirty()
  end
end
function M.emit(p,encode,out)
  if not next(p.gen3Trades or {}) then return end
  for id,row in pairs(p.gen3Trades) do
    assert(type(id)=="string" and type(row.give)=="string" and type(row.get)=="string","Invalid scripted trade")
  end
  out[#out+1]="  local trades="..encode(p.gen3Trades)
  out[#out+1]=[=[
  local Runtime=require("src.core.game3.runtime")
  local Pokemon=require("src.core.game3.pokemon")
  local Party=require("src.core.game3.party")
  local Flags=require("src.core.game3.scripting.flags")
  mod.hooks:wrap("script.command",function(proceed,ctx,op,row)
    if op~="editor_trade" or row.owner~=mod.id then return proceed(ctx,op,row) end
    local vm=ctx.vm or ctx.runner
    local session=ctx.session or Runtime.getSession()
    if not vm or not session then return false end
    local confirmed=Flags.getVar(vm.store,vm.ctx,0x800D)==1
    Flags.setVar(vm.store,vm.ctx,0x800D,0)
    local trade=trades[row.trade]
    if not confirmed or not trade then return false end
    session.modData=session.modData or {};session.modData[mod.id]=session.modData[mod.id] or {}
    local saved=session.modData[mod.id]
    saved.editorTrades=saved.editorTrades or {}
    if saved.editorTrades[row.trade] then return false end
    local want=assert(mod.content.pokemon:get(trade.give),"Unknown requested species").index
    local give=assert(mod.content.pokemon:get(trade.get),"Unknown trade species").index
    local selected
    for i,mon in ipairs(session.party or {}) do
      if Pokemon.speciesOf(mon)==want and not Pokemon.isEgg(mon) then selected=i;break end
    end
    if not selected then return false end
    -- Construct the replacement before committing any change to the real party.
    local temporary={party={},name=trade.otName or "NPC",trainerId=trade.otId or 12345}
    local offered=session.party[selected]
    if not Party.giveMon(temporary,give,offered.level or 5,trade.nickname) then return false end
    local received=temporary.party[1]
    if trade.ivs then
      received.ivs={};for i,name in ipairs({"hp","attack","defense","speed","spAtk","spDef"}) do received.ivs[name]=trade.ivs[i] end
    end
    if trade.personality then received.personality=trade.personality end
    if trade.heldItem then received.heldItem=trade.heldItem end
    if trade.abilityNum then received.abilityNum=trade.abilityNum end
    if trade.otGender then received.otGender=trade.otGender end
    Pokemon.applyStats(received);received.hp=received.maxHp
    session.party[selected]=received
    if session.move_overlay then session.move_overlay[selected]=nil end
    session.dex=session.dex or {seen={},owned={}}
    require("src.core.game3.dex").registerCapture(session.dex,give,session)
    saved.editorTrades[row.trade]=true
    Flags.setVar(vm.store,vm.ctx,0x800D,1)
    return false
  end)
]=]
end
return M
