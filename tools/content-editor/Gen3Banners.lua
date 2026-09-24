local M={}
function M.emit(p,encode,out)
  if not next(p.gen3Banners or {}) then return end
  for id,rec in pairs(p.gen3Banners) do
    assert(type(id)=="string" and type(rec)=="table","Invalid location banner")
    assert(rec.enabled==nil or type(rec.enabled)=="boolean","Banner visibility must be on or off")
    assert(rec.text==nil or type(rec.text)=="string" and #rec.text<=160 and not rec.text:find("[%c]"),"Banner text must be a single line, up to 160 bytes")
    assert(rec.image==nil or type(rec.image)=="string" and rec.image:match("^assets/") and not rec.image:find("..",1,true),"Invalid banner image path")
  end
  out[#out+1]="local banners=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3BannersRuntime.lua")).."\nend)()\nbanners.install(mod,"..encode(p.gen3Banners)..")"
end
function M.enabled(S,id)
  local rec=(S.project.gen3Banners or {})[id]
  if rec and rec.enabled~=nil then return rec.enabled end
  for _,maps in ipairs({S.project.maps or {},(S.project.gen3 or {}).maps or {},S.data.maps or {}}) do
    local map=maps[id]
    if map then
      local value=map.showMapName
      if value==nil then value=map.show_map_name end
      if value~=nil then return value==true or value==1 end
    end
  end
  return false
end
function M.import(S,id,picked)
  local IO=require("ModIO")
  local bytes,err=IO.readText(picked);if not bytes then return nil,err end
  local ok,img=pcall(function() return love.image.newImageData(love.filesystem.newFileData(bytes,"banner.png")) end)
  if not ok or img:getWidth()~=128 or img:getHeight()~=24 then return nil,"Banner artwork must be a 128 x 24 PNG, without text" end
  assert(IO.ensureDirectory(S.path.."/assets/banners"))
  local rel=IO.uniqueAssetPath(S.path,"assets/banners/"..id:gsub("[^%w_-]","_")..".png")
  local saved,why=IO.writeText(S.path.."/"..rel,bytes);if not saved then return nil,why end
  S.project.gen3Banners=S.project.gen3Banners or {}
  local rec=S.project.gen3Banners[id] or {};S.project.gen3Banners[id]=rec;rec.image=rel
  return rel
end
function M.template(S)
  local bytes=S.data._gen3Read("data/generated/gba/chrome/std_rgba.rgba")
  if not bytes or #bytes~=24*24*4 then return nil,"Import the game's window artwork first" end
  local sheet=love.image.newImageData(24,24,"rgba8",bytes)
  local result=love.image.newImageData(128,24)
  result:mapPixel(function() return 1,1,1,1 end)
  local function cell(tile,x,y,flip)
    local sx,sy=tile%3*8,math.floor(tile/3)*8
    for dy=0,7 do for dx=0,7 do result:setPixel(x+dx,y+dy,sheet:getPixel(sx+dx,sy+(flip and 7-dy or dy))) end end
  end
  cell(6,0,0,true);cell(8,120,0,true);cell(3,0,8);cell(5,120,8);cell(6,0,16);cell(8,120,16)
  for i=1,14 do cell(7,i*8,0,true);cell(7,i*8,16) end
  return result
end
function M.draw(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then K.caption(x,y,"Open a project first");return end
  local ids=require("RegList").mergeIds(S.project.maps or {},S.data.maps or {})
  S.g3BannerMap=S.g3BannerMap or S.mapId or ids[1]
  local id=S.g3BannerMap
  local labels={};for _,key in ipairs(ids) do labels[key]=require("Gen3Labels").map(key) end
  require("ChoicePicker").field(S,{x=x,y=y,w=math.min(w,500*s),h=30*s,current=id,ids=ids,labels=labels,title="Choose a map",onPick=function(v) S.g3BannerMap=v end})
  if not id then return end
  local rec=(S.project.gen3Banners or {})[id] or {}
  y=y+42*s
  local enabled=M.enabled(S,id)
  local checked=K.checkbox(x,y,math.min(w,450*s),28*s,enabled,"Show banner on arrival")
  if checked~=enabled then
    S.project.gen3Banners=S.project.gen3Banners or {};S.project.gen3Banners[id]=rec
    rec.enabled=checked;App.markDirty()
  end
  y=y+40*s;K.caption(x,y,"Banner text (leave blank for the original location name)");y=y+25*s
  local text=K.textfield("banner_text_"..id,x,y,math.min(w,650*s),30*s,rec.text or "","")
  if text~=(rec.text or "") then
    if #text<=160 and not text:find("[%c]") then
      S.project.gen3Banners=S.project.gen3Banners or {};S.project.gen3Banners[id]=rec;rec.text=text;App.markDirty()
    else S.status="Use one line of text, up to 160 bytes" end
  end
  y=y+45*s;K.caption(x,y,"Artwork: 128 x 24 PNG. Keep the middle clear; the game draws the text.");y=y+28*s
  if K.button(x,y,170*s,30*s,"Export template",{}) then
    local img,err=M.template(S)
    if img then
      local IO=require("ModIO");IO.ensureDirectory(S.path.."/assets/banners")
      local rel=IO.uniqueAssetPath(S.path,"assets/banners/banner-template.png")
      local ok,why=IO.writeText(S.path.."/"..rel,img:encode("png"):getString())
      S.status=ok and ("Exported "..S.path.."/"..rel) or tostring(why)
    else S.status=tostring(err) end
  end
  if K.button(x+180*s,y,170*s,30*s,"Import artwork",{kind="primary"}) then
    App.pickFile("Location banner (128 x 24, without text)","PNG (*.png)|*.png",function(picked)
      local rel,err=M.import(S,id,picked);if rel then App.markDirty();S.status="Banner artwork imported for "..id else S.status=tostring(err) end
    end)
  end
  if K.button(x+360*s,y,170*s,30*s,"Use original artwork",{}) then rec.image=nil;App.markDirty() end
  y=y+46*s
  K.caption(x,y,rec.image or "Original game artwork");y=y+32*s
  local IO=require("ModIO")
  local key=rec.image or "original"
  if not S._bannerPreview or S._bannerPreview.key~=key or S._bannerPreview.project~=S.project then
    local ok,img=pcall(function()
      local data
      if rec.image then data=love.image.newImageData(love.filesystem.newFileData(assert(IO.readText(S.path.."/"..rec.image)),"banner.png")) else data=M.template(S) end
      if data then local image=love.graphics.newImage(data);image:setFilter("nearest","nearest");return image end
    end)
    S._bannerPreview={key=key,project=S.project,image=ok and img or nil}
  end
  local img=S._bannerPreview.image
  if img then
    local scale=math.min(4*s,w/128)
    love.graphics.setColor(1,1,1,1);love.graphics.draw(img,x,y,0,scale,scale)
    local name=rec.text and rec.text~="" and rec.text or labels[id] or id
    local Font=require("src.ui.game3.frlg_font")
    love.graphics.push("all");love.graphics.translate(x,y);love.graphics.scale(scale,scale)
    Font.draw(name,8+math.floor((112-Font.measure(name))/2),5,{colors=Font.COLOR.NORMAL,maxWidth=112})
    love.graphics.pop()
    y=y+24*scale+24*s
  end
  K.caption(x,y,"Applies to this map's arrival banner only. Save and restart Playtest.")
  K.caption(x,y+26*s,"Long names may be clipped by the game's 112-pixel text area.")
end
return M
