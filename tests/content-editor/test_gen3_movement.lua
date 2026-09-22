return function(data,root,output)
  output=output or root.."/tests/content-editor/gen3-smoke"
  local M=require("Gen3MovementEditor")
  local step={op="applymovement",localId=255,movement={16,19,254}}
  M.insert(step,17)
  assert(step.movement[3]==17 and step.movement[4]==254)
  local path=M.path(step.movement)
  assert(#path==4 and path[4][1]==1 and path[4][2]==0)
  local K=require("Kit");local C=require("ChoicePicker")
  local oldText,oldChoice=K.textfield,C.field
  local S={};local changes=0
  K.textfield=function(id,x,y,w,h,value) return "7" end
  C.field=function(_,opts) opts.onPick(opts.title=="CHARACTER TO MOVE" and "7" or "18") end
  local canvas=love.graphics.newCanvas(800,600)
  love.graphics.setCanvas({canvas,stencil=true});K.layout(800,600);K.beginFrame(0,0,false,0)
  M.draw(S,"test",step,20,20,600,520,function() changes=changes+1 end)
  K.endFrame();love.graphics.setCanvas()
  K.textfield,C.field=oldText,oldChoice
  assert(step.localId==7 and changes==2)
  assert(step.movement[4]==18 and step.movement[5]==254)
  local bytes="return "..require("ModWriter").encodeLua({step,{op="waitmovement",localId=7},{op="end"}})
  local saved=assert(require("Gen3Decode").decode(bytes,{allowArray=true}))
  local actions=require("src.core.game3.scripting.movement").actionsFromBytes(saved[1].movement)
  assert(#actions==4 and actions[4].dir=="left")
  local commands={{op="end"}}
  local Steps=require("Gen3ScriptSteps")
  C.field=function(_,opts) if opts.title=="WHAT SHOULD HAPPEN?" then opts.onPick("move") end end
  love.graphics.setCanvas({canvas,stencil=true});K.beginFrame(0,0,false,0)
  Steps.draw(S,"new",commands,{applymovement={op="applymovement",localId=255,movement={254}}},20,20,760,560,function() end)
  K.endFrame();love.graphics.setCanvas();C.field=oldChoice
  assert(commands[1].op=="applymovement" and commands[2].op=="waitmovement" and commands[3].op=="end","New movement actions must finish before script termination")
  local f=assert(io.open(output.."/movement-editor.png","wb"))
  f:write(canvas:newImageData():encode("png"):getString());f:close()
end
