local Kit=require("Kit")
local R=require("Gen3Resources")
local List=require("RegList")
local IO=require("ModIO")
local Panel={}
local function assetLabel(path)
  local name=path:match("([^/]+)%.[^.]+$") or path
  if path:find("/teachy_tv/",1,true) then
    return ({screen="TV frame",title="Title graphic",["end"]="End graphic",bg3="Scrolling background",static="TV static frames"})[name] or name
  end
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
-- Custom overworld sprite import: any layout, preview, name, then save.
local OW=require("Gen3Overworld")
local function openOwImport(S,App,opts)
  opts=opts or {}
  App.pickFile(opts.title or "New overworld sprite (PNG: one frame, a column, a row or a grid)","PNG (*.png)|*.png",function(picked)
    local img,err=OW.readPng(picked)
    if not img then S.status=tostring(err);return end
    local name=opts.name or (picked:match("([^/\\]+)%.[^.]+$") or "Custom sprite"):gsub("[_%-]+"," ")
    S.g3OwImport={file=picked,img=img,replaceId=opts.replaceId,replacePath=opts.replacePath,name=name}
    S.g3OwImportSize=opts.size or "auto"
  end)
end
Panel.openOwImport=openOwImport

local function drawOwImport(S,App,fx,y,fw,h)
  local st=S.g3OwImport
  local s=Kit.scale
  local img=st.img
  local iw,ih=img:getDimensions()
  Kit.caption(fx,y,st.replaceId and ("Replace custom sprite "..st.replaceId) or "New overworld sprite")
  Kit.caption(fx,y+24*s,(st.file:match("([^/\\]+)$") or st.file).."  ·  "..iw.." x "..ih)
  Kit.caption(fx,y+50*s,"Frame size")
  local cy=List.modeChips(S,"g3OwImportSize",OW.SIZE_CHOICES,fx,y+72*s,s)
  if st.size~=S.g3OwImportSize then
    st.size=S.g3OwImportSize
    st.L,st.err=OW.layout(iw,ih,st.size)
    st.stacked,st.image=nil,nil
    if st.L then
      st.stacked=OW.stack(img,st.L)
      st.image=love.graphics.newImage(st.stacked);st.image:setFilter("nearest","nearest")
      st.start=love.timer.getTime()
    end
  end
  local L=st.L
  local yy=cy+4*s
  if not L then
    Kit.caption(fx,yy,tostring(st.err))
    yy=yy+60*s
  else
    Kit.caption(fx,yy,L.count.." frame"..(L.count==1 and "" or "s").." of "..L.fw.." x "..L.fh..", from "..OW.MODE_TEXT[L.mode])
    yy=yy+22*s
    if L.count~=1 and L.count~=3 and L.count<9 then
      Kit.caption(fx,yy,"Fewer than 9 frames: it can face each way but won't animate when it walks");yy=yy+22*s
    elseif L.count==1 then
      Kit.caption(fx,yy,"One frame: it always looks the same, whichever way it faces");yy=yy+22*s
    end
    local frame=math.floor((love.timer.getTime()-(st.start or 0))*6)%L.count
    local scale=math.max(1,math.min(6,math.floor(math.min((fw-24*s)/L.fw,160*s/L.fh))))
    Kit.card(fx,yy+6*s,L.fw*scale+12*s,L.fh*scale+12*s)
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(st.image,love.graphics.newQuad(0,frame*L.fh,L.fw,L.fh,L.fw,L.fh*L.count),fx+6*s,yy+12*s,0,scale,scale)
    Kit.caption(fx+L.fw*scale+24*s,yy+10*s,"Frame "..(frame+1).." / "..L.count)
    yy=yy+L.fh*scale+28*s
  end
  Kit.caption(fx,yy,"Name (shown in the Appearance picker)")
  st.name=Kit.textfield("g3OwImportName",fx,yy+22*s,math.min(fw,320*s),28*s,st.name or "","Sprite name")
  yy=yy+62*s
  if L and Kit.button(fx,yy,170*s,30*s,st.replaceId and "Replace sprite" or "Add sprite",{kind="primary"}) then
    local id,path=OW.save(S,st.stacked,L,{id=st.replaceId,name=st.name})
    if not id then S.status=tostring(path);return true end
    S.g3OwImport=nil;S.g3AssetId=path;S._g3AssetKey=nil;S._mapOwSprites=nil;App.markDirty()
    S.status=(st.replaceId and "Replaced" or "Added").." overworld sprite "..id.." ("..(S.project.gen3Assets[path].name)..") · pick it in a map character's Appearance · Save to apply"
    return true
  end
  if Kit.button(fx+(L and 182 or 0)*s,yy,110*s,30*s,"Cancel",{}) then S.g3OwImport=nil end
  return true
end

