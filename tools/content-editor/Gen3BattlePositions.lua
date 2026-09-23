local M={}
function M.emit(p,encode,out)
  if not next(p.gen3BattlePositions or {}) then return end
  for _,rec in pairs(p.gen3BattlePositions) do
    for _,field in ipairs({"frontY","backY"}) do
      local v=rec[field]
      assert(type(v)=="number" and v%1==0 and v>=-64 and v<=64,"Battle offsets must be integers from -64 to 64")
    end
  end
  out[#out+1]="local positions=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3BattlePositionsRuntime.lua"))
    .."\nend)()\npositions.install(mod,"..encode(p.gen3BattlePositions)..")"
end
function M.draw(S,mon,x,y,w,App)
  local K,Preview=require("Kit"),require("Preview")
  local s=K.scale
  local p=S.project
  local rec=(p.gen3BattlePositions or {})[mon.id] or {frontY=0,backY=0}
  K.text("small","Battle position offsets (pixels)",x,y,require("Theme").PAL.heading);y=y+28*s
  K.text("micro","Negative moves up; positive moves down. Existing mod positioning is preserved.",x,y,require("Theme").PAL.muted);y=y+26*s
  for _,row in ipairs({{"frontY","Opponent / front Y"},{"backY","Player / back Y"}}) do
    K.text("small",row[2],x,y+6*s,require("Theme").PAL.text)
    local value=require("RegList").num(App,"battle_pos_"..mon.id..row[1],x+180*s,y,100*s,30*s,rec[row[1]])
    value=math.max(-64,math.min(64,math.floor(value)))
    if value~=rec[row[1]] then
      rec={frontY=rec.frontY,backY=rec.backY};rec[row[1]]=value
      p.gen3BattlePositions=p.gen3BattlePositions or {};p.gen3BattlePositions[mon.id]=rec;App.markDirty()
    end
    y=y+38*s
  end
  if K.button(x,y,160*s,30*s,"Reset offsets",{}) then
    if p.gen3BattlePositions then p.gen3BattlePositions[mon.id]=nil end
    rec={frontY=0,backY=0};App.markDirty()
  end
  if K.chip(x+170*s,y,80*s,30*s,"Shiny",S.battlePositionShiny,require("Theme").PAL.blue) then S.battlePositionShiny=not S.battlePositionShiny end
  y=y+42*s
  local scale=math.min(w/240,2*s)
  local g=love.graphics
  g.push("all");g.translate(x,y);g.scale(scale)
  g.setColor(.64,.77,.72,1);g.rectangle("fill",0,0,240,112)
  g.setColor(.42,.59,.48,1);g.ellipse("fill",176,68,47,11);g.ellipse("fill",72,106,60,14)
  local Ui=require("src.core.game3.battle.ui")
  for _,back in ipairs({false,true}) do
    local field=S.battlePositionShiny and (back and "spriteShinyBack" or "spriteShinyFront") or (back and "spriteBack" or "spriteFront")
    local path=require("ModPokemonArt").path(S,mon,field) or require("Gen3Forms").spritePath(mon,back,S.battlePositionShiny,S)
    local image=Preview.image(S,path)
    local base=back and {x=72,y=80} or {x=176,y=40}
    local cx,cy=Ui.battlerSpriteCenter(back and "player" or "enemy",mon.index,base,0,false)
    cy=cy+Ui.bounceOffset("mon",back and 0 or 1)+(back and rec.backY or rec.frontY)
    g.setColor(1,1,1,1)
    if image then g.draw(image,cx-32,cy-32,0,64/image:getWidth(),64/image:getHeight()) end
    g.setColor(1,.25,.25,.8);g.line(cx-3,cy,cx+3,cy);g.line(cx,cy-3,cx,cy+3)
  end
  g.pop()
  return y+112*scale+16*s
end
return M
