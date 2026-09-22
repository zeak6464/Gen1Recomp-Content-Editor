-- Movement names follow the FireRed runtime's decoded actions.
local M={names={},choices={}}
local function add(byte,label)
  M.names[byte]=label;M.choices[#M.choices+1]=tostring(byte)
end
local function directions(first,verb)
  for i,dir in ipairs({"down","up","left","right"}) do add(first+i-1,verb.." "..dir) end
end
for _,group in ipairs({{0,"Face"},{4,"Turn"},{8,"Walk very slowly"},{12,"Walk slowly"},{16,"Walk"},
  {20,"Jump two tiles"},{29,"Walk fast"},{33,"Turn in place"},{37,"Turn in place slowly"},
  {41,"Turn in place fast"},{45,"Turn in place very fast"},{53,"Walk faster"},{57,"Walk very fast"},
  {61,"Run"},{65,"Run slowly"},{70,"Hop"},{78,"Jump one tile"},{82,"Turn with a jump"},
  {86,"Turn with a quick jump"},{166,"Jump with an effect"}}) do directions(group[1],group[2]) end
for i,frames in ipairs({2,4,8,16,32}) do add(23+i,"Wait "..frames.." frames ("..string.format("%.2f",frames/60).." seconds)") end
for byte,label in pairs({[74]="Face the player",[75]="Face away from the player",[76]="Keep facing this direction",[77]="Allow turning",
  [90]="Face the original direction",[91]="Bow",[94]="Stop the character's animation",[95]="Resume the character's animation",
  [96]="Hide the character",[97]="Show the character",[98]="Show an exclamation mark",[99]="Show a question mark",
  [100]="Show an X mark",[101]="Show two exclamation marks",[102]="Show a smile",[104]="Break a rock",[105]="Cut down a tree"}) do add(byte,label) end
table.sort(M.choices,function(a,b) return M.names[tonumber(a)]<M.names[tonumber(b)] end)
function M.label(byte) return M.names[byte] or "Unrecognized movement "..tostring(byte).." (kept unchanged)" end
return M
