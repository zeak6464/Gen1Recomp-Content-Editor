local root=assert(os.getenv("EDITOR_TEST_ROOT")):gsub("\\","/")
package.path=root.."/tools/content-editor/?.lua;"..root.."/tools/save-editor/?.lua;"..package.path
function love.load()
  local ok,err=xpcall(function() dofile(root.."/tests/content-editor/test_gen3_pokemon_icons.lua") end,debug.traceback)
  love.graphics.setCanvas()
  print(ok and "PASS: Pokemon icon import/export, preview, revert, runtime override" or err)
  love.event.quit(ok and 0 or 1)
end

