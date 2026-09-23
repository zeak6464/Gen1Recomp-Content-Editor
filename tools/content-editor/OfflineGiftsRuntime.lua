-- Embedded in exported mods. Claims live in the save, scoped to mod and gift.
local M = {}

function M.claim(mod, rows, id, generation, save, data, events)
  local row = rows[id]
  if not save or not row or row.enabled == false then return 0 end
  local saved = save.modData and save.modData[mod.id]
  if saved and saved.offlineGifts and saved.offlineGifts[id] then return 2 end
  local ok = false
  if row.kind == "item" then
    if generation == 3 then
      local rec = mod.content.items:get(row.item)
      if not rec then return 0 end
      local Bag = require("src.core.game3.bag")
      save.bag = save.bag or Bag.new()
      ok = Bag.add(save.bag, rec.index, row.quantity)
    else
      if not (data.items and data.items[row.item]) then return 0 end
      save.inventory = save.inventory or {}
      ok = require("src.inventory.Bag").add(save, row.item, row.quantity, data)
    end
  elseif row.kind == "decoration" and generation == 2 then
    local D = require("src.core.gen2.Decorations")
    if not events or not D.attributes(row.decoration) then return 0 end
    ok = D.give(events, row.decoration)
  elseif row.kind == "pokemon" then
    -- Keep delivery explicit: make a party slot rather than silently boxing it.
    if #(save.party or {}) >= 6 then return 3 end
    if generation == 3 then
      local rec = mod.content.pokemon:get(row.species)
      if not rec then return 0 end
      ok = require("src.core.game3.party").giveMon(save, rec.index, row.level)
    else
      if not (data.pokemon and data.pokemon[row.species]) then return 0 end
      local mon
      if generation == 2 then
        local Mon = require("src.battle.gen2.Mon")
        mon = Mon.new(data, row.species, row.level)
        if mon then Mon.stampOT(save, mon) end
      else
        mon = require("src.pokemon.Pokemon").new(data, row.species, row.level)
        if mon then require("src.battle.BattleState").stampOT(save, mon) end
      end
      if not mon then return 0 end
      save.party = save.party or {}
      ok = require("src.pokemon.Party").add(save.party, mon)
      if ok then
        save.pokedex = save.pokedex or {seen={}, owned={}}
        save.pokedex.seen = save.pokedex.seen or {}
        save.pokedex.owned = save.pokedex.owned or {}
        save.pokedex.seen[row.species] = true
        save.pokedex.owned[row.species] = true
      end
    end
  else return 0 end
  if not ok then return 3 end
  save.modData = save.modData or {}
  saved = save.modData[mod.id] or {}; save.modData[mod.id] = saved
  saved.offlineGifts = saved.offlineGifts or {}
  saved.offlineGifts[id] = true
  return 1
end

function M.install(mod, rows, generation)
  if mod.generation and mod.generation ~= generation then return end
  if generation == 3 then
    local Flags = require("src.core.game3.scripting.flags")
    mod.hooks:wrap("script.command", function(proceed, ctx, op, row)
      if op ~= "editor_offline_gift" or row.owner ~= mod.id then return proceed(ctx, op, row) end
      local vm = ctx.vm or ctx.runner
      if not vm then return false end
      local session = ctx.session or require("src.core.game3.runtime").getSession()
      Flags.setVar(vm.store, vm.ctx, 0x800D, M.claim(mod, rows, row.gift, 3, session))
      return false
    end)
  else
    mod.content.commands:register(mod.id .. ":offline_gift", {
      foreground = true,
      fn = function(ctx, id)
        local game = ctx.game or (mod.world and mod.world.game)
        local save = ctx.save or (game and game.save)
        local world = game and game.world
        local result = M.claim(mod, rows, id, generation, save, game and game.data, world and world.events)
        local row = rows[id]
        local text = row and (result == 1 and (row.title .. "\n" .. row.message)
          or result == 2 and row.done or result == 3 and row.full or row.unavailable)
          or "This gift is unavailable."
        if generation == 2 then ctx.vm:showRaw(text)
        else require("src.script.Commands").show_text(ctx, text) end
      end,
    })
  end
end
return M
