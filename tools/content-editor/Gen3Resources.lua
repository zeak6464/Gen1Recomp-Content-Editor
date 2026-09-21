-- Native resources are kept separate from the generation-gated public registries.
local M = {}
M.animationPath = "data/generated/gba/pokemon/battle_anims/pack.lua"
M.sections = {"moves", "status", "general", "special", "labels", "tags", "animBgs"}
function M.readTable(data,path)
  local bytes=data._gen3Read and data._gen3Read(path)
  if not bytes then return {} end
  local value,err=require("Gen3Decode").decode(bytes,{allowArray=true,allowComments=true,
    maxBytes=16*1024*1024,maxNodes=2000000,maxTableEntries=1000000,maxDepth=64,maxStringBytes=4194304})
  assert(value,path..": "..tostring(err));return value
end
function M.animations(data)
  if data._g3Animations then return data._g3Animations end
  local pack=M.readTable(data,M.animationPath)
  local result={}
  for _,section in ipairs(M.sections) do
    for id,value in pairs(pack[section] or {}) do result[section.."/"..tostring(id)]=value end
  end
  data._g3Animations=result;return result
end
function M.audio(data)
  if not data._g3Audio then data._g3Audio=M.readTable(data,"data/generated/gba/audio/index.lua") end
  return data._g3Audio
end
function M.assets(data)
  if data._g3Assets then return data._g3Assets end
  local result={}
  local root="data/generated/gba/"
  local function visit(path,depth)
    if depth>8 then return end
    for _,entry in ipairs(data._gen3List and data._gen3List(path) or {}) do
      local child=path.."/"..entry.name
      if entry.type=="directory" then visit(child,depth+1)
      elseif child:match("%.png$") or child:match("%.rgba$") then result[child]={path=child} end
    end
  end
  for _,dir in ipairs({"minigames","slot_machine","berry_crush","pokemon_jump","dodrio_berry_picking","trainers","chrome","items","pokemon/battle","pokemon/party","pokemon/summary","pokemon/battle_anims","pokemon/battle_transition","intro","region_map","naming","pokedex","pokemon/pokedex","trainer_card","help","quest_log","ow","field_effects","native"}) do visit(root..dir,0) end
  -- Available even when a cache provider cannot enumerate files.
  local known={menu_message_rgba={48,24},std_rgba={24,24},signpost_rgba={40,32},keypad_icons={128,32}}
  for i=0,9 do known["user_frame_"..i]={24,24} end
  known["fonts/down_arrows_fg"]={128,16};known["fonts/text_cursor"]={16,16};known["fonts/keypad_icons"]={128,32}
  for _,suffix in ipairs({"fg","shadow"}) do
    known["fonts/latin_normal_"..suffix]={256,512};known["fonts/latin_small_"..suffix]={256,288}
  end
  for name,size in pairs(known) do
    local path=root.."chrome/"..name..".rgba"
    if data._gen3Read and data._gen3Read(path) then result[path]={path=path,width=size[1],height=size[2]} end
  end
  local ow=M.readTable(data,root.."ow/manifest.lua")
  for id,meta in pairs(ow.sprites or {}) do
    local path=root.."ow/"..id..".rgba"
    if result[path] then
      result[path].width=meta.atlasW or meta.width
      result[path].height=meta.atlasH or meta.height*meta.frameCount
      result[path].frameWidth=meta.width;result[path].frameHeight=meta.height;result[path].frameCount=meta.frameCount
    end
  end
  local card=M.readTable(data,root.."trainer_card/manifest.lua")
  for _,name in ipairs({"bg","bg_female","badges"}) do
    local rec=result[root.."trainer_card/"..name..".rgba"]
    if rec then rec.width=name=="badges" and (card.badgeWidth or 16)*(card.badgeCount or 8) or card.width or 240 end
  end
  -- These are already composed pixel images, not 64-pixel-wide tile sheets.
  local summary=M.readTable(data,root.."pokemon/summary/manifest.lua")
  local party=M.readTable(data,root.."pokemon/party/manifest.lua")
  for path,rec in pairs(result) do
    local name=path:match("/pokemon/summary/([^/]+)%.rgba$")
    if name then
      if name:match("^page_") then rec.width=summary.width or 240
      elseif name:match("^hp_bar_") or name=="exp_bar" then rec.width=96
      elseif name=="menu_info" then rec.width=128
      elseif name=="status_icons" then rec.width=32
      elseif name=="cursor_left" or name=="cursor_right" then rec.width=64
      elseif name=="shiny_star" or name=="pokerus" then rec.width=8 end
    end
    name=path:match("/pokemon/party/([^/]+)%.rgba$")
    if name then
      if name=="bg" then rec.width=party.width or 240
      elseif name:match("^slot_main") then rec.width=party.slotMainW or 80
      elseif name:match("^slot_wide") then rec.width=party.slotWideW or 144
      elseif name:match("^cancel_button") then rec.width=party.cancelButtonW or 56
      elseif name=="status_balls" then rec.width=party.ballW or 32
      elseif name=="status_icons" then rec.width=32 end
    end
  end
  local bag=M.readTable(data,root.."items/bag/manifest.lua")
  for path,rec in pairs(result) do
    local name=path:match("/items/bag/([^/]+)%.rgba$")
    if name then
      if name=="bg" or name=="bg_female" or name=="desc_sel" then rec.width=bag.width or 240
      elseif name:match("^list") then rec.width=bag.listW or 144
      elseif name:match("^bag_") then
        rec.width=bag.bagW or 64;rec.height=bag.bagH or 256
        rec.frameWidth=rec.width;rec.frameCount=bag.bagFrames or 4;rec.frameHeight=rec.height/rec.frameCount
      elseif name=="red_arrow" then rec.width=16 end
    elseif path:find("/items/bag/icons/",1,true) then rec.width=bag.iconW or 24 end
  end
  local battle=M.readTable(data,root.."pokemon/battle/manifest.lua")
  for path,rec in pairs(result) do
    local name=path:match("/pokemon/battle/([^/]+)%.rgba$")
    if name then
      if name=="elements" or name=="elements_exp" then rec.width=320
      elseif name=="hp_bold_digits" then rec.width=88
      elseif name=="party_summary_bar" then rec.width=128
      elseif name:match("^healthbox") then rec.width=128
      elseif name=="textbox" or name:match("^terrain") then rec.width=256 end
    end
  end
  data._g3Assets=result;return result
end
function M.checkAnimation(id,value)
  if type(id)~="string" then return false,"Animation ID must be text" end
  local section,key=id:match("^([%w_]+)/(.+)$")
  local found=false;for _,s in ipairs(M.sections) do if s==section then found=true end end
  if not found or not key or type(value)~="table" then return false,"Choose an animation section and a table value" end
  if section~="tags" and section~="animBgs" then
    for k in pairs(value) do if type(k)~="number" or k%1~=0 or k<1 or k>#value then return false,"Animation commands must be an ordered list" end end
    for i,row in ipairs(value) do
      if type(row)~="table" or type(row.op)~="string" then return false,"Command "..i.." needs an op" end
    end
  end
  return true
end
return M
