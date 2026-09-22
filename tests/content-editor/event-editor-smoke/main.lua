local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
local runtime=assert(os.getenv("POKEPORT_RECOMP")):gsub("\\","/")
local cache=assert(os.getenv("POKEPORT_GEN3_CACHE")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/content-editor/panels/?.lua;"
  ..root.."/tools/save-editor/?.lua;"..runtime.."/?.lua;"..package.path
local function report(message)
  local f=assert(io.open(root.."/tests/content-editor/event-editor-smoke/result.txt","wb"));f:write(message);f:close()
end
love.errorhandler=function(err) report(debug.traceback(tostring(err)));return function() return 1 end end
function love.load()
  local ffi=require("ffi");ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
  local lib=ffi.load(root.."/love/love.dll")
  assert(lib.PHYSFS_mount(root,"",1)~=0);assert(lib.PHYSFS_mount(runtime,"",1)~=0)
  assert(lib.PHYSFS_mount(cache,"event-cache",1)~=0)
  require("src.core.GameVersion").set("firered")
  local data={}
  require("Gen3").load(data,function(path)
    local f=io.open(cache.."/"..path,"rb");if not f then return end
    local bytes=f:read("*a");f:close();return bytes
  end,function(path)
    local entries={}
    for _,name in ipairs(love.filesystem.getDirectoryItems("event-cache/"..path)) do
      entries[#entries+1]={name=name,type=love.filesystem.getInfo("event-cache/"..path.."/"..name).type}
    end
    return entries
  end)
  local S=require("State").new();S.data=data;S.version="firered"
  S.project=require("State").blankProject("event_editor_test");S.project.game="firered"
  require("Gen3ContentAdapter").prepare(S);require("Gen3Workspace").prepare(S)
  local d={kind="dialog",map="FR_PALLET_TOWN",npc="1",text="Welcome, {PLAYER}!\nEnjoy your adventure."}
  local script=assert(require("Gen3EventBuilder").create(S,d))
  local storyModule=require("Gen3EventStory")
  S.project.gen3.map_scripts.EditorBattleTest={{op="end"}}
  storyModule.openAddMenu(S,"EditorBattleTest",require("Gen3").catalog(S.data,"map_scripts"),{markDirty=function() end})
  local addBattle=S.choicePicker.onPick;require("ChoicePicker").close(S);addBattle("wild_battle")
  local battleRows=storyModule.rows(S,"EditorBattleTest",require("Gen3").catalog(S.data,"map_scripts"))
  assert(battleRows[1].kind=="wild_battle" and battleRows[1].level==5)
  S.project.gen3.map_scripts.EditorTrainerTest={{op="end"}}
  storyModule.openAddMenu(S,"EditorTrainerTest",require("Gen3").catalog(S.data,"map_scripts"),{markDirty=function() end})
  local addTrainer=S.choicePicker.onPick;require("ChoicePicker").close(S);addTrainer("trainer_battle")
  assert(storyModule.rows(S,"EditorTrainerTest",require("Gen3").catalog(S.data,"map_scripts"))[1].kind=="trainer_battle")
  S.g3EventMode="map";S.g3EventMap=d.map;S.g3MapEventId="objects/1"
  S._g3StepSelection={["event/"..script]=3}
  local K=require("Kit");local Panel=require("Gen3Events");local Writer=require("ModWriter")
  local dirty=0;local App={markDirty=function() dirty=dirty+1 end}
  local before=Writer.encodeLua(S.project)
  local function render(name,width,height)
    local canvas=love.graphics.newCanvas(width,height)
    love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
    K.layout(width,height);K.beginFrame(0,0,false,0)
    Panel.draw(S,20,45,width-40,height-65,App)
    if S.choicePicker then require("ChoicePicker").draw(S,0,0,width,height) end
    K.endFrame();love.graphics.setCanvas()
    local f=assert(io.open(root.."/tests/content-editor/event-editor-smoke/"..name..".png","wb"))
    f:write(canvas:newImageData():encode("png"):getString());f:close()
  end
  render("map-events",1360,860);render("map-events-small",1024,768)
  local Story=require("Gen3EventStory")
  local catalog=require("Gen3").catalog(S.data,"map_scripts")
  local nativeBefore=Writer.encodeLua(catalog["g3:0816575c"])
  local story=Story.rows(S,"g3:0816575c",catalog)
  local dialogueCount=0;local branchText
  for _,row in ipairs(story) do if row.text then dialogueCount=dialogueCount+1;if row.script~="g3:0816575c" then branchText=row end end end
  assert(dialogueCount>=4 and branchText,"Vanilla event must expose dialogue from its branches")
  assert(Writer.encodeLua(catalog["g3:0816575c"])==nativeBefore)
  local itemStory=Story.rows(S,"g3:081be755",catalog)
  assert(#itemStory==1 and itemStory[1].kind=="item" and itemStory[1].label=="Pick up ESCAPE ROPE",itemStory[1] and itemStory[1].label)
  local savedKey=S.project.maps[d.map].objects[1].scriptKey
  S.project.maps[d.map].objects[1].scriptKey="g3:0816575c"
  render("vanilla-story",1360,860);render("vanilla-story-small",1024,768)
  S.project.maps[d.map].objects[1].scriptKey=savedKey
  S.g3EventMap="FR_POKEMON_TOWER_3F";S.g3MapEventId="objects/4"
  render("native-item-event",1360,860)
  S.g3EventMap=d.map;S.g3MapEventId="objects/1"
  S.project.maps[d.map].objects[1].scriptKey="g3:081be755"
  render("item-event",1360,860)
  S.project.maps[d.map].objects[1].scriptKey=savedKey
  local textRow=require("src.mods.Merge").deepCopy(catalog[branchText.script][branchText.index])
  local textBefore=require("Gen3EventActions").text(S,textRow)
  local textProject=S.project.text
  S.project.text=require("src.mods.Merge").deepCopy(textProject)
  require("Gen3EventActions").setText(S,textRow,"A changed branch conversation")
  assert(textRow.value==textRow[2] and require("Gen3EventActions").text(S,textRow)=="A changed branch conversation")
  assert(require("Gen3EventActions").text(S,catalog[branchText.script][branchText.index])==textBefore)
  S.project.text=textProject
  S["g3StoryAdvanced/"..script]=true
  render("advanced-actions",1360,860)
  S.g3InlineEventSettings=true;render("event-settings",1360,860);S.g3InlineEventSettings=nil
  assert(dirty==0 and Writer.encodeLua(S.project)==before,"Browsing must not change event data")
  -- Pickers must edit the event being displayed even if another map is selected elsewhere.
  local picker=require("ChoicePicker");local field=picker.field;local movementPick
  picker.field=function(state,opts) if opts.title=="Movement" then movementPick=opts.onPick end;return field(state,opts) end
  S.g3InlineEventSettings=true;render("event-settings",1360,860);S.g3InlineEventSettings=nil;picker.field=field
  assert(movementPick);S.mapId="FR_VIRIDIAN_CITY";movementPick("7")
  assert(S.project.maps[d.map].objects[1].movementType==7)
  assert(not S.project.maps.FR_VIRIDIAN_CITY)
  local dirtyBeforeText=dirty
  -- Exercise Apply text through the real draw path and persist the generated IR.
  S._g3MessageDraft.lines={"Edited in the event editor!"}
  local button=K.button
  K.button=function(x,y,w,h,label,opts) if label=="Apply text" then return true end;return button(x,y,w,h,label,opts) end
  render("edited-text",1360,860);K.button=button
  local step=S.project.gen3.map_scripts[script][3]
  assert(require("Gen3EventActions").text(S,step)=="Edited in the event editor!" and dirty==dirtyBeforeText+1)
  K.button=function(x,y,w,h,label,opts) if label=="Add action" then return true end;return button(x,y,w,h,label,opts) end
  render("action-picker",1360,860);K.button=button
  assert(S.choicePicker and S.choicePicker.labels.text=="Text / Show text")
  local add=S.choicePicker.onPick;picker.close(S);add("move")
  assert(S.project.gen3.map_scripts[script][7].op=="applymovement")
  render("movement",1360,860)
  local original=Writer.encodeLua(S.project.gen3.map_scripts[script])
  local clone=assert(require("Gen3EventEditor").copyScript(S,d.map,"objects",1))
  assert(clone~=script and S.project.maps[d.map].objects[1].scriptKey==clone)
  assert(Writer.encodeLua(S.project.gen3.map_scripts[clone])==original)
  local snapshot=Writer.encodeLua(S.project)
  assert(not require("Gen3EventEditor").copyScript(S,d.map,"objects",99999))
  assert(Writer.encodeLua(S.project)==snapshot)
  local IO=require("ModIO");local path=root.."/tests/content-editor/event-editor-smoke/project"
  IO.ensureDirectory(path);assert(IO.save(path,S.project));local loaded=assert(IO.load(path))
  assert(loaded.maps[d.map].objects[1].scriptKey==clone)
  assert(loaded.text[step.ptr],"Edited text must survive saving and reopening")
  -- Existing builder and item reward VM/save tests.
  dofile(root.."/tests/content-editor/test_gen3_event_builder.lua")(data,root,root.."/tests/content-editor/event-editor-smoke")
  dofile(root.."/tests/content-editor/test_gen3_movement.lua")(data,root,root.."/tests/content-editor/event-editor-smoke")
  report("PASS: real FireRed event editor rendering, text edits, isolated scripts, save/reopen, and event builder")
  love.event.quit()
end
