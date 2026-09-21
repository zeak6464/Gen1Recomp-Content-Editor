local M={}
local K,C=require("Kit"),require("ChoicePicker")
local Data=require("Gen3FameData")
local Copy=require("src.mods.Merge").deepCopy
function M.validate(rows)
  assert(type(rows)=="table" and #rows==16,"Fame Checker needs its 16 original character slots")
  local function rule(r)
    assert(r.unlock=="original" or r.unlock=="always" or r.unlock=="flag","Choose how the Fame Checker entry unlocks")
    if r.unlock=="flag" then assert(type(r.flag)=="number" and r.flag>0 and r.flag<=65535 and r.flag%1==0,"Choose a story flag") end
  end
  local function text(v) assert(type(v)=="string" and #v<=16000,"Fame Checker text must be under 16000 bytes") end
  for _,r in ipairs(rows) do
    text(r.name);assert(r.name:match("%S"),"Give each Fame Checker character a name");text(r.message);rule(r)
    assert(type(r.portrait)=="number" and r.portrait>=0 and r.portrait%1==0,"Choose a character portrait")
    if r.image then
      local pixels=love.image.newImageData(love.filesystem.newFileData(love.data.decode("string","base64",r.image),"fame.png"))
      assert(pixels:getWidth()==64 and pixels:getHeight()==64,"Fame Checker portraits must be 64 x 64 pixels")
    end
    assert(type(r.facts)=="table" and #r.facts==6,"Each character needs six fact slots")
    for _,f in ipairs(r.facts) do for _,key in ipairs({"question","text","location","source"}) do text(f[key]) end;rule(f) end
  end
end
function M.draw(S,x,y,w,h,App)
  local defaults,err=Data.load(S);if not defaults then K.caption(x,y,tostring(err));return end
  local rows=Data.enrich(S.project.gen3Fame or defaults,defaults);local person=S.g3FamePerson or 1;local part=S.g3FamePart or 1
  local function row() return (S.project.gen3Fame or defaults)[person] end
  local function edit()
    S.project.gen3Fame=S.project.gen3Fame or Copy(defaults);App.markDirty();return S.project.gen3Fame[person]
  end
  local s=K.scale;local fh=30*s;local ids,labels={},{}
  for i,r in ipairs(rows) do ids[i]=i;labels[i]=r.name end
  C.field(S,{x=x,y=y,w=w*.48,h=fh,current=person,ids=ids,labels=labels,title="Choose a person",onPick=function(v) S.g3FamePerson=v;S.g3FamePage=1 end})
  local sections={[1]="Character and personal message"};local choices={1}
  for j=1,6 do sections[j+1]="Fact "..j..": "..row().facts[j].question;choices[#choices+1]=j+1 end
  C.field(S,{x=x+w*.5,y=y,w=w*.5,h=fh,current=part,ids=choices,labels=sections,title="Choose what to edit",onPick=function(v) S.g3FamePart=v;S.g3FamePage=1 end})
  y=y+42*s;h=h-42*s
  local previewX=x+w*.63;local pw=w*.37
  local runtime=require("Gen3FameRuntime")
  local scale=math.min(pw/240,3);local view={rows=rows,person=person,fact=part==1 and 7 or part-1,page=S.g3FamePage or 1,preview=true,session={playerName="PLAYER",rivalName="RIVAL"}}
  S._g3FameCanvas=S._g3FameCanvas or love.graphics.newCanvas(240,160)
  local old=love.graphics.getCanvas();love.graphics.push("all");love.graphics.setCanvas(S._g3FameCanvas);love.graphics.origin();love.graphics.setScissor();runtime.draw(view)
  if old then love.graphics.setCanvas({old,stencil=true}) else love.graphics.setCanvas() end;love.graphics.pop();love.graphics.setColor(1,1,1,1);S._g3FameCanvas:setFilter("nearest","nearest");love.graphics.draw(S._g3FameCanvas,previewX,y,0,scale,scale)
  local py=y+160*scale+12*s
  if K.button(previewX,py,90*s,fh,"Previous",{}) then S.g3FamePage=math.max(1,view.page-1) end
  if K.button(previewX+100*s,py,90*s,fh,"Next page",{}) then S.g3FamePage=view.page%view.pageCount+1 end
  K.caption(previewX,py+42*s,"Page "..view.page.." / "..view.pageCount)
  K.caption(previewX,py+68*s,"Preview shows all entries, including locked facts.")
  if not S.project.gen3Fame and K.button(previewX,py+100*s,220*s,fh,"Enable Fame Checker in mod",{kind="primary"}) then edit() end
  local Pane=require("FormPane");Pane.track(S,"g3FameScroll",person..":"..part)
  local top,v=Pane.begin(S,"g3FameScroll",x,y,w*.60,h-40*s);local fy=top;local fw=v.contentW
  local function target(write) local r=write and edit() or row();return part==1 and r or r.facts[part-1] end
  local function field(label,key)
    K.caption(x,fy,label);fy=fy+20*s;local oldValue=target()[key]
    local value=K.textfield("fame_"..person.."_"..part.."_"..key,x,fy,fw,fh,oldValue,"")
    if value~=oldValue then target(true)[key]=value end;fy=fy+40*s
  end
  if part==1 then
    field("Character name","name")
    local pics,plabels={},{[0]="Imported portrait"}
    for i,r in ipairs(defaults) do pics[#pics+1]=i;plabels[i]=Data.names[i] end
    K.caption(x,fy,"Portrait");fy=fy+20*s
    C.field(S,{x=x,y=fy,w=fw,h=fh,current=row().portraitChoice or person,ids=pics,labels=plabels,title="Choose a portrait",onPick=function(i)
      local r=edit();r.portrait=defaults[i].portrait;r.image=defaults[i].image;r.portraitChoice=i
    end});fy=fy+38*s
    if K.button(x,fy,220*s,fh,"Import portrait PNG (64 x 64)",{}) then
      App.pickFile("Fame Checker portrait","PNG|*.png",function(path)
        local bytes=require("ModIO").readText(path)
        local ok,img=pcall(function() return love.image.newImageData(love.filesystem.newFileData(bytes,"portrait.png")) end)
        if not ok or img:getWidth()~=64 or img:getHeight()~=64 then S.status="Choose a 64 x 64 PNG portrait";return end
        local r=edit();r.image=love.data.encode("string","base64",img:encode("png"):getString());r.portraitChoice=0
      end)
    end;fy=fy+44*s
  else
    field("Fact heading / question","question")
    field("Where the information was found (display name)","location")
    field("Who said it / source name","source")
  end
  K.caption(x,fy,part==1 and "Show this person" or "Unlock this fact");fy=fy+20*s
  C.field(S,{x=x,y=fy,w=fw,h=fh,current=target().unlock,ids={"original","always","flag"},labels={original="Through the original story events",always="Available immediately",flag="When a story flag is set"},title="When is this available?",onPick=function(id) local r=target(true);r.unlock=id;r.flag=r.flag or 1 end});fy=fy+42*s
  if target().unlock=="flag" then
    local flags,names={},{};for id,name in pairs(require("src.core.game3.scripting.flags").NAMES or {}) do if type(id)=="number" and id>0 then flags[#flags+1]=id;names[id]=name:gsub("^FLAG_",""):gsub("_"," ") end end;table.sort(flags)
    C.field(S,{x=x,y=fy,w=fw,h=fh,current=target().flag,ids=flags,labels=names,title="Choose a story flag",onPick=function(id) target(true).flag=id end});fy=fy+42*s
  end
  K.caption(x,fy,part==1 and "Personal message (unlocked after all six facts)" or "What the Fame Checker says");fy=fy+24*s
  local key=part==1 and "message" or "text";local pages={}
  for page in (target()[key].."\f"):gmatch("(.-)\f") do pages[#pages+1]=page end
  local function savePages() target(true)[key]=table.concat(pages,"\f");S.g3FamePage=1 end
  for i,page in ipairs(pages) do
    K.caption(x,fy,"Text page "..i);fy=fy+20*s
    local shown=page:gsub("\n"," ");local value=K.textfield("fame_page_"..person.."_"..part.."_"..i,x,fy,math.max(80*s,fw-70*s),fh,shown,"")
    if value~=shown then pages[i]=value;savePages() end
    if #pages>1 and K.button(x+fw-62*s,fy,60*s,fh,"Delete",{}) then table.remove(pages,i);savePages();break end
    fy=fy+40*s
  end
  if K.button(x,fy,140*s,fh,"Add text page",{}) then pages[#pages+1]="";savePages() end;fy=fy+42*s
  K.caption(x,fy,"Text wraps automatically. {PLAYER} and {RIVAL} insert their names.");fy=fy+28*s
  K.caption(x,fy,"Original event unlocks are tracked from when this mod is enabled.");fy=fy+28*s
  K.caption(x,fy,"Source names describe the fact; changing them does not move its event.");fy=fy+28*s
  Pane.finish(S,"g3FameScroll",top,fy,v)
  if K.button(x,y+h-30*s,170*s,fh,"Revert this character",{kind="danger"}) and S.project.gen3Fame then S.project.gen3Fame[person]=Copy(defaults[person]);App.markDirty() end
end
function M.emit(p,encode,out)
  if not p.gen3Fame then return end;M.validate(p.gen3Fame)
  local rows=Data.enrich(p.gen3Fame,Data.load({data={},project=p}))
  out[#out+1]="local fame=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3FameRuntime.lua")).."\nend)()\nfame.install(mod,"..encode(rows)..")"
end
return M
