local M={}
local games={slots="Slot Machine",crush="Berry Crush",jump="Pokemon Jump",dodrio="Dodrio Berry Picking"}
function M.draw(S,x,y,w,h,App)
 local K=require("Kit");local P=require("ChoicePicker");local s=K.scale
 local id=games[S.g3Minigame] and S.g3Minigame or "slots"
 P.field(S,{x=x,y=y,w=w,h=28*s,ids={"slots","crush","jump","dodrio"},labels=games,current=id,title="CHOOSE MINI-GAME",onPick=function(v) S.g3Minigame=v;S.g3MinigameImage="1" end})
 local top=require("RegList").modeChips(S,"g3MinigameView",{{id="playback",label="Animation preview"},{id="images",label="Image library"}},x,y+38*s,s)
 h=h-(top-y);y=top
 if S.g3MinigameView=="playback" then require("Gen3MinigamePreview").draw(S,id,x,y,w,h);return end
 require("Gen3MinigamePreview").stop(S)
 local Images=require("Gen3MinigameImages");local ids,labels={},{}
 for i,rec in ipairs(Images.assets[id]) do ids[i]=tostring(i);labels[tostring(i)]=rec.name end
 local selected=tostring(S.g3MinigameImage or "1");if not labels[selected] then selected="1" end
 P.field(S,{x=x,y=y,w=w,h=28*s,ids=ids,labels=labels,current=selected,title="CHOOSE IMAGE",onPick=function(v) S.g3MinigameImage=v end})
 local data,err=Images.image(S,id,tonumber(selected))
 if not data then K.caption(x,y+80*s,err or "Unable to read mini-game image");return end
 local rec=Images.assets[id][tonumber(selected)]
 if S._miniGameImageData~=data then S._miniGameImageData=data;S._miniGameTexture=love.graphics.newImage(data);S._miniGameTexture:setFilter("nearest","nearest") end
 local image=S._miniGameTexture
 local scale=math.min((w-24*s)/data:getWidth(),math.max(1,h-140*s)/data:getHeight(),4*s)
 love.graphics.setColor(1,1,1,1);love.graphics.draw(image,x+12*s,y+80*s,0,scale,scale)
 K.caption(x,y+h-45*s,rec.name.." - original ROM graphics ("..data:getWidth().." x "..data:getHeight()..")")
 K.caption(x,y+h-20*s,"Image preview. Use Animation preview to watch a demonstration. Asset replacement is not supported yet.")
end
return M
