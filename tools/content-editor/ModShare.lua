-- Portable ZIP export using LÖVE's filesystem; no external archiver required.
local M={}
local bit=require("bit")
local crcTable={}
for n=0,255 do
  local c=n
  for _=1,8 do c=bit.bxor(bit.rshift(c,1),bit.band(c,1)==1 and 0xEDB88320 or 0) end
  crcTable[n]=c
end
local function crc(data)
  local c=-1
  for i=1,#data do c=bit.bxor(bit.rshift(c,8),crcTable[bit.band(bit.bxor(c,data:byte(i)),255)]) end
  return bit.bnot(c)
end
local function le(n,size)
  local bytes={}
  for i=1,size do bytes[i]=string.char(n%256);n=math.floor(n/256) end
  return table.concat(bytes)
end
function M.zip(files)
  assert(#files<=65535,"Too many files to share")
  local chunks,central={},{};local offset=0
  for _,file in ipairs(files) do
    local name,data=file.name,file.data
    assert(name~="" and #name<=65535 and not name:find("\\",1,true) and not name:match("^/")
      and not name:find(":",1,true) and not ("/"..name.."/"):find("/../",1,true),"Invalid archive path")
    local sum=crc(data);local size=#data
    -- Stored ZIP entries, UTF-8 names, fixed DOS timestamp (1980-01-01).
    local header="PK\003\004"..le(20,2)..le(2048,2)..le(0,2)..le(0,2)..le(33,2)
      ..le(sum,4)..le(size,4)..le(size,4)..le(#name,2)..le(0,2)..name
    chunks[#chunks+1]=header;chunks[#chunks+1]=data
    central[#central+1]="PK\001\002"..le(20,2)..le(20,2)..le(2048,2)..le(0,2)..le(0,2)..le(33,2)
      ..le(sum,4)..le(size,4)..le(size,4)..le(#name,2)..le(0,2)..le(0,2)..le(0,2)..le(0,2)..le(0,4)..le(offset,4)..name
    offset=offset+#header+size
  end
  local directory=table.concat(central);chunks[#chunks+1]=directory
  chunks[#chunks+1]="PK\005\006"..le(0,2)..le(0,2)..le(#files,2)..le(#files,2)..le(#directory,4)..le(offset,4)..le(0,2)
  return table.concat(chunks)
end
local excludedDirs={generated=true,saves=true,cache=true,backups=true,["event-playtests"]=true}
local excludedExtensions={gb=true,gbc=true,gba=true,nds=true,["3ds"]=true,cia=true,nsp=true,xci=true,sav=true,srm=true,zip=true,g1rcart=true,love=true}
function M.include(relative,isDirectory)
  local name=(relative:match("([^/]+)$") or relative):lower()
  if name:sub(1,1)=="." then return false end
  if isDirectory then return not excludedDirs[name] end
  return not excludedExtensions[name:match("%.([^%.]+)$")] and not name:match("%.bak$") and not name:match("%.tmp$")
end
local serial=0
function M.export(path,project)
  local fs=love.filesystem;local IO=require("ModIO")
  if not project or not IO.isValidId(project.id) then return nil,"Open a mod first" end
  local id=project.id
  serial=serial+1
  local mount="_mod_share_"..serial
  local Mount=require("RuntimeMount")
  local mounted,err=Mount.mountAt(path,mount)
  if not mounted then return nil,"Could not read the mod folder: "..tostring(err) end
  local ok,result,skipped=pcall(function()
    local files,omitted={},{};local bytes=0
    local function add(name,data)
      assert(data,"Could not read "..name)
      bytes=bytes+#data;assert(bytes<=256*1024*1024,"Mod exceeds the 256 MB sharing limit")
      files[#files+1]={name=name,data=data}
    end
    local function walk(relative,depth)
      assert(depth<32,"Mod folders are nested too deeply")
      local names=fs.getDirectoryItems(mount..relative);table.sort(names)
      for _,name in ipairs(names) do
        local rel=relative=="" and name or relative:sub(2).."/"..name
        local source=mount.."/"..rel;local info=assert(fs.getInfo(source),"Cannot inspect "..rel)
        if info.type=="symlink" or not M.include(rel,info.type=="directory") then omitted[#omitted+1]=rel
        elseif info.type=="directory" then walk("/"..rel,depth+1)
        elseif info.type=="file" then
          assert(info.size<=128*1024*1024,"File is too large: "..rel)
          add(id.."/"..rel,assert(fs.read(source)))
        end
      end
    end
    assert(fs.getInfo(mount.."/manifest.json","file"),"Save the mod before sharing")
    walk("",0)
    local authoring=assert(IO.readText(IO.projectPath(path)),"Save the editable project before sharing")
    add(id..".editor_project.lua",authoring)
    add("INSTALL.txt","Install: copy the "..id.." folder into your Gen1Recomp mods folder, then enable it for the compatible game in the launcher.\n"
      .."Use your own game ROM. Required games and dependencies are listed in "..id.."/manifest.json.\n"
      .."To edit: keep the adjacent "..id..".editor_project.lua file and open the mod folder in Content Editor.\n"
      .."Export does not replace in-game testing or an asset scan.\n")
    assert(fs.createDirectory("shared-mods"))
    local target="shared-mods/"..id.."-"..os.date("%Y%m%d-%H%M%S").."-"..serial..".zip"
    assert(fs.write(target,M.zip(files)))
    return fs.getSaveDirectory():gsub("\\","/").."/"..target,omitted
  end)
  Mount.unmountData(path)
  -- The zip is already on disk. Drop the in-memory copy of every file.
  collectgarbage("collect")
  if not ok then return nil,tostring(result) end
  return result,skipped
end
return M