function Panel.draw(S,x,y,w,h,App,filter)
  if not S.project then Kit.caption(x,y,"Open a Gen 3 project first");return end
  local s=Kit.scale
  -- Sprite files left without a project record (e.g. an import that was
  -- never saved) are put back once per opened project.
  if S._g3OwRelinked~=S.project then
    S._g3OwRelinked=S.project
    local n=OW.relink(S)
    if n>0 then App.markDirty();S.status="Relinked "..n.." overworld sprite"..(n==1 and "" or "s").." that "..(n==1 and "was" or "were").." missing from the project · Save to apply" end
  end
  local owMode=filter and filter("data/generated/gba/ow/0.rgba")
  local catalog=R.assets(S.data,S.project)
  local ids={}
  for _,id in ipairs(List.sortedKeys(catalog)) do if not filter or filter(id) then ids[#ids+1]=id end end
  table.sort(ids,require("Gen3Labels").natural)
  local found=false;for _,id in ipairs(ids) do if id==S.g3AssetId then found=true end end
  if not found then S.g3AssetId=nil;S.g3AssetOffset=0 end
  S.g3AssetId=S.g3AssetId or ids[1]
  local assets=S.project.gen3Assets or {}
  local function label(p)
    local rec=assets[p]
    if OW.isCustom(rec) and rec.name then return rec.name.."  ("..(p:match("/(%d+)%.rgba$") or "?")..")" end
    return assetLabel(p)
  end
  local fx,fw=List.drawList(S,App,x,y,w,h,"Native UI / image assets",ids,{selKey="g3AssetId",queryKey="g3AssetQuery",offsetKey="g3AssetOffset",label=label,listW=math.min(w*.43,510*s),
    footerLabel=owMode and "+ New overworld sprite" or ((not filter or filter("data/generated/gba/trainers/front/0.rgba")) and "+ New trainer sprite" or nil),
    onFooter=function()
      if owMode then openOwImport(S,App);return end
      App.pickFile("New trainer battle sprite (64 x 64)","PNG (*.png)|*.png",function(picked)
        local id,path=R.importTrainerPic(S,picked)
        if not id then S.status=tostring(path);return end
        S.g3AssetId=path;S._g3AssetKey=nil;App.markDirty();S.status="Added trainer sprite "..id.."; select it on Trainers"
      end)
    end})
  if S.g3OwImport and owMode then drawOwImport(S,App,fx,y,fw,h);return end
  local path=S.g3AssetId
  if not path or not catalog[path] then Kit.caption(fx,y,"Import FireRed, LeafGreen or Emerald to extract UI and animation assets");return end
  local override=(S.project.gen3Assets or {})[path]
  local custom=OW.isCustom(override)
  if S._g3AssetKey~=path or S._g3AssetOverride~=override then
    S._g3AssetKey,S._g3AssetOverride=path,override;S._g3AssetImage=nil;S.g3AssetFrame=0;S.g3AssetPlaying=false
    S.g3AssetWidth=tostring(override and override.width or catalog[path].width or 64)
  end
  Kit.caption(fx,y,custom and ("Custom overworld sprite "..(path:match("/(%d+)%.rgba$") or "")) or assetLabel(path))
  if custom then
    Kit.caption(fx,y+31*s,"Name")
    local name=Kit.textfield("g3OwName|"..path,fx+60*s,y+26*s,math.min(fw-60*s,300*s),28*s,override.name or "","Sprite name")
    if name~=(override.name or "") then override.name=name;App.markDirty() end
  elseif path:match("%.rgba$") then
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
        local record={file=rel,width=iw,height=ih}
        if override and override.ow then record.ow=override.ow;record.metaFile=override.metaFile;record.name=override.name end
        S.project.gen3Assets=S.project.gen3Assets or {};S.project.gen3Assets[path]=record
        App.markDirty();S.status="Imported native asset; Save to apply"
      end)
    end
    if Kit.button(fx+142*s,by,130*s,28*s,"Export PNG",{}) then
      local dest=S.path.."/assets/gen3-export/"..path:gsub("^data/generated/gba/",""):gsub("%.rgba$",".png")
      IO.ensureDirectory(dest:match("^(.*)/"))
      local ok,err=IO.writeText(dest,data:encode("png"):getString());S.status=ok and ("Exported "..dest) or tostring(err)
    end
    if custom then
      if Kit.button(fx,by+37*s,130*s,28*s,"Delete sprite",{}) then
        if S.g3OwDeleteArm==path then
          OW.delete(S,path);S.g3OwDeleteArm=nil;S.g3AssetId=nil;S._g3AssetKey=nil;S._mapOwSprites=nil;App.markDirty()
          S.status="Deleted the custom sprite · characters still set to it fall back to the game's default"
        else
          S.g3OwDeleteArm=path;S.status="Click Delete sprite again to remove it and its files"
        end
      end
    elseif Kit.button(fx,by+37*s,130*s,28*s,"Revert asset",{}) then
      if S.project.gen3Assets then S.project.gen3Assets[path]=nil end
      S._g3AssetKey=nil;App.markDirty()
    end
    if path:match("/ow/%d+%.rgba$") and catalog[path].frameCount then
      local meta=catalog[path]
      if Kit.button(fx+142*s,by+37*s,210*s,28*s,custom and "Replace sprite..." or "Import as new sprite",{kind="primary"}) then
        local size=meta.frameWidth and (meta.frameWidth.."x"..meta.frameHeight) or "auto"
        local known=false;for _,c in ipairs(OW.SIZE_CHOICES) do if c.id==size then known=true end end
        local id=tonumber(path:match("/(%d+)%.rgba$"))
        openOwImport(S,App,{size=known and size or "auto",replaceId=custom and id or nil,name=custom and override.name or nil,
          title=custom and ("Replace custom sprite "..id.." (keeps its ID)") or nil})
      end
    end
  end
end
return Panel
