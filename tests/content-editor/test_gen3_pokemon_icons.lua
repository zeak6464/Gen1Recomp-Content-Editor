-- Run with LÖVE: EDITOR_TEST_ROOT=<repo> love tests/content-editor/icon-smoke
local files={}
local failWrites=false
package.loaded.ModIO={
  readText=function(path) return files[path] end,
  writeText=function(path,bytes)
    if failWrites then return nil,"Write denied" end
    files[path]=bytes;return true
  end,
  ensureDirectory=function() return true end,
}
local Icons=require("Gen3PokemonIcons")
local original=love.image.newImageData(32,64)
original:mapPixel(function() return 1,0,0,1 end)
local base=original:getString()
local S={path="mod",project={},data={_editorGen3=true,_gen3Read=function() return base end}}
local key=Icons.path(25)
assert(Icons.read(S,25)==base)
local replacement=love.image.newImageData(32,64)
replacement:mapPixel(function(x,y) return 0,y<32 and 1 or 0,y>=32 and 1 or 0,1 end)
files.input=replacement:encode("png"):getString()
assert(Icons.import(S,25,"input"))
assert(Icons.read(S,25)==replacement:getString())
assert(S.project.gen3Assets[key].height==64)
local exported=assert(Icons.export(S,25))
local decoded=love.image.newImageData(love.filesystem.newFileData(files[exported],"out.png"))
assert(decoded:getString()==replacement:getString(),"Export lost frame pixels")
-- Preview must use the override and refresh after a second import at the same path.
local Preview=require("Preview")
local savedDraw=love.graphics.draw
local shown
love.graphics.draw=function(img) shown=img end
Preview.drawPokemonIcon(S,{index=25},0,0,32,32)
local first=shown
assert(first and first:getHeight()==64)
local single=love.image.newImageData(32,32)
single:mapPixel(function() return 1,1,0,1 end)
files.single=single:encode("png"):getString()
assert(Icons.import(S,25,"single"))
Preview.drawPokemonIcon(S,{index=25},0,0,32,32)
assert(shown~=first and shown:getHeight()==32,"Preview retained previous import")
local override=S.project.gen3Assets[key]
files.bad=love.image.newImageData(64,32):encode("png"):getString()
local ok,err=Icons.import(S,25,"bad")
assert(not ok and err:find("32 × 32",1,true))
assert(S.project.gen3Assets[key]==override,"Bad dimensions changed override")
files.broken="not a PNG"
assert(not Icons.import(S,25,"broken"))
failWrites=true
assert(not Icons.import(S,25,"input"))
assert(S.project.gen3Assets[key]==override,"Failed write changed override")
failWrites=false
-- Exercise the same exported runtime bridge used by saved mods.
local hook
local Cache={read=function() return base end}
package.loaded["src.import.CacheFs"]=Cache
package.loaded["src.mods.Runtime"]={call=function(_,proceed,path) return hook(proceed,path) end}
local mod={hooks={wrap=function(_,_,fn) hook=fn end},events={on=function() end},read=function(_,path) return files["mod/"..path] end}
local native={assets=S.project.gen3Assets,items={},help={},animations={},audio={}}
assert(loadstring("return function(native,mod) "..require("Gen3Native").source.." end"))()(native,mod)
assert(Cache.read(key)==single:getString(),"Runtime did not receive replacement")
assert(Cache.read("firered/"..key)==single:getString())
local beforeRevert=shown
Icons.revert(S,25)
assert(Icons.read(S,25)==base)
Preview.drawPokemonIcon(S,{index=25},0,0,32,32)
assert(shown~=beforeRevert and shown:getHeight()==64,"Revert did not refresh preview")
love.graphics.draw=savedDraw
local missing={project={},data={}}
-- Shiny preview assets are independent of normal icons and their cache entries.
assert(Icons.import(S,25,"input",true))
assert(Icons.read(S,25)==base,"Shiny import overwrote normal icon")
assert(Icons.read(S,25,true)==replacement:getString())
love.graphics.draw=function(img) shown=img end
Preview.drawPokemonIcon(S,{index=25},0,0,32,32,nil,nil,true)
local shinyImage=shown
Preview.drawPokemonIcon(S,{index=25},0,0,32,32,nil,nil,false)
assert(shown~=shinyImage,"Normal toggle retained shiny image")
Preview.drawPokemonIcon(S,{index=25},0,0,32,32,nil,nil,true)
assert(shown==shinyImage,"Shiny toggle failed to restore shiny image")
local shinyExport=assert(Icons.export(S,25,true))
assert(shinyExport:find('/shiny/',1,true))
assert(love.image.newImageData(love.filesystem.newFileData(files[shinyExport],"shiny.png")):getString()==replacement:getString())
Icons.revert(S,25,true)
assert(Icons.read(S,25,true)==base,"Shiny revert did not fall back to normal")
love.graphics.draw=savedDraw
local forms={path="mod",project={pokemon={WINTER={index=440},LETTER_B={index=441}},gen3Forms={
  PIKACHU={forms={{species="PIKACHU"},{species="WINTER"}}},
  UNOWN={forms={{species="UNOWN"},{species="LETTER_B"}}},
}},data={pokemon={PIKACHU={index=25},UNOWN={index=201}},_gen3Read=function(path)
  if path==Icons.path(25) then return base end
  if path==Icons.path(413) then return single:getString() end
end}}
assert(Icons.read(forms,440)==base,"Custom form lost inherited icon")
assert(Icons.read(forms,441)==single:getString(),"Unown form lost letter icon")
-- Real FireRed extracts stop at 411: extra Unown artwork slots have no icon file.
forms.data._gen3Read=function(path)
  if path==Icons.path(201) or path==Icons.path(25) then return base end
