return function(data,root)
  local IO,State=require("ModIO"),require("State");local S=State.new()
  S.data=data;S.version="firered";S.project=State.blankProject("fame_test");S.project.game="firered"
  S.path=root.."/tests/content-editor/gen3-smoke/fame-project";assert(IO.ensureDirectory(S.path))
  assert(IO.writeText(S.path.."/manifest.json",'{"id":"fame_test","name":"Fame test","version":"1.0.0","entry":"main.lua","games":["gen3"]}'))
  local defaults=assert(require("Gen3FameData").load(S));assert(#defaults==16)
  for _,r in ipairs(defaults) do assert(#r.facts==6 and #r.message>10);for _,f in ipairs(r.facts) do assert(#f.question>5 and #f.text>5 and #f.location>0 and #f.source>0) end end
  assert(defaults[1].facts[1].text:find("RESEARCH LAB",1,true));assert(defaults[16].name=="Giovanni")
  S.project.gen3Fame=require("src.mods.Merge").deepCopy(defaults)
  local rows=S.project.gen3Fame;rows[1].name="Professor Test";rows[1].facts[1].text="A changed fact.\fA second page for {PLAYER}."
  require("Gen3Fame").validate(rows)
  -- Existing saves lack the background/source-icon metadata: preserve their edits
  -- while enriching the exported viewer from ROM data.
  rows[1].background=nil
  for _,r in ipairs(rows) do for _,f in ipairs(r.facts) do f.graphics=nil end end
  assert(IO.save(S.path,S.project));assert(IO.load(S.path).gen3Fame[1].facts[1].text==rows[1].facts[1].text)
  local fresh={};require("Gen3").load(fresh,data._gen3Read);assert(require("Gen3Mod").load(fresh,S.path))
  local R=require("Gen3FameRuntime");local F=require("src.core.game3.field");local old=F._session
  local session={flags={},vars={},party={},playerName="AMANDA"};F._session=session
  local Native=require("src.core.game3.scripting.natives");local ctx={specialVars={[0x8004]=0,[0x8005]=0}}
  Native.special(ctx,371);local p=R.progress(session,"fame_test")["1"]
  assert(p.facts["1"] and p.state==1 and ctx.specialVars[0x8005]==1)
  assert(R.personOpen(rows[1],session,p) and not R.messageOpen(rows[1],session,p))
  for j=1,5 do ctx.specialVars[0x8005]=j;Native.special(ctx,371) end
  assert(R.messageOpen(rows[1],session,p));ctx.specialVars[0x8005]=2;Native.special(ctx,372);assert(p.state==2)
  ctx.specialVars[0x8005]=0;Native.special(ctx,371);assert(p.state==2,"Fact unlock downgraded portrait")
  local Json=require("src.link.Json");local restored=Json.decode(Json.encode(session.modData));assert(restored.fame_test.fameChecker["1"].facts["6"])
  assert(not R.available({unlock="flag",flag=20},session));session.flags[20]=true;assert(R.available({unlock="flag",flag=20},session))
  local Item=require("src.core.game3.item_use");assert(Item.useField(session,{},"FAME_CHECKER"))
  local Stack=require("src.ui.game3.stack");local view=assert(Stack.top()).mod;assert(view.rows[1].name=="Professor Test");assert(view.rows[1].background and view.rows[1].facts[1].graphics)
  assert(view.rows[1].facts[1].text==rows[1].facts[1].text)
  local screen=love.graphics.newCanvas(240,160);love.graphics.setCanvas(screen);view.draw();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/gen3-smoke/fame-game.png",screen:newImageData():encode("png"):getString()))
  local function key(k) return {wasPressed=function(_,v) return k==v end} end
  view.handleInput(key("a"));assert(view.focus=="facts");view.handleInput(key("a"));assert(view.page==2);view.handleInput(key("right"));assert(view.fact==2 and view.page==1)
  view.handleInput(key("b"));assert(view.focus=="people");view.handleInput(key("b"));assert(not Stack.has("editor_fame_checker"))
  local reference={rows=defaults,person=5,fact=2,page=2,session={},progress={}}
  for i=1,8 do reference.progress[tostring(i)]={state=2,facts={}};for j=1,5 do reference.progress[tostring(i)].facts[tostring(j)]=true end end
  assert(#R.visible(reference)==8,"Locked characters appeared in the list")
  love.graphics.setCanvas(screen);R.draw(reference);love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/gen3-smoke/fame-native-layout.png",screen:newImageData():encode("png"):getString()))
  reference.person=8;R.draw(reference);assert(reference.scroll>0,"Character list did not scroll")
  R.input(reference,key("up"));assert(reference.person==7);R.input(reference,key("right"));R.input(reference,key("down"));assert(reference.fact==4)
  R.input(reference,key("select"));assert(reference.fact==7);R.input(reference,key("select"));assert(reference.fact==1)
  require("src.mods.Runtime").reset();local before=p.state;ctx.specialVars[0x8005]=1;Native.special(ctx,372,{log=function() end});assert(p.state==before)
  F._session=old
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  K.layout(1360,860);S.g3FamePart=2
  for i=1,2 do love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1);K.beginFrame(0,0,false,0);require("Gen3Fame").draw(S,20,20,1320,810,{markDirty=function() end});K.endFrame();love.graphics.setCanvas() end
  assert(IO.writeText(root.."/tests/content-editor/gen3-smoke/fame-editor.png",canvas:newImageData():encode("png"):getString()))
end
