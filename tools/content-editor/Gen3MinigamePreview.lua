-- Editor-only animation demonstrations using the original ROM graphics.
-- These timelines do not simulate game rules, networking, rewards or saves.
local M={}
local Images=require("Gen3MinigameImages")
function M.start(S,game)
 if not Images.assets[game] then return nil,"Unknown mini-game" end
 M.stop(S)
 local p={game=game,project=S.project,data=S.data,frame=0,remainder=0,paused=false,speed=1,textures={},quads={}}
 S.g3MinigamePreview=p
 local ok,err=pcall(function()
  for i in ipairs(Images.assets[game]) do
   local data,problem=Images.image(S,game,i);assert(data,problem)
   p.textures[i]=love.graphics.newImage(data);p.textures[i]:setFilter("nearest","nearest")
  end
  p.canvas=love.graphics.newCanvas(240,160);p.canvas:setFilter("nearest","nearest")
 end)
 if not ok then p.error=tostring(err);p.paused=true;return nil,p.error end
 return p
end
function M.stop(S)
 local p=S.g3MinigamePreview
 if type(p)=="table" then
  if p.canvas then p.canvas:release() end
  for _,image in pairs(p.textures or {}) do image:release() end
  for _,quad in pairs(p.quads or {}) do quad:release() end
 end
 S.g3MinigamePreview=nil
end
function M.step(S)
 local p=S.g3MinigamePreview
 if type(p)=="table" and not p.error then p.frame=(p.frame+1)%360 end
end
function M.update(S,dt)
 local p=S.g3MinigamePreview;if type(p)~="table" then return end
 if S.project~=p.project or S.data~=p.data or S.tab~="ui" or S.g3UiMode~="minigames" or S.g3MinigameView~="playback" then M.stop(S);return end
 if p.paused or p.error then return end
 p.remainder=p.remainder+math.min(math.max(dt or 0,0),.1)*60*p.speed
 local frames=math.floor(p.remainder);p.remainder=p.remainder-frames
 for _=1,frames do M.step(S) end
end
local function frame(p,index,fw,fh,n,x,y,flip)
 local image=p.textures[index];local across=math.floor(image:getWidth()/fw)
 local count=across*math.floor(image:getHeight()/fh);n=n%count
 local key=index..":"..fw..":"..fh..":"..n
 local q=p.quads[key]
 if not q then q=love.graphics.newQuad((n%across)*fw,math.floor(n/across)*fh,fw,fh,image:getDimensions());p.quads[key]=q end
 love.graphics.draw(image,q,x+(flip and fw or 0),y,0,flip and -1 or 1,1)
end
local function scene(S,p)
 local f=p.frame
 love.graphics.setColor(1,1,1,1);love.graphics.draw(p.textures[1],0,0)
 if p.game=="slots" then
  -- Symbols are clipped to the three reel windows. The scene loops through
  -- spinning, stopping one reel at a time, and Clefairy's payout poses.
  for reel=0,2 do
   local stop=120+reel*35;local distance=math.min(f,stop)*3
   love.graphics.setScissor(66+40*reel,56,30,72)
   for row=-1,3 do
    local symbol=(math.floor(distance/32)+row+7+reel*2)%7
    frame(p,3,32,32,symbol,65+40*reel,56+row*32+distance%32)
   end
  end
  love.graphics.setScissor()
  local pose=f<190 and math.floor(f/24)%2 or 2+math.floor(f/28)%2
  frame(p,4,32,32,pose,7,57);frame(p,4,32,32,pose,201,57,true)
 elseif p.game=="crush" then
  local phase=f%45;local press=math.floor(math.sin(phase/45*math.pi)*12)
  frame(p,2,64,64,0,88,24+press)
  if phase>=14 and phase<35 then
   frame(p,3,32,32,math.floor((phase-14)/3),70,66)
   frame(p,3,32,32,math.floor((phase-14)/3),138,66,true)
   for i=0,3 do frame(p,4,16,16,(math.floor(f/3)+i)%14,88+i*18,92+((f+i*8)%30)) end
  end
 elseif p.game=="dodrio" then
  local cycle=f%90;local pose=cycle<55 and 0 or 1+math.floor(f/90)%3
  for i=0,2 do
   local bx=72+i*40;local by=20+(f*1.5+i*23)%85
   frame(p,3,16,16,i*3,bx,by)
  end
  frame(p,2,64,64,pose,88,91)
  frame(p,4,64,32,0,(f/3)%280-40,20)
 elseif p.game=="jump" then
  local phase=f%90;local sweep=math.floor(phase/15)%6
  for i=0,4 do frame(p,6,32,16,sweep,40+i*32,91) end
  -- Original Pokemon front sprites provide a clear jumping demonstration.
  for i,id in ipairs({25,35,39}) do
   local key="pokemon"..id
   if not p.textures[key] then
    local bytes=S.data._gen3Read("data/generated/gba/pokemon/front/"..id..".rgba")
    if bytes and #bytes>=64*64*4 then p.textures[key]=love.graphics.newImage(love.image.newImageData(64,64,"rgba8",bytes:sub(1,64*64*4)));p.textures[key]:setFilter("nearest","nearest") end
   end
   local height=math.floor(math.max(0,math.sin((phase-15)/60*math.pi))*24)
   if p.textures[key] then love.graphics.draw(p.textures[key],48+(i-1)*48,104-height,0,.5,.5) end
  end
 end
end
function M.render(S)
 local p=S.g3MinigamePreview;if type(p)~="table" or p.error then return nil,p and p.error end
 local old=love.graphics.getCanvas();love.graphics.push("all")
 love.graphics.setCanvas(p.canvas);love.graphics.origin();love.graphics.setScissor();love.graphics.setShader();love.graphics.clear(0,0,0,1)
 local ok,err=xpcall(function() scene(S,p) end,debug.traceback)
 love.graphics.setCanvas(old);love.graphics.pop()
 if not ok then p.error=tostring(err);p.paused=true;return nil,p.error end
 return p.canvas
end
function M.draw(S,game,x,y,w,h)
 local K=require("Kit");local s=K.scale
 local p=S.g3MinigamePreview
 if type(p)~="table" or p.game~=game or p.project~=S.project or p.data~=S.data then M.stop(S);M.start(S,game);p=S.g3MinigamePreview end
 if p.error then K.caption(x,y,p.error);return end
 if K.button(x,y,100*s,28*s,p.paused and "Play" or "Pause",{kind="good"}) then p.paused=not p.paused end
 if K.button(x+110*s,y,110*s,28*s,"Restart",{}) then p.frame=0;p.remainder=0 end
 if K.button(x+230*s,y,130*s,28*s,"Next frame",{}) then p.paused=true;M.step(S) end
 require("ChoicePicker").field(S,{x=x+370*s,y=y,w=130*s,h=28*s,ids={"0.5","1","2"},labels={["0.5"]="Half speed",["1"]="Normal speed",["2"]="Double speed"},current=tostring(p.speed),title="PLAYBACK SPEED",onPick=function(v) p.speed=tonumber(v) end})
 local canvas,err=M.render(S)
 if not canvas then K.caption(x,y+40*s,err);return end
 local scale=math.min(w/240,math.max(1,h-115*s)/160,4*s)
 love.graphics.setColor(1,1,1,1);love.graphics.draw(canvas,x,y+42*s,0,scale,scale)
 K.caption(x,y+h-55*s,"Frame "..p.frame.." / 359 - looping animation preview")
 K.caption(x,y+h-30*s,"Original artwork with an editor animation timeline. This is not playable game logic.")
end
return M
