local M={}
M.fields={
  {key="critMultiplier",label="Critical damage multiplier",default=2,min=1,max=10},
  {key="weatherChipDenom",label="Weather damage divisor",default=16,min=1,max=256},
  {key="partialTrapChipDenom",label="Trapping damage divisor",default=16,min=1,max=256},
  {key="partialTrapMinTurns",label="Minimum trapping turns",default=3,min=1,max=100},
  {key="partialTrapMaxTurns",label="Maximum trapping turns",default=6,min=1,max=100},
}
function M.draw(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  K.caption(x,y,"FIRERED BATTLE RULES")
  y=y+38*s
  local values=S.project.gen3BattleRules or {}
  for _,row in ipairs(M.fields) do
    K.caption(x,y,row.label)
    local old=values[row.key] or row.default
    local n=require("RegList").num(App,"g3_rule_"..row.key,x+310*s,y,110*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3BattleRules=S.project.gen3BattleRules or {};values=S.project.gen3BattleRules
      values[row.key]=n;App.markDirty()
    end
    y=y+38*s
  end
  if K.button(x,y+12*s,160*s,28*s,"Reset to FireRed",{}) then S.project.gen3BattleRules=nil;App.markDirty() end
end
function M.emit(p,encode,out)
  if not next(p.gen3BattleRules or {}) then return end
  local values=p.gen3BattleRules
  for _,row in ipairs(M.fields) do
    local v=values[row.key]
    assert(v==nil or type(v)=="number" and v%1==0 and v>=row.min and v<=row.max,"Invalid battle rule "..row.key)
  end
  assert((values.partialTrapMaxTurns or 6)>=(values.partialTrapMinTurns or 3),"Maximum trap turns must be at least the minimum")
  out[#out+1]="  local battleRules="..encode(values)
  out[#out+1]=[=[
  local Runtime=require("src.mods.Runtime")
  local Rules=require("src.core.game3.battle.rules")
  if not Rules._editorRuleBridge then
    Rules._editorRuleBridge=true
    for _,entry in ipairs({{"crit","multiplier"},{"weather","chipAmount"},{"partialTrap","chipAmount"},{"partialTrap","rollTurns"}}) do
      local group,method=entry[1],entry[2]
      local base=Rules[group][method]
      Rules[group][method]=function(...) return Runtime.call("editor.gen3.rules."..group.."."..method,base,...) end
    end
  end
  mod.hooks:wrap("editor.gen3.rules.crit.multiplier",function(proceed)
    return battleRules.critMultiplier or proceed()
  end)
  for _,entry in ipairs({{"weather","weatherChipDenom"},{"partialTrap","partialTrapChipDenom"}}) do
    local group,key=entry[1],entry[2]
    mod.hooks:wrap("editor.gen3.rules."..group..".chipAmount",function(proceed,hp)
      if not battleRules[key] then return proceed(hp) end
      return math.max(1,math.floor((hp or 16)/battleRules[key]))
    end)
  end
  mod.hooks:wrap("editor.gen3.rules.partialTrap.rollTurns",function(proceed,rng)
    if not battleRules.partialTrapMinTurns and not battleRules.partialTrapMaxTurns then return proceed(rng) end
    local low,high=battleRules.partialTrapMinTurns or 3,battleRules.partialTrapMaxTurns or 6
    local n=(rng or math.random)(0,high-low)
    return low+math.floor(n)%(high-low+1)
  end)
]=]
end
return M
