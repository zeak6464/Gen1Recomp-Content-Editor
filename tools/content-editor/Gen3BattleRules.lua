local M={}
M.fields={
  {key="critMultiplier",label="Critical damage multiplier",default=2,min=1,max=10},
  {key="critChance0",label="Crit stage 0 (1 in N)",default=16,min=1,max=255},
  {key="critChance1",label="Crit stage 1 (1 in N)",default=8,min=1,max=255},
  {key="critChance2",label="Crit stage 2 (1 in N)",default=4,min=1,max=255},
  {key="critChance3",label="Crit stage 3 (1 in N)",default=3,min=1,max=255},
  {key="critChance4",label="Crit stage 4 (1 in N)",default=2,min=1,max=255},
  {key="damageRollMin",label="Damage roll minimum",default=85,min=1,max=100},
  {key="damageRollMax",label="Damage roll maximum",default=100,min=1,max=100},
  {key="expDivisor",label="Experience divisor",default=7,min=1,max=255},
  {key="maxLevel",label="Maximum level",default=100,min=1,max=100},
  {key="expShareDiv",label="Exp. Share split",default=2,min=1,max=16},
  {key="expTrainerPercent",label="Trainer experience %",default=150,min=0,max=1000},
  {key="expTradedPercent",label="Traded experience %",default=150,min=0,max=1000},
  {key="expLuckyPercent",label="Lucky Egg experience %",default=150,min=0,max=1000},
  {key="poisonFraction",label="Poison HP fraction",default=8,min=1,max=255},
  {key="burnFraction",label="Burn HP fraction",default=8,min=1,max=255},
  {key="toxicFraction",label="Toxic step fraction",default=16,min=1,max=255},
  {key="toxicCap",label="Toxic counter cap",default=15,min=1,max=255},
  {key="rainWaterPercent",label="Rain boosts Water %",default=150,min=0,max=1000},
  {key="rainFirePercent",label="Rain cuts Fire %",default=50,min=0,max=1000},
  {key="sunFirePercent",label="Sun boosts Fire %",default=150,min=0,max=1000},
  {key="sunWaterPercent",label="Sun cuts Water %",default=50,min=0,max=1000},
  {key="thunderSunAccuracy",label="Thunder accuracy in sun",default=50,min=0,max=100},
  {key="pokerusSpreadDenom",label="Pokerus spread (1 in N)",default=3,min=1,max=256},
  {key="pokerusContractBelow",label="Pokerus contract (below N of 65536)",default=3,min=0,max=65536},
  {key="shinyBelow",label="Shiny if the check is below",default=8,min=0,max=65536},
  {key="genderRoll",label="Gender roll",default=256,min=1,max=256},
  {key="abilitySlot",label="Ability slot roll",default=2,min=1,max=256},
  {key="prizeFactor",label="Trainer prize factor",default=4,min=0,max=255},
  {key="amuletMultiplier",label="Amulet Coin multiplier",default=2,min=0,max=255},
  {key="secretBaseFactor",label="Secret Base prize factor",default=20,min=0,max=255},
  {key="pickupDenom",label="Pickup (1 in N)",default=10,min=1,max=100},
  {key="pickupRoll",label="Pickup item roll",default=100,min=1,max=256},
  {key="confusionMin",label="Confusion minimum turns",default=2,min=0,max=255},
  {key="confusionSpan",label="Confusion turn count",default=4,min=1,max=255},
  {key="confusionHit",label="Confusion self-hit (out of 256)",default=128,min=0,max=256},
  {key="confusionPower",label="Confusion self-hit power",default=40,min=0,max=255},
  {key="attractFail",label="Infatuation fail at or above",default=128,min=0,max=256},
  {key="stabPercent",label="Same-type bonus percent",default=150,min=0,max=999},
  {key="paralysisSkip",label="Full paralysis (1 in N)",default=4,min=1,max=256},
  {key="paralysisSpeed",label="Paralysis Speed divisor",default=4,min=1,max=255},
  {key="weatherSpeed",label="Swift Swim and Chlorophyll multiplier",default=2,min=0,max=16},
  {key="earlyBird",label="Early Bird turns removed",default=2,min=0,max=16},
  {key="rainDishDiv",label="Rain Dish divisor",default=16,min=1,max=255},
  {key="absorbDiv",label="Volt Absorb and Water Absorb divisor",default=4,min=1,max=255},
  {key="roughSkinDiv",label="Rough Skin divisor",default=16,min=1,max=255},
  {key="shedSkin",label="Shed Skin (1 in N)",default=3,min=1,max=256},
  {key="effectSpore",label="Effect Spore (1 in N)",default=10,min=1,max=256},
  {key="contactStatus",label="Static, Poison Point, and Flame Body (1 in N)",default=3,min=1,max=256},
  {key="cuteCharm",label="Cute Charm (1 in N)",default=3,min=1,max=256},
  {key="intimidateDrop",label="Intimidate Attack drop",default=1,min=0,max=12},
  {key="thawChance",label="Thaw chance (1 in N)",default=5,min=1,max=256},
  {key="burnDamageDiv",label="Burn damage divisor",default=2,min=1,max=16},
  {key="spreadDiv",label="Spread move divisor",default=2,min=1,max=16},
  {key="solarBeamDiv",label="Solar Beam in bad weather divisor",default=2,min=1,max=16},
  {key="flashFire",label="Flash Fire percent",default=150,min=0,max=999},
  {key="helpingHand",label="Helping Hand percent",default=150,min=0,max=999},
  {key="chargeMult",label="Charge multiplier",default=2,min=0,max=16},
  {key="doubleMult",label="Doubling moves and Huge Power multiplier",default=2,min=0,max=16},
  {key="returnNum",label="Return numerator",default=10,min=0,max=255},
  {key="returnDen",label="Return denominator",default=25,min=1,max=255},
  {key="abilityBoost",label="Ability boost percent",default=150,min=0,max=999},
  {key="itemBoost",label="Choice Band and Soul Dew percent",default=150,min=0,max=999},
  {key="pinchHpDiv",label="Pinch HP divisor",default=3,min=1,max=255},
  {key="heldStatMult",label="Thick Club, Light Ball, Metal Powder, Deep Sea multiplier",default=2,min=0,max=16},
  {key="thickFatDiv",label="Thick Fat divisor",default=2,min=1,max=16},
  {key="sportDiv",label="Mud Sport and Water Sport divisor",default=2,min=1,max=16},
  {key="compoundEyes",label="Compound Eyes accuracy percent",default=130,min=0,max=999},
  {key="sandVeil",label="Sand Veil accuracy percent",default=80,min=0,max=999},
  {key="hustleAccuracy",label="Hustle accuracy percent",default=80,min=0,max=999},
  {key="explodeDiv",label="Explosion defense divisor",default=2,min=1,max=255},
  {key="screenDiv",label="Screen damage divisor",default=2,min=1,max=255},
  {key="screenTurns",label="Reflect and Light Screen turns",default=5,min=1,max=255},
  {key="safeguardTurns",label="Safeguard turns",default=5,min=1,max=255},
  {key="mistTurns",label="Mist and Guard Spec turns",default=5,min=1,max=255},
  {key="badgePercent",label="Badge stat percent",default=110,min=0,max=999},
  {key="obedienceNone",label="Obedience, no badge",default=10,min=0,max=100},
  {key="obedienceSecond",label="Obedience, 2nd badge",default=30,min=0,max=100},
  {key="obedienceFourth",label="Obedience, 4th badge",default=50,min=0,max=100},
  {key="obedienceSixth",label="Obedience, 6th badge",default=70,min=0,max=100},
  {key="doubleScreenNum",label="Double battle screen numerator",default=2,min=0,max=255},
  {key="doubleScreenDen",label="Double battle screen denominator",default=3,min=1,max=255},
  {key="sleepMin",label="Sleep minimum turns",default=2,min=0,max=255},
  {key="sleepSpan",label="Sleep turn count",default=4,min=1,max=255},
  {key="restTurns",label="Rest turns",default=3,min=1,max=255},
  {key="weatherChipDenom",label="Weather damage divisor",default=16,min=1,max=256},
  {key="partialTrapChipDenom",label="Trapping damage divisor",default=16,min=1,max=256},
  {key="partialTrapMinTurns",label="Minimum trapping turns",default=3,min=1,max=100},
  {key="partialTrapMaxTurns",label="Maximum trapping turns",default=6,min=1,max=100},
}
function M.draw(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local top,view,viewX,viewW=require("RegList").beginForm(S,x,y,w,h,"g3BattleScroll",S.project,12*s)
  x,y,w=viewX,top,viewW
  K.caption(x,y,(({firered="FIRERED",leafgreen="LEAFGREEN",emerald="EMERALD",ruby="RUBY",sapphire="SAPPHIRE"})[require("Generation").id(S)] or "GEN 3").." BATTLE RULES")
  y=y+38*s
  local values=S.project.gen3BattleRules or {}
  for _,row in ipairs(M.fields) do
    K.caption(x,y,row.label)
    local old=values[row.key]
    if old == nil then old = row.default end
    local n=require("RegList").num(App,"g3_rule_"..row.key,x+310*s,y,110*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3BattleRules=S.project.gen3BattleRules or {};values=S.project.gen3BattleRules
      values[row.key]=n
      -- Keep ranges valid while editing either endpoint so Save/Playtest can
      -- always export the project produced by this form.
      if row.key=="damageRollMin" and n>(values.damageRollMax or 100) then values.damageRollMax=n end
      if row.key=="damageRollMax" and n<(values.damageRollMin or 85) then values.damageRollMin=n end
      if row.key=="partialTrapMinTurns" and n>(values.partialTrapMaxTurns or 6) then values.partialTrapMaxTurns=n end
      if row.key=="partialTrapMaxTurns" and n<(values.partialTrapMinTurns or 3) then values.partialTrapMinTurns=n end
      App.markDirty()
    end
    y=y+38*s
  end
  if K.button(x,y+12*s,160*s,28*s,"Reset to defaults",{}) then S.project.gen3BattleRules=nil;App.markDirty() end
  y=y+48*s
  local id=require("Generation").id(S)
  if id=="firered" or id=="leafgreen" or id=="ruby" or id=="sapphire" then
    y=require("PickupItems").draw(S,x,y,w,App)+12*s
  end
  if id=="emerald" then
    y=require("PickupBands").draw(S,x,y,w,App)+12*s
  end
  if id=="ruby" or id=="sapphire" or id=="emerald" then
    y=require("PyramidRules").draw(S,x,y,w,App)+12*s
    y=require("FrontierRules").draw(S,x,y,w,App)
  end
  require("FormPane").finish(S,"g3BattleScroll",top,y,view)
end
function M.emit(p,encode,out)
  if not next(p.gen3BattleRules or {}) then return end
  local values=p.gen3BattleRules
  for _,row in ipairs(M.fields) do
    local v=values[row.key]
    assert(v==nil or type(v)=="number" and v%1==0 and v>=row.min and v<=row.max,"Invalid battle rule "..row.key)
  end
  assert((values.partialTrapMaxTurns or 6)>=(values.partialTrapMinTurns or 3),"Maximum trap turns must be at least the minimum")
  assert((values.damageRollMax or 100)>=(values.damageRollMin or 85),"Damage roll maximum must be at least the minimum")
  out[#out+1]="  local battleRules="..encode(values)
  out[#out+1]=[=[
  local Rules=require("src.core.game3.battle.rules")
]=]
  -- The cart function reads Capabilities.critMultiplier. A direct write would
  -- stay after the mod is disabled, so only this one value goes through a
  -- hook, and only when it was actually edited.
  if values.critMultiplier ~= nil then
    out[#out+1]=[=[
  local Runtime=require("src.mods.Runtime")
  if not Rules._editorCritBridge then
    Rules._editorCritBridge=true
    local base=Rules.crit.multiplier
    Rules.crit.multiplier=function(...) return Runtime.call("editor.gen3.rules.crit.multiplier",base,...) end
  end
  mod.hooks:wrap("editor.gen3.rules.crit.multiplier",function(proceed)
    if battleRules.critMultiplier == nil then return proceed() end
    return battleRules.critMultiplier
  end)
]=]
  end
  out[#out+1]=[=[
  do
    local Capabilities=require("src.core.game3.battle.capabilities")
    if battleRules.critChance0 ~= nil then Rules.crit.CHANCE[0] = battleRules.critChance0 end
    if battleRules.critChance1 ~= nil then Rules.crit.CHANCE[1] = battleRules.critChance1 end
    if battleRules.critChance2 ~= nil then Rules.crit.CHANCE[2] = battleRules.critChance2 end
    if battleRules.critChance3 ~= nil then Rules.crit.CHANCE[3] = battleRules.critChance3 end
    if battleRules.critChance4 ~= nil then Rules.crit.CHANCE[4] = battleRules.critChance4 end
    if battleRules.damageRollMin ~= nil then Capabilities.damageRollMin = battleRules.damageRollMin end
    if battleRules.damageRollMax ~= nil then Capabilities.damageRollMax = battleRules.damageRollMax end
    if battleRules.screenTurns ~= nil then Capabilities.screenDefaultTurns = battleRules.screenTurns end
    if battleRules.safeguardTurns ~= nil then Capabilities.safeguardDefaultTurns = battleRules.safeguardTurns end
    if battleRules.mistTurns ~= nil then Capabilities.mistDefaultTurns = battleRules.mistTurns end
    if battleRules.weatherChipDenom ~= nil then Capabilities.weatherChipDenom = battleRules.weatherChipDenom end
    if battleRules.partialTrapChipDenom ~= nil then Capabilities.partialTrapChipDenom = battleRules.partialTrapChipDenom end
    if battleRules.partialTrapMinTurns ~= nil then Capabilities.partialTrapMinTurns = battleRules.partialTrapMinTurns end
    if battleRules.partialTrapMaxTurns ~= nil then Capabilities.partialTrapMaxTurns = battleRules.partialTrapMaxTurns end
    if battleRules.badgePercent ~= nil then
      require("src.core.game3.battle.damage").BADGE_PERCENT = battleRules.badgePercent
    end
    local Engine=require("src.core.game3.battle.engine")
    if battleRules.obedienceNone ~= nil then Engine.OBEDIENCE_LEVELS.none = battleRules.obedienceNone end
    if battleRules.obedienceSecond ~= nil then Engine.OBEDIENCE_LEVELS.second = battleRules.obedienceSecond end
    if battleRules.obedienceFourth ~= nil then Engine.OBEDIENCE_LEVELS.fourth = battleRules.obedienceFourth end
    if battleRules.obedienceSixth ~= nil then Engine.OBEDIENCE_LEVELS.sixth = battleRules.obedienceSixth end
    if Capabilities.damageRollMax < Capabilities.damageRollMin then
      Capabilities.damageRollMax = Capabilities.damageRollMin
    end
    local Experience=require("src.core.game3.battle.experience")
    if battleRules.expDivisor ~= nil then Experience.DIVISOR = battleRules.expDivisor end
    if battleRules.maxLevel ~= nil then Experience.MAX_LEVEL = battleRules.maxLevel end
    if battleRules.expShareDiv ~= nil then Experience.SHARE_DIV = battleRules.expShareDiv end
    if battleRules.expTrainerPercent ~= nil then
      Experience.TRAINER_NUM = battleRules.expTrainerPercent
      Experience.TRAINER_DEN = 100
    end
    if battleRules.expTradedPercent ~= nil then
      Experience.TRADED_NUM = battleRules.expTradedPercent
      Experience.TRADED_DEN = 100
    end
    if battleRules.expLuckyPercent ~= nil then
      Experience.LUCKY_NUM = battleRules.expLuckyPercent
      Experience.LUCKY_DEN = 100
    end
    local Status=require("src.core.game3.battle.status")
    if battleRules.poisonFraction ~= nil then Status.POISON_FRACTION = battleRules.poisonFraction end
    if battleRules.burnFraction ~= nil then Status.BURN_FRACTION = battleRules.burnFraction end
    if battleRules.toxicFraction ~= nil then Status.TOXIC_FRACTION = battleRules.toxicFraction end
    if battleRules.toxicCap ~= nil then Status.TOXIC_CAP = battleRules.toxicCap end
    Rules.weather.TYPE_MODIFIERS = Rules.weather.TYPE_MODIFIERS or {}
    Rules.weather.TYPE_MODIFIERS.RAIN = Rules.weather.TYPE_MODIFIERS.RAIN or {}
    Rules.weather.TYPE_MODIFIERS.SUN = Rules.weather.TYPE_MODIFIERS.SUN or {}
    if battleRules.rainWaterPercent ~= nil then
      Rules.weather.TYPE_MODIFIERS.RAIN.WATER = battleRules.rainWaterPercent / 100
    end
    if battleRules.rainFirePercent ~= nil then
      Rules.weather.TYPE_MODIFIERS.RAIN.FIRE = battleRules.rainFirePercent / 100
    end
    if battleRules.sunFirePercent ~= nil then
      Rules.weather.TYPE_MODIFIERS.SUN.FIRE = battleRules.sunFirePercent / 100
    end
    if battleRules.sunWaterPercent ~= nil then
      Rules.weather.TYPE_MODIFIERS.SUN.WATER = battleRules.sunWaterPercent / 100
    end
    if battleRules.thunderSunAccuracy ~= nil then
      Rules.weather.THUNDER_SUN_ACCURACY = battleRules.thunderSunAccuracy
    end
    local Pokemon=require("src.core.game3.pokemon")
    if battleRules.pokerusSpreadDenom ~= nil then
      Pokemon.POKERUS_SPREAD_DENOM = battleRules.pokerusSpreadDenom
      Pokemon.POKERUS_ENABLED = true
    end
    if battleRules.pokerusContractBelow ~= nil then
      Pokemon.POKERUS_CONTRACT_BELOW = battleRules.pokerusContractBelow
      Pokemon.POKERUS_ENABLED = true
    end
    if battleRules.shinyBelow ~= nil then Pokemon.SHINY_BELOW = battleRules.shinyBelow end
    if battleRules.genderRoll ~= nil then Pokemon.GENDER_ROLL = battleRules.genderRoll end
    if battleRules.abilitySlot ~= nil then Pokemon.ABILITY_SLOT = battleRules.abilitySlot end
    local Prize=require("src.core.game3.battle.prize")
    if battleRules.prizeFactor ~= nil then Prize.FACTOR = battleRules.prizeFactor end
    if battleRules.amuletMultiplier ~= nil then Prize.AMULET_MULTIPLIER = battleRules.amuletMultiplier end
    if battleRules.secretBaseFactor ~= nil then Prize.SECRET_BASE_FACTOR = battleRules.secretBaseFactor end
    if battleRules.pickupDenom ~= nil then Prize.PICKUP_DENOM = battleRules.pickupDenom end
    if battleRules.pickupRoll ~= nil then Prize.PICKUP_ROLL = battleRules.pickupRoll end
    if battleRules.pickupBand ~= nil then Prize.PICKUP_BAND = battleRules.pickupBand end
    if battleRules.pickupBandCap ~= nil then Prize.PICKUP_BAND_CAP = battleRules.pickupBandCap end
    if battleRules.pickupRareHigh ~= nil then Prize.PICKUP_RARE_HIGH = battleRules.pickupRareHigh end
    if battleRules.pickupRareLow ~= nil then Prize.PICKUP_RARE_LOW = battleRules.pickupRareLow end
    if battleRules.confusionMin ~= nil then Rules.confusion.MIN = battleRules.confusionMin end
    if battleRules.confusionSpan ~= nil then Rules.confusion.SPAN = battleRules.confusionSpan end
    if battleRules.confusionHit ~= nil then Rules.confusion.HIT = battleRules.confusionHit end
    if battleRules.confusionPower ~= nil then Rules.confusion.POWER = battleRules.confusionPower end
    if battleRules.attractFail ~= nil then Rules.attract.FAIL = battleRules.attractFail end
    if battleRules.stabPercent ~= nil then
      local Damage=require("src.core.game3.battle.damage")
      Damage.STAB_NUM = battleRules.stabPercent
      Damage.STAB_DEN = 100
    end
    if battleRules.screenDiv ~= nil or battleRules.doubleScreenNum ~= nil or battleRules.doubleScreenDen ~= nil or battleRules.explodeDiv ~= nil or battleRules.abilityBoost ~= nil or battleRules.itemBoost ~= nil or battleRules.pinchHpDiv ~= nil or battleRules.heldStatMult ~= nil or battleRules.thickFatDiv ~= nil or battleRules.sportDiv ~= nil or battleRules.compoundEyes ~= nil or battleRules.sandVeil ~= nil or battleRules.hustleAccuracy ~= nil or battleRules.burnDamageDiv ~= nil or battleRules.spreadDiv ~= nil or battleRules.solarBeamDiv ~= nil or battleRules.flashFire ~= nil or battleRules.helpingHand ~= nil or battleRules.chargeMult ~= nil or battleRules.doubleMult ~= nil or battleRules.returnNum ~= nil or battleRules.returnDen ~= nil then
      local Damage=require("src.core.game3.battle.damage")
      if battleRules.screenDiv ~= nil then Damage.SCREEN_DIV = battleRules.screenDiv end
      if battleRules.explodeDiv ~= nil then Damage.EXPLOSION_DEF_DIV = battleRules.explodeDiv end
      if battleRules.abilityBoost ~= nil then
        Damage.ABILITY_BOOST_NUM = battleRules.abilityBoost
        Damage.ABILITY_BOOST_DEN = 100
      end
      if battleRules.itemBoost ~= nil then
        Damage.ITEM_BOOST_NUM = battleRules.itemBoost
        Damage.ITEM_BOOST_DEN = 100
      end
      if battleRules.pinchHpDiv ~= nil then Damage.PINCH_HP_DIV = battleRules.pinchHpDiv end
      if battleRules.heldStatMult ~= nil then Damage.HELD_STAT_MULT = battleRules.heldStatMult end
      if battleRules.thickFatDiv ~= nil then Damage.THICK_FAT_DIV = battleRules.thickFatDiv end
      if battleRules.sportDiv ~= nil then Damage.SPORT_DIV = battleRules.sportDiv end
      if battleRules.compoundEyes ~= nil then Damage.COMPOUND_EYES_PERCENT = battleRules.compoundEyes end
      if battleRules.sandVeil ~= nil then Damage.SAND_VEIL_PERCENT = battleRules.sandVeil end
      if battleRules.hustleAccuracy ~= nil then Damage.HUSTLE_ACC_PERCENT = battleRules.hustleAccuracy end
      if battleRules.burnDamageDiv ~= nil then Damage.BURN_DAMAGE_DIV = battleRules.burnDamageDiv end
      if battleRules.spreadDiv ~= nil then Damage.SPREAD_DIV = battleRules.spreadDiv end
      if battleRules.solarBeamDiv ~= nil then Damage.SOLAR_BEAM_DIV = battleRules.solarBeamDiv end
      if battleRules.flashFire ~= nil then Damage.FLASH_FIRE_PERCENT = battleRules.flashFire end
      if battleRules.helpingHand ~= nil then Damage.HELPING_HAND_PERCENT = battleRules.helpingHand end
      if battleRules.chargeMult ~= nil then Damage.CHARGE_MULT = battleRules.chargeMult end
      if battleRules.doubleMult ~= nil then Damage.DOUBLE_MULT = battleRules.doubleMult end
      if battleRules.returnNum ~= nil then Damage.RETURN_NUM = battleRules.returnNum end
      if battleRules.returnDen ~= nil then Damage.RETURN_DEN = battleRules.returnDen end
      if battleRules.doubleScreenNum ~= nil then Damage.DOUBLE_SCREEN_NUM = battleRules.doubleScreenNum end
      if battleRules.doubleScreenDen ~= nil then Damage.DOUBLE_SCREEN_DEN = battleRules.doubleScreenDen end
    end
    if battleRules.paralysisSkip ~= nil then Rules.paralysis.SKIP = battleRules.paralysisSkip end
    if battleRules.paralysisSpeed ~= nil then Rules.paralysis.SPEED_DIV = battleRules.paralysisSpeed end
    if battleRules.weatherSpeed ~= nil then
      require("src.core.game3.battle.damage").WEATHER_SPEED_MULT = battleRules.weatherSpeed
    end
    local Abilities=require("src.core.game3.battle.abilities")
    if battleRules.earlyBird ~= nil then Abilities.EARLY_BIRD_TURNS = battleRules.earlyBird end
    if battleRules.rainDishDiv ~= nil then Abilities.RAIN_DISH_DIV = battleRules.rainDishDiv end
    if battleRules.absorbDiv ~= nil then Abilities.ABSORB_DIV = battleRules.absorbDiv end
    if battleRules.roughSkinDiv ~= nil then Abilities.ROUGH_SKIN_DIV = battleRules.roughSkinDiv end
    if battleRules.shedSkin ~= nil then Abilities.SHED_SKIN_DENOM = battleRules.shedSkin end
    if battleRules.effectSpore ~= nil then Abilities.EFFECT_SPORE_DENOM = battleRules.effectSpore end
    if battleRules.contactStatus ~= nil then Abilities.CONTACT_STATUS_DENOM = battleRules.contactStatus end
    if battleRules.cuteCharm ~= nil then Abilities.CUTE_CHARM_DENOM = battleRules.cuteCharm end
    if battleRules.intimidateDrop ~= nil then Abilities.INTIMIDATE_DROP = battleRules.intimidateDrop end
    if battleRules.thawChance ~= nil then Rules.freeze.THAW = battleRules.thawChance end
    if battleRules.sleepMin ~= nil then Rules.sleep.MIN = battleRules.sleepMin end
    if battleRules.sleepSpan ~= nil then Rules.sleep.SPAN = battleRules.sleepSpan end
    if battleRules.restTurns ~= nil then Rules.sleep.REST = battleRules.restTurns end
  end
]=]
end
M.ballFields={
  {key="master",slot=1,label="Master Ball",default=255,min=0,max=255},
  {key="ultra",slot=2,label="Ultra Ball",default=20,min=0,max=255},
  {key="great",slot=3,label="Great Ball",default=15,min=0,max=255},
  {key="poke",slot=4,label="Poke Ball",default=10,min=0,max=255},
  {key="safari",slot=5,label="Safari Ball",default=15,min=0,max=255},
  {key="net",slot=6,label="Net Ball",default=10,min=0,max=255},
  {key="dive",slot=7,label="Dive Ball",default=10,min=0,max=255},
  {key="nest",slot=8,label="Nest Ball",default=10,min=0,max=255},
  {key="repeatBall",slot=9,label="Repeat Ball",default=10,min=0,max=255},
  {key="timer",slot=10,label="Timer Ball",default=10,min=0,max=255},
  {key="luxury",slot=11,label="Luxury Ball",default=10,min=0,max=255},
  {key="premier",slot=12,label="Premier Ball",default=10,min=0,max=255},
  {key="netBoost",label="Net Ball type boost",default=30,min=0,max=255},
  {key="diveBoost",label="Dive Ball water boost",default=35,min=0,max=255},
  {key="repeatBoost",label="Repeat Ball owned boost",default=30,min=0,max=255},
  {key="timerCap",label="Timer Ball cap",default=40,min=0,max=255},
  {key="timerBase",label="Timer Ball start",default=10,min=0,max=255},
  {key="timerStep",label="Timer Ball per turn",default=1,min=0,max=255},
  {key="nestLevel",label="Nest Ball level cutoff",default=40,min=1,max=100},
  {key="nestFloor",label="Nest Ball lowest bonus",default=10,min=0,max=255},
}
function M.drawBalls(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3BallScroll","balls",12*s)
  local top=fy
  K.caption(viewX,fy,"BALL CATCH BONUSES")
  fy=fy+28*s
  local values=S.project.gen3BallBonus or {}
  for _,row in ipairs(M.ballFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_ball_"..row.key,viewX+310*s,fy,110*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3BallBonus=S.project.gen3BallBonus or {}
      values=S.project.gen3BallBonus
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3BallBonus=nil end
      App.markDirty()
    end
    fy=fy+38*s
  end
  if values and next(values) and K.button(viewX,fy,160*s,28*s,"Reset to defaults",{}) then
    S.project.gen3BallBonus=nil
    App.markDirty()
  end
  require("FormPane").finish(S,"g3BallScroll",top,fy+36*s,view)
end
function M.emitBalls(p,encode,out)
  local values=p.gen3BallBonus
  if type(values)~="table" or not next(values) then return end
  for _,row in ipairs(M.ballFields) do
    local v=values[row.key]
    assert(v==nil or type(v)=="number" and v%1==0 and v>=row.min and v<=row.max,"Invalid ball bonus "..row.key)
  end
  out[#out+1]="  local ballBonus="..encode(values)
  out[#out+1]=[=[
  mod.events:on("mods.loaded", function()
    local Catching=require("src.core.game3.battle.catching")
]=]
  for _,row in ipairs(M.ballFields) do
    if row.slot then
      out[#out+1]=string.format("    if ballBonus.%s ~= nil then Catching.BALL_BONUS[%d] = ballBonus.%s end",row.key,row.slot,row.key)
    end
  end
  out[#out+1]="    if ballBonus.netBoost ~= nil then Catching.NET_BOOST = ballBonus.netBoost end"
  out[#out+1]="    if ballBonus.diveBoost ~= nil then Catching.DIVE_BOOST = ballBonus.diveBoost end"
  out[#out+1]="    if ballBonus.repeatBoost ~= nil then Catching.REPEAT_BOOST = ballBonus.repeatBoost end"
  out[#out+1]="    if ballBonus.timerCap ~= nil then Catching.TIMER_CAP = ballBonus.timerCap end"
  out[#out+1]="    if ballBonus.timerBase ~= nil then Catching.TIMER_BASE = ballBonus.timerBase end"
  out[#out+1]="    if ballBonus.timerStep ~= nil then Catching.TIMER_STEP = ballBonus.timerStep end"
  out[#out+1]="    if ballBonus.nestLevel ~= nil then Catching.NEST_LEVEL = ballBonus.nestLevel end"
  out[#out+1]="    if ballBonus.nestFloor ~= nil then Catching.NEST_FLOOR = ballBonus.nestFloor end"
  out[#out+1]="  end)"
end
local STAT_PERCENT={
  [-6]=25,[-5]=28,[-4]=33,[-3]=40,[-2]=50,[-1]=66,
  [0]=100,[1]=150,[2]=200,[3]=250,[4]=300,[5]=350,[6]=400,
}
local ACC_PERCENT={
  [-6]=33,[-5]=36,[-4]=43,[-3]=50,[-2]=60,[-1]=75,
  [0]=100,[1]=133,[2]=166,[3]=200,[4]=233,[5]=266,[6]=300,
}
function M.drawStages(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3StageScroll","stages",12*s)
  local top=fy
  local function section(title,field,defaults)
    K.caption(viewX,fy,title)
    fy=fy+28*s
    local values=S.project[field]
    for stage=-6,6 do
      local key=tostring(stage)
      local default=defaults[stage]
      K.caption(viewX,fy,"Stage "..key)
      local old=values and values[key]
      if old==nil then old=default end
      local n=RegList.num(App,"g3_st_"..field.."_"..key,viewX+220*s,fy,90*s,28*s,old)
      n=math.max(0,math.min(1000,math.floor(n)))
      if n~=old then
        S.project[field]=S.project[field] or {}
        values=S.project[field]
        values[key]=n==default and nil or n
        if next(values)==nil then S.project[field]=nil end
        App.markDirty()
      end
      fy=fy+34*s
    end
    fy=fy+8*s
  end
  K.text("micro","Percent of the unmodified stat or accuracy. 100 leaves it alone.",viewX,fy,nil)
  fy=fy+24*s
  section("STAT STAGES", "gen3StatStages", STAT_PERCENT)
  section("ACCURACY STAGES", "gen3AccStages", ACC_PERCENT)
  require("FormPane").finish(S,"g3StageScroll",top,fy,view)
end
function M.emitStages(p,encode,out)
  local function lines(bag)
    local list={}
    if type(bag)~="table" then return list end
    for key,percent in pairs(bag) do
      local stage=tonumber(key)
      local n=tonumber(percent)
      if stage and stage>=-6 and stage<=6 and stage%1==0 and n~=nil then
        n=math.max(0,math.min(1000,math.floor(n)))
        list[#list+1]=string.format("[%d] = { %d, 100 }",stage,n)
      end
    end
    table.sort(list)
    return list
  end
  local stat,acc=lines(p.gen3StatStages),lines(p.gen3AccStages)
  if #stat==0 and #acc==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  if #stat>0 then
    out[#out+1]="    local Damage=require(\"src.core.game3.battle.damage\")"
    for _,line in ipairs(stat) do out[#out+1]="    Damage.STAGE_RATIO"..line end
  end
  if #acc>0 then
    out[#out+1]="    local Rules=require(\"src.core.game3.battle.rules\")"
    for _,line in ipairs(acc) do out[#out+1]="    Rules.ACCURACY_STAGE"..line end
  end
  out[#out+1]="  end)"
end
local CLASS_NAMES = {
  [57]="Youngster",[58]="Bug Catcher",[59]="Lass",[60]="Sailor",[61]="Camper",
  [62]="Picnicker",[63]="Pokemaniac",[64]="Super Nerd",[65]="Hiker",[66]="Biker",
  [67]="Burglar",[68]="Engineer",[69]="Fisherman",[70]="Swimmer M",[71]="Cue Ball",
  [72]="Gamer",[73]="Beauty",[74]="Swimmer F",[75]="Psychic",[76]="Rocker",
  [77]="Juggler",[78]="Tamer",[79]="Bird Keeper",[80]="Black Belt",[81]="Rival early",
  [82]="Scientist",[83]="Boss",[84]="Leader",[85]="Team Rocket",[86]="Cooltrainer",
  [87]="Elite Four",[88]="Gentleman",[89]="Rival late",[90]="Champion",[91]="Channeler",
  [92]="Twins",[93]="Cool Couple",[94]="Young Couple",[95]="Crush Kin",[96]="Sis and Bro",
  [97]="Professor",[98]="Player",[99]="Crush Girl",[100]="Tuber",[101]="Pokemon Breeder",
  [102]="Pokemon Ranger",[103]="Aroma Lady",[104]="Ruin Maniac",[105]="Lady",[106]="Painter",
  [2]="Aqua Leader",[3]="Team Aqua",[4]="RS Aroma Lady",[11]="RS Lady",[12]="RS Beauty",
  [13]="Rich Boy",[24]="RS Leader",[29]="RS Youngster",[30]="RS Champion",[44]="Pokemon Trainer",
  [47]="Magma Leader",[48]="Team Magma",[49]="RS Lass",[55]="Aqua Admin",[56]="Magma Admin",
}
function M.drawClasses(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local Prize=require("src.core.game3.battle.prize")
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3ClassScroll","classes",12*s)
  local top=fy
  K.text("micro","FireRed and LeafGreen pay this factor times the level. Ruby, Sapphire, and Emerald use the same number when a class is changed here. An unchanged class keeps that game's own table. Unknown FireRed classes use the first number, which is 5.",viewX,fy,nil)
  fy=fy+48*s
  local bag=S.project.gen3ClassMoney
  local function shownDefault()
    if bag and bag.default ~= nil then return bag.default end
    return 5
  end
  local function commitDefault(v)
    S.project.gen3ClassMoney=S.project.gen3ClassMoney or {}
    bag=S.project.gen3ClassMoney
    bag.default=v==5 and nil or v
    if bag.default==nil and (type(bag.classes)~="table" or next(bag.classes)==nil) then
      S.project.gen3ClassMoney=nil
      bag=nil
    end
    App.markDirty()
  end
  K.caption(viewX,fy,"Unknown class")
  local old=shownDefault()
  local n=RegList.num(App,"g3_class_default",viewX+220*s,fy,90*s,28*s,old)
  n=math.max(0,math.min(255,math.floor(n)))
  if n~=old then commitDefault(n) end
  fy=fy+40*s
  local rows={}
  for id,value in pairs(Prize.CLASS_MONEY) do
    rows[#rows+1]={id=id,value=value,name=CLASS_NAMES[id] or ("Class "..id)}
  end
  table.sort(rows,function(a,b)
    if a.name==b.name then return a.id<b.id end
    return a.name<b.name
  end)
  local function shown(id,vanilla)
    local classes=bag and bag.classes
    local stored=classes and classes[tostring(id)]
    if stored==nil then return vanilla end
    return stored
  end
  local function commit(id,vanilla,v)
    S.project.gen3ClassMoney=S.project.gen3ClassMoney or {}
    bag=S.project.gen3ClassMoney
    bag.classes=bag.classes or {}
    bag.classes[tostring(id)]=v==vanilla and nil or v
    if next(bag.classes)==nil then bag.classes=nil end
    if bag.default==nil and bag.classes==nil then S.project.gen3ClassMoney=nil; bag=nil end
    App.markDirty()
  end
  for _,row in ipairs(rows) do
    K.caption(viewX,fy,row.name)
    local cur=shown(row.id,row.value)
    local v=RegList.num(App,"g3_class_"..row.id,viewX+220*s,fy,90*s,28*s,cur)
    v=math.max(0,math.min(255,math.floor(v)))
    if v~=cur then commit(row.id,row.value,v) end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3ClassScroll",top,fy,view)
end
function M.emitClasses(p,encode,out)
  local bag=p.gen3ClassMoney
  if type(bag)~="table" then return end
  local lines={}
  if bag.default~=nil then
    local n=math.max(0,math.min(255,math.floor(tonumber(bag.default) or 5)))
    lines[#lines+1]="    Prize.DEFAULT_CLASS_VALUE = "..n
  end
  if type(bag.classes)=="table" then
    local ids={}
    for id in pairs(bag.classes) do ids[#ids+1]=id end
    table.sort(ids)
    for _,id in ipairs(ids) do
      local classId=tonumber(id)
      local n=tonumber(bag.classes[id])
      if classId and classId%1==0 and classId>=0 and n~=nil then
        n=math.max(0,math.min(255,math.floor(n)))
        lines[#lines+1]=string.format("    Prize.CLASS_OVERRIDES[%d] = %d",classId,n)
      end
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Prize=require(\"src.core.game3.battle.prize\")"
  out[#out+1]="    Prize.CLASS_OVERRIDES = Prize.CLASS_OVERRIDES or {}"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.drawFlail(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3FlailScroll","flail",12*s)
  local top=fy
  K.text("micro","Flail and Reversal use remaining HP times the scale, divided by max HP. The cart scale is 48. The lowest band is power 200 and a healthy Pokémon is power 20.",viewX,fy,nil)
  fy=fy+40*s
  local bag=S.project.flailRules
  local cur=bag and bag.scale or 48
  K.caption(viewX,fy,"HP scale")
  local n=RegList.num(App,"g3_flail_scale",viewX+220*s,fy,90*s,28*s,cur)
  n=math.max(0,math.min(255,math.floor(n)))
  if n~=cur then
    S.project.flailRules=S.project.flailRules or {}
    S.project.flailRules.scale=n==48 and nil or n
    if S.project.flailRules.scale==nil and S.project.flailRules.bands==nil then S.project.flailRules=nil end
    App.markDirty()
  end
  fy=fy+40*s
  local vanilla={200,150,100,80,40,20}
  local cuts={1,4,9,16,32}
  for i,power in ipairs(vanilla) do
    local label=cuts[i] and ("Ratio at most "..cuts[i]) or "Healthier"
    K.caption(viewX,fy,label)
    local stored=bag and bag.bands and bag.bands[i] and bag.bands[i].power
    local shown=stored~=nil and stored or power
    local v=RegList.num(App,"g3_flail_p"..i,viewX+220*s,fy,90*s,28*s,shown)
    v=math.max(0,math.min(255,math.floor(v)))
    if v~=shown then
      S.project.flailRules=S.project.flailRules or {}
      local bands={}
      for j,base in ipairs(vanilla) do
        local old=S.project.flailRules.bands and S.project.flailRules.bands[j]
        local p=j==i and v or (old and old.power or base)
        if cuts[j] then bands[j]={atMost=cuts[j],power=p} else bands[j]={power=p} end
      end
      local same=true
      for j,base in ipairs(vanilla) do if bands[j].power~=base then same=false end end
      S.project.flailRules.bands=same and nil or bands
      if S.project.flailRules.scale==nil and S.project.flailRules.bands==nil then S.project.flailRules=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3FlailScroll",top,fy,view)
end
M.moveFields={
  {key="payDay",label="Pay Day coins per level",default=5,min=0,max=255,field="Damage.PAY_DAY_PER_LEVEL"},
  {key="eruptionMin",label="Eruption minimum power",default=1,min=0,max=255,field="Damage.ERUPTION_MIN"},
  {key="rampMult",label="Rollout and Fury Cutter multiplier",default=2,min=0,max=16,field="Damage.RAMP_MULT"},
  {key="curlMult",label="Defense Curl extra multiplier",default=2,min=0,max=16,field="Damage.CURL_MULT"},
  {key="rolloutTurns",label="Rollout turns",default=5,min=1,max=16,field="Damage.ROLLOUT_TURNS"},
  {key="furyCap",label="Fury Cutter doublings",default=5,min=1,max=16,field="Damage.FURY_CAP"},
  {key="futureTurns",label="Future Sight delay",default=3,min=1,max=16,field="Damage.FUTURE_SIGHT_TURNS"},
  {key="hpBase",label="Hidden Power base",default=30,min=0,max=255,field="Damage.HIDDEN_POWER_BASE"},
  {key="hpPowerNum",label="Hidden Power numerator",default=40,min=0,max=255,field="Damage.HIDDEN_POWER_POWER_NUM"},
  {key="hpPowerDen",label="Hidden Power denominator",default=63,min=1,max=255,field="Damage.HIDDEN_POWER_POWER_DEN"},
  {key="hpTypeNum",label="Hidden Power type numerator",default=15,min=0,max=255,field="Damage.HIDDEN_POWER_TYPE_NUM"},
  {key="hpTypeDen",label="Hidden Power type denominator",default=63,min=1,max=255,field="Damage.HIDDEN_POWER_TYPE_DEN"},
  {key="hpTypeSkip",label="Hidden Power type skip",default=9,min=0,max=255,field="Damage.HIDDEN_POWER_TYPE_SKIP"},
  {key="superFangDiv",label="Super Fang divisor",default=2,min=1,max=16,field="Damage.SUPER_FANG_DIV"},
  {key="sonicBoom",label="Sonic Boom damage",default=20,min=0,max=255,field="Damage.SONIC_BOOM"},
  {key="dragonRage",label="Dragon Rage damage",default=40,min=0,max=255,field="Damage.DRAGON_RAGE"},
  {key="psywaveSpan",label="Psywave roll span",default=10,min=0,max=255,field="Damage.PSYWAVE_SPAN"},
  {key="psywaveStep",label="Psywave step",default=10,min=0,max=255,field="Damage.PSYWAVE_STEP"},
  {key="psywaveBase",label="Psywave base",default=50,min=0,max=255,field="Damage.PSYWAVE_BASE"},
  {key="psywaveDen",label="Psywave denominator",default=100,min=1,max=255,field="Damage.PSYWAVE_DEN"},
  {key="recoilDiv",label="Recoil divisor",default=4,min=1,max=16,field="Damage.RECOIL_DIV"},
  {key="recoil33Div",label="One-third recoil divisor",default=3,min=1,max=16,field="Damage.RECOIL_33_DIV"},
  {key="drainDiv",label="Drain divisor",default=2,min=1,max=16,field="Damage.DRAIN_DIV"},
  {key="presentHeal",label="Present heal divisor",default=4,min=1,max=16,field="Damage.PRESENT_HEAL_DIV"},
}
M.healFields={
  {key="recoverDiv",label="Recover divisor",default=2,min=1,max=16,field="Healing.RECOVER_DIV"},
  {key="clearDiv",label="Morning Sun with no weather",default=2,min=1,max=16,field="Healing.CLEAR_DIV"},
  {key="sunNum",label="Morning Sun in sun numerator",default=20,min=0,max=255,field="Healing.SUN_NUM"},
  {key="sunDen",label="Morning Sun in sun denominator",default=30,min=1,max=255,field="Healing.SUN_DEN"},
  {key="badDiv",label="Morning Sun in bad weather",default=4,min=1,max=16,field="Healing.BAD_DIV"},
  {key="bellyDiv",label="Belly Drum cost divisor",default=2,min=1,max=16,field="Healing.BELLY_DIV"},
  {key="curseDiv",label="Ghost Curse cost divisor",default=2,min=1,max=16,field="Healing.CURSE_DIV"},
  {key="wishTurns",label="Wish delay",default=2,min=1,max=16,field="Healing.WISH_TURNS"},
  {key="wishDiv",label="Wish heal divisor",default=2,min=1,max=16,field="Healing.WISH_DIV"},
  {key="substituteDiv",label="Substitute cost divisor",default=4,min=1,max=16,field="Healing.SUBSTITUTE_DIV"},
  {key="swallow1",label="Swallow 1 stock divisor",default=4,min=1,max=16},
  {key="swallow2",label="Swallow 2 stocks divisor",default=2,min=1,max=16},
  {key="swallow3",label="Swallow 3 stocks divisor",default=1,min=1,max=16},
}
M.hitFields={
  {key="doubleHits",label="Double hit count",default=2,min=1,max=16,field="Damage.DOUBLE_HITS"},
  {key="tripleHits",label="Triple Kick count",default=3,min=1,max=16,field="Damage.TRIPLE_KICK_HITS"},
  {key="triplePower",label="Triple Kick power step",default=10,min=0,max=255,field="Damage.TRIPLE_KICK_POWER"},
  {key="perish",label="Perish Song count",default=3,min=1,max=16,field="Volatiles.PERISH_TURNS"},
  {key="encoreMin",label="Encore minimum turns",default=3,min=0,max=16,field="Volatiles.ENCORE_MIN"},
  {key="encoreSpan",label="Encore turn span",default=4,min=1,max=16,field="Volatiles.ENCORE_SPAN"},
}
function M.drawHits(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3HitsScroll","hits",12*s)
  local top=fy
  K.text("micro","Fury-style moves pick one of eight outcomes. The cart is 2, 2, 2, 3, 3, 3, 4, 5. Perish Song starts at 3. Encore lasts 3 to 6 turns.",viewX,fy,nil)
  fy=fy+40*s
  local vanilla={2,2,2,3,3,3,4,5}
  local function shown(i)
    local list=S.project.gen3Hits and S.project.gen3Hits.multiHit
    if list and list[i]~=nil then return list[i] end
    return vanilla[i]
  end
  local function writeHit(i,value)
    local list={}
    local same=true
    for j,base in ipairs(vanilla) do
      local n=j==i and value or shown(j)
      if n~=base then same=false end
      list[j]=n
    end
    S.project.gen3Hits=S.project.gen3Hits or {}
    S.project.gen3Hits.multiHit=same and nil or list
    if next(S.project.gen3Hits)==nil then S.project.gen3Hits=nil end
    App.markDirty()
  end
  for i,base in ipairs(vanilla) do
    K.caption(viewX,fy,"Outcome "..i)
    local n=math.floor(RegList.num(App,"g3_hit_"..i,viewX+220*s,fy,72*s,28*s,shown(i)))
    n=math.max(1,math.min(16,n))
    if n~=shown(i) then writeHit(i,n) end
    fy=fy+34*s
  end
  local values=S.project.gen3Hits or {}
  for _,row in ipairs(M.hitFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_hitf_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3Hits=S.project.gen3Hits or {}
      values=S.project.gen3Hits
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3Hits=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3HitsScroll",top,fy,view)
end
function M.emitHits(p,encode,out)
  local values=p.gen3Hits
  if type(values)~="table" or not next(values) then return end
  local damage,volatile={},{}
  if type(values.multiHit)=="table" then
    local list={}
    for _,n in ipairs(values.multiHit) do
      n=math.max(1,math.min(16,math.floor(tonumber(n) or 2)))
      list[#list+1]=n
    end
    if #list>0 then damage[#damage+1]="    Damage.MULTI_HIT = { "..table.concat(list,", ").." }" end
  end
  for _,row in ipairs(M.hitFields) do
    local v=values[row.key]
    if v~=nil then
      v=math.max(row.min,math.min(row.max,math.floor(tonumber(v) or row.default)))
      local line="    "..row.field.." = "..v
      if row.field:find("Volatiles.",1,true) then volatile[#volatile+1]=line else damage[#damage+1]=line end
    end
  end
  if #damage==0 and #volatile==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  if #damage>0 then
    out[#out+1]="    local Damage=require(\"src.core.game3.battle.damage\")"
    for _,line in ipairs(damage) do out[#out+1]=line end
  end
  if #volatile>0 then
    out[#out+1]="    local Volatiles=require(\"src.core.game3.battle.effects.volatiles\")"
    for _,line in ipairs(volatile) do out[#out+1]=line end
  end
  out[#out+1]="  end)"
end
M.residualFields={
  {key="leechDiv",label="Leech Seed divisor",default=8,min=1,max=255,field="Rules.residual.leechDiv"},
  {key="nightmareDiv",label="Nightmare divisor",default=4,min=1,max=255,field="Rules.residual.nightmareDiv"},
  {key="curseDiv",label="Curse divisor",default=4,min=1,max=255,field="Rules.residual.curseDiv"},
  {key="ingrainDiv",label="Ingrain divisor",default=16,min=1,max=255,field="Rules.residual.ingrainDiv"},
  {key="leftoversDiv",label="Leftovers divisor",default=16,min=1,max=255,field="Rules.residual.leftoversDiv"},
  {key="berryHpDiv",label="Berry HP divisor",default=2,min=1,max=255,field="Rules.residual.berryHpDiv"},
  {key="weatherTurns",label="Weather turns",default=5,min=1,max=255,field="Capabilities.weatherDefaultTurns"},
}
M.specialFields={
  {key="protectBase",label="Protect decay base",default=2,min=1,max=16,field="Volatiles.PROTECT_BASE"},
  {key="protectCap",label="Protect decay cap",default=3,min=0,max=16,field="Volatiles.PROTECT_CAP"},
  {key="bideTurns",label="Bide store turns",default=2,min=1,max=16,field="Damage.BIDE_TURNS"},
  {key="bideMult",label="Bide payback multiplier",default=2,min=0,max=16,field="Damage.BIDE_MULT"},
  {key="ohkoScale",label="OHKO accuracy per level",default=1,min=0,max=16,field="Damage.OHKO_SCALE"},
}
M.lockFields={
  {key="disableMin",label="Disable minimum turns",default=2,min=0,max=16,field="Volatiles.DISABLE_MIN"},
  {key="disableSpan",label="Disable turn span",default=4,min=1,max=16,field="Volatiles.DISABLE_SPAN"},
  {key="spiteMin",label="Spite minimum PP",default=2,min=0,max=16,field="Volatiles.SPITE_MIN"},
  {key="spiteSpan",label="Spite PP span",default=4,min=1,max=16,field="Volatiles.SPITE_SPAN"},
  {key="uproarMin",label="Uproar minimum turns",default=2,min=0,max=16,field="Volatiles.UPROAR_MIN"},
  {key="uproarSpan",label="Uproar turn span",default=4,min=1,max=16,field="Volatiles.UPROAR_SPAN"},
  {key="crashDiv",label="Crash damage divisor",default=2,min=1,max=16,field="Damage.CRASH_DIV"},
  {key="crashCapDiv",label="Crash cap divisor",default=2,min=1,max=16,field="Damage.CRASH_CAP_DIV"},
}
M.switchFields={
  {key="forceOutDiv",label="Level divisor",default=4,min=1,max=255,field="Damage.FORCE_OUT_DIV"},
  {key="forceOutScale",label="Roll scale",default=256,min=1,max=256,field="Damage.FORCE_OUT_SCALE"},
  {key="copyPp",label="Mimic and Transform PP cap",default=5,min=0,max=64,field="Damage.COPY_PP"},
}
M.fleeFields={
  {key="num",label="Speed multiplier",default=128,min=0,max=999,field="Damage.FLEE_NUM"},
  {key="bonus",label="Bonus per try",default=30,min=0,max=255,field="Damage.FLEE_BONUS"},
  {key="cap",label="Roll size",default=256,min=2,max=999,field="Damage.FLEE_CAP"},
}
M.spikeFields={
  {key="maxLayers",label="Maximum layers",default=3,min=1,max=8,field="Hazards.MAX_LAYERS"},
  {key="div1",label="One layer divisor",default=8,min=1,max=255},
  {key="div2",label="Two layer divisor",default=6,min=1,max=255},
  {key="div3",label="Three layer divisor",default=4,min=1,max=255},
}
M.formulaFields={
  {key="levelNum",label="Level numerator",default=2,min=0,max=16,field="Damage.LEVEL_NUM"},
  {key="levelDen",label="Level divisor",default=5,min=1,max=255,field="Damage.LEVEL_DEN"},
  {key="levelAdd",label="Level add",default=2,min=0,max=255,field="Damage.LEVEL_ADD"},
  {key="statDiv",label="Stat divisor",default=50,min=1,max=255,field="Damage.STAT_DIV"},
  {key="minDamage",label="Minimum added",default=2,min=0,max=999,field="Damage.MIN_DAMAGE"},
}
function M.drawFormula(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3FormulaScroll","formula",12*s)
  local top=fy
  K.text("micro","A hit starts from level times the numerator, divided by the denominator, plus the level add. Attack, power, and defense are then divided by the stat divisor, and this minimum is added at the end.",viewX,fy,nil)
  fy=fy+48*s
  local values=S.project.gen3Formula or {}
  for _,row in ipairs(M.formulaFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_fm_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3Formula=S.project.gen3Formula or {}
      values=S.project.gen3Formula
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3Formula=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3FormulaScroll",top,fy,view)
end
function M.emitFormula(p,encode,out)
  local values=p.gen3Formula
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for _,row in ipairs(M.formulaFields) do
    local n=values[row.key]
    if n~=nil then
      n=math.max(row.min,math.min(row.max,math.floor(tonumber(n) or row.default)))
      lines[#lines+1]="    "..row.field.." = "..n
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Damage=require(\"src.core.game3.battle.damage\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
M.accuracyFields={
  {key="hitLo",label="Roll low",default=1,min=0,max=255,field="Damage.HIT_LO"},
  {key="hitHi",label="Roll high",default=100,min=0,max=255,field="Damage.HIT_HI"},
}
M.statCalcFields={
  {key="baseMult",label="Base multiplier",default=2,min=0,max=16,field="Pokemon.STAT_BASE_MULT"},
  {key="evDiv",label="Effort divisor",default=4,min=1,max=255,field="Pokemon.STAT_EV_DIV"},
  {key="levelDen",label="Level divisor",default=100,min=1,max=255,field="Pokemon.STAT_LEVEL_DEN"},
  {key="statAdd",label="Stat add",default=5,min=0,max=255,field="Pokemon.STAT_ADD"},
  {key="hpAdd",label="HP add",default=10,min=0,max=255,field="Pokemon.HP_ADD"},
  {key="hpLevel",label="HP level multiplier",default=1,min=0,max=16,field="Pokemon.HP_LEVEL"},
  {key="natureUp",label="Nature boost percent",default=110,min=0,max=255,field="Pokemon.NATURE_UP"},
  {key="natureDown",label="Nature drop percent",default=90,min=0,max=255,field="Pokemon.NATURE_DOWN"},
}
M.catchFields={
  {key="maxMult",label="Max HP multiplier",default=3,min=0,max=16,field="Catching.HP_MAX_MULT"},
  {key="curMult",label="Current HP multiplier",default=2,min=0,max=16,field="Catching.HP_CUR_MULT"},
  {key="ballDiv",label="Ball divisor",default=10,min=1,max=255,field="Catching.BALL_DIV"},
  {key="sleepNum",label="Sleep and freeze numerator",default=2,min=0,max=255,field="Catching.SLEEP_NUM"},
  {key="sleepDen",label="Sleep and freeze denominator",default=1,min=1,max=255,field="Catching.SLEEP_DEN"},
  {key="statusNum",label="Other status numerator",default=15,min=0,max=255,field="Catching.STATUS_NUM"},
  {key="statusDen",label="Other status denominator",default=10,min=1,max=255,field="Catching.STATUS_DEN"},
  {key="oddsCap",label="Certain catch",default=255,min=1,max=255,field="Catching.ODDS_CAP"},
  {key="shakeTries",label="Shake checks",default=4,min=1,max=8,field="Catching.SHAKE_TRIES"},
  {key="shakeRoll",label="Shake roll maximum",default=65535,min=0,max=65535,field="Catching.SHAKE_ROLL"},
  {key="shakeNum",label="Shake numerator",default=1048560,min=0,max=16711680,field="Catching.SHAKE_NUM"},
  {key="shakeInner",label="Shake inner",default=16711680,min=1,max=16711680,field="Catching.SHAKE_INNER"},
}
M.effortFields={
  {key="perStat",label="Per-stat cap",default=255,min=0,max=999,field="Pokemon.MAX_PER_STAT_EVS"},
  {key="total",label="Total cap",default=510,min=0,max=5994,field="Pokemon.MAX_TOTAL_EVS"},
  {key="pokerus",label="Pokérus multiplier",default=2,min=0,max=16,field="Pokemon.POKERUS_EV_MULT"},
  {key="macho",label="Macho Brace multiplier",default=2,min=0,max=16,field="Pokemon.MACHO_EV_MULT"},
  {key="vitamin",label="Vitamin limit",default=100,min=0,max=999,field="Pokemon.EV_ITEM_RAISE_LIMIT"},
}
M.friendScalars={
  {key="low",label="Low band below",default=100,min=0,max=255,field="Pokemon.FRIENDSHIP_LOW"},
  {key="high",label="High band below",default=200,min=0,max=255,field="Pokemon.FRIENDSHIP_HIGH"},
  {key="sootheNum",label="Soothe Bell numerator",default=150,min=0,max=255,field="Pokemon.SOOTHE_NUM"},
  {key="sootheDen",label="Soothe Bell denominator",default=100,min=1,max=255,field="Pokemon.SOOTHE_DEN"},
  {key="luxury",label="Luxury Ball bonus",default=1,min=0,max=16,field="Pokemon.LUXURY_BONUS"},
  {key="met",label="Met-location bonus",default=1,min=0,max=16,field="Pokemon.MET_BONUS"},
  {key="faintGap",label="Large-faint level gap",default=29,min=0,max=100,field="Pokemon.FAINT_GAP"},
  {key="walkMod",label="Walking skip modulus",default=2,min=1,max=16,field="Pokemon.WALK_SKIP_MOD"},
  {key="walkSteps",label="Steps per walk gain",default=128,min=0,max=65535,field="StepEvents.HAPPINESS_PERIOD"},
}
M.friendEvents={
  {0,"Level up",{5,3,2}},
  {1,"Vitamin and Rare Candy",{5,3,2}},
  {2,"Battle item",{1,1,0}},
  {3,"League battle",{3,2,1}},
  {4,"Learned a TM",{1,1,0}},
  {5,"Walking",{1,1,1}},
  {6,"Massage",{3,3,3}},
  {7,"Fainted",{-1,-1,-1}},
  {8,"Fainted outside battle",{-5,-5,-10}},
  {9,"Fainted to a stronger foe",{-5,-5,-10}},
}
M.bitterHerbs={
  {30,"Energy Powder",{-5,-5,-10}},
  {31,"Energy Root",{-10,-10,-15}},
  {32,"Heal Powder",{-5,-5,-10}},
  {33,"Revival Herb",{-15,-15,-20}},
}
local FRIEND_TIERS={"Low","Mid","High"}
M.ppFields={
  {key="num",label="PP numerator",default=20,min=0,max=255,field="Pokemon.PP_NUM"},
  {key="den",label="PP denominator",default=100,min=1,max=255,field="Pokemon.PP_DEN"},
  {key="maxUps",label="Maximum PP Ups",default=3,min=0,max=3,field="Pokemon.PP_MAX_UPS"},
}
function M.drawPp(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3PpScroll","pp",12*s)
  local top=fy
  K.text("micro","Maximum PP is the base plus base times the numerator times the number of PP Ups, divided by the denominator. The cart uses 20 and 100, which is one fifth per PP Up.",viewX,fy,nil)
  fy=fy+48*s
  local values=S.project.gen3Pp or {}
  for _,row in ipairs(M.ppFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_pp_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3Pp=S.project.gen3Pp or {}
      values=S.project.gen3Pp
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3Pp=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3PpScroll",top,fy,view)
end
local HEAL_HP_NAME={
  [13]="POTION",[22]="SUPER_POTION",[21]="HYPER_POTION",[20]="MAX_POTION",
  [26]="FRESH_WATER",[27]="SODA_POP",[28]="LEMONADE",[29]="MOOMOO_MILK",
  [139]="ORAN_BERRY",[142]="SITRUS_BERRY",
}
function M.emitHealHp(p,encode,out)
  local values=p.gen3HealHp
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for id,name in pairs(HEAL_HP_NAME) do
    local n=values[id]
    if n~=nil then
      n=math.max(0,math.min(9999,math.floor(tonumber(n) or 0)))
      lines[#lines+1]="    ItemsData.HEAL_AMOUNT["..id.."] = "..n
      lines[#lines+1]="    ItemsData.HEAL_AMOUNT."..name.." = "..n
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local ItemsData=require(\"src.core.game3.items_data\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.emitSell(p,encode,out)
  local div=p.sellRules and p.sellRules.div
  if div==nil then return end
  div=math.max(1,math.min(16,math.floor(tonumber(div) or 2)))
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    require(\"src.ui.game3.sell_flow\").SELL_DIV = "..div
  out[#out+1]="  end)"
end
function M.emitHerbHeal(p,encode,out)
  local values=p.gen3HerbHeal
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for _,id in ipairs({30,31}) do
    local n=values[id]
    if n~=nil then
      n=math.max(0,math.min(9999,math.floor(tonumber(n) or 0)))
      lines[#lines+1]="    ItemUse.HERB_HEAL["..id.."] = "..n
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local ItemUse=require(\"src.core.game3.item_use\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.emitXItem(p,encode,out)
  local values=p.gen3XItem
  if type(values)~="table" or values.stages==nil then return end
  local n=math.max(0,math.min(6,math.floor(tonumber(values.stages) or 1)))
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local BattleItems=require(\"src.core.game3.battle.items\")"
  out[#out+1]="    BattleItems.X_STAGE = "..n
  out[#out+1]="  end)"
end
function M.emitVitamin(p,encode,out)
  local values=p.gen3Vitamin
  if type(values)~="table" or values.gain==nil then return end
  local n=math.max(0,math.min(255,math.floor(tonumber(values.gain) or 10)))
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local ItemUse=require(\"src.core.game3.item_use\")"
  out[#out+1]="    ItemUse.VITAMIN_GAIN = "..n
  out[#out+1]="  end)"
end
function M.emitRepel(p,encode,out)
  local values=p.gen3Repel
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for id,amount in pairs(values) do
    local n=math.max(0,math.min(999,math.floor(tonumber(amount) or 0)))
    if type(id)=="number" then
      lines[#lines+1]="    ItemsData.REPEL_STEPS["..id.."] = "..n
    elseif type(id)=="string" and id:match("^[%w_]+$") then
      lines[#lines+1]="    ItemsData.REPEL_STEPS."..id.." = "..n
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local ItemsData=require(\"src.core.game3.items_data\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.emitPpRestore(p,encode,out)
  local values=p.gen3PpRestore
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for id,amount in pairs(values) do
    local n=math.max(0,math.min(63,math.floor(tonumber(amount) or 0)))
    if type(id)=="number" then
      lines[#lines+1]="    ItemUse.PP_RESTORE["..id.."] = "..n
    elseif type(id)=="string" and id:match("^[%w_]+$") then
      lines[#lines+1]="    ItemUse.PP_RESTORE["..string.format("%q", id).."] = "..n
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local ItemUse=require(\"src.core.game3.item_use\")"
  out[#out+1]="    ItemUse.PP_RESTORE = ItemUse.PP_RESTORE or {}"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.emitRevive(p,encode,out)
  local values=p.gen3Revive
  if type(values)~="table" or values.div==nil then return end
  local n=math.max(1,math.min(16,math.floor(tonumber(values.div) or 2)))
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local ItemUse=require(\"src.core.game3.item_use\")"
  out[#out+1]="    ItemUse.REVIVE_DIV = "..n
  out[#out+1]="  end)"
end
function M.emitPp(p,encode,out)
  local values=p.gen3Pp
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for _,row in ipairs(M.ppFields) do
    local n=values[row.key]
    if n~=nil then
      n=math.max(row.min,math.min(row.max,math.floor(tonumber(n) or row.default)))
      lines[#lines+1]="    "..row.field.." = "..n
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Pokemon=require(\"src.core.game3.pokemon\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.drawFriendship(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3FriendScroll","friendship",12*s)
  local top=fy
  K.text("micro","Friendship steps depend on the current band. A Soothe Bell scales a gain. A Luxury Ball and being on the met map add their bonuses after a gain. Walking skips when the random roll modulo this number is 1.",viewX,fy,nil)
  fy=fy+48*s
  local values=S.project.gen3Friendship or {}
  local function commit(key,n,default)
    if n==default then n=nil end
    if n==values[key] then return end
    S.project.gen3Friendship=S.project.gen3Friendship or {}
    values=S.project.gen3Friendship
    values[key]=n
    if next(values)==nil then S.project.gen3Friendship=nil end
    App.markDirty()
  end
  for _,row in ipairs(M.friendScalars) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_fr_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then commit(row.key,n,row.default) end
    fy=fy+34*s
  end
  for _,event in ipairs(M.friendEvents) do
    fy=fy+8*s
    K.caption(viewX,fy,event[2])
    fy=fy+28*s
    for tier=1,3 do
      local key="e"..event[1].."t"..tier
      local default=event[3][tier]
      K.caption(viewX,fy,FRIEND_TIERS[tier])
      local old=values[key]
      if old==nil then old=default end
      local n=RegList.num(App,"g3_fr_"..key,viewX+360*s,fy,90*s,28*s,old)
      n=math.max(-128,math.min(127,math.floor(n)))
      if n~=old then commit(key,n,default) end
      fy=fy+34*s
    end
  end
  for _,herb in ipairs(M.bitterHerbs) do
    fy=fy+8*s
    K.caption(viewX,fy,herb[2])
    fy=fy+28*s
    for tier=1,3 do
      local key="h"..herb[1].."t"..tier
      local default=herb[3][tier]
      K.caption(viewX,fy,FRIEND_TIERS[tier])
      local old=values[key]
      if old==nil then old=default end
      local n=RegList.num(App,"g3_fr_"..key,viewX+360*s,fy,90*s,28*s,old)
      n=math.max(-128,math.min(127,math.floor(n)))
      if n~=old then commit(key,n,default) end
      fy=fy+34*s
    end
  end
  require("FormPane").finish(S,"g3FriendScroll",top,fy,view)
end
function M.emitFriendship(p,encode,out)
  local values=p.gen3Friendship
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for _,row in ipairs(M.friendScalars) do
    local n=values[row.key]
    if n~=nil then
      n=math.max(row.min,math.min(row.max,math.floor(tonumber(n) or row.default)))
      lines[#lines+1]="    "..row.field.." = "..n
    end
  end
  for _,event in ipairs(M.friendEvents) do
    for tier=1,3 do
      local key="e"..event[1].."t"..tier
      local n=values[key]
      if n~=nil then
        n=math.max(-128,math.min(127,math.floor(tonumber(n) or event[3][tier])))
        lines[#lines+1]="    Pokemon.FRIENDSHIP_DELTAS["..event[1].."]["..tier.."] = "..n
      end
    end
  end
  local herbs=false
  for _,herb in ipairs(M.bitterHerbs) do
    for tier=1,3 do
      local n=values["h"..herb[1].."t"..tier]
      if n~=nil then
        herbs=true
        n=math.max(-128,math.min(127,math.floor(tonumber(n) or herb[3][tier])))
        lines[#lines+1]="    ItemUse.BITTER_MEDICINE_FRIENDSHIP["..herb[1].."]["..tier.."] = "..n
      end
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Pokemon=require(\"src.core.game3.pokemon\")"
  out[#out+1]="    local StepEvents=require(\"src.core.game3.step_events\")"
  if herbs then
    out[#out+1]="    local ItemUse=require(\"src.core.game3.item_use\")"
  end
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.drawEffort(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3EffortScroll","effort",12*s)
  local top=fy
  K.text("micro","A defeated Pokémon gives its effort yield. Pokérus and a Macho Brace multiply that yield. Each stat stops at the per-stat cap, and the six stats together stop at the total. Vitamins stop at their own limit.",viewX,fy,nil)
  fy=fy+48*s
  local values=S.project.gen3Effort or {}
  for _,row in ipairs(M.effortFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_ef_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3Effort=S.project.gen3Effort or {}
      values=S.project.gen3Effort
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3Effort=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3EffortScroll",top,fy,view)
end
function M.emitEffort(p,encode,out)
  local values=p.gen3Effort
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for _,row in ipairs(M.effortFields) do
    local n=values[row.key]
    if n~=nil then
      n=math.max(row.min,math.min(row.max,math.floor(tonumber(n) or row.default)))
      lines[#lines+1]="    "..row.field.." = "..n
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Pokemon=require(\"src.core.game3.pokemon\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.drawCatchMath(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3CatchScroll","catchmath",12*s)
  local top=fy
  K.text("micro","Catch odds use max HP times the first multiplier, minus current HP times the second, then the ball bonus divided by the ball divisor. Sleep and freeze use their fraction. Other statuses use theirs. Reaching the certain-catch number skips the shakes.",viewX,fy,nil)
  fy=fy+60*s
  local values=S.project.gen3CatchMath or {}
  for _,row in ipairs(M.catchFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_ct_"..row.key,viewX+360*s,fy,110*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3CatchMath=S.project.gen3CatchMath or {}
      values=S.project.gen3CatchMath
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3CatchMath=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3CatchScroll",top,fy,view)
end
function M.emitCatchMath(p,encode,out)
  local values=p.gen3CatchMath
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for _,row in ipairs(M.catchFields) do
    local n=values[row.key]
    if n~=nil then
      n=math.max(row.min,math.min(row.max,math.floor(tonumber(n) or row.default)))
      lines[#lines+1]="    "..row.field.." = "..n
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Catching=require(\"src.core.game3.battle.catching\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.drawStatCalc(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3StatCalcScroll","statcalc",12*s)
  local top=fy
  K.text("micro","A stat is twice the base, plus the IV, plus effort divided by 4, times the level, divided by 100. HP then adds the level and 10. Other stats add 5, then a boosting nature uses its percent.",viewX,fy,nil)
  fy=fy+48*s
  local values=S.project.gen3StatCalc or {}
  for _,row in ipairs(M.statCalcFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_sc_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3StatCalc=S.project.gen3StatCalc or {}
      values=S.project.gen3StatCalc
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3StatCalc=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3StatCalcScroll",top,fy,view)
end
function M.emitStatCalc(p,encode,out)
  local values=p.gen3StatCalc
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for _,row in ipairs(M.statCalcFields) do
    local n=values[row.key]
    if n~=nil then
      n=math.max(row.min,math.min(row.max,math.floor(tonumber(n) or row.default)))
      lines[#lines+1]="    "..row.field.." = "..n
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Pokemon=require(\"src.core.game3.pokemon\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.drawAccuracy(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3AccuracyScroll","accuracy",12*s)
  local top=fy
  K.text("micro","The accuracy check rolls from the low number through the high number. A hit lands when the roll is less than or equal to the move's accuracy after stages.",viewX,fy,nil)
  fy=fy+48*s
  local values=S.project.gen3Accuracy or {}
  for _,row in ipairs(M.accuracyFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_ac_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3Accuracy=S.project.gen3Accuracy or {}
      values=S.project.gen3Accuracy
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3Accuracy=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3AccuracyScroll",top,fy,view)
end
function M.emitAccuracy(p,encode,out)
  local values=p.gen3Accuracy
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for _,row in ipairs(M.accuracyFields) do
    local n=values[row.key]
    if n~=nil then
      n=math.max(row.min,math.min(row.max,math.floor(tonumber(n) or row.default)))
      lines[#lines+1]="    "..row.field.." = "..n
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Damage=require(\"src.core.game3.battle.damage\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.drawSpikes(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3SpikesScroll","spikes",12*s)
  local top=fy
  K.text("micro","Spikes stack to 3 layers. One layer is an eighth of max HP, two layers a sixth, three layers a quarter. Flying and Levitate take nothing.",viewX,fy,nil)
  fy=fy+48*s
  local values=S.project.gen3Spikes or {}
  for _,row in ipairs(M.spikeFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_spk_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3Spikes=S.project.gen3Spikes or {}
      values=S.project.gen3Spikes
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3Spikes=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3SpikesScroll",top,fy,view)
end
function M.emitSpikes(p,encode,out)
  local values=p.gen3Spikes
  if type(values)~="table" or not next(values) then return end
  local lines={}
  local maxLayers=values.maxLayers
  if maxLayers~=nil then
    maxLayers=math.max(1,math.min(8,math.floor(tonumber(maxLayers) or 3)))
    lines[#lines+1]="    Hazards.MAX_LAYERS = "..maxLayers
  end
  if values.div1~=nil or values.div2~=nil or values.div3~=nil then
    local function take(key, default)
      local n=values[key]
      if n==nil then return default end
      return math.max(1,math.min(255,math.floor(tonumber(n) or default)))
    end
    lines[#lines+1]="    Hazards.DIV = { "..take("div1",8)..", "..take("div2",6)..", "..take("div3",4).." }"
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Hazards=require(\"src.core.game3.battle.effects.hazards\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.drawFlee(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3FleeScroll","flee",12*s)
  local top=fy
  K.text("micro","A faster Pokémon always escapes. Otherwise the chance is your Speed times 128, divided by the foe's Speed, plus 30 for each earlier try, taken out of 256.",viewX,fy,nil)
  fy=fy+48*s
  local values=S.project.gen3Flee or {}
  for _,row in ipairs(M.fleeFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_fl_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3Flee=S.project.gen3Flee or {}
      values=S.project.gen3Flee
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3Flee=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3FleeScroll",top,fy,view)
end
function M.emitFlee(p,encode,out)
  local values=p.gen3Flee
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for _,row in ipairs(M.fleeFields) do
    local v=values[row.key]
    if v~=nil then
      v=math.max(row.min,math.min(row.max,math.floor(tonumber(v) or row.default)))
      lines[#lines+1]="    "..row.field.." = "..v
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Damage=require(\"src.core.game3.battle.damage\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.drawSwitch(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3SwitchScroll","switch",12*s)
  local top=fy
  K.text("micro","A higher-level user always forces the switch. A lower-level user fails when a scaled roll is at or under a quarter of the target's level. Mimic and Transform cap copied PP at 5.",viewX,fy,nil)
  fy=fy+48*s
  local values=S.project.gen3Switch or {}
  for _,row in ipairs(M.switchFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_sw_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3Switch=S.project.gen3Switch or {}
      values=S.project.gen3Switch
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3Switch=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3SwitchScroll",top,fy,view)
end
function M.emitSwitch(p,encode,out)
  local values=p.gen3Switch
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for _,row in ipairs(M.switchFields) do
    local v=values[row.key]
    if v~=nil then
      v=math.max(row.min,math.min(row.max,math.floor(tonumber(v) or row.default)))
      lines[#lines+1]="    "..row.field.." = "..v
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Damage=require(\"src.core.game3.battle.damage\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.drawLocks(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3LocksScroll","locks",12*s)
  local top=fy
  K.text("micro","Disable, Spite, and Uproar each last 2 to 5. Jump Kick crash damage is half the hit, and never more than half the target's max HP.",viewX,fy,nil)
  fy=fy+48*s
  local values=S.project.gen3Locks or {}
  for _,row in ipairs(M.lockFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_lk_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3Locks=S.project.gen3Locks or {}
      values=S.project.gen3Locks
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3Locks=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3LocksScroll",top,fy,view)
end
function M.emitLocks(p,encode,out)
  local values=p.gen3Locks
  if type(values)~="table" or not next(values) then return end
  local damage,volatile={},{}
  for _,row in ipairs(M.lockFields) do
    local v=values[row.key]
    if v~=nil then
      v=math.max(row.min,math.min(row.max,math.floor(tonumber(v) or row.default)))
      local line="    "..row.field.." = "..v
      if row.field:find("Volatiles.",1,true) then volatile[#volatile+1]=line else damage[#damage+1]=line end
    end
  end
  if #damage==0 and #volatile==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  if #damage>0 then
    out[#out+1]="    local Damage=require(\"src.core.game3.battle.damage\")"
    for _,line in ipairs(damage) do out[#out+1]=line end
  end
  if #volatile>0 then
    out[#out+1]="    local Volatiles=require(\"src.core.game3.battle.effects.volatiles\")"
    for _,line in ipairs(volatile) do out[#out+1]=line end
  end
  out[#out+1]="  end)"
end
function M.drawSpecial(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3SpecialScroll","special",12*s)
  local top=fy
  K.text("micro","Protect always works the first time, then succeeds 1 in 2, 1 in 4, and 1 in 8. Bide stores for 2 turns and pays back double. A one-hit KO gains 1 accuracy for each level the user leads by.",viewX,fy,nil)
  fy=fy+48*s
  local values=S.project.gen3Special or {}
  for _,row in ipairs(M.specialFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_sp_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3Special=S.project.gen3Special or {}
      values=S.project.gen3Special
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3Special=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3SpecialScroll",top,fy,view)
end
function M.emitSpecial(p,encode,out)
  local values=p.gen3Special
  if type(values)~="table" or not next(values) then return end
  local damage,volatile={},{}
  for _,row in ipairs(M.specialFields) do
    local v=values[row.key]
    if v~=nil then
      v=math.max(row.min,math.min(row.max,math.floor(tonumber(v) or row.default)))
      local line="    "..row.field.." = "..v
      if row.field:find("Volatiles.",1,true) then volatile[#volatile+1]=line else damage[#damage+1]=line end
    end
  end
  if #damage==0 and #volatile==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  if #damage>0 then
    out[#out+1]="    local Damage=require(\"src.core.game3.battle.damage\")"
    for _,line in ipairs(damage) do out[#out+1]=line end
  end
  if #volatile>0 then
    out[#out+1]="    local Volatiles=require(\"src.core.game3.battle.effects.volatiles\")"
    for _,line in ipairs(volatile) do out[#out+1]=line end
  end
  out[#out+1]="  end)"
end
function M.drawResiduals(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3ResidualScroll","residuals",12*s)
  local top=fy
  K.text("micro","Each divisor is a fraction of max HP. 8 means an eighth. Weather lasts 5 turns. Wrap's length and chip stay on Battle rules.",viewX,fy,nil)
  fy=fy+40*s
  local values=S.project.gen3Residual or {}
  for _,row in ipairs(M.residualFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_res_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3Residual=S.project.gen3Residual or {}
      values=S.project.gen3Residual
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3Residual=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3ResidualScroll",top,fy,view)
end
function M.emitResiduals(p,encode,out)
  local values=p.gen3Residual
  if type(values)~="table" or not next(values) then return end
  local rules,caps={},{}
  for _,row in ipairs(M.residualFields) do
    local v=values[row.key]
    if v~=nil then
      v=math.max(row.min,math.min(row.max,math.floor(tonumber(v) or row.default)))
      local line="    "..row.field.." = "..v
      if row.field:find("Capabilities.",1,true) then caps[#caps+1]=line else rules[#rules+1]=line end
    end
  end
  if #rules==0 and #caps==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  if #rules>0 then
    out[#out+1]="    local Rules=require(\"src.core.game3.battle.rules\")"
    for _,line in ipairs(rules) do out[#out+1]=line end
  end
  if #caps>0 then
    out[#out+1]="    local Capabilities=require(\"src.core.game3.battle.capabilities\")"
    for _,line in ipairs(caps) do out[#out+1]=line end
  end
  out[#out+1]="  end)"
end
function M.drawHeal(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3HealScroll","heal",12*s)
  local top=fy
  K.text("micro","Recover, Morning Sun, Wish, Swallow, Belly Drum, Ghost Curse, and Substitute. Synthesis and Moonlight share Morning Sun. An unchanged row keeps the cart number.",viewX,fy,nil)
  fy=fy+40*s
  local values=S.project.gen3Heal or {}
  for _,row in ipairs(M.healFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_heal_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3Heal=S.project.gen3Heal or {}
      values=S.project.gen3Heal
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3Heal=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3HealScroll",top,fy,view)
end
function M.emitHeal(p,encode,out)
  local values=p.gen3Heal
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for _,row in ipairs(M.healFields) do
    local v=values[row.key]
    if row.field and v~=nil then
      v=math.max(row.min,math.min(row.max,math.floor(tonumber(v) or row.default)))
      lines[#lines+1]="    "..row.field.." = "..v
    end
  end
  if values.swallow1~=nil or values.swallow2~=nil or values.swallow3~=nil then
    local function bite(key, default)
      local n=values[key]
      if n==nil then return default end
      return math.max(1,math.min(16,math.floor(tonumber(n) or default)))
    end
    lines[#lines+1]=string.format("    Healing.SWALLOW = { %d, %d, %d }",bite("swallow1",4),bite("swallow2",2),bite("swallow3",1))
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Healing=require(\"src.core.game3.battle.effects.healing\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.drawMoves(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3MoveScroll","moves",12*s)
  local top=fy
  K.text("micro","Pay Day, Eruption, Rollout, Hidden Power, Present, Super Fang, Psywave, recoil, and drain. An unchanged row keeps the cart number.",viewX,fy,nil)
  fy=fy+36*s
  local values=S.project.gen3MovePower or {}
  for _,row in ipairs(M.moveFields) do
    K.caption(viewX,fy,row.label)
    local old=values[row.key]
    if old==nil then old=row.default end
    local n=RegList.num(App,"g3_move_"..row.key,viewX+360*s,fy,90*s,28*s,old)
    n=math.max(row.min,math.min(row.max,math.floor(n)))
    if n~=old then
      S.project.gen3MovePower=S.project.gen3MovePower or {}
      values=S.project.gen3MovePower
      values[row.key]=n==row.default and nil or n
      if next(values)==nil then S.project.gen3MovePower=nil end
      App.markDirty()
    end
    fy=fy+34*s
  end
  local presentVanilla={
    {below=102,power=40},{below=178,power=80},{below=204,power=120},{heal=true},
  }
  local function presentShown(i,key)
    local stored=S.project.gen3MovePower
    local row=stored and stored.presentBands and stored.presentBands[i]
    if row and row[key]~=nil then return row[key] end
    return presentVanilla[i][key]
  end
  local function writePresent(i,key,value)
    local bands={}
    local same=true
    for j,base in ipairs(presentVanilla) do
      local below=presentShown(j,"below")
      local power=presentShown(j,"power")
      local heal=base.heal and true or nil
      if j==i then
        if key=="below" then below=value elseif key=="power" then power=value end
      end
      if base.heal then bands[j]={heal=true}
      else
        if below~=base.below or power~=base.power then same=false end
        bands[j]={below=below,power=power}
      end
      if heal and not base.heal then same=false end
    end
    S.project.gen3MovePower=S.project.gen3MovePower or {}
    S.project.gen3MovePower.presentBands=same and nil or bands
    if next(S.project.gen3MovePower)==nil then S.project.gen3MovePower=nil end
    App.markDirty()
  end
  for i,base in ipairs(presentVanilla) do
    K.caption(viewX,fy,base.heal and "Present heal" or ("Present below "..base.below))
    if not base.heal then
      local below=math.floor(RegList.num(App,"g3_present_b"..i,viewX+220*s,fy,70*s,28*s,presentShown(i,"below")))
      below=math.max(0,math.min(256,below))
      if below~=presentShown(i,"below") then writePresent(i,"below",below) end
      local power=math.floor(RegList.num(App,"g3_present_p"..i,viewX+300*s,fy,70*s,28*s,presentShown(i,"power")))
      power=math.max(0,math.min(255,power))
      if power~=presentShown(i,"power") then writePresent(i,"power",power) end
    end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3MoveScroll",top,fy,view)
end
function M.emitMoves(p,encode,out)
  local values=p.gen3MovePower
  if type(values)~="table" or not next(values) then return end
  local lines={}
  for _,row in ipairs(M.moveFields) do
    local v=values[row.key]
    if v~=nil then
      v=math.max(row.min,math.min(row.max,math.floor(tonumber(v) or row.default)))
      lines[#lines+1]="    "..row.field.." = "..v
    end
  end
  if type(values.presentBands)=="table" then
    local parts={}
    for _,band in ipairs(values.presentBands) do
      if type(band)=="table" then
        if band.heal then
          parts[#parts+1]="{ heal = true }"
        else
          local below=math.max(0,math.min(256,math.floor(tonumber(band.below) or 0)))
          local power=math.max(0,math.min(255,math.floor(tonumber(band.power) or 0)))
          parts[#parts+1]=string.format("{ below = %d, power = %d }",below,power)
        end
      end
    end
    if #parts>0 then
      lines[#lines+1]="    Damage.PRESENT_BANDS = { "..table.concat(parts,", ").." }"
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Damage=require(\"src.core.game3.battle.damage\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
function M.drawLowKick(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3KickScroll","lowkick",12*s)
  local top=fy
  K.text("micro","Low Kick uses the target's weight. The first row heavier than that weight wins. The cart starts at power 20 under 100 and ends at power 120.",viewX,fy,nil)
  fy=fy+40*s
  local vanilla={
    {below=100,power=20},{below=250,power=40},{below=500,power=60},
    {below=1000,power=80},{below=2000,power=100},{power=120},
  }
  local function shown(i,key)
    local stored=S.project.lowKickBands
    local row=stored and stored[i]
    if row and row[key]~=nil then return row[key] end
    return vanilla[i][key]
  end
  local function write(i,key,value)
    local bands={}
    local same=true
    for j,base in ipairs(vanilla) do
      local below=shown(j,"below")
      local power=shown(j,"power")
      if j==i then
        if key=="below" then below=value else power=value end
      end
      if below~=base.below or power~=base.power then same=false end
      bands[j]=base.below~=nil and {below=below,power=power} or {power=power}
    end
    S.project.lowKickBands=same and nil or bands
    App.markDirty()
  end
  for i,base in ipairs(vanilla) do
    K.caption(viewX,fy,base.below and ("Weight below "..base.below) or "Heavier")
    if base.below~=nil then
      local below=math.floor(RegList.num(App,"g3_kick_b"..i,viewX+180*s,fy,72*s,28*s,shown(i,"below")))
      below=math.max(0,math.min(9999,below))
      if below~=shown(i,"below") then write(i,"below",below) end
    end
    local power=math.floor(RegList.num(App,"g3_kick_p"..i,viewX+270*s,fy,64*s,28*s,shown(i,"power")))
    power=math.max(0,math.min(255,power))
    if power~=shown(i,"power") then write(i,"power",power) end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3KickScroll",top,fy,view)
end
function M.emitLowKick(p,encode,out)
  local bands=p.lowKickBands
  if type(bands)~="table" then return end
  local parts={}
  for _,band in ipairs(bands) do
    if type(band)=="table" then
      local power=math.max(0,math.min(255,math.floor(tonumber(band.power) or 0)))
      if band.below~=nil then
        local below=math.max(0,math.min(9999,math.floor(tonumber(band.below) or 0)))
        parts[#parts+1]=string.format("{ below = %d, power = %d }",below,power)
      else
        parts[#parts+1]=string.format("{ power = %d }",power)
      end
    end
  end
  if #parts==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Damage=require(\"src.core.game3.battle.damage\")"
  out[#out+1]="    Damage.LOW_KICK_BANDS = { "..table.concat(parts,", ").." }"
  out[#out+1]="  end)"
end
function M.drawMagnitude(S,x,y,w,h,App)
  local K=require("Kit");local s=K.scale
  if not S.project then return end
  local RegList=require("RegList")
  local fy,view,viewX=RegList.beginForm(S,x,y,w,h,"g3MagScroll","magnitude",12*s)
  local top=fy
  K.text("micro","A roll from 0 to 99 walks these rows. The first row whose roll is below the cutoff wins. The last row catches everything else. The cart ends at Magnitude 10, power 150.",viewX,fy,nil)
  fy=fy+40*s
  local vanilla={
    {below=5,number=4,power=10},{below=15,number=5,power=30},{below=35,number=6,power=50},
    {below=65,number=7,power=70},{below=85,number=8,power=90},{below=95,number=9,power=110},
    {number=10,power=150},
  }
  local function shown(i,key)
    local stored=S.project.magnitudeBands
    local row=stored and stored[i]
    if row and row[key]~=nil then return row[key] end
    return vanilla[i][key]
  end
  local function write(i,key,value)
    local bands={}
    local same=true
    for j,base in ipairs(vanilla) do
      local below=shown(j,"below")
      local number=shown(j,"number")
      local power=shown(j,"power")
      if j==i then
        if key=="below" then below=value elseif key=="number" then number=value else power=value end
      end
      if below~=base.below or number~=base.number or power~=base.power then same=false end
      bands[j]=base.below~=nil and {below=below,number=number,power=power} or {number=number,power=power}
    end
    S.project.magnitudeBands=same and nil or bands
    App.markDirty()
  end
  for i,base in ipairs(vanilla) do
    K.caption(viewX,fy,"Band "..i)
    if base.below~=nil then
      local below=math.floor(RegList.num(App,"g3_mag_b"..i,viewX+90*s,fy,56*s,28*s,shown(i,"below")))
      below=math.max(0,math.min(100,below))
      if below~=shown(i,"below") then write(i,"below",below) end
    end
    local number=math.floor(RegList.num(App,"g3_mag_n"..i,viewX+160*s,fy,56*s,28*s,shown(i,"number")))
    number=math.max(0,math.min(255,number))
    if number~=shown(i,"number") then write(i,"number",number) end
    local power=math.floor(RegList.num(App,"g3_mag_p"..i,viewX+230*s,fy,56*s,28*s,shown(i,"power")))
    power=math.max(0,math.min(255,power))
    if power~=shown(i,"power") then write(i,"power",power) end
    fy=fy+34*s
  end
  require("FormPane").finish(S,"g3MagScroll",top,fy,view)
end
function M.emitMagnitude(p,encode,out)
  local bands=p.magnitudeBands
  if type(bands)~="table" or bands[1]==nil or bands[1].below==nil and bands[1].number==nil then return end
  if bands[1].at~=nil then return end
  local parts={}
  for _,band in ipairs(bands) do
    if type(band)=="table" then
      local number=math.max(0,math.min(255,math.floor(tonumber(band.number) or 0)))
      local power=math.max(0,math.min(255,math.floor(tonumber(band.power) or 0)))
      if band.below~=nil then
        local below=math.max(0,math.min(100,math.floor(tonumber(band.below) or 0)))
        parts[#parts+1]=string.format("{ below = %d, number = %d, power = %d }",below,number,power)
      else
        parts[#parts+1]=string.format("{ number = %d, power = %d }",number,power)
      end
    end
  end
  if #parts==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Damage=require(\"src.core.game3.battle.damage\")"
  out[#out+1]="    Damage.MAGNITUDE_BANDS = { "..table.concat(parts,", ").." }"
  out[#out+1]="  end)"
end
function M.emitFlail(p,encode,out)
  local bag=p.flailRules
  if type(bag)~="table" then return end
  local lines={}
  if bag.scale~=nil then
    local scale=math.max(0,math.min(255,math.floor(tonumber(bag.scale) or 48)))
    lines[#lines+1]="    Damage.FLAIL_SCALE = "..scale
  end
  if type(bag.bands)=="table" then
    local parts={}
    for i,band in ipairs(bag.bands) do
      if type(band)=="table" then
        local power=math.max(0,math.min(255,math.floor(tonumber(band.power) or 0)))
        if band.atMost~=nil then
          local atMost=math.max(0,math.min(255,math.floor(tonumber(band.atMost) or 0)))
          parts[#parts+1]=string.format("{ atMost = %d, power = %d }",atMost,power)
        else
          parts[#parts+1]=string.format("{ power = %d }",power)
        end
      end
    end
    if #parts>0 then
      lines[#lines+1]="    Damage.FLAIL_BANDS = { "..table.concat(parts,", ").." }"
    end
  end
  if #lines==0 then return end
  out[#out+1]="  mod.events:on(\"mods.loaded\", function()"
  out[#out+1]="    local Damage=require(\"src.core.game3.battle.damage\")"
  for _,line in ipairs(lines) do out[#out+1]=line end
  out[#out+1]="  end)"
end
return M
