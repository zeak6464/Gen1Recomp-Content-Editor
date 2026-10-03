-- The new-game intro of a clean project (GAME PATCHES > Clean Project): only
-- the player's questions -- boy or girl, and their name. No help pages, no
-- professor, no rival. The title screen and main menu are unchanged.
--
-- Shared by the game (Gen3Clean inlines this file into main.lua) and the
-- editor's intro preview. Nothing in the engine is changed: the scene's own
-- tasks are re-pointed as they run (pokefirered/src/oak_speech.c order).
local M = {}

M.LINES = {
  ask_gender = "Are you a boy?\nOr are you a girl?",
  your_name = "What is your name?\f",
  confirm_player = "So your name is {PLAYER}?",
}

function M.configure(scene)
  if type(scene) ~= "table" or rawget(scene, "_cleanIntroConfigured") then return scene end
  scene._cleanIntroConfigured = true
  local Scene = require("src.ui.game3.new_game_scene")
  -- no controls guide or Pikachu pages: straight to the questions
  if scene.bgVisible then scene.bgVisible[0], scene.bgVisible[1] = true, true end
  scene.tasks = {}
  local task = scene:createTask(Scene.Task_OakSpeech_Init, 0)
  task.data.timer = 0
  -- the question lines, without the professor: the scene prints them as it
  -- prints its own (its text box, speed and page breaks), only the words
  -- differ -- the ROM line it asks for is answered with ours, once.
  local print = scene.oakPrint
  scene.oakPrint = function(self, key, speed)
    local line = M.LINES[key]
    if not line then return print(self, key, speed) end
    local RomText = require("src.core.game3.rom_text")
    local ascii = RomText.ascii
    RomText.ascii = function(_, ctx)
      RomText.ascii = ascii
      return (line:gsub("{PLAYER}", function() return tostring((ctx or {}).playerName or self.playerName or "") end))
    end
    local ok, err = pcall(print, self, key, speed)
    RomText.ascii = ascii
    if not ok then error(err, 0) end
  end
  local remap = {}
  -- the professor never appears: after the scene is set up, ask boy or girl
  remap[Scene.Task_OakSpeech_WelcomeToTheWorld] = function(self, t)
    self:clearTrainerPic()
    t.data.picFadeState, t.data.timer = 1, 0
    t.func = Scene.Task_OakSpeech_AskPlayerGender
  end
  -- the name confirmed: no rival -- show the player again and go
  remap[Scene.Task_OakSpeech_FadeOutPlayerPic] = Scene.Task_OakSpeech_ReshowPlayersPic
  remap[Scene.Task_OakSpeech_LetsGo] = function(self, t)
    if t.data.picFadeState == 0 then return end
    t.data.timer = 30
    t.func = Scene.Task_OakSpeech_FadeOutBGM
  end
  local run = scene.runTasks
  scene.runTasks = function(self, ...)
    for _, t in ipairs(self.tasks) do
      local to = remap[t.func]
      if to then t.func = to end
    end
    return run(self, ...)
  end
  return scene
end

--- Emerald (pokeemerald/src/main_menu.c birch speech): the same short intro
-- -- the player fades in at once, is asked boy or girl and a name, then
-- shrinks into the game. No professor or Pokemon, and no moving truck.
function M.configureBirch(scene)
  if type(scene) ~= "table" or rawget(scene, "_cleanIntroConfigured") then return scene end
  scene._cleanIntroConfigured = true
  local remap = {}
  -- the scene is set up: straight to the player (the platform already
  -- slid aside, nothing fading)
  remap.WaitToShowBirch = function(self, m)
    m.timer, m.bg1hofs, m.doneFading = 0, -60, true
    self.showDialogue = true
    self:clearWindow()
    m.func = "StartPlayerFadeIn"
  end
  -- the name confirmed: the player comes back to the middle and goes
  remap.ReshowBirchLotad = function(self, m)
    if not m.doneFading then return end
    local sprites = self.sprites
    sprites.brendan.invisible, sprites.may.invisible = true, true
    local key = self.gender ~= 0 and "may" or "brendan"
    local s = sprites[key]
    s.x, s.y, s.invisible, s.blend = 120, 60, false, true
    m.player = key
    self:startFadeInTarget1OutTarget2(2)
    self:startFadePlatformOut(1)
    self:clearWindow()
    self.showDialogue = false
    m.func = "ShrinkPlayer"
  end
  -- the scene's own steps are swapped for ours only while this scene runs
  -- a frame (its tasks, sprites and fades run as always)
  local frame = scene.frame
  scene.frame = function(self, inp)
    local steps = getmetatable(self).TASKS or {}
    local kept = {}
    for name, fn in pairs(remap) do kept[name] = steps[name]; steps[name] = fn end
    local ok, result = pcall(frame, self, inp)
    for name in pairs(remap) do steps[name] = kept[name] end
    if not ok then error(result, 0) end
    -- the game starts on the start map, not in the truck
    if type(result) == "table" then result.fieldCallback = nil end
    return result
  end
  return scene
end

return M
