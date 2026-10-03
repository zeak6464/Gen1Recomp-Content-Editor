-- Export source (not bytecode): plays a song of the OTHER Gen 3 game on a map.
-- A song of the other game is written as base + its song number (see
-- Gen3ForeignMusic). The song is read from the player's own import of that
-- game and played through the engine's own sequencer and mixer, on the game's
-- music source, so volume, pause, fades and fanfares work as they do for the
-- game's own songs. Nothing is changed in the engine, and nothing of the other
-- game is carried by the mod.
local M = {}

local ORIGIN_ID = { emerald = { "emerald" }, firered = { "firered", "leafgreen" } }

function M.install(mod, cfg)
  cfg = cfg or {}
  local okA, Audio = pcall(require, "src.core.game3.audio")
  local okP, Player = pcall(require, "src.core.game3.m4a_player")
  local okM, Mix = pcall(require, "src.core.game3.m4a_mix")
  local okG, GV = pcall(require, "src.core.GameVersion")
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if not (okA and okP and okM and okG and okC) then return end
  local base = tonumber(cfg.base) or 0x4000
  local span = 0x1000
  local origin = cfg.origin == "firered" and "firered" or "emerald"

  if Audio._foreignMusic then return end
  local St = { slot = nil, pack = nil, cache = nil, prefix = nil }
  Audio._foreignMusic = St

  -- the player's import of the other game ("emerald/", "firered/" or "leafgreen/")
  for _, id in ipairs(ORIGIN_ID[origin]) do
    local prefix = GV.cachePrefix(id)
    local okR, marker = pcall(CacheFs.readAt, prefix .. "rom-cache.complete")
    if okR and type(marker) == "string" and marker:find("^rom%-cache%-v%d+%-" .. id .. ":") then
      St.prefix = prefix
      break
    end
  end
  if not St.prefix then return end

  local function loadPack()
    if St.pack ~= nil then return St.pack end
    St.pack = false
    local cache = {
      read = function(_, rel)
        local ok, bytes = pcall(CacheFs.readAt, St.prefix .. rel)
        return ok and bytes or nil
      end,
    }
    local pack = Player.loadPack(cache, "data/generated/gba/audio")
    if pack then St.pack, St.cache = pack, cache end
    return St.pack
  end

  local function isForeign(id)
    local n = tonumber(id)
    return n ~= nil and n >= base and n < base + span
  end

  local function stopForeign()
    if St.slot and Audio._bgmLocal == St.slot then Audio._bgmLocal = nil end
    St.slot = nil
  end

  local function source()
    if Audio._bgmSource then return Audio._bgmSource end
    if not (love and love.audio and love.audio.newQueueableSource) then return nil end
    Audio._bgmRate = Mix.SAMPLE_RATE
    Audio._bgmSource = love.audio.newQueueableSource(Audio._bgmRate, 16, 2, Player.BUFFER_COUNT)
    if Audio.applyBgmFilter then Audio.applyBgmFilter() end
    return Audio._bgmSource
  end

  local playSong = Audio.playSong
  Audio.playSong = function(id, opts)
    opts = opts or {}
    local n = tonumber(id)
    if not isForeign(n) then
      stopForeign()
      return playSong(id, opts)
    end
    if not opts.restart and Audio._currentSong and Audio._currentSong.id == n and St.slot then return true end
    local pack = loadPack()
    if not pack then
      -- the other game isn't imported: stay quiet rather than play the wrong song
      stopForeign()
      return playSong(0, opts)
    end
    -- the new song owns the music bus (as in the engine's own playSong)
    Audio._currentSong = { id = n, loop = true, startedAt = os.clock and os.clock() or 0 }
    Audio._mapSong = Audio._mapSong or n
    Audio._fadeOut, Audio._fadeIn = nil, nil
    Audio._fanfareActive, Audio._fanfareFrames = false, 0
    Audio._fanfareRestore, Audio._fanfareDeferred, Audio._fanfarePending = nil, nil, nil
    Audio._bgmPaused = false
    -- silence the engine's own song and drop what it already rendered
    if Audio._cmdCh then Audio._cmdCh:push({ cmd = "stop" }) end
    Audio._bgmEpoch = (Audio._bgmEpoch or 0) + 1
    if Audio._outCh then Audio._outCh:clear() end
    Audio._pendingBgm = nil
    Audio._bgmQueuedAt = {}
    Audio._bgmBaseAt = 0
    local native = n - base
    local slot = { voices = {}, songId = native }
    if not Player.start(pack, St.cache, slot, native, { forceSeq = true }) then
      Audio._currentSong = nil
      stopForeign()
      return true
    end
    Audio._bgmLocal, St.slot = slot, slot
    Audio._bgmGen = n
    local src = source()
    if src then
      pcall(function()
        src:stop()
        if Audio.applyGain then Audio.applyGain() end
      end)
    end
    return true
  end

  -- With the engine's music thread running it doesn't render a song held in
  -- Audio._bgmLocal (that is only its fallback without a thread), so this
  -- does it the same way: one buffer when the music source has room.
  local update = Audio.update
  Audio.update = function(dt, ...)
    local result = update(dt, ...)
    local slot = St.slot
    if slot and Audio._bgmLocal == slot and Audio._worker and Audio._bgmSource
        and not Audio._bgmPaused and not Audio._suspended then
      local src = Audio._bgmSource
      local okFree, free = pcall(src.getFreeBufferCount, src)
      if okFree and type(free) == "number" and free > 0 then
        local okR, sd = pcall(Player.renderBuffered, slot, Player.BUFFER_SAMPLES, {
          master = 1, sampleRate = Mix.SAMPLE_RATE })
        if okR and sd then
          pcall(function()
            src:queue(sd)
            if not src:isPlaying() then src:play() end
          end)
        end
      end
    end
    return result
  end
end

return M
