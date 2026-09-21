local M={}
function M.validate(rules)
  for _,rule in ipairs(rules or {}) do
    if type(rule.species)~="string" or rule.species=="" then return nil,"Choose a target species" end
    if type(rule.level)~="number" or rule.level%1~=0 or rule.level<1 or rule.level>100 then return nil,"Starter level must be 1–100" end
    if type(rule.map)~="string" or rule.map=="" then return nil,"Choose a map" end
    if type(rule.matchSpecies)~="table" or #rule.matchSpecies==0 then return nil,"Add a species to match" end
  end
  return true
end
function M.emit(project,encode,out)
  local rules=project.gen3Starters
  if not rules or #rules==0 then return end
  assert(M.validate(rules))
  out[#out+1]="  local starterRules = "..encode(rules)
  out[#out+1]=[=[  local function starterContext(ctx, rule)
    local world = ctx and ctx.overworld
    local map = world and world.map
    local id = map and (map.gen3Id or map.id)
    local save = ctx and ctx.save
    if not (id and save) or id:gsub("^FR_", "") ~= rule.map:gsub("^FR_", "") then return false end
    return not rule.onlyFirst or (not (save.flags or {}).EVENT_GOT_STARTER and #(save.party or {}) == 0)
  end
  local function matches(rule, species)
    for _, name in ipairs(rule.matchSpecies) do if name == species then return true end end
    return false
  end
  local originalGifts = setmetatable({}, {__mode="k"})
  local selectedStarters = setmetatable({}, {__mode="k"})
  for _, rule in ipairs(starterRules) do
    local target = assert(mod.content.pokemon:get(rule.species), "Unknown starter species: " .. rule.species)
    local sourceIndices = {}
    for _, name in ipairs(rule.matchSpecies) do
      local rec = assert(mod.content.pokemon:get(name), "Unknown starter source: " .. name)
      sourceIndices[rec.index] = true
    end

    mod.hooks:wrap("script.command", function(next, ctx, op, row)
      if rule.onlyFirst and not row._editorStarterChanged and op == "setvar" and (row.var or row[1]) == (rule.variable or 0x4002)
          and sourceIndices[row.value or row[2]] and starterContext(ctx, rule) then
        local copy = {}; for k,v in pairs(row) do copy[k]=v end
        copy.value,copy[2]=target.index,target.index
        copy._editorStarterChanged=true
        if rule.onlyFirst and ctx and ctx.save then selectedStarters[ctx.save]=rule end
        return next(ctx,op,copy)
      end
      if rule.egg and op=="giveegg" and sourceIndices[row.species or row[1]] and starterContext(ctx,rule) then
        local Party=require("src.core.game3.party")
        local Pokemon=require("src.core.game3.pokemon")
        local session=ctx.save
        local ok=false
        if #(session.party or {})<6 then
          -- Construct separately so an unhatched Egg is not registered in the Pokedex.
          local temp={party={},name=session.name,playerName=session.playerName,trainerId=session.trainerId}
          ok=Party.giveMon(temp,target.index,rule.level,rule.nickname)
          if ok then
            local egg=temp.party[1];egg.isEgg=true;egg.egg=true
            egg.friendship=(Pokemon.speciesMeta(target.index) or {}).eggCycles or 20;egg.eggCycles=egg.friendship
            session.party=session.party or {};table.insert(session.party,egg)
          end
        end
        local vm=ctx.vm or ctx.runner
        if vm and vm.store then require("src.core.game3.scripting.flags").setVar(vm.store,vm.ctx,0x800D,ok and 0 or 2) end
        return true
      end
      return next(ctx,op,row)
    end)
    -- Run after handwritten gift listeners, preserving all unrelated gifts.
    mod.events:on("pokemon.before_give", function(gift)
      originalGifts[gift] = originalGifts[gift] or gift.species
      local selected = gift.ctx and gift.ctx.save and selectedStarters[gift.ctx.save]
      local match = rule.onlyFirst and selected and selected==rule and (matches(rule,originalGifts[gift]) or originalGifts[gift]==rule.species)
        or (not (rule.onlyFirst and selected) and matches(rule,originalGifts[gift]))
      if match and starterContext(gift.ctx,rule) then
        gift.species,gift.level=rule.species,rule.level
        if rule.nickname and rule.nickname~="" then gift.nickname=rule.nickname end
      end
    end,-1000)
  end]=]
end
return M


