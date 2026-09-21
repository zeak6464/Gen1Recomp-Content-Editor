local M={}
local Data=require("Gen3ScreenData")
local Copy=require("src.mods.Merge").deepCopy
local encodedCache=setmetatable({},{__mode="k"})
local function encoded(image)
 if not encodedCache[image] then encodedCache[image]=love.data.encode("string","base64",image:encode("png"):getString()) end
 return encodedCache[image]
end
function M.addArea(S)
 S.project.gen3Screens=S.project.gen3Screens or {}
 local config=S.project.gen3Screens
 config.areas=config.areas or Copy(M.defaults(S,"areas"))
 local used={};for _,r in ipairs(config.areas) do used[r.id]=true end
 local n=1;while used["custom_area_"..n] do n=n+1 end
 local row={id="custom_area_"..n,custom=true,name="New area",map="",show="off",seconds=4}
 config.areas[#config.areas+1]=row;config.areasEnabled=true
 S.g3Screens_areas=#config.areas;S.g3ScreensPlaying=false
 return row
end
function M.defaults(S,kind)
 if kind=="credits" then return Data.credits(S) end
 local rows={};local keys=require("RegList").sortedKeys(S.data.maps or {})
 for _,rec in ipairs(Data.areas) do
  local row={id=rec.id,name=rec.name,map="",show="first",seconds=4}
  local prefix="_"..rec.id:upper()
  local bestRank=-1
  for _,id in ipairs(keys) do
   local at=id:find(prefix,1,true)
   if at and (at+#prefix>#id or id:sub(at+#prefix,at+#prefix)=="_") then
    local rank=id=="FR"..prefix and 100 or (id:match("_EXTERIOR$") or id:match("_CENTER$")) and 80 or id:match("_1F$") and 60 or 0
    if rank>bestRank then row.map=id;bestRank=rank end
   end
  end
  if row.map=="" then row.show="off" end
  rows[#rows+1]=row
 end
 return rows
end
function M.validate(config)
 for _,kind in ipairs({"credits","areas"}) do
  local rows=config[kind]
  if rows then
   assert(type(rows)=="table" and #rows>0 and #rows<=200,"Choose between 1 and 200 screens")
   for _,r in ipairs(rows) do
    assert(type(r.seconds)=="number" and r.seconds>=1 and r.seconds<=60,"Screen duration must be 1–60 seconds")
    if kind=="areas" then assert(r.show=="first" or r.show=="every" or r.show=="off","Choose when to show this area")
     assert(r.show=="off" or type(r.map)=="string" and r.map~="","Choose an arrival map")
    else assert(type(r.title)=="string" and type(r.text)=="string" and #r.title<=2000 and #r.text<=8000,"Credit text is too long") end
    if r.image then
     local img=love.image.newImageData(love.filesystem.newFileData(love.data.decode("string","base64",r.image),"screen.png"))
     assert(img:getWidth()==240 and img:getHeight()==160,"Screen replacements must be 240 x 160")
    end
   end
  end
 end
end
function M.payload(S,config)
 M.validate(config);local result=Copy(config);result.art={}
 for _,kind in ipairs({"credits","areas"}) do if config[kind.."Enabled"]==false then result[kind]=nil end end
 for _,r in ipairs(result.areas or {}) do
  if r.show~="off" and not r.image and not r.custom then r.image=encoded(assert(Data.image(S,"areas",r.id))) end
 end
 for _,r in ipairs(result.credits or {}) do
  if not r.image and r.art and r.art~="none" and not result.art[r.art] then result.art[r.art]=encoded(assert(Data.image(S,"credits",r.art))) end
 end
 if result.credits and config.creditsStyle~="pages" then result.movie=require("Gen3CreditsBuild").build(S,result.credits) end
 return result
end
function M.emit(p,encode,out)
 if not p.gen3Screens then return end
 local payload=M.payload({project=p,data={}},p.gen3Screens)
 out[#out+1]="local creditsMovie=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3CreditsMovie.lua")).."\nend)()\nlocal screens=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3ScreensRuntime.lua")).."\nend)()\nscreens.movie=creditsMovie\nscreens.install(mod,"..encode(payload)..")"
end
function M.draw(S,x,y,w,h,App,kind)
 local K,C,IO=require("Kit"),require("ChoicePicker"),require("ModIO");local s=K.scale;local fh=28*s
 local defaults,err=M.defaults(S,kind);if not defaults then K.caption(x,y,tostring(err));return end
 local config=S.project.gen3Screens or {};local rows=config[kind] or defaults
 local key="g3Screens_"..kind;local selected=math.min(S[key] or 1,#rows)
 if S.g3ScreensPlaying==kind and not S._creditsMovie and love.timer.getTime()-(S.g3ScreensStarted or 0)>=(rows[selected].seconds or 4) then
  selected=selected%#rows+1;S[key]=selected;S.g3ScreensStarted=love.timer.getTime()
 end
 local row=rows[selected]
 local function edit()
  S.project.gen3Screens=S.project.gen3Screens or {};local c=S.project.gen3Screens
  S._creditsMovie=nil;S.g3ScreensPlaying=false;c[kind]=c[kind] or Copy(defaults);c[kind.."Enabled"]=true;App.markDirty();return c[kind][selected],c[kind]
 end
 local ids,labels={},{};for i,r in ipairs(rows) do ids[i]=i;labels[i]=kind=="areas" and r.name or i..". "..r.title:gsub("\n"," / ") end
 C.field(S,{x=x,y=y,w=w*.62,h=fh,ids=ids,labels=labels,current=selected,title=kind=="areas" and "Choose an area" or "Choose a credits page",onPick=function(v) S[key]=v;S.g3ScreensPlaying=false;S._creditsMovie=nil end})
 if K.button(x+w*.65,y,w*.35,fh,config[kind] and config[kind.."Enabled"]~=false and "Disable in game" or "Enable in game",{}) then
  if config[kind] and config[kind.."Enabled"]~=false then config[kind.."Enabled"]=false;App.markDirty() else edit() end
 end
 y=y+40*s;h=h-40*s
 local fw=w*.54;local px=x+w*.58;local scale=math.min((w*.42)/240,(h-100*s)/160,3)
 local image,art
 if row.image then image=row.image elseif not row.custom then
  local img,e=Data.image(S,kind,kind=="areas" and row.id or row.art)
  if img then image=encoded(img) elseif row.art~="none" then err=e end
 end
 local view=Copy(row);view.image=image
 -- Ground sheets use the same frame crop as the in-game credits renderer.
 if kind=="credits" and not row.image then view.image=nil;art={[row.art]=image} end
 S._g3ScreensCanvas=S._g3ScreensCanvas or love.graphics.newCanvas(240,160)
 local g=love.graphics;local old=g.getCanvas();g.push("all");g.setCanvas(S._g3ScreensCanvas);g.origin();g.setScissor()
 if kind=="credits" and S._creditsMovie then
  local now=love.timer.getTime()
  if S.g3ScreensPlaying==kind then require("Gen3CreditsMovie").update(S._creditsMovie,math.min(.25,now-(S._creditsMovieTime or now))) end
  S._creditsMovieTime=now
  require("Gen3CreditsMovie").draw(S._creditsMovie,require("Gen3ScreensRuntime").image)
 else require("Gen3ScreensRuntime").draw(view,kind,art) end
 if old then g.setCanvas({old,stencil=true}) else g.setCanvas() end;g.pop();g.setColor(1,1,1,1)
 S._g3ScreensCanvas:setFilter("nearest","nearest");g.draw(S._g3ScreensCanvas,px,y,0,scale,scale)
 if err then K.caption(px,y+160*scale+8*s,tostring(err)) end
 local fy=y
 local function field(label,property)
  K.caption(x,fy,label);fy=fy+22*s
  local v=K.textfield(key..selected..property,x,fy,fw,fh,tostring(row[property] or ""):gsub("\n","\\n"),"")
  local decoded=v:gsub("\\n","\n");if decoded~=row[property] then edit()[property]=decoded end;fy=fy+40*s
 end
 if kind=="areas" then
  field("Area name","name")
  K.caption(x,fy,"Show when arriving on this map");fy=fy+23*s
  local mapSet={};for id in pairs(S.data.maps or {}) do mapSet[id]=true end;for id in pairs(S.project.maps or {}) do mapSet[id]=true end
  local maps=require("RegList").sortedKeys(mapSet);local names={};for _,id in ipairs(maps) do names[id]=require("Gen3Labels").map(id) end
  C.field(S,{x=x,y=fy,w=fw,h=fh,current=row.map,ids=maps,labels=names,title="Arrival map",onPick=function(v) edit().map=v end});fy=fy+40*s
  C.field(S,{x=x,y=fy,w=fw,h=fh,current=row.show,ids={"first","every","off"},labels={first="First arrival per save",every="Every arrival",off="Do not show"},title="When to show",onPick=function(v) edit().show=v end});fy=fy+40*s
 else
  field("Heading (use \\n for a new line)","title");field("Remaining credit lines (use \\n for a new line)","text")
  local choices,names={"none"},{none="Black background"};for _,r in ipairs(Data.creditArt) do choices[#choices+1]=r.id;names[r.id]=r.name end
  C.field(S,{x=x,y=fy,w=fw,h=fh,current=row.art,ids=choices,labels=names,title="Credits artwork",onPick=function(v) local r=edit();r.art=v;r.image=nil end});fy=fy+40*s
 end
 local times={1,2,3,4,5,6,8,10,15,20,30,60};local labels2={};if row.seconds%1~=0 then times[#times+1]=row.seconds end;for _,n in ipairs(times) do labels2[n]=n.." seconds" end
 C.field(S,{x=x,y=fy,w=fw,h=fh,current=row.seconds,ids=times,labels=labels2,title="Screen duration",onPick=function(v) edit().seconds=v end});fy=fy+40*s
 if K.button(x,fy,fw*.48,fh,"Import screen PNG",{}) then
  App.pickFile("240 x 160 screen","PNG (*.png)|*.png",function(path)
   local ok,img=pcall(function() return love.image.newImageData(love.filesystem.newFileData(assert(IO.readText(path)),"screen.png")) end)
   if not ok or img:getWidth()~=240 or img:getHeight()~=160 then S.status="Choose a 240 x 160 PNG";return end
   edit().image=encoded(img);S.status="Screen replaced. Save to apply in game."
  end)
 end
 if K.button(x+fw*.52,fy,fw*.48,fh,row.custom and "Clear artwork" or "Revert artwork",{}) then edit().image=nil end;fy=fy+40*s
 if K.button(x,fy,fw,fh,"Export preview PNG",{}) then
  local dest=S.path.."/assets/screen-exports/"..kind.."-"..selected..".png";IO.ensureDirectory(dest:match("^(.*)/"))
  local ok,e=IO.writeText(dest,S._g3ScreensCanvas:newImageData():encode("png"):getString());S.status=ok and "Exported "..dest or tostring(e)
 end;fy=fy+40*s
 if kind=="areas" then
  if K.button(x,fy,fw*.48,fh,"New area preview",{kind="good"}) then M.addArea(S);App.markDirty();S.status="Choose an arrival map, import a 240 x 160 PNG, then choose when to show it." end
  if row.custom and K.button(x+fw*.52,fy,fw*.48,fh,"Delete preview",{kind="danger"}) then local _,r=edit();table.remove(r,selected);S[key]=math.min(selected,#r) end
 end
 if kind=="credits" then
  if K.button(x,fy,fw*.48,fh,"Add page",{}) then local _,r=edit();r[#r+1]={title="New credit",text="Your name",seconds=6,art="none"};S[key]=#r end
  if #rows>1 and K.button(x+fw*.52,fy,fw*.48,fh,"Delete page",{kind="danger"}) then local _,r=edit();table.remove(r,selected);S[key]=math.min(selected,#r) end
  fy=fy+40*s
  if K.button(x,fy,fw*.48,fh,"Move earlier",{}) and selected>1 then local _,r=edit();r[selected],r[selected-1]=r[selected-1],r[selected];S[key]=selected-1 end
  if K.button(x+fw*.52,fy,fw*.48,fh,"Move later",{}) and selected<#rows then local _,r=edit();r[selected],r[selected+1]=r[selected+1],r[selected];S[key]=selected+1 end
 end
 local by=y+160*scale+12*s
 if K.button(px,by,130*s,fh,S.g3ScreensPlaying==kind and "Pause preview" or "Play preview",{}) then
  S.g3ScreensPlaying=S.g3ScreensPlaying==kind and false or kind;S.g3ScreensStarted=love.timer.getTime()
  if kind=="credits" and config.creditsStyle~="pages" and (not S._creditsMovie or S._creditsMovie.done) then
   local ok,movie=pcall(require("Gen3CreditsBuild").build,S,rows)
   if ok then S._creditsMovie=require("Gen3CreditsMovie").new(movie,false);S._creditsMovieTime=love.timer.getTime()
   else S.status="Credits preview: "..tostring(movie);S.g3ScreensPlaying=false end
  end
 end
 if K.button(px+140*s,by,100*s,fh,"Next screen",{}) then if kind=="credits" and S._creditsMovie then require("Gen3CreditsMovie").next(S._creditsMovie) else S[key]=selected%#rows+1 end;S.g3ScreensStarted=love.timer.getTime() end
 K.caption(px,by+42*s,kind=="areas" and "A / B skips the area screen in game." or "Plays after Hall of Fame. A / B advances.")
 if kind=="credits" then
  C.field(S,{x=px,y=by+68*s,w=w*.42,h=fh,current=config.creditsStyle or "cinematic",ids={"cinematic","pages"},labels={cinematic="Original cinematic sequence",pages="Simple timed pages"},title="Credits playback",onPick=function(v)
   edit();S.project.gen3Screens.creditsStyle=v;S._creditsMovie=nil;S.g3ScreensPlaying=false
  end})
 end
end
return M
