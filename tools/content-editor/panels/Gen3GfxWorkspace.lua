local M={}
function M.draw(S,x,y,w,h,App)
  local top=require("RegList").modeChips(S,"g3GfxMode",{{id="pokemon",label="Pokemon"},
    {id="ow",label="Overworld"},{id="trainers",label="Trainers"},{id="native",label="Tilesets"},
    {id="field_effects",label="Field effects"}},x,y,require("Kit").scale)
  if S.g3GfxMode=="pokemon" then
    return require("Gen3Sprites").draw(S,x,top,w,h-(top-y),App)
  end
  require("Gen3Assets").draw(S,x,top,w,h-(top-y),App,function(path)
    return path:find("/"..S.g3GfxMode.."/",1,true)
  end)
end
return M
