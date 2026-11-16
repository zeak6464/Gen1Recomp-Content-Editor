package.path="tools/content-editor/?.lua;runtime/gen1recomp/?.lua;"..package.path
local clicked, picker, invalid
package.loaded.Kit={text=function() end,ellipsize=function(_,v) return v end,
  button=function(_,_,_,_,label) return label==clicked end}
package.loaded.Theme={PAL={}}
package.loaded.SpeciesPicker={open=function(_,opts) picker=opts end}
package.loaded.ModIO={readText=function() return "audio bytes" end}
love={filesystem={newFileData=function(bytes) return bytes end},audio={newSource=function()
  if invalid then error("invalid audio") end
  return {release=function() end}
end}}
local Cries=require("Gen3Cries")
local Adapter=require("Gen3AudioAdapter")
local S={project={pokemon={CUSTOM={id="CUSTOM",index=440}},audio={cries={}},gen3AudioWorkspace=1},
  data={_editorGen3Audio={cries={}},_g3Audio={},pokemon={BULBASAUR={index=1}}}}
local dirty=0
local App={markDirty=function() dirty=dirty+1 end,
  pickFile=function(_,_,cb) cb("C:/cry.wav") end,
  importToMod=function(_,_,cb) cb("assets/custom-cry.wav") end}
local function draw(button)
  clicked=button
  Cries.draw(S,S.project.pokemon.CUSTOM,App,0,0,500,28,1)
end
draw("Browse")
Adapter.compile(S.project)
assert(S.project.gen3Audio.cries["440"].file=="assets/custom-cry.wav")
assert(S.project.audio.cries.CUSTOM==nil,"runtime requires numeric species keys")
invalid=true
draw("Browse")
assert(dirty==1,"invalid audio must not replace the cry")
invalid=false
draw("Alias")
picker.onPick("BULBASAUR")
Adapter.compile(S.project)
assert(S.project.gen3Audio.cries["440"]==1)
S.project.audio.cries["1"]={file="assets/bulbasaur.wav"}
draw("Alias")
picker.onPick("BULBASAUR")
assert(S.project.audio.cries["440"].file=="assets/bulbasaur.wav")
assert(S.project.audio.cries["440"]~=S.project.audio.cries["1"])
draw("Reset")
Adapter.compile(S.project)
assert(S.project.gen3Audio.cries["440"]==nil)
assert(S.project.gen3Audio.cries["1"].file=="assets/bulbasaur.wav")
assert(loadfile("tools/content-editor/Gen3ContentForms.lua"))
print("PASS custom Gen 3 cry import, validation, aliases and reset export")
