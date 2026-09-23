local M={}
function M.build(S,rows)
 local D=require("Gen3ScreenData");local seq=require("Gen3CreditsSequence");local copy=require("src.mods.Merge").deepCopy
 local movie={art={},maps={},commands={{op="opening",frames=504}}}
 local function encode(img) return love.data.encode("string","base64",img:encode("png"):getString()) end
 for _,r in ipairs(D.creditArt) do movie.art[r.id]=encode(assert(D.image(S,"credits",r.id))) end
 if not S.data._gen3Read then
  local cache=require("src.core.game3.dataset").cache();require("Gen3").load(S.data,function(path) return cache:read(path) end)
 end
 -- Bake isolated editor renderers. Never warp the live session or run map scripts.
 local preview={data=S.data,project=copy(S.project),version=require("Generation").id(S)}
 for id,spec in pairs(seq.maps) do
  local ok,map=require("Maps").loadEditorMap(preview,spec.map);assert(ok,"Credits map: "..tostring(map))
  local g=love.graphics;local old=g.getCanvas();local canvas=g.newCanvas(map.widthCells*16,map.heightCells*16)
  g.push("all");g.setCanvas(canvas);g.origin();g.setScissor();g.clear(0,0,0,1);g.setColor(1,1,1,1)
  local rendered,err=pcall(map.renderer.draw,map.renderer,0,0,map.widthCells*16,map.heightCells*16)
  if old then g.setCanvas({old,stencil=true}) else g.setCanvas() end;g.pop();if not rendered then canvas:release();error(err) end
  local record=copy(spec);record.image=encode(canvas:newImageData());movie.maps[id]=record;canvas:release()
 end
 local slot=0;local extras=false;local closing
 for _,r in ipairs(rows) do if r.art=="the_end" then closing=r end end
 for _,command in ipairs(seq.commands) do
  local c=copy(command)
  if c.op=="text" then
   if c.page<=42 then
    slot=slot+1;local row=rows[slot]
    if row and not (slot==#rows and row.art=="the_end") then
     c.row=copy(row);c.frames=(row.seconds and row.seconds*60 or c.frames)+32
    else c.frames=1 end
   end
  end
  if c.op=="ending" and not extras then
   extras=true
   for i=43,#rows do if rows[i]~=closing then
    movie.commands[#movie.commands+1]={op="text",row=copy(rows[i]),frames=rows[i].seconds*60+32}
   end end
  end
  if c.op=="ending" and c.id=="the_end" then c.row=closing and copy(closing) end
  movie.commands[#movie.commands+1]=c
 end
 return movie
end
return M
