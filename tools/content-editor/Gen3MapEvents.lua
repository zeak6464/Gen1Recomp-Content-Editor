-- Native event fields within the shared Map Builder selection/drawer workflow.
local M={}
local groups={objects={"Objects","mapObjectIndex"},signs={"Signs","mapSignIndex"},
  coordEvents={"Triggers","g3CoordIndex"},warps={"Warps","mapWarpIndex"}}
function M.place(S,tool,x,y,App)
  local kind=({object="objects",sign="signs",trigger="coordEvents",warp="warps"})[tool]
  if not kind then return false end
  if kind=="objects" and require("Gen3MapTemplates").place(S,x,y,App) then return true end
  local source=assert(require("Gen3Workspace").convert(S,S.mapId))
  local map=S.project.maps[S.mapId]
  local rows=map[kind] or {};map[kind]=rows
  local index=#rows+1
  local script="EDITOR_"..S.mapId.."_"..kind.."_"..index
  local ev={x=x,y=y,elevation=(source.gen3Elevation or {})[y*source.cellWidth+x+1] or 3,scriptKey=script}
  if kind=="objects" then
    local max=0;for _,r in ipairs(rows) do max=math.max(max,r.localId or r.index or 0) end
    ev.localId=max+1;ev.index=max+1;ev.graphicsId=1;ev.graphics=1;ev.movement="STAY";ev.movementType=9;ev.flag=0
  elseif kind=="signs" then ev.kind=0
  elseif kind=="coordEvents" then ev.var=16384;ev.value=0
  else ev={x=x,y=y,destMap=S.mapId,destWarp=index} end
  rows[index]=ev
  if kind=="warps" then require("LayeredMap").adoptWarpRecord(S.project,S.mapId,ev)
  else
    S.project.gen3=S.project.gen3 or {};S.project.gen3.map_scripts=S.project.gen3.map_scripts or {}
    S.project.gen3.map_scripts[script]={{op="end"}}
    S.project.gen3Modes=S.project.gen3Modes or {};S.project.gen3Modes.map_scripts=S.project.gen3Modes.map_scripts or {}
    S.project.gen3Modes.map_scripts[script]="register"
  end
  S.mapSection=kind;S[groups[kind][2]]=index;S.mapEditMode="events"
  App.markDirty()
  require("Gen3EventWindow").request(S,S.mapId,kind,index)
  return true
end
function M.draw(S,x,y,w,h,App)
  local Kit=require("Kit");local Pane=require("FormPane")
  local s=Kit.scale
  local bottom=y+h
  local map=require("Maps").resolveMap(S,S.mapId)
  if not map then return end
  local bx,by=x,y
  for _,kind in ipairs({"objects","signs","coordEvents","warps"}) do
    local bw=(w-6*s)/2
    if Kit.button(bx,by,bw,26*s,groups[kind][1],{kind=S.mapSection==kind and "primary" or "ghost"}) then S.mapSection=kind end
    if bx>x then bx=x;by=by+31*s else bx=x+bw+6*s end
  end
  local kind=groups[S.mapSection] and S.mapSection or "objects"
  local rows=map[kind] or {};local key=groups[kind][2]
  S[key]=math.max(1,math.min(S[key] or 1,#rows))
  y=by+8*s;h=bottom-y
  Kit.caption(x,y,groups[kind][1].." "..S[key].." / "..#rows)
  if Kit.button(x,y+25*s,45*s,25*s,"<",{}) then S[key]=math.max(1,S[key]-1) end
  if Kit.button(x+50*s,y+25*s,45*s,25*s,">",{}) then S[key]=math.min(#rows,S[key]+1) end
  local ev=rows[S[key]]
  if not ev then return end
  local identity=S.mapId..kind..S[key]
  if S._g3EventIdentity~=identity or S._g3EventValue~=ev then
    S._g3EventIdentity,S._g3EventValue=identity,ev
    S._g3EventDraft={value=require("ModWriter").encodeLua(ev)}
    S._g3Expanded=S._g3Expanded or {};S._g3Expanded.value=true
  end
  if S.g3MapEventAdvanced==true and Kit.button(x+102*s,y+25*s,90*s,25*s,"Apply",{kind="primary"}) then
    local decoded,err=require("Gen3Decode").decode("return {value="..S._g3EventDraft.value.."}",{allowArray=true})
    if decoded and type(decoded.value)=="table" and type(decoded.value.x)=="number" and type(decoded.value.y)=="number" then
      require("Gen3Workspace").convert(S,S.mapId)
      S.project.maps[S.mapId][kind][S[key]]=decoded.value
      if kind=="warps" then require("LayeredMap").syncMapWarps(S,S.project.maps[S.mapId]) end
      App.markDirty()
    else S.status=err or "Event needs numeric x and y coordinates" end
  end
  if Kit.button(x,y+57*s,w,27*s,"Open event window",{}) then
    require("Gen3EventWindow").request(S,S.mapId,kind,S[key])
  end
  local fieldTop=y+92*s
  if kind~="warps" then
    local scripts=require("RegList").mergeIds((S.project.gen3 or {}).map_scripts or {},require("Gen3").catalog(S.data,"map_scripts"))
    require("ChoicePicker").field(S,{x=x,y=fieldTop,w=w,h=27*s,ids=scripts,current=ev.scriptKey or "",emptyLabel="Assign event script",title="EVENT SCRIPT",
      onPick=function(id)
        require("Gen3Workspace").convert(S,S.mapId)
        S.project.maps[S.mapId][kind][S[key]].scriptKey=id
        S._g3EventIdentity=nil;App.markDirty()
      end})
    fieldTop=fieldTop+35*s
  end
  local top,view=Pane.begin(S,"g3MapEventScroll",x,fieldTop,w,math.max(80*s,bottom-fieldTop-20*s))
  local controlsTop=top
  if kind~="warps" then controlsTop=require("Gen3RpgEventEditor").drawQuick(S,ev,x,controlsTop,view.contentW,App) end
  local advanced=S.g3MapEventAdvanced==true
  if Kit.button(x,controlsTop,view.contentW,27*s,advanced and "Show simple controls" or "Advanced fields",{}) then S.g3MapEventAdvanced=not advanced end
  local ending
  if advanced then ending=require("Gen3Fields").draw(S,identity,x,controlsTop+35*s,view.contentW,S._g3EventDraft,{})
  else ending=require("Gen3MapEventForm").draw(S,ev,kind,key,x,controlsTop+35*s,view.contentW,App) end
  Pane.finish(S,"g3MapEventScroll",top,ending,view)
end
return M
