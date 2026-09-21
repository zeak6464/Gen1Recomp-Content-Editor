return function(data,root)
  local P=require("Gen3AnimPreview")
  local S=require("State").new()
  S.data=data;S.version="firered";S.tab="anims";S.project=require("State").blankProject("preview")
  S.project.game="firered";S.path=root.."/tests/content-editor/gen3-smoke/native-project"
  require("Gen3ContentAdapter").prepare(S)
  local catalog=require("Gen3Resources").animations(data)
  local originalCache=require("src.core.game3.dataset").cache
  local originalRead=require("src.import.CacheFs").read
  assert(P.play(S,"moves/1",catalog["moves/1"]))
  assert(require("src.core.game3.dataset").cache==originalCache)
  assert(require("src.import.CacheFs").read==originalRead)
  for i=1,20 do P.update(S,1/60) end
  assert(not S.g3AnimPreview.error,S.g3AnimPreview.error)
  local canvas=assert(P.render(S))
  assert(not S.g3AnimPreview.error,S.g3AnimPreview.error)
  local f=assert(io.open(root.."/tests/content-editor/gen3-smoke/animation-preview.png","wb"))
  f:write(canvas:newImageData():encode("png"):getString());f:close()
  S.g3AnimPreview.paused=true
  local frame=S.g3AnimPreview.frame;P.update(S,1);assert(S.g3AnimPreview.frame==frame)
  P.step(S);assert(S.g3AnimPreview.frame==frame+1 or S.g3AnimPreview.finished)
  for i=1,600 do P.step(S);if S.g3AnimPreview.finished then break end end
  assert(not S.g3AnimPreview.error,S.g3AnimPreview.error)
  assert(S.g3AnimPreview.finished,"Native animation did not finish")
  S.tab="maps";P.update(S,0);assert(not S.g3AnimPreview)
  assert(P.play(S,"moves/1",{{op="delay",frames=9},{op="end"}}))
  S.tab="anims";P.update(S,1/120);assert(S.g3AnimPreview.frame==0)
  P.update(S,1/120);assert(S.g3AnimPreview.frame==1)
  P.stop(S)
  local Audio=require("src.core.game3.audio")
  local originalCry=Audio.playCry
  for _,move in ipairs({52,57,85,94,126,153}) do
    local id="moves/"..move
    S.g3PreviewReverse=move==94
    assert(P.play(S,id,assert(catalog[id])))
    local parent=love.graphics.newCanvas(320,240)
    love.graphics.setCanvas(parent)
    for frame=1,1800 do
      P.step(S)
      if frame%15==0 then P.render(S);assert(love.graphics.getCanvas()==parent) end
      assert(not S.g3AnimPreview.error,id..": "..tostring(S.g3AnimPreview.error))
      if S.g3AnimPreview.finished then break end
    end
    love.graphics.setCanvas()
    assert(S.g3AnimPreview.finished,id.." did not finish")
    assert(Audio.playCry==originalCry,"Preview leaked audio overrides")
    P.stop(S)
  end
end
