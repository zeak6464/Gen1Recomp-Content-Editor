local M={}
M.defaults={
  welcome = "Hello, there!\nGlad to meet you!\fWelcome to the world of POKéMON!\fMy name is OAK.\fPeople affectionately refer to me\nas the POKéMON PROFESSOR.\f",
  this_world = "This world…",
  inhabited = "…is inhabited far and wide by\ncreatures called POKéMON.\f",
  study = "For some people, POKéMON are pets.\nOthers use them for battling.\fAs for myself…\fI study POKéMON as a profession.\f",
  tell_me = "But first, tell me a little about\nyourself.\f",
  ask_gender = "Now tell me. Are you a boy?\nOr are you a girl?",
  your_name = "Let's begin with your name.\nWhat is it?\f",
  confirm_player = "Right…\nSo your name is {PLAYER}.",
  rival_intro = "This is my grandson.\fHe's been your rival since you both\nwere babies.\f…Erm, what was his name now?",
  rival_name_ask = "Your rival's name, what was it now?",
  confirm_rival = "…Er, was it {RIVAL}?",
  remember_rival = "That's right! I remember now!\nHis name is {RIVAL}!\f",
  lets_go = "{PLAYER}!\fYour very own POKéMON legend is\nabout to unfold!\fA world of dreams and adventures\nwith POKéMON awaits! Let's go!",
}
M.order={"welcome","this_world","inhabited","study","tell_me","ask_gender","your_name","confirm_player","rival_intro","rival_name_ask","confirm_rival","remember_rival","lets_go"}
M.labels={welcome="Welcome and professor introduction",this_world="Introducing the Pokemon world",inhabited="Showing a Pokemon",study="The professor's research",tell_me="Introducing the player",ask_gender="Choosing boy or girl",your_name="Asking your name",confirm_player="Confirming your name",rival_intro="Introducing your rival",rival_name_ask="Asking your rival's name",confirm_rival="Confirming the rival's name",remember_rival="Remembering the rival",lets_go="Starting the adventure"}
function M.scene(S,x,y,w,h,App)
  local K,C=require("Kit"),require("ChoicePicker");local scale=K.scale
  local settings=S.project.gen3OakScene or {};local left=math.min(350*scale,w*.36)
  local function edit(key,value) S.project.gen3OakScene=S.project.gen3OakScene or {};S.project.gen3OakScene[key]=value;App.markDirty() end
  K.caption(x,y,"Pokemon shown by the professor");local yy=y+26*scale
  local current="NIDORAN_F"
  for id,mon in pairs(S.data.pokemon or {}) do if mon.index==settings.species then current=id end end
  require("SpeciesPicker").field(S,{x=x,y=yy,w=left,h=30*scale,current=current,onPick=function(id)
    local mon=S.project.pokemon[id] or S.data.pokemon[id];if mon then edit("species",mon.index) end
  end});yy=yy+44*scale
  K.caption(x,yy,"Text speed");yy=yy+26*scale
  C.field(S,{x=x,y=yy,w=left,h=30*scale,ids={"0","1","2"},labels={["0"]="Slow",["1"]="Normal",["2"]="Fast"},current=tostring(settings.textSpeed or 1),onPick=function(id) edit("textSpeed",tonumber(id)) end});yy=yy+44*scale
  K.caption(x,yy,"Opening help pages");yy=yy+26*scale
  C.field(S,{x=x,y=yy,w=left,h=30*scale,ids={"show","skip"},labels={show="Show controls and advice",skip="Start with the professor"},current=settings.skipGuides and "skip" or "show",onPick=function(id) edit("skipGuides",id=="skip") end});yy=yy+48*scale
  if K.button(x,yy,left,30*scale,"Play / restart intro",{kind="good"}) then require("Gen3IntroPreview").play(S,"oak") end;yy=yy+42*scale
  local p=S.g3IntroPreview
  if p and p.kind=="oak" then
    if K.button(x,yy,left,28*scale,p.paused and "Resume" or "Pause",{}) then p.paused=not p.paused end;yy=yy+38*scale
    for i,key in ipairs({"a","b","up","down","left","right","start","select"}) do
      local col=(i-1)%2;local row=math.floor((i-1)/2)
      if K.button(x+col*(left/2+2*scale),yy+row*34*scale,left/2-4*scale,28*scale,key:upper(),{}) then p.keys=p.keys or {};p.keys[key]=true;p.paused=false end
    end
    local canvas=require("Gen3IntroPreview").render(S)
    if canvas then local zoom=math.min((w-left-24*scale)/240,(h-70*scale)/160);love.graphics.setColor(1,1,1,1);love.graphics.draw(canvas,x+left+24*scale,y,0,zoom,zoom) end
    if p.error then K.caption(x,y+h-28*scale,K.ellipsize("micro",p.error,w))
    elseif p.oak and p.oak.result then K.caption(x+left+24*scale,y+h-28*scale,"Intro finished. Restart to play again.") end
  else K.caption(x+left+24*scale,y,"Play the full intro, then use the buttons to advance and choose names.") end
  K.caption(x,y+h-52*scale,"Restart the preview after changing settings or dialogue.")
