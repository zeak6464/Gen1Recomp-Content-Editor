return function(data,root)
 local IO,State=require("ModIO"),require("State");local S=State.new();S.data=data;S.version="firered";S.project=State.blankProject("screens_test");S.project.game="firered"
 S.path=root.."/tests/content-editor/gen3-smoke/screens-project";assert(IO.ensureDirectory(S.path))
 assert(IO.writeText(S.path.."/manifest.json",'{"id":"screens_test","name":"Screens test","version":"1.0.0","entry":"main.lua","games":["gen3"]}'))
 local D,E=require("Gen3ScreenData"),require("Gen3Screens")
 local credits=assert(D.credits(S));assert(#credits==43 and credits[1].title=="Director" and credits[1].text=="Junichi Masuda",credits[1].title)
 for _,r in ipairs(D.areas) do local img=assert(D.image(S,"areas",r.id));assert(img:getWidth()==240 and img:getHeight()==160) end
 for _,r in ipairs(D.creditArt) do assert(D.image(S,"credits",r.id)) end
 local movie=assert(require("Gen3CreditsBuild").build(S,credits))
 local Player=require("Gen3CreditsMovie");local playback=Player.new(movie,false)
 local contact=love.graphics.newCanvas(960,800);local oldCanvas=love.graphics.getCanvas()
 love.graphics.setCanvas(contact);love.graphics.clear(0,0,0,1);love.graphics.setCanvas(oldCanvas)
 local sampled=0;local monCount=0;local mapCount=0
 for i,c in ipairs(movie.commands) do
  if c.op=="map" then mapCount=mapCount+1 end
  if c.op=="mon" then monCount=monCount+1 end
  Player.update(playback,math.min(c.frames/2,150)/60)
  if (c.op=="mon" or c.op=="map" or c.op=="ending") and sampled<20 then
   love.graphics.setCanvas(contact);love.graphics.push("all");love.graphics.translate((sampled%4)*240,math.floor(sampled/4)*160)
   Player.draw(playback,require("Gen3ScreensRuntime").image);love.graphics.pop();love.graphics.setCanvas(oldCanvas);sampled=sampled+1
  end
  Player.update(playback,(c.frames-math.min(c.frames/2,150))/60)
 end
 assert(playback.done and mapCount==13 and monCount==4,"Cinematic did not complete its native scene sequence")
 assert(IO.writeText(root.."/tests/content-editor/gen3-smoke/credits-cinematic.png",contact:newImageData():encode("png"):getString()))
 local fast=Player.new(movie,false);Player.update(fast,10000);assert(fast.done,"Long-frame playback stalled")
 local areas=E.defaults(S,"areas");assert(#areas==21)
 for _,r in ipairs(areas) do assert(r.map~="","Missing original arrival map: "..r.id) end
 for _,r in ipairs(areas) do if r.id=="viridian_forest" then assert(r.map=="FR_VIRIDIAN_FOREST","Forest preview selected an entrance gate") end end
 local first;for _,r in ipairs(areas) do if r.id=="mt_moon" then first=r end end
 assert(first and first.map~="");first.show="first"
 local image=love.image.newImageData(240,160);image:mapPixel(function() return .2,.7,.9,1 end)
 first.image=love.data.encode("string","base64",image:encode("png"):getString())
 local every=E.addArea(S);assert(every.custom and every.show=="off" and #S.project.gen3Screens.areas==22)
 local another=E.addArea(S);assert(another.id~=every.id,"Custom previews need unique visit-history IDs")
 E.payload(S,{areas={another}}) -- An unfinished preview must remain saveable.
 every.name="Custom route preview";every.image=first.image;every.map="FR_ROUTE1";every.show="every"
 local off=require("src.mods.Merge").deepCopy(first);off.id="off_test";off.map="FR_ROUTE2";off.show="off"
 S.project.gen3Screens={creditsStyle="pages",areas={first,every,off},credits={{title="TEST CREDITS",text="Test author",seconds=2,art="the_end"}}}
 assert(IO.save(S.path,S.project));assert(IO.load(S.path).gen3Screens.credits[1].text=="Test author")
 local fresh={};require("Gen3").load(fresh,data._gen3Read);assert(require("Gen3Mod").load(fresh,S.path))
 local F,Stack=require("src.core.game3.field"),require("src.ui.game3.stack");local old=F._session;local running=F.running;F.running=false;Stack.clear()
 F._session={map="FR_PALLET_TOWN"};F.update(0);F._session.map=first.map;F.update(0)
 local view=assert(Stack.top()).mod;assert(view.kind=="areas" and view.rows[1].image==first.image)
 local canvas=love.graphics.newCanvas(240,160);love.graphics.setCanvas(canvas);view.draw();love.graphics.setCanvas()
 local r,g,b=canvas:newImageData():getPixel(100,80);assert(g>.65 and b>.85 and r<.3,"Area replacement not rendered")
 view.update(10);assert(not Stack.busy());F._session.map="FR_PALLET_TOWN";F.update(0);F._session.map=first.map;F.update(0);assert(not Stack.busy(),"First-arrival preview repeated")
 for i=1,2 do
  F._session.map="FR_ROUTE1";F.update(0);local v=assert(Stack.top()).mod;assert(v.rows[1].id==every.id and v.rows[1].image==every.image)
  v.handleInput({wasPressed=function(_,k) return k=="a" end});assert(not Stack.busy())
  F._session.map="FR_ROUTE2";F.update(0);assert(not Stack.busy(),"Disabled area opened")
 end
 local H=require("src.ui.game3.hall_of_fame");local done=0;H.open=true;H._onDone=function() done=done+1 end;H.close()
 view=assert(Stack.top()).mod;assert(view.kind=="credits" and view.rows[1].title=="TEST CREDITS" and done==0)
 view.update(3);assert(done==1 and not Stack.busy());view.update(3);assert(done==1)
 require("src.mods.Runtime").reset();F._session=old;F.running=running
 S.project.gen3Screens.creditsEnabled=false
 local disabled=E.payload(S,S.project.gen3Screens);assert(not disabled.credits and S.project.gen3Screens.credits[1].title=="TEST CREDITS","Disable lost edits")
 -- Export and run the actual cinematic module, including deferred completion.
 S.project.gen3Screens={creditsStyle="cinematic",credits=require("src.mods.Merge").deepCopy(credits)}
 S.project.gen3Screens.credits[1].title="CUSTOM DIRECTOR"
 assert(IO.save(S.path,S.project))
 local rebuilt={};require("Gen3").load(rebuilt,data._gen3Read);assert(require("Gen3Mod").load(rebuilt,S.path))
 local A=require("src.core.game3.audio");local song,cry=A.playSong,A.playCry;A.playSong=function() end;A.playCry=function() end
 H.open=true;done=0;H._onDone=function() done=done+1 end;H.close()
 local cine=assert(Stack.top()).mod;assert(cine.cinematic,"Export used timed pages")
 local changed=false;for _,c in ipairs(cine.cinematic.payload.commands) do if c.row and c.row.title=="CUSTOM DIRECTOR" then changed=true end end;assert(changed,"Cinematic dropped edited text")
 cine.update(10000);assert(done==1 and not Stack.busy(),"Cinematic did not release Hall of Fame completion")
 A.playSong,A.playCry=song,cry;require("src.mods.Runtime").reset()
 local K=require("Kit");canvas=love.graphics.newCanvas(1360,860);S.project.gen3Screens=nil
 for _,kind in ipairs({"areas","credits"}) do
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.layout(1360,860);K.beginFrame(0,0,false,0)
  E.draw(S,20,20,1320,810,{markDirty=function() error("Browsing changed project") end},kind)
  K.endFrame();love.graphics.setCanvas();assert(IO.writeText(root.."/tests/content-editor/gen3-smoke/screens-"..kind..".png",canvas:newImageData():encode("png"):getString()))
 end
end
