local M={}
local tips={
  graphicsId="Choose the picture used for this character or object on the map. This changes its appearance, not its dialogue or actions.",
  movementType="Choose whether this character stands still, looks around, or walks around its starting tile.",
  elevation="The map's elevation layer, not the character's size. Match the height of the tile where the event belongs. Different heights are used for places such as bridges. Height 3 is commonly used for ordinary ground; 0 means any height.",
  x="Horizontal tile position, counted from the left edge starting at 0. Column 9 is the tenth tile from the left. You can also drag the event on the map.",
  y="Vertical tile position, counted from the top edge starting at 0. Row 6 is the seventh tile from the top. You can also drag the event on the map.",
  destMap="The map the player enters when using this exit, such as the inside of a building.",
  destWarp="The destination map's exit index. It selects the arrival exit on that map, not a tile position. Match the index of the exit you want to connect to.",
  flag="A saved story switch that hides this character or object when turned on. For example, hide an item after it is collected. Set 0 to never hide it using a flag.",
  var="The saved story variable this step-on event checks. A variable stores a number, such as the current stage of a quest.",
  value="Run this event only when its story variable equals this number. For example, value 2 can mean the second stage of a quest.",
}
function M.draw(S,ev,kind,indexKey,x,y,w,App)
  local K=require("Kit");local P=require("ChoicePicker");local s=K.scale
  local function set(key,value,alias)
    assert(require("Gen3Workspace").convert(S,S.mapId))
    local row=S.project.maps[S.mapId][kind][S[indexKey]]
    row[key]=value;if alias then row[alias]=value end
    if key=="movementType" then local m=require("src.core.game3.scripting.gfx_ids").hostMovement(value,row.rangeX,row.rangeY);row.movement=m.movement;row.range=m.range;row.radius=m.radius end
    S._g3EventIdentity=nil;App.markDirty()
  end
  local function pick(key,label,values,alias)
    K.caption(x,y,label);K.offerTooltip(x,y,w,22*s,tips[key]);y=y+22*s
    local ids,labels={},{}
    for id,name in pairs(values) do ids[#ids+1]=tostring(id);labels[tostring(id)]=name end
    local current=tostring(ev[key] or (alias and ev[alias]) or 0)
    if not labels[current] then ids[#ids+1]=current;labels[current]="Keep current ("..current..")" end
    table.sort(ids,require("Gen3Labels").natural)
    P.field(S,{x=x,y=y,w=w,h=28*s,ids=ids,labels=labels,current=current,title=label,tooltip=tips[key],onPick=function(v) set(key,tonumber(v) or v,alias) end});y=y+37*s
  end
  local function number(key,label)
    K.caption(x,y,label);K.offerTooltip(x,y,w,22*s,tips[key]);y=y+22*s
    local old=ev[key] or 0
    local value=K.textfield("mapEvent/"..kind.."/"..key,x,y,w,28*s,tostring(old),"",tips[key])
    local n=tonumber(value);if n and n>=0 and n%1==0 and n~=old then set(key,n) end
    y=y+37*s
  end
  if kind=="objects" then
    local names={}
    for path in pairs(require("Gen3Resources").assets(S.data)) do local id=path:match("/ow/(%d+)%.rgba$");if id then names[tonumber(id)]="Overworld sprite "..id end end
    pick("graphicsId","Character / object sprite",names,"graphics")
    require("Gen3MapSprites").draw(S,ev,x+16*s,y+16*s);y=y+48*s
    pick("movementType","Movement",{[0]="Stay in place",[1]="Look around",[2]="Walk around",[7]="Face up",[8]="Face down",[9]="Face left",[10]="Face right"})
  end
  if kind~="warps" then
    local levels={[0]="Any height"};for i=1,15 do levels[i]="Height "..i end
    pick("elevation","Walking height",levels)
  else
    local names={};for _,id in ipairs(require("RegList").mergeIds(S.project.maps or {},S.data.maps or {})) do names[id]=require("Gen3Names").map(id) end
    pick("destMap","Destination map",names)
    number("destWarp","Destination exit number")
  end
  number("x","Position: column");number("y","Position: row")
  if kind=="objects" then number("flag","Hide when this story flag is set (0 = never)") end
  if kind=="coordEvents" then number("var","Story variable to check");number("value","Start when its value equals") end
  return y
end
return M