end
function M.draw(S,x,y,w,h,App)
  local K,C=require("Kit"),require("ChoicePicker");local scale=K.scale
  local top=require("RegList").modeChips(S,"g3OakMode",{{id="scene",label="Full intro"},{id="dialogue",label="Dialogue"},{id="artwork",label="Artwork"}},x,y,scale)
  h=h-(top-y);y=top
  if S.g3OakMode=="artwork" then
    return require("Gen3Assets").draw(S,x,y,w,h,App,function(path)
      local name=path:match("/intro/([^/]+)%.png$")
      return name and (name=="oak" or name=="boy" or name=="girl" or name=="rival" or name=="oak_speech_bg" or name=="platform" or name=="ball_poke" or name:match("^pikachu_") or name:match("^controls_page"))
    end)
  end
  if S.g3OakMode~="dialogue" then return M.scene(S,x,y,w,h,App) end
  S.g3OakLine=S.g3OakLine or "welcome";local id=S.g3OakLine
  C.field(S,{x=x,y=y,w=w,h=30*scale,ids=M.order,labels=M.labels,current=id,onPick=function(v) S.g3OakLine=v;S.g3OakPage=1 end});y=y+42*scale
  K.caption(x,y,"Edit the speech. Keep {PLAYER} and {RIVAL} where names should appear.");y=y+30*scale
  K.caption(x,y,"Use \\n for a new line and \\f for the next dialogue page.");y=y+30*scale
  local old=(S.project.gen3Oak or {})[id] or M.defaults[id]
  local escaped=old:gsub("\n","\\n"):gsub("\f","\\f")
  local edited=K.textfield("g3_oak_text_"..id,x,y,w,40*scale,escaped,"");y=y+52*scale
  if edited~=escaped then
    S.project.gen3Oak=S.project.gen3Oak or {};S.project.gen3Oak[id]=edited:gsub("\\n","\n"):gsub("\\f","\f");App.markDirty()
  end
  local text=(S.project.gen3Oak or {})[id] or M.defaults[id]
  require("Gen3Dialog").preview(S,text,x,y,math.min(w,700*scale),{page=S.g3OakPage or 1})
  y=y+180*scale
  for i,d in ipairs({-1,1}) do if K.button(x+(i-1)*150*scale,y,140*scale,28*scale,d==-1 and "Previous page" or "Next page",{}) then S.g3OakPage=select(1,require("Gen3Dialog").step(text,S.g3OakPage,d)) end end
  y=y+40*scale
  if K.button(x,y,220*scale,28*scale,"Restore this original line",{}) then if S.project.gen3Oak then S.project.gen3Oak[id]=nil;App.markDirty() end end
  y=y+40*scale;K.caption(x,y,"Use Artwork to change portraits, backgrounds and intro graphics.")
end
function M.emit(p,encode,out)
  if not next(p.gen3Oak or {}) and not next(p.gen3OakScene or {}) then return end
  local settings=p.gen3OakScene or {}
  assert(settings.species==nil or type(settings.species)=="number" and settings.species>0 and settings.species%1==0,"Invalid intro Pokemon")
  assert(settings.textSpeed==nil or settings.textSpeed==0 or settings.textSpeed==1 or settings.textSpeed==2,"Invalid intro text speed")
  local source=assert(love.filesystem.read("tools/content-editor/Gen3OakRuntime.lua"))
  out[#out+1]="  local oakScene=(function()\n"..source.."\nend)()\n  oakScene.install(mod,"..encode(settings)..")"
  for key,text in pairs(p.gen3Oak or {}) do assert(M.defaults[key] and type(text)=="string","Invalid Oak speech line") end
  out[#out+1]="  local oakLines="..encode(p.gen3Oak or {})
  out[#out+1]=[=[
  local Scene=require("src.ui.game3.new_game_scene")
  local Runtime=require("src.mods.Runtime")
  if not Scene._editorOakBridge then
    Scene._editorOakBridge=true;local original=Scene.oakPrint
    Scene.oakPrint=function(self,key,speed) return Runtime.call("editor.gen3.oakPrint",original,self,key,speed) end
  end
  mod.hooks:wrap("editor.gen3.oakPrint",function(proceed,scene,key,speed)
    return proceed(scene,oakLines[key] or key,speed)
  end)
]=]
end
return M
