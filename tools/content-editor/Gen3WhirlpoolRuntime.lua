-- Export source (not bytecode) for whirlpools (Gen3Whirlpool): the game side.
--
-- Four engine functions are wrapped the way the other editor runtimes do it
-- (Runtime.call + mod.hooks:wrap); nothing in the engine is changed:
--   Collision.canEnter   -- whirlpool cells can't be entered (except crossing)
--   Collision.isWater    -- while crossing, whirlpool cells count as water, so
--                           the player stays surfing the whole way
--   Field.interact       -- A facing a whirlpool while surfing: the prompt
--   Field.updateWaterfall-- runs every frame: carries the player across
-- A cell is a whirlpool when its behaviour is the whirlpool one
-- (Gen3Whirlpool.BEHAVIOR): cells painted with the map editor's Whirlpool
-- collision get it, and so does a block with that behaviour on an untouched
-- game map.
return function(data, encode)
  return "  local whirl=" .. encode(data) .. "\n"
    .. [=[
  mod.events:on("game.ready",function(ctx)
    local Field=require("src.core.game3.field")
    local Collision=require("src.core.game3.collision")
    local Player=require("src.core.game3.player")
    local Runtime=require("src.mods.Runtime")
    local DELTA={up={0,-1},down={0,1},left={-1,0},right={1,0}}
    local crossing=nil

    local function bridge(object,name,key)
      if object[key] then return end
      object[key]=true
      local original=object[name]
      object[name]=function(...) return Runtime.call(key,original,...) end
    end
    bridge(Collision,"canEnter","editor.gen3.whirlpool.enter")
    bridge(Collision,"isWater","editor.gen3.whirlpool.water")
    bridge(Field,"interact","editor.gen3.whirlpool.interact")
    bridge(Field,"updateWaterfall","editor.gen3.whirlpool.tick")

    -- A whirlpool is a cell whose behaviour is the whirlpool one: painted
    -- with the map editor's Whirlpool collision (or a block that has it).
    local function isWhirl(x,y)
      local ok,beh=pcall(Collision.behavior,x,y)
      return ok and beh==whirl.behavior
    end

    -- Nobody surfs into a whirlpool; the crossing itself is let through.
    mod.hooks:wrap("editor.gen3.whirlpool.enter",function(proceed,game,tx,ty,opts,...)
      if not crossing and isWhirl(tx,ty) then return false,"tile" end
      return proceed(game,tx,ty,opts,...)
    end)

    -- While crossing, the whirlpool is water: the player stays on the Surf
    -- mount (the engine drops Surf after a step onto anything that isn't).
    mod.hooks:wrap("editor.gen3.whirlpool.water",function(proceed,x,y,...)
      if crossing and isWhirl(x,y) then return true end
      return proceed(x,y,...)
    end)

    local function partyMon()
      local FieldMoves=require("src.core.game3.field_moves")
      local party=Field._session and Field._session.party or {}
      for _,mon in ipairs(party) do
        if mon and not mon.isEgg and not mon.egg then
          for _,m in ipairs(mon.moves or {}) do
            if FieldMoves.normalizeMoveId(type(m)=="table" and (m.id or m.move) or m)==whirl.move then return mon end
          end
        end
      end
      return nil
    end
    local function hasBadge()
      if not whirl.flag then return true end
      local Space=package.loaded["src.core.game3.scripting.space"]
      local Flags=require("src.core.game3.scripting.flags")
      if Space and Space.store then return Flags.getFlag(Space.store,nil,whirl.flag) and true or false end
      local flags=Field._session and Field._session.flags
      return flags and flags[whirl.flag] and true or false
    end

    mod.hooks:wrap("editor.gen3.whirlpool.interact",function(proceed,game,...)
      if crossing or Field.locked or not Field.running or Player.moving or not Player.surfing then
        return proceed(game,...)
      end
      local d=DELTA[Player.facing]
      if not d then return proceed(game,...) end
      local fx,fy=Player.cellX+d[1],Player.cellY+d[2]
      if not isWhirl(fx,fy) then return proceed(game,...) end
      local R=package.loaded["src.core.game3.runtime"]
      if R and R.uiBusy and R.uiBusy() then return false end
      local Space=package.loaded["src.core.game3.scripting.space"]
      if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then return false end

      -- The far side: the first cell past the whirlpool must take a surfer.
      local x,y,n=fx,fy,0
      while n<16 and isWhirl(x,y) do x,y,n=x+d[1],y+d[2],n+1 end
      local land=n<16 and Collision.canEnter(game or Field._game,x,y,{fromX=x-d[1],fromY=y-d[2],
        dir=Player.facing,surfing=true,elevation=Player.currentElevation})
      local Message=require("src.ui.game3.message")
      local mon=partyMon()
      if not mon or not hasBadge() or not land then
        Message.show(whirl.cant,function() Message.close() end)
        return true
      end
      local Choice=require("src.ui.game3.choice")
      local dir=Player.facing
      Message.show(whirl.ask,function()
        Choice.yesNo(function(yes)
          if not yes then Message.close() return end
          Field.locked=true
          local name=require("src.core.game3.pokemon").displayMonName(mon) or "POKéMON"
          Message.show((whirl.used:gsub("{MON}",(tostring(name):gsub("%%","%%%%")))),function()
            Message.close()
            require("src.core.game3.field_move_show_mon").start(mon,{pose=false},function()
              crossing={dir=dir,started=false,steps=0,cells=n}
            end)
          end)
        end)
      end)
      return true
    end)

    -- How long the crossing sound lasts, in seconds, once the game has
    -- baked it (it keeps the baked samples); nil when it can't tell.
    local function soundSeconds()
      local okA,Audio=pcall(require,"src.core.game3.audio")
      local okS,SE=pcall(require,"src.core.game3.se_ids")
      local okM,Mix=pcall(require,"src.core.game3.m4a_mix")
      local id=okS and SE and SE.resolve and SE.resolve(whirl.sound)
      local baked=okA and id and type(Audio._seRaw)=="table" and Audio._seRaw[id]
      local rate=okM and Mix and tonumber(Mix.SAMPLE_RATE)
      if baked and not baked.loop and tonumber(baked.frames) and rate and rate>0 then
        return baked.frames/rate
      end
      return nil
    end

    -- Every frame: one slow step at a time until past the whirlpool. The
    -- sound plays once, and the steps are paced so the player comes out of
    -- the whirlpool as it ends.
    mod.hooks:wrap("editor.gen3.whirlpool.tick",function(proceed,game,...)
      local st=crossing
      if not st then return proceed(game,...) end
      if not st.started and not st.frames then
        st.frames=whirl.frames or 32
        if whirl.sound then
          local okA,Audio=pcall(require,"src.core.game3.audio")
          if okA and Audio and Audio.playSe then pcall(Audio.playSe,whirl.sound) end
          local secs=soundSeconds()
          -- the cells of the whirlpool, plus the step out onto open water
          if secs then st.frames=math.max(16,math.floor(secs*60/((st.cells or 2)+1)+0.5)) end
        end
      end
      if Player.moving then return end
      if (st.started and not isWhirl(Player.cellX,Player.cellY)) or st.steps>=18 then
        crossing=nil
        Field.locked=false
        return
      end
      st.started=true
      st.steps=st.steps+1
      Player.forceStep(st.dir,function() end)
      Player.stepFrames=st.frames
    end)
  end,-200)
]=]
end
