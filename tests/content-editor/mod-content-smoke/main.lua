local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"
  ..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local function report(message)
  local f=assert(io.open(root.."/tests/content-editor/mod-content-smoke/result.txt","wb"))
  f:write(message);f:close()
end
love.errorhandler=function(err) report(debug.traceback(tostring(err)));return function() return 1 end end
function love.load()
  local ffi=require("ffi")
  ffi.cdef("int PHYSFS_mount(const char*,const char*,int);")
  local lib=ffi.load(root.."/love/love.dll")
  assert(lib.PHYSFS_mount(root,"",1)~=0)
  assert(lib.PHYSFS_mount(runtime,"",1)~=0)
  -- Keep the user's editor preferences and options untouched during this audit.
  local read=love.filesystem.read
  local memory={}
  love.filesystem.write=function(path,bytes) memory[path]=bytes;return true end
  love.filesystem.read=function(path,...)
    if memory[path] then return memory[path] end
    if path=="content_editor_data.json" then return nil end
    return read(path,...)
  end
  local App=require("App")
  App.load(assert(os.getenv("POKEPORT_CONTENT_MOD")),{version="firered"})
  local S=App.getState()
  assert(not S.gen3ModError,S.gen3ModError)
  assert(S.data.pokemon.PECHARUNT,"Added species not available after open")
  assert(S.data._editorGen3Report.counts.pokemon.total>=1025)
  local art=require("ModPokemonArt")
  local mon=assert(S.data.pokemon.ACCELGOR)
  for _,field in ipairs({"spriteFront","spriteBack","spriteShinyFront","spriteShinyBack"}) do
    local path=assert(art.path(S,mon,field),field)
    local image=assert(require("Preview").image(S,path),field)
    assert(image:getWidth()==image:getHeight(),"Preview must crop a single animation frame")
  end
  assert(art.icon(S,mon,"ACCELGOR"),"Added-species icon missing")
  local edited=require("src.mods.Merge").deepCopy(mon)
  edited.spriteFront="assets/custom_front.png"
  assert(not art.path(S,edited,"spriteFront"),"Pack replaced the editor's imported sprite")
  for _,tab in ipairs({"project","pokemon","moves"}) do
    S.tab=tab
    if tab=="pokemon" then S.pokemonId="ACCELGOR" end
    App.draw()
  end
  S.tab="pokemon"
  local trees=require("EvoBreedTrees")
  local children,parents=trees.buildChildren(S,false)
  assert(parents.COALOSSAL[1]=="CARKOL" and parents.CARKOL[1]=="ROLYCOLY")
  assert(children.ROLYCOLY[1].evo.referenceText=="Level 18")
  assert(children.CARKOL[1].evo.referenceText=="Level 34")
  S.project.pokemon.ROLYCOLY={id="ROLYCOLY",evolutions={}}
  local edited=trees.buildChildren(S,false)
  assert(not edited.ROLYCOLY,"Explicitly removed evolution was restored by reference data")
  S.project.pokemon.ROLYCOLY=nil
  S.pokemonId="COALOSSAL"
  S.pokemonSection="trees"
  S.project.gen3BattlePositions={ACCELGOR={frontY=-5,backY=8}}
  local canvas=love.graphics.newCanvas(1360,860)
  S.tab="effects";S.g3EffectsMode="custom";S.g3BehaviorId="COMBO"
  S.project.gen3Behaviors={COMBO={kind="ability",index=78,name="Contact Guard",trigger="receiveContact",target="opponent",condition="hpBelow",hpPercent=50,chance=100,
    actions={{kind="damage",amount=12},{kind="clearNegative",target="self"}}}}
  love.graphics.setCanvas({canvas,stencil=true});App.draw();love.graphics.setCanvas()
  local image=canvas:newImageData():encode("png")
  local f=assert(io.open(root.."/tests/content-editor/mod-content-smoke/pokemon.png","wb"))
  f:write(image:getString());f:close()
  report("PASS: 1025Dex panels render; Accelgor front/back/normal/shiny frames and icon load; explicit imported sprites take priority")
  love.event.quit()
end
