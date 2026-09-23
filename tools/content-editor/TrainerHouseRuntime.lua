local M={}
function M.install(mod,row)
  if mod.generation~=2 then return end
  local House=require("src.world.gen2.TrainerHouse")
  local Runtime=require("src.mods.Runtime")
  local function bridge(name)
    local key="editor.trainerHouse."..name
    if House[key] then return end;House[key]=true
    local original=House[name];House[name]=function(...) return Runtime.call(key,original,...) end
  end
  bridge("hasCustomTrainer");bridge("lookup");bridge("name")
  mod.hooks:wrap("editor.trainerHouse.hasCustomTrainer",function() return true end)
  mod.hooks:wrap("editor.trainerHouse.lookup",function(proceed,data,save,class,member)
    local original=proceed(data,save,class,member)
    if class~=House.CAL or (member~=House.CAL2 and member~=House.CAL3) then return original end
    if not original then return nil end
    local entry=require("src.mods.Merge").deepCopy(original)
    entry.name=row.name;entry.roster=require("src.mods.Merge").deepCopy(row.party)
    entry.trainerType=3 -- item + moves; individual empty move lists use learned moves
    return entry
  end)
  mod.hooks:wrap("editor.trainerHouse.name",function(proceed,data,save,class,member)
    if class==House.CAL and (member==House.CAL2 or member==House.CAL3) then return row.name end
    return proceed(data,save,class,member)
  end)
  if not row.daily then
    mod.hooks:wrap("script.command",function(proceed,ctx,op,args,cmd)
      local a=(cmd and cmd.args) or args or {}
      local flag=cmd and cmd.flag or ((a[1] or 0)+(a[2] or 0)*256)
      if ctx.mapId=="TRAINER_HOUSE_B1F" and flag==House.ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY then
        if op=="checkflag" then ctx.vm.scriptVar=0;return nil end
        -- Keep recording battles so restoring the daily rule respects today's visit.
      end
      return proceed(ctx,op,args,cmd)
    end)
  end
end
return M
