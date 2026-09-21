local M={}
function M.draw(x,y,w,h)
  local s=require("Kit").scale
  love.graphics.push("all");love.graphics.setColor(.65,.75,.9,1)
  local cx,cy=x+w-12*s,y+h/2
  love.graphics.polygon("fill",cx-4*s,cy-2*s,cx+4*s,cy-2*s,cx,cy+3*s)
  love.graphics.pop()
end
return M