end
assert(Icons.read(forms,441)==base,"Missing letter icon must fall back to base Unown")
assert(Icons.import(forms,201,"single",true))
assert(Icons.read(forms,441,true)==single:getString(),"Form did not inherit shiny base icon")
assert(Icons.read(forms,441)==base,"Shiny inheritance changed normal icon")
assert(Icons.import(forms,441,"input",true))
assert(Icons.read(forms,441,true)==replacement:getString(),"Form shiny override was ignored")
Icons.revert(forms,441,true)
assert(Icons.read(forms,441,true)==single:getString(),"Form shiny revert lost inheritance")
assert(Icons.read(forms,422)==base,"Native Unown preview must fall back to base Unown")
forms.data._editorGen3=true
shown=nil
love.graphics.draw=function(img) shown=img end
Preview.drawPokemonIcon(forms,forms.project.pokemon.LETTER_B,0,0,32,32)
assert(shown and shown:getHeight()==64,"Unown form preview still shows a missing icon")
love.graphics.draw=savedDraw
assert(Icons.import(forms,440,"single"))
assert(Icons.read(forms,440)==single:getString(),"Form override was ignored")
Icons.revert(forms,440)
assert(Icons.read(forms,440)==base,"Form revert lost inherited icon")
assert(not Icons.import(missing,25,"input"))
assert(not Icons.export(missing,25))
-- Draw the real controls and exercise their click handlers.
local K=require("Kit")
K.layout(1360,860)
local dirty=0
local App={markDirty=function() dirty=dirty+1 end,pickFile=function(_,_,callback) callback("input") end}
local canvas=love.graphics.newCanvas(640,140)
love.graphics.setCanvas({canvas,stencil=true})
K.beginFrame(25,25,true,0)
Icons.drawControls(S,25,App,20,20,580,32,1)
K.endFrame()
assert(dirty==1 and S.project.gen3Assets[key],"Import button did not register replacement")
K.beginFrame(450,25,true,0)
Icons.drawControls(S,25,App,20,20,580,32,1)
K.endFrame()
assert(dirty==2 and not S.project.gen3Assets[key],"Revert button did not remove replacement")
K.beginFrame(450,25,true,0)
Icons.drawControls(S,25,App,20,20,580,32,1)
K.endFrame()
assert(dirty==2,"Revert should be disabled for an original icon")
love.graphics.setCanvas()
for _,path in ipairs({"Gen3ContentForms.lua","Gen3Native.lua","Preview.lua","panels/Gen3Sprites.lua"}) do
  assert(loadfile(os.getenv("EDITOR_TEST_ROOT").."/tools/content-editor/"..path))
end

