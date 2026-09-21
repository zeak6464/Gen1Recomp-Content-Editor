-- Pure sequence player, shared by the editor and exported mod.
local M={}
function M.new(payload,female)
 return {payload=payload,index=1,frame=0,total=0,map="INDIGO",ground="ground_city",mapFrame=0,female=female,done=false}
end
function M.enter(v)
 local c=v.payload.commands[v.index];if not c then v.done=true;return end
 if c.op=="ending" then v.endingRow=c.row end
 if c.op=="map" then
  v.map=c.id;v.mapFrame=0
  if c.reset then v.actor=c.id=="ROUTE17" and "rival" or (v.female and "player_female" or "player_male");v.actorFrame=0;v.ground=c.id=="ROUTE10" and "ground_city" or c.id=="ROUTE17" and "ground_grass" or c.id=="ROUTE21_NORTH" and "ground_grass" or "ground_dirt" end
 end
end
function M.update(v,dt)
 if v.done then return end
 local frames=dt*60
 while frames>0 and not v.done do
  if not v.entered then M.enter(v);v.entered=true end
  local c=v.payload.commands[v.index];if not c then break end
  local step=math.min(frames,math.max(0,c.frames-v.frame));if c.op=="mon" and v.frame<102 and v.frame+step>=102 and v.onCry then v.onCry(c.id) end
  v.frame=v.frame+step;v.total=v.total+step
  if c.op=="map" or c.op=="text" or c.op=="opening" then v.mapFrame=v.mapFrame+step;v.actorFrame=(v.actorFrame or 0)+step end
  frames=frames-step
  if v.frame>=c.frames then v.index=v.index+1;v.frame=0;v.entered=false;if not v.payload.commands[v.index] then v.done=true end end
 end
end
function M.next(v)
 if not v.done then local c=v.payload.commands[v.index];M.update(v,math.max(1,c.frames-v.frame)/60) end
end
function M.draw(v,image)
 if not v.entered then M.enter(v);v.entered=true end
 local g=love.graphics;g.push("all");local sx,sy=g.transformPoint(0,0);local ex,ey=g.transformPoint(240,160);g.intersectScissor(sx,sy,ex-sx,ey-sy);g.setColor(0,0,0,1);g.rectangle("fill",0,0,240,160)
 local c=v.payload.commands[v.index];if not c then g.pop();return end
 local art=v.payload.art
 local function sprite(id,x,y,frame,fw,fh,scale)
  local img=image(art[id]);if not img then return end;g.setColor(1,1,1,1)
  if fw then g.draw(img,g.newQuad(0,frame*fh,fw,fh,img:getDimensions()),x,y,0,scale or 1,scale or 1) else g.draw(img,x,y,0,scale or 1,scale or 1) end
 end
 local function fade(a,white)
  g.setColor(white and 1 or 0,white and 1 or 0,white and 1 or 0,math.max(0,math.min(1,a)));g.rectangle("fill",0,0,240,160)
 end
 local font=require("src.ui.game3.frlg_font")
 if c.op=="map" or c.op=="text" or c.op=="opening" then
  local spec=v.payload.maps[v.map or "ROUTE23"];local img=spec and image(spec.image)
  if img then
   local w,h=img:getDimensions();local travel=math.min(1280,math.floor(v.mapFrame/2))
   local cx=math.max(0,math.min(w-240,spec.x*16-112+spec.dx*travel));local cy=math.max(0,math.min(h-160,spec.y*16-72+spec.dy*travel))
   g.setColor(.375,.375,.375,1);g.draw(img,-math.floor(cx),-math.floor(cy))
  end
  local opening=c.op=="opening";local gap=opening and math.min(44,1+v.frame) or 44
  g.setColor(0,0,0,1);g.rectangle("fill",0,0,240,80-gap);g.rectangle("fill",0,80+gap,240,80-gap)
  local actor=v.actor or (v.female and "player_female" or "player_male")
  local ax=opening and math.max(208,272-math.max(0,v.frame-44)) or 208
  local ay=actor=="rival" and math.max(80,160-(v.actorFrame or 0)/2) or 80
  local ground=v.ground or "ground_city"
  sprite(ground,ax-32,ay+22,actor=="rival" and 0 or math.floor(v.total/8)%8,64,32)
  sprite(actor,ax-32,ay-32,math.floor(v.total/8)%6,64,64)
  local row=c.row
  if row then
   if row.image then local replacement=image(row.image);g.setColor(1,1,1,1);g.draw(replacement,0,0) end
   if not row.image and row.art and row.art~="none" then
    local overlay=image(art[row.art]);if overlay then local w,h=overlay:getDimensions();local z=math.min(1,240/w,160/h);g.setColor(1,1,1,1);g.draw(overlay,120-w*z/2,80-h*z/2,0,z,z) end
   end
   local alpha=math.min(1,v.frame/16,(c.frames-v.frame)/16)
   font.draw(row.title or "",2,18,{color={.7,.85,1,alpha},small=true,maxWidth=172,linePitch=13})
   font.draw(row.text or "",8,44,{color={1,1,1,alpha},small=true,maxWidth=166,linePitch=13})
  elseif opening and v.frame>144 then font.draw("POKEMON FIRERED\nSTAFF",8,54,{color={1,1,1,1},maxWidth=164}) end
  if c.op=="map" then fade(1-v.frame/c.frames) end
 elseif c.op=="mon" then
  local t=v.frame;local id=c.id;local img
  if t<48 then img=image(art[id.."_front"])
  elseif t<53 then img=image(art[id.."_1"])
  else img=image(art[id.."_2"]) end
  if t>=102 then
   local ball=image(art["ball_"..id]);g.setColor(1,1,1,1);if ball then g.draw(ball,0,0) end
  elseif t>=54 then
   local circle=image(art.circle_screen);local zoom=256/math.min(256,24+math.max(0,t-54)*16);g.setColor(1,1,1,1);if circle then g.draw(circle,120,80,0,zoom,zoom,128,128) end
  end
  if img then g.setColor(1,1,1,1);local w,h=img:getDimensions();g.draw(img,120-w/2,id=="charizard" and t>=53 and 24 or 80-h/2) end
  if t<16 then fade(1-t/16) elseif t>c.frames-16 then fade((t-c.frames+16)/16) end
 elseif c.op=="ending" or c.op=="wait" then
  local row=c.row or v.endingRow
  local img=image((row or {}).image or art[(c.id or "the_end").."_screen"]);if img then g.setColor(1,1,1,1);g.draw(img,0,0) end
  if row and (row.title~="THE END" or row.text~="") then
   font.draw(row.title or "",12,16,{color={1,1,1,1},maxWidth=216})
   font.draw(row.text or "",12,40,{color={1,1,1,1},small=true,maxWidth=216,linePitch=12})
  end
  if c.op=="ending" then fade(1-v.frame/16) elseif v.frame>c.frames-16 then fade((v.frame-c.frames+16)/16,true) end
 end
 g.pop()
end
return M
