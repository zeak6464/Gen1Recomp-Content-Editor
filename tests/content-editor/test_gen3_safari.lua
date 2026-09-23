return function(data,root)
  local IO=require("ModIO")
  local S={data=data,version="firered",project=require("State").blankProject("safari_test")}
  S.project.game="firered";S.project.safariSettings=require("SafariSettings").defaults(3)
  S.project.safariSettings.balls=45;S.project.safariSettings.steps=1200
  S.path=root.."/tests/content-editor/gifts-smoke/safari-project"
  assert(IO.ensureDirectory(S.path))
  assert(IO.writeText(S.path.."/manifest.json",'{"id":"safari_test","name":"Safari test","version":"1.0.0","entry":"main.lua","games":["gen3"]}'))
  assert(IO.save(S.path,S.project));S.project=assert(IO.load(S.path))
  assert(S.project.safariSettings.steps==1200)
  local fresh={};require("Gen3").load(fresh,data._gen3Read)
  local loader,err=require("Gen3Mod").load(fresh,S.path);assert(loader,err)
  local Safari=require("src.core.game3.safari")
  local session={flags={}}
  assert(Safari.enter(session));assert(Safari.isActive(session))
  assert(Safari.balls(session)==45 and Safari.steps(session)==1200)
  session.safari.steps=789;session.safari.balls=20
  local saved=require("src.core.SaveSerializer")
  local restored=assert(saved.decode(saved.encode(session)))
  assert(Safari.steps(restored)==789 and Safari.balls(restored)==20,"Saved visit reset its allowance")
  assert(Safari.exit(restored));assert(not Safari.isActive(restored))
  require("src.mods.Runtime").reset()
  assert(Safari.enter({flags={}}))
  local vanilla={flags={}};Safari.enter(vanilla)
  assert(Safari.balls(vanilla)==30 and Safari.steps(vanilla)==600,"Safari override remained after mod unload")
  -- Draw the actual Rules integration, not only the isolated form.
  local K=require("Kit");local canvas=love.graphics.newCanvas(1360,860)
  love.graphics.setCanvas({canvas,stencil=true});love.graphics.clear(.04,.06,.12,1)
  K.layout(1360,860);K.beginFrame(0,0,false,0);S.g3RulesMode="safari"
  require("Rules").draw(S,20,50,1320,790,{markDirty=function() error("Viewing Safari settings changed the project") end})
  K.endFrame();love.graphics.setCanvas()
  assert(IO.writeText(root.."/tests/content-editor/gifts-smoke/safari-firered.png",canvas:newImageData():encode("png"):getString()))
end
