local Kit=require("Kit")
local R=require("Gen3Resources")
local List=require("RegList")
local IO=require("ModIO")
local Panel={}
local function assetLabel(path)
  local name=path:match("([^/]+)%.[^.]+$") or path
  local aliases={bg="Background",bg_female="Background (female player)",desc_sel="Selected item description",page_info="Summary: Pokemon information",page_moves="Summary: moves",page_moves_info="Summary: move details",page_skills="Summary: stats",page_egg="Summary: egg",list="Item list",list_blank="Empty item list"}
  return aliases[name] or (name:gsub("_"," "):gsub("^%l",string.upper))
end
Panel.assetLabel=assetLabel
local function imageData(S,path,rec,width)
  local override=(S.project.gen3Assets or {})[path]
  local bytes=override and IO.readText(S.path.."/"..override.file) or S.data._gen3Read(path)
  if not bytes then return nil,"Asset is missing" end
  if path:match("%.rgba$") then
    width=tonumber(width) or (override and override.width) or rec.width or 64
    if width<1 or width%1~=0 or (#bytes/4)%width~=0 then return nil,"Set a width that divides "..(#bytes/4).." pixels" end
    return love.image.newImageData(width,#bytes/4/width,"rgba8",bytes)
  end
  local ok,value=pcall(love.image.newImageData,love.filesystem.newFileData(bytes,"asset.png"))
  return ok and value or nil,not ok and tostring(value) or nil
end
function Panel.draw(S,x,y,w,h,App,filter)
  if not S.project then Kit.caption(x,y,"Open a Gen 3 project first");return end
  local s=Kit.scale
  local catalog=R.assets(S.data)
  local ids={}
  for _,id in ipairs(List.sortedKeys(catalog)) do if not filter or filter(id) then ids[#ids+1]=id end end
  table.sort(ids,require("Gen3Labels").natural)
  local found=false;for _,id in ipairs(ids) do if id==S.g3AssetId then found=true end end
  if not found then S.g3AssetId=nil;S.g3AssetOffset=0 end
  S.g3AssetId=S.g3AssetId or ids[1]
  local fx,fw=List.drawList(S,App,x,y,w,h,"Native UI / image assets",ids,{selKey="g3AssetId",queryKey="g3AssetQuery",offsetKey="g3AssetOffset",label=assetLabel,listW=math.min(w*.43,510*s)})
  local path=S.g3AssetId
  if not path or not catalog[path] then Kit.caption(fx,y,"Import FireRed or LeafGreen to extract UI and animation assets");return end
  local override=(S.project.gen3Assets or {})[path]
  if S._g3AssetKey~=path or S._g3AssetOverride~=override then
    S._g3AssetKey,S._g3AssetOverride=path,override;S._g3AssetImage=nil;S.g3AssetFrame=0;S.g3AssetPlaying=false
    S.g3AssetWidth=tostring(override and override.width or catalog[path].width or 64)
  end
  Kit.caption(fx,y,assetLabel(path))
  if path:match("%.rgba$") then
    Kit.caption(fx,y+26*s,"Image width")
    local widths,labels={},{}
    local bytes=S.data._gen3Read(path);local pixels=bytes and #bytes/4 or 0
    for n=1,1024 do if pixels>0 and pixels%n==0 then widths[#widths+1]=tostring(n);labels[tostring(n)]=n.." pixels"..(n==catalog[path].width and " (original)" or "") end end
    require("ChoicePicker").field(S,{x=fx,y=y+50*s,w=240*s,h=28*s,current=S.g3AssetWidth,ids=widths,labels=labels,title="Sheet width",onPick=function(width) S.g3AssetWidth=width;S._g3AssetImage=nil end})
  end
  if not S._g3AssetImage then
    local ok,data,err=pcall(imageData,S,path,catalog[path],S.g3AssetWidth)
    if ok and data then S._g3AssetData=data;S._g3AssetImage=love.graphics.newImage(data);S._g3AssetImage:setFilter("nearest","nearest")
    else S._g3AssetData=nil;Kit.caption(fx,y+95*s,tostring(ok and err or data)) end
  end
  local data=S._g3AssetData
  if data and S._g3AssetImage then
    local iw,ih=data:getDimensions();local meta=catalog[path]
    local frameMode=meta.frameHeight and iw==meta.width and ih==meta.height and not S.g3AssetSheet
    local drawY=y+118*s
    if meta.frameHeight then
      if Kit.button(fx,y+87*s,110*s,25*s,frameMode and "Show sheet" or "Show frames",{}) then S.g3AssetSheet=not S.g3AssetSheet end
      if frameMode then
        if Kit.button(fx+118*s,y+87*s,90*s,25*s,S.g3AssetPlaying and "Pause" or "Play",{}) then S.g3AssetPlaying=not S.g3AssetPlaying;S.g3AssetPlayStart=love.timer.getTime()-(S.g3AssetFrame or 0)/8 end
        if Kit.button(fx+216*s,y+87*s,50*s,25*s,"<",{}) then S.g3AssetPlaying=false;S.g3AssetFrame=((S.g3AssetFrame or 0)-1)%meta.frameCount end
        if Kit.button(fx+274*s,y+87*s,50*s,25*s,">",{}) then S.g3AssetPlaying=false;S.g3AssetFrame=((S.g3AssetFrame or 0)+1)%meta.frameCount end
        if S.g3AssetPlaying then S.g3AssetFrame=math.floor((love.timer.getTime()-S.g3AssetPlayStart)*8)%meta.frameCount end
      end
      drawY=y+149*s
    end
    local dw,dh=frameMode and meta.frameWidth or iw,frameMode and meta.frameHeight or ih
    local scale=math.min((fw-12*s)/dw,math.max(70*s,h-255*s)/dh,frameMode and 6 or 4)
    Kit.caption(fx,drawY-28*s,frameMode and ("Frame "..((S.g3AssetFrame or 0)+1).." / "..meta.frameCount.." · "..dw.." x "..dh) or (iw.." x "..ih..(override and " — mod replacement" or " — extracted original")))
    Kit.card(fx,drawY,dw*scale,dh*scale)
    love.graphics.setColor(1,1,1,1)
    if frameMode then love.graphics.draw(S._g3AssetImage,love.graphics.newQuad(0,(S.g3AssetFrame or 0)*dh,dw,dh,iw,ih),fx,drawY,0,scale,scale)
    else love.graphics.draw(S._g3AssetImage,fx,drawY,0,scale,scale) end
    local by=y+h-88*s
    if Kit.button(fx,by,130*s,28*s,"Import PNG",{kind="primary"}) then
      App.pickFile("Replace native image ("..iw.." x "..ih..")","PNG (*.png)|*.png",function(picked)
        local bytes=IO.readText(picked)
        local ok,img=pcall(function() return love.image.newImageData(love.filesystem.newFileData(bytes,"replacement.png")) end)
        if not ok or img:getWidth()~=iw or img:getHeight()~=ih then S.status="Replacement must be "..iw.." x "..ih;return end
        local rel="assets/gen3/"..path:gsub("^data/generated/gba/","")
        local output=path:match("%.rgba$") and img:getString() or img:encode("png"):getString()
        IO.ensureDirectory((S.path.."/"..rel):match("^(.*)/"))
        local saved,err=IO.writeText(S.path.."/"..rel,output)
        if not saved then S.status=tostring(err);return end
        S.project.gen3Assets=S.project.gen3Assets or {};S.project.gen3Assets[path]={file=rel,width=iw,height=ih}
        App.markDirty();S.status="Imported native asset; Save to apply"
      end)
    end
    if Kit.button(fx+142*s,by,130*s,28*s,"Export PNG",{}) then
      local dest=S.path.."/assets/gen3-export/"..path:gsub("^data/generated/gba/",""):gsub("%.rgba$",".png")
      IO.ensureDirectory(dest:match("^(.*)/"))
      local ok,err=IO.writeText(dest,data:encode("png"):getString());S.status=ok and ("Exported "..dest) or tostring(err)
    end
    if Kit.button(fx,by+37*s,130*s,28*s,"Revert asset",{}) then
      if S.project.gen3Assets then S.project.gen3Assets[path]=nil end
      S._g3AssetKey=nil;App.markDirty()
    end
  end
end
return Panel
