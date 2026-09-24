local M={}
local modes={{id="credits",label="End credits"},{id="areas",label="Area previews"},{id="intro",label="Title / Intro"},{id="oak",label="Oak intro"},{id="playback",label="Animation preview"},{id="menus",label="Windows / borders"},{id="bag",label="Bag screens"},{id="party",label="Pokemon menu"},{id="summary",label="Pokemon summary"},{id="backgrounds",label="Battle backgrounds"},{id="minigames",label="Mini-games"},{id="battle",label="Battle"},
  {id="town",label="Town Map"},{id="fonts",label="Fonts"},{id="dex",label="Pokedex"},{id="trainer",label="Trainer Card"},
  {id="fame",label="Fame Checker"},{id="teachy",label="Teachy TV"},{id="naming",label="Naming"},{id="help",label="Help"},{id="overworld",label="Overworld sprites"},{id="banners",label="Location banners"},{id="all",label="All assets"}}
function M.draw(S,x,y,w,h,App)
  local scale=require("Kit").scale
  local ids,labels={},{}
  for _,mode in ipairs(modes) do ids[#ids+1]=mode.id;labels[mode.id]=mode.label end
  S.g3UiMode=S.g3UiMode or "intro"
  require("ChoicePicker").field(S,{x=x,y=y,w=math.min(w,340*scale),h=28*scale,current=S.g3UiMode,ids=ids,labels=labels,title="Choose a game screen",onPick=function(id)
    S.g3UiMode=id;S.g3AssetQuery="";S.g3AssetId=nil;S.g3AssetOffset=0
  end})
  local top=y+36*scale
  if S.g3UiMode=="banners" then require("Gen3Banners").draw(S,x,top,w,h-(top-y),App);return end
  if S.g3UiMode=="credits" or S.g3UiMode=="areas" then require("Gen3Screens").draw(S,x,top,w,h-(top-y),App,S.g3UiMode);return end
  if S.g3UiMode=="fame" then require("Gen3Fame").draw(S,x,top,w,h-(top-y),App);return end
  if S.g3UiMode=="teachy" then require("Gen3TeachyTv").draw(S,x,top,w,h-(top-y),App);return end
  if S.g3UiMode=="oak" then require("Gen3Oak").draw(S,x,top,w,h-(top-y),App);return end
  if S.g3UiMode=="minigames" then require("Gen3Minigames").draw(S,x,top,w,h-(top-y),App);return end
  if S.g3UiMode=="playback" then require("Gen3IntroPreview").draw(S,x,top,w,h-(top-y));return end
  if S.g3UiMode=="help" or S.g3UiMode=="dex" or S.g3UiMode=="town" then require("Gen3UiContent").draw(S,x,top,w,h-(top-y),App,S.g3UiMode);return end
  local function filter(path)
    local mode=S.g3UiMode
    if mode=="all" then return true end
    if mode=="overworld" then return path:match("/ow/%d+%.rgba$") end
    if mode=="intro" then return path:find("/intro/",1,true) end
    if mode=="menus" then return path:find("/chrome/",1,true) and not path:find("/fonts/",1,true) end
    if mode=="bag" then return path:find("/items/bag/",1,true) and not path:find("/icons/",1,true) end
    if mode=="party" then return path:find("/pokemon/party/",1,true) end
    if mode=="summary" then return path:find("/pokemon/summary/",1,true) end
    if mode=="backgrounds" then return path:find("/pokemon/battle/terrain",1,true) end
    if mode=="battle" then return path:find("/pokemon/battle",1,true) end
    if mode=="fonts" then return path:find("/fonts/",1,true) end
    if mode=="dex" then return path:find("/pokedex/",1,true) end
    if mode=="trainer" then return path:find("/trainer_card/",1,true) end
    if mode=="naming" then return path:find("/naming/",1,true) end
    if mode=="help" then return path:find("/help/",1,true) or path:find("/quest_log/",1,true) end
  end
  require("Gen3Assets").draw(S,x,top,w,h-(top-y),App,filter)
end
return M
