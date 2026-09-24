local M={}
M.kinds={"none","map","hour","season","nature","personality","flag","tag","grooming"}
M.labels={none="No field rule",map="On a map",hour="During local time hours",season="During a season",nature="Individual's nature",personality="Personality rarity / variant",flag="While a story flag is set",tag="Inherited individual variant",grooming="Timed grooming / costume"}
function M.validate(f)
  local kinds={};for _,id in ipairs(M.kinds) do kinds[id]=true end
  local function integer(v,lo,hi,label)
    assert(type(v)=="number" and v%1==0 and v>=lo and v<=hi,"Invalid "..label)
  end
  for _,row in ipairs(f.forms) do local c=row.fieldRule
    if c and c.kind~="none" then
      assert(kinds[c.kind],"Choose a valid field form rule")
      if c.kind=="hour" then integer(c.startHour or 6,0,23,"start hour");integer(c.endHour or 18,0,23,"end hour") end
      if c.kind=="season" then integer(c.season or 1,1,4,"season") end
      if c.kind=="nature" then integer(c.nature or 0,0,24,"nature") end
      if c.kind=="grooming" then assert(type(c.days or 5)=="number" and (c.days or 5)>0,"Grooming duration must be positive") end
      if c.kind=="map" then assert(c.map and c.map~="","Choose a form map") end
      if c.kind=="flag" then assert(tonumber(c.flag) and tonumber(c.flag)>=0,"Choose a numeric story flag") end
      if c.kind=="tag" then assert(c.tag and c.tag~="","Choose an inherited form tag") end
      if c.kind=="grooming" then assert(c.item and c.item~="","Choose a grooming item") end
      if c.kind=="personality" then assert(tonumber(c.modulus or 100) and (c.modulus or 100)>=1 and (c.modulus or 100)%1==0,"Invalid personality divisor");assert((c.remainder or 0)>=0 and (c.remainder or 0)<(c.modulus or 100),"Remainder must be smaller than divisor") end
    end
  end
end
function M.draw(S,f,selection,x,y,w,App)
  local K,C=require("Kit"),require("ChoicePicker");local H=require("Gen3FormHelp");local s=K.scale;local row=f.forms[selection]
  row.fieldRule=row.fieldRule or {kind="none"};local c=row.fieldRule
  local function choice(key,ids,labels,title,default)
    K.caption(x,y,title);y=y+26*s;C.field(S,{x=x,y=y,w=w,h=30*s,current=c[key] or default,ids=ids,labels=labels,title=title,tooltips=key=="kind" and H.fieldKinds or nil,tooltip=key=="kind" and H.fieldKinds[c.kind or "none"] or H.field[key],onPick=function(v) c[key]=v;App.markDirty() end});y=y+40*s
  end
  local function text(key,title,default,numeric)
    K.caption(x,y,title);y=y+26*s
    local value=K.textfield("fieldForm"..selection..key,x,y,w,30*s,tostring(c[key] or default or ""),title,H.field[key])
    if value~=tostring(c[key] or default or "") then c[key]=numeric and tonumber(value) or value;App.markDirty() end;y=y+40*s
  end
  choice("kind",M.kinds,M.labels,"Field / individual form selection","none")
  if c.kind=="map" then text("map","Map ID")
  elseif c.kind=="hour" then
    local ids={};for i=0,23 do ids[#ids+1]=i end
    choice("startHour",ids,nil,"Start hour (inclusive)",6);choice("endHour",ids,nil,"End hour (exclusive)",18)
  elseif c.kind=="season" then choice("season",{1,2,3,4},{[1]="Spring",[2]="Summer",[3]="Autumn",[4]="Winter"},"Season",1)
  elseif c.kind=="nature" then local ids={};for i=0,24 do ids[#ids+1]=i end;choice("nature",ids,nil,"Nature ID",0)
  elseif c.kind=="personality" then text("modulus","Personality divisor",100,true);text("remainder","Required remainder",0,true)
  elseif c.kind=="flag" then text("flag","Numeric story flag",0,true)
  elseif c.kind=="tag" then text("tag","Inherited variant tag")
  elseif c.kind=="grooming" then
    K.caption(x,y,"Item used to apply this appearance");y=y+26*s
    require("ItemPicker").field(S,{x=x,y=y,w=w,h=30*s,current=c.item,title="GROOMING ITEM",tooltip=H.field.item,onPick=function(id) c.item=id;App.markDirty() end});y=y+40*s
    text("days","Duration in real days",5,true)
  end
  if c.kind and c.kind~="none" then
    K.caption(x,y,"The first matching field rule wins. Otherwise the original form is used.");y=y+28*s
  end
  return y
end
return M
