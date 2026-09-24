-- Native layouts contain runtime COLL_* bytes, not ROM collision nibbles.
local M={}
local modes={ [0x18]="grass",[0x29]="water",[0x2B]="walk",
  [0x71]="door",[0x72]="panel",[0xA0]="ledge_right",
  [0xA1]="ledge_left",[0xA2]="ledge_up",[0xA3]="ledge_down" }
local painted={
  solid={0xFF,0},walk={0,0},grass={0x18,2},water={0x29,0x10},
  shore={0,0x17},cut={0x07,0},face={0x07,0},
  face_right={0,0x30},face_left={0,0x31},face_up={0,0x32},face_down={0,0x33},
  ledge={0xA3,0x3B},ledge_right={0xA0,0x38},ledge_left={0xA1,0x39},
  ledge_up={0xA2,0x3A},ledge_down={0xA3,0x3B},
  door={0x71,0x69},stairs={0x72,0x61},cave={0x71,0x60},panel={0x72,0x67},
  carpet={0x72,0x65},carpet_right={0x72,0x62},carpet_left={0x72,0x63},
  carpet_up={0x72,0x64},carpet_down={0x72,0x65},
  fall={0x72,0x66},escalator_up={0x72,0x6A},escalator_down={0x72,0x6B},
  stair_up_right={0x72,0x6C},stair_up_left={0x72,0x6D},
  stair_down_right={0x72,0x6E},stair_down_left={0x72,0x6F},
}
M.exitTypes={
  {id="door",label="Door",tip="Animated building door; use a native door graphic"},
  {id="cave",label="Cave",tip="Entrance without a door animation"},
  {id="stairs",label="Ladder",tip="Climb between floors"},
  {id="panel",label="Warp pad",tip="Step onto a teleport pad"},
  {id="carpet",label="Arrow exit",tip="Leave in the selected direction"},
  {id="fall",label="Fall",tip="Drop through a hole to the destination"},
  {id="escalator_up",label="Escalator up",tip="Take an upward escalator"},
  {id="escalator_down",label="Escalator down",tip="Take a downward escalator"},
  {id="stair_up_right",label="Stairs up-right",tip="Ascend stairs toward the right"},
  {id="stair_up_left",label="Stairs up-left",tip="Ascend stairs toward the left"},
  {id="stair_down_right",label="Stairs down-right",tip="Descend stairs toward the right"},
  {id="stair_down_left",label="Stairs down-left",tip="Descend stairs toward the left"},
}
M.modes=modes
M.painted=painted
function M.mode(coll)
  return modes[coll] or (coll==0 and "walk" or "solid")
end
function M.resolve(mode,original,behavior)
  -- Accept old projects that represented every nonzero byte as a wall.
  if original~=nil and (mode==M.mode(original) or
      mode==(original==0 and "walk" or "solid")) then
    return original,behavior
  end
  local value=painted[mode] or painted.solid
  return value[1],value[2]
end
return M
