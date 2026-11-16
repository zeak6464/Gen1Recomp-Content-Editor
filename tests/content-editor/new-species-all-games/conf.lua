function love.conf(t)
  t.identity = "new-species-verification"
  t.window.visible = false
  t.window.width = 1400
  t.window.height = 900
  t.modules.audio = os.getenv("CRY_CHECK") == "1"
end
