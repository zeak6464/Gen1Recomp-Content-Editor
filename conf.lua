function love.conf(t)
  love.filesystem.setSymlinksEnabled(true)
  t.identity = os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d"
  t.version = "11.5"
  t.window.title = "Gen1Recomp Content Editor"
  t.window.width = 1360
  t.window.height = 860
  t.window.minwidth = 720
  t.window.minheight = 540
  t.window.resizable = true
  t.window.vsync = 1
  t.modules.physics = false
  if type(arg) == "table" then
    for i = -5, 40 do
      if arg[i] == "--pokemonium-pack" then
        t.console = true
        t.window.vsync = 0
        break
      end
    end
  end
end
