-- Shared presentation of imported actions. Never change data while describing it.
local M={}
M.names={
  nop="Do nothing",nop1="Do nothing",special="Run a built-in game action",specialvar="Run a game action and remember its answer",
  callnative="Run a built-in game function",gotonative="Continue with a built-in game function",
  callstd="Run a common game action",gotostd="Finish with a common game action",waitstate="Wait for the game action to finish",
  loadword="Prepare a value for the next action",loadbyte="Prepare a small value",copylocal="Copy a temporary value",
  setvar="Remember a number",setorcopyvar="Remember a number or copy a saved value",addvar="Increase a saved number",subvar="Decrease a saved number",copyvar="Copy a saved number",
  compare_var_to_value="Check a saved number",compare_var_to_var="Compare two saved numbers",
  goto_if="Continue elsewhere if the check matches",call_if="Run another event if the check matches",
  setflag="Turn a saved switch ON",clearflag="Turn a saved switch OFF",checkflag="Check a saved switch",
  playse="Play a sound",waitse="Wait for the sound to finish",playfanfare="Play a celebration tune",waitfanfare="Wait for the tune to finish",
  playbgm="Play background music",savebgm="Remember the background music",fadedefaultbgm="Return to the map's music",fadenewbgm="Fade into new music",fadeoutbgm="Fade music out",fadeinbgm="Fade music in",
  additem="Give the player an item",removeitem="Take an item from the player",checkitem="Check the player's Bag",checkitemspace="Check for room in the Bag",checkitemtype="Find an item's Bag pocket",addpcitem="Put an item in the PC",checkpcitem="Check items in the PC",
  removeobject="Hide a character",addobject="Show a character",removeobjectat="Hide a character on another map",addobjectat="Show a character on another map",hideobjectat="Hide a character on another map",showobjectat="Show a character on another map",
  setobjectxy="Move a character to a position",setobjectxyperm="Remember a character's home position",copyobjectxytoperm="Keep a character's current position",turnobject="Turn a character",setobjectmovementtype="Change how a character moves",
  applymovementat="Move a character on another map",waitmovementat="Wait for a character on another map",
  trainerbattle="Battle a trainer",dotrainerbattle="Start the prepared trainer battle",gotopostbattlescript="Continue after the battle",gotobeatenscript="Continue after an already defeated trainer",
  checktrainerflag="Check whether a trainer was defeated",settrainerflag="Remember that a trainer was defeated",cleartrainerflag="Allow a trainer to battle again",
  yesnobox="Ask the player: Yes / No",multichoice="Let the player choose from a list",multichoicedefault="Show choices with one preselected",multichoicegrid="Show choices in a grid",
  showmonpic="Show a Pokémon picture",hidemonpic="Hide the Pokémon picture",givemon="Give the player a Pokémon",giveegg="Give the player a Pokémon Egg",setmonmove="Change a Pokémon's move",checkpartymove="Check whether the team knows a move",
  bufferspeciesname="Prepare a Pokémon name for dialogue",bufferleadmonspeciesname="Prepare the first Pokémon's species name",bufferpartymonnick="Prepare a team Pokémon's nickname",bufferitemname="Prepare an item name for dialogue",buffermovename="Prepare a move name for dialogue",buffernumberstring="Prepare a number for dialogue",bufferstdstring="Prepare a common phrase for dialogue",bufferstring="Prepare text for dialogue",
  pokemart="Open a shop",random="Choose a random number",addmoney="Give the player money",removemoney="Take money from the player",checkmoney="Check whether the player has enough money",showmoneybox="Show the player's money",hidemoneybox="Hide the money display",updatemoneybox="Refresh the money display",
  fadescreen="Fade the screen",fadescreenspeed="Fade the screen at a chosen speed",setflashlevel="Set how dark the area is",animateflash="Change how much of the area is lit",messageautoscroll="Show text that advances automatically",braillemessage="Show a Braille message",
  dofieldeffect="Show an effect on the map",setfieldeffectargument="Prepare a setting for a map effect",waitfieldeffect="Wait for a map effect to finish",setrespawn="Choose where the player returns after losing",checkplayergender="Check the player's gender",playmoncry="Play a Pokémon's cry",waitmoncry="Wait for the Pokémon's cry",
  setmetatile="Change a map tile",resetweather="Restore the map's weather",setweather="Choose the weather",doweather="Apply the chosen weather",setmaplayoutindex="Change the map layout",
  opendoor="Open a door",closedoor="Close a door",waitdooranim="Wait for the door",setdooropen="Leave a door open",setdoorclosed="Leave a door closed",showelevmenu="Choose an elevator floor",addelevmenuitem="Add an elevator destination",
  checkcoins="Check the player's coins",addcoins="Give the player coins",removecoins="Take coins from the player",showcoinsbox="Show the player's coins",hidecoinsbox="Hide the coin display",updatecoinsbox="Refresh the coin display",
  setwildbattle="Prepare a wild Pokémon battle",dowildbattle="Start the prepared wild battle",getpartysize="Count the Pokémon on the team",getplayerxy="Remember the player's position",gettime="Check the time",initclock="Set the clock",dotimebasedevents="Update events that depend on time",
  signmsg="Use a sign-style text box",normalmsg="Use a normal text box",textcolor="Change the text color",setworldmapflag="Mark a place as visited",incrementgamestat="Increase a game statistic",playslotmachine="Play a slot machine",
  compare_ptr_to_value="Compare a number from game memory",compare_local_to_value="Check a temporary number",compare_local_to_ptr="Compare a temporary number with game memory",compare_local_to_local="Compare two temporary numbers",compare_ptr_to_ptr="Compare two values in game memory",compare_ptr_to_local="Compare game memory with a temporary number",
  drawbox="Draw a box on screen",erasebox="Erase a box from the screen",drawboxtext="Draw text inside a box",
  setmysteryeventstatus="Set the Mystery Event result",trywondercardscript="Run the Wonder Card event",setmonmodernfatefulencounter="Mark a Pokémon as a fateful encounter",checkmonmodernfatefulencounter="Check a Pokémon's fateful encounter mark",setmonmetlocation="Set where a Pokémon was met",
  endram="Finish the temporary event",returnram="Return from the temporary event",loadhelp="Show help text",unloadhelp="Close help text",getbraillestringwidth="Measure the Braille message width",comparestat="Check a game statistic",
  bufferitemnameplural="Prepare an item name with a quantity",bufferboxname="Prepare a storage box name",bufferdecorationname="Prepare a decoration name",
  warpspinenter="Move to another map with a spinning entrance",setvaddress="Set the starting address of a relocated event",vgoto="Continue in a relocated event",vcall="Run a relocated event",vgoto_if="Continue in a relocated event if the check matches",vcall_if="Run a relocated event if the check matches",vmessage="Show text from a relocated event",vbuffermessage="Prepare a message from a relocated event",vbufferstring="Prepare text from a relocated event",
  createvobject="Show a temporary character",turnvobject="Turn a temporary character",setobjectsubpriority="Change a character's drawing order",resetobjectsubpriority="Restore a character's drawing order",setstepcallback="Choose what happens after each player step",
  callstd_if="Run a common action if the check matches",gotostd_if="Finish with a common action if the check matches",copybyte="Copy a small value in game memory",setptr="Write a value to game memory",loadbytefromptr="Read a small value from game memory",setptrbyte="Write a small value to game memory",
  choosecontestmon="Choose a Pokémon for a contest",startcontest="Start a Pokémon contest",showcontestresults="Show the contest results",contestlinktransfer="Share contest data with other players",showcontestpainting="Show a contest painting",getpokenewsactive="Check whether Pokémon news is active",
  pokemartdecoration="Open a decoration shop",pokemartdecoration2="Open a second decoration shop",setberrytree="Set up a Berry tree",adddecoration="Give a decoration",removedecoration="Remove a decoration",checkdecor="Check for a decoration",checkdecorspace="Check for room for a decoration",
}
for op,label in pairs({warp="Move to another map",warpsilent="Move to another map without a transition",warpdoor="Go through a door to another map",warphole="Fall into another map",warpteleport="Teleport to another map",setwarp="Choose the next map destination",setdynamicwarp="Remember a return destination",setdivewarp="Choose the underwater destination",setholewarp="Choose where a hole leads",setescapewarp="Choose the escape destination"}) do M.names[op]=label end
M.specials={
  [0x00]="Heal the player's Pokémon",[0x3C]="Open Pokémon storage",[0xFB]="Show the town map",
  [0xD6]="Animate the PC turning on",[0xD7]="Animate the PC turning off",[0xF9]="Open the bedroom PC",[0xFA]="Open the player's PC",[0x106]="Open the PC menu",
  [0x9E]="Change a Pokémon's nickname",[0x166]="Change a stored Pokémon's nickname",[0x9F]="Choose a Pokémon from the team",[0x18D]="Choose a Pokémon to learn a move",
  [0x110]="Enter the Hall of Fame",[0x16F]="Unlock the National Pokédex",[0x193]="Check whether the National Pokédex is unlocked",
  [0x36]="Check whether this trainer has been battled",[0x38]="Play the trainer's encounter music",[0x39]="Check whether a rematch should start",[0x3A]="Check whether the trainer is ready for a rematch",[0x3D]="Check for enough Pokémon for a double battle",
  [0xB4]="Check how the battle ended",[0xE6]="Check the first Pokémon's friendship",[0x197]="Offer Daisy's Pokémon massage",[0xB6]="Check the Day Care",[0x9D]="Start the old man's catching lesson",
  [0x156]="Start the Marowak battle",[0x138]="Start a legendary Pokémon battle",[0x15B]="Set up the Vermilion Gym trash-can puzzle",
  [0x83]="Count the Pokémon on the team",[0x84]="Count team Pokémon that are not Eggs",[0xD4]="Count Pokédex entries",[0x130]="Check for room in Pokémon storage",[0x162]="Check which starter the player chose",[0x17B]="Show the ferry journey",[0x1A7]="Choose a ferry destination",
  [0x169]="Record a visit to the Pokémon Center",[0x184]="Resume recording the player's actions",[0x187]="Check whether the adventure recap is recording",[0x188]="Stop recording the adventure recap",
  [0x7C]="Prepare a Pokémon's nickname for dialogue",[0x7D]="Check whether a Pokémon has a different original trainer ID",[0x1B2]="Show or hide the Braille reading cursor",[0x181]="Record which Pokédex features are unlocked",
  [0x17D]="Choose the current help topic",[0x17E]="Remember the current help topic",[0x17F]="Restore the previous help topic",[0x190]="Choose the help topic for this map",[0x198]="Turn off the help system",[0x199]="Turn on the help system",
  [0x13A]="Prepare the trainer to walk toward the player",[0x164]="Restore character movement after using the Vs. Seeker",[0x172]="Pause characters after using the Vs. Seeker",[0x18F]="Remember that the trainer was battled",
  [0x5F]="Let the player build a phrase",[0x60]="Show the phrase the player built",[0x137]="Start the Groudon or Kyogre battle",[0x139]="Start a Regi battle",[0x143]="Start the Southern Island battle",
  [0x7B]="Check whether the Name Rater changed the nickname",[0x85]="Count other team Pokémon that can battle",[0x94]="Prepare the player's form of address",[0x96]="Remember that a hidden item was found",[0xBA]="Prepare the chosen Pokémon's nickname and species",
  [0xC5]="Check whether the player can afford the prepared price",[0xC6]="Charge the player the prepared price",[0x11E]="Choose a random slot machine",[0x147]="Check a team Pokémon's species",[0x148]="Check whether the chosen Pokémon is an Egg",
  [0x14F]="Check whether the Kanto Pokédex is complete",[0x150]="Check whether a Pokémon has a different original trainer name",[0x153]="Check whether a team Pokémon holds an Enigma Berry",[0x163]="Mark a Pokémon as seen in the Pokédex",[0x165]="Check whether to show the storage-box-full message",
  [0x17C]="Check for a species on the player's team",[0x18A]="Find the storage box for a received Pokémon",[0x19B]="Check whether the player has any Berries",[0x1AA]="Check which way the player is facing",
  [0x1A8]="Read the chosen ferry destination",[0x1A9]="Check which ferry is being used",[0x1AD]="Check whether the player is left of the Vermilion sailor",[0x1AE]="Check for a Bad Egg on the team",[0x1B0]="Check whether the Pokédex is complete",[0x1B1]="Check whether the player is outside the Trainer Tower lobby",[0x1B4]="Check for a species caught by this player",[0x1B6]="Check for Dodrio on the team",
  [0x183]="Prepare a Union Room player's name",[0x8D]="Show the prepared map message",[0x8E]="Redraw the map",[0xAB]="Check for a wild battle after Rock Smash",[0xCD]="Start a Safari Zone visit",[0xCE]="End the Safari Zone visit",[0x129]="Set up the roaming legendary Pokémon",
  [0x135]="Set up the cracked ice in Icefall Cave",[0x136]="Shake the screen",[0x155]="Unlock events after becoming Champion",[0x157]="Put the player on a bicycle",[0x15D]="Choose the requested Pokémon and reward at Resort Gorgeous",[0x161]="Make the player start Surfing",[0x171]="Keep the player from walking away from the message",[0x19A]="Unlock events after becoming Champion",[0x1AC]="Change the Deoxys triangle's colors",[0x1B9]="Update Lorelei's doll collection",[0x1BB]="Prepare the event's opposing Pokémon",
  [0xD8]="Check the current elevator floor",[0x111]="Animate the elevator ride",[0x113]="Create a separate camera target",[0x114]="Remove the separate camera target",[0x132]="Show the current elevator floor",[0x158]="Open a scrolling choice list",[0x159]="Return to the scrolling choice list",[0x160]="Hide the elevator floor display",[0x1B5]="Animate the teleporter housing",[0x1B7]="Animate the teleporter cable",[0x1B8]="Set the starting elevator-floor choice",
  [0xFC]="Read the Pokémon species for an in-game trade",[0xFD]="Prepare the Pokémon received in a trade",[0xFE]="Show the Pokémon trade",[0xFF]="Check the trade's Pokémon species",
  [0xB5]="Prepare the Day Care Pokémon's nicknames",[0xB7]="Decline the Day Care Egg",[0xB8]="Give the player the Day Care Egg",[0xB9]="Prepare the Day Care compatibility message",[0xBB]="Leave the chosen Pokémon at the Day Care",[0xBC]="Choose a Pokémon to leave at the Day Care",[0xBD]="Show the Day Care Pokémon and their levels",[0xBE]="Check levels gained at the Day Care",[0xBF]="Calculate the Day Care fee",[0xC0]="Return a Pokémon from the Day Care",[0x15F]="Count Pokémon staying at the Day Care",
  [0x176]="Leave a Pokémon at the Route 5 Day Care",[0x177]="Calculate the Route 5 Day Care fee",[0x178]="Check for a Pokémon at the Route 5 Day Care",[0x179]="Check levels gained at the Route 5 Day Care",[0x17A]="Return a Pokémon from the Route 5 Day Care",
  [0xF001]="Fade the screen",[0xF002]="Open the naming screen",[0xF003]="Play a Pokémon's cry",
}
local common={[0]="Give an item with a message",[1]="Pick up an item",[2]="Show character dialogue",[3]="Show a sign message",[4]="Show a normal message",[5]="Ask a Yes / No question",[6]="Show a message that closes automatically",[7]="Give a decoration",[8]="Show the item being put away",[9]="Show the item received"}
-- FireRed data/specials.inc: zero-based entry 32 is EnterColosseumPlayerSpot.
-- src/cable_club.c uses 0x8004 for format and 0x8005 for the player's spot.
M.specials[32]="Start a multiplayer battle at the Colosseum"
M.specialHelp={
  [32]="Wait for the other players, then start a Colosseum battle. The current game skips this action; settings are saved but multiplayer battles are not supported yet.",
}
M.options={special=M.specials,common=common,
  linkBattleFormat={[1]="Single battle",[2]="Double battle",[5]="Multi battle (four players)"},
  linkBattleSpot={[0]="Player spot 1",[1]="Player spot 2",[2]="Player spot 3",[3]="Player spot 4"},
  direction={[1]="Down",[2]="Up",[3]="Left",[4]="Right"},
  fade={[0]="Reveal from black",[1]="Fade to black",[2]="Reveal from white",[3]="Fade to white"},
  condition={[0]="Is less than",[1]="Equals",[2]="Is greater than",[3]="Is at most",[4]="Is at least",[5]="Does not equal"},
  yesno={[0]="No",[1]="Yes"},
  idleMovement={[0]="Stay still",[1]="Look around",[2]="Walk around",[7]="Face up",[8]="Face down",[9]="Face left",[10]="Face right"},
  pokedex={[0]="Kanto Pokédex",[1]="National Pokédex"},
  daycareSlot={[0]="First Day Care Pokémon",[1]="Second Day Care Pokémon"},
  elevatorFloor={[0]="Basement 4",[1]="Basement 3",[2]="Basement 2",[3]="Basement 1",[4]="Floor 1",[5]="Floor 2",[6]="Floor 3",[7]="Floor 4",[8]="Floor 5",[9]="Floor 6",[10]="Floor 7",[11]="Floor 8",[12]="Floor 9",[13]="Floor 10",[14]="Floor 11",[15]="Rooftop"},
  weather={[0]="Clear",[1]="Rain",[2]="Falling ash",[3]="Fog",[4]="Sandstorm",[5]="Bright sun"},
  teamSlot={[0]="First Pokémon",[1]="Second Pokémon",[2]="Third Pokémon",[3]="Fourth Pokémon",[4]="Fifth Pokémon",[5]="Sixth Pokémon"},
  moveSlot={[0]="First move",[1]="Second move",[2]="Third move",[3]="Fourth move"},
}
function M.label(step)
  if type(step)=="string" then return M.names[step] end
  if step.op=="special" or step.op=="specialvar" then
    local id=step.op=="special" and (step.id or step[1]) or step[2]
    local name=M.specials[id] or "Built-in game action "..tostring(id).." (purpose not yet described)"
    return name..(step.op=="specialvar" and " and remember the answer" or "")
  end
  if step.op=="callstd" or step.op=="gotostd" then return common[step.std or step[1]] or "Common game action "..tostring(step.std or step[1]).." (purpose not yet described)" end
  return M.names[step.op]
end
-- Named aliases mirror the importer. Editing updates both representations only
-- when present, so imported commands and editor-created commands both round trip.
local schemas={}
local function schema(ops,fields) for op in ops:gmatch("%S+") do schemas[op]=fields end end
schema("setvar addvar subvar compare_var_to_value",{{"var","Saved number to check or change"},{"value","Number"}})
schema("setorcopyvar copyvar compare_var_to_var",{{false,"Saved number to check or change"},{false,"Number or saved-number ID"}})
schema("setflag clearflag checkflag",{{"flag","Saved switch number"}})
schema("delay",{{"frames","Wait time (60 = one second)"}})
schema("special",{{"id","Built-in game action","special"}})
schema("specialvar",{{false,"Save the answer in this saved number"},{false,"Built-in game action","special"}})
schema("callstd gotostd",{{"std","Common game action","common"}})
schema("loadword loadbyte",{{"dest","Temporary slot for the next action"},{"value","Value to prepare"}})
schema("additem removeitem checkitem checkitemspace addpcitem checkpcitem",{{"item","Item","item"},{"quantity","How many"}})
schema("warp warpsilent warpdoor warpteleport warpspinenter setwarp setdynamicwarp setdivewarp setholewarp setescapewarp",{{false,"Destination map group"},{false,"Destination map number"},{false,"Destination exit (255 = use position below)"},{false,"Destination column"},{false,"Destination row"}})
schema("setweather",{{false,"Weather","weather"}})
schema("setmetatile",{{false,"Map column"},{false,"Map row"},{false,"Replacement tile number"},{false,"Block walking","yesno"}})
schema("yesnobox",{{false,"Menu column"},{false,"Menu row"}})
schema("multichoice",{{false,"Menu column"},{false,"Menu row"},{false,"List of choices"},{false,"Prevent cancel","yesno"}})
schema("multichoicedefault",{{false,"Menu column"},{false,"Menu row"},{false,"List of choices"},{false,"Starting choice (0 = first)"},{false,"Prevent cancel","yesno"}})
schema("multichoicegrid",{{false,"Menu column"},{false,"Menu row"},{false,"List of choices"},{false,"Number of columns"},{false,"Prevent cancel","yesno"}})
schema("addmoney removemoney checkmoney",{{"amount","Amount of money"},{false,"Use multiplayer money","yesno"}})
schema("addcoins removecoins",{{"amount","Number of coins"}})
schema("removeobject addobject copyobjectxytoperm",{{"localId","Character","character"}})
schema("waitmovement",{{"localId","Wait for","movingCharacter"}})
schema("playse playfanfare playbgm savebgm fadenewbgm",{{"song","Sound or music","audio"},{false,"Music playback setting"}})
schema("fadescreen fadescreenspeed",{{false,"Screen transition","fade"},{false,"Fade speed"}})
schema("setobjectxy setobjectxyperm",{{"localId","Character","character"},{false,"Map column"},{false,"Map row"}})
schema("turnobject",{{"localId","Character","character"},{"direction","Face toward","direction"}})
schema("goto call",{{"target","Event to run","event"}})
schema("goto_if call_if",{{"cond","Continue when the previous check","condition"},{"target","Event to run","event"}})
schema("opendoor closedoor setdooropen setdoorclosed",{{false,"Map column"},{false,"Map row"}})
schema("giveegg",{{false,"Pokémon inside the Egg","species"}})
schema("setwildbattle",{{"species","Wild Pokémon","species"},{"level","Level"},{"item","Held item","item"}})
schema("givemon",{{"species","Pokémon to give","species"},{"level","Level"},{false,"Held item","item"},{false,"Reserved game value"},{false,"Reserved game value"}})
schema("showmonpic",{{false,"Pokémon picture","species"},{false,"Screen column"},{false,"Screen row"}})
schema("setmonmove",{{false,"Pokémon on the team","teamSlot"},{false,"Move to replace","moveSlot"},{false,"New move","move"}})
schema("checkpartymove",{{false,"Move to look for","move"}})
schema("bufferspeciesname",{{"dest","Text slot"},{"src","Pokémon name","species"}})
schema("buffermovename",{{"dest","Text slot"},{"src","Move name","move"}})
schema("bufferitemname",{{"dest","Text slot"},{"src","Item name","item"}})
schema("bufferpartymonnick",{{"dest","Text slot"},{"src","Pokémon on the team","teamSlot"}})
schema("buffernumberstring",{{"dest","Text slot"},{"src","Number to show"}})
schema("checkitemtype",{{"item","Item","item"}})
schema("checktrainerflag settrainerflag cleartrainerflag",{{false,"Trainer","trainer"}})
schema("getplayerxy",{{false,"Save the player's column in"},{false,"Save the player's row in"}})
schema("random",{{false,"Choose from 0 up to this number minus 1"}})
schema("fadeoutbgm fadeinbgm",{{false,"Fade speed"}})
schema("warphole",{{false,"Destination map group"},{false,"Destination map number"}})
schema("setflashlevel animateflash",{{false,"Darkness level"}})
schema("playmoncry",{{false,"Pokémon","species"},{false,"Cry effect"}})
schema("showmoneybox",{{false,"Screen column"},{false,"Screen row"},{false,"Use multiplayer money","yesno"}})
schema("showcoinsbox hidecoinsbox updatecoinsbox updatemoneybox",{{false,"Screen column"},{false,"Screen row"}})
require("Gen3ActionFields")(schema)
local extraFields={introText={"Before-battle dialogue","dialogue"},defeatText={"Trainer's defeat dialogue","dialogue"},victoryText={"Trainer's victory dialogue","dialogue"},notEnoughText={"Dialogue when the player cannot battle","dialogue"},eventScript={"Event after the battle","event"},localId={"Character","character"},flags={"Battle flags"}}
M.schemas=schemas
function M.fields(step)
  local out,used={}, {op=true,opcode=true,opaque=true}
  for i,d in ipairs(schemas[step.op] or {}) do
    local alias=d[1];local key=alias and step[alias]~=nil and alias or i
    if step[key]~=nil and not used[i] then
      local destination=d[2]=="Destination map group" and step[i+1]~=nil
      out[#out+1]={key=key,index=i,alias=alias,label=destination and "Destination map" or d[2],choices=destination and "destination" or d[3],second=destination and i+1 or nil}
      used[i]=true;if alias then used[alias]=true end;if destination then used[i+1]=true end
    end
  end
  local keys={};for key in pairs(step) do if not used[key] then keys[#keys+1]=key end end
  table.sort(keys,function(a,b) if type(a)==type(b) then return a<b end;return type(a)=="number" end)
  for _,key in ipairs(keys) do
    local d=extraFields[key]
    out[#out+1]={key=key,label=d and d[1] or (type(key)=="number" and "Game setting "..key.." (meaning not yet described)" or tostring(key):gsub("(%l)(%u)","%1 %2"):gsub("_"," ")),choices=d and d[2]}
  end
  return out
end
local limits
function M.validNumber(step,field,n)
  if not limits then
    limits={}
    local ok,ops=pcall(require,"src.core.game3.scripting.opcodes")
    if ok then for _,op in pairs(ops.TABLE) do limits[op.name]=op.args end end
  end
  local args=limits[step.op];local arg=args and args[field.index or field.key]
  local max=arg and ({byte=255,half=65535,word=4294967295,ptr=4294967295})[arg.kind] or 65535
  return n and n==math.floor(n) and n>=0 and n<=max
end
function M.set(step,field,value)
  step[field.key]=value
  if field.index and step[field.index]~=nil then step[field.index]=value end
  if field.alias and step[field.alias]~=nil then step[field.alias]=value end
end
function M.choiceData(S,kind,current)
  local labels={}
  for id,label in pairs(M.options[kind] or {}) do labels[tostring(id)]=label end
  local bucket=({species="pokemon",move="moves",trainer="trainers"})[kind]
  if bucket then
    for _,records in ipairs({(S.data or {})[bucket] or {},(S.project or {})[bucket] or {}}) do
      for id,record in pairs(records) do
        if type(record)=="table" and type(record.index)=="number" then
          local name=record.name or record.trainerName or tostring(id):gsub("^MOVE_",""):gsub("^SPECIES_",""):gsub("_"," ")
          labels[tostring(record.index)]=tostring(name).." ("..record.index..")"
        end
      end
    end
  end
  if kind=="event" then
    local catalog=require("Gen3").catalog(S.data,"map_scripts")
    for _,records in ipairs({catalog,((S.project or {}).gen3 or {}).map_scripts or {}}) do
      for id in pairs(records) do labels[tostring(id)]=tostring(id) end
    end
  end
  if kind=="audio" then
    for id,record in pairs(require("Gen3Resources").audio(S.data).songs or {}) do
      labels[tostring(id)]=type(record)=="table" and tostring(record.name or record.label or record.symbol or "Sound "..id):gsub("_"," ") or "Sound "..id
    end
    labels["0"]="Silence"
  end
  if kind=="character" or kind=="movingCharacter" then
    labels["255"]="The player";labels["32783"]="The character being spoken to"
    if kind=="movingCharacter" then labels["0"]="All moving characters" end
    local mapId=(S._eventWindowTarget or {}).mapId or S.g3EventMap or S.mapId
    local map=((S.project or {}).maps or {})[mapId] or ((S.data or {}).maps or {})[mapId]
    for i,object in ipairs(map and map.objects or {}) do
      local id=object.localId or i
      labels[tostring(id)]=(object.editorName or "Character "..id).." at "..tostring(object.x)..", "..tostring(object.y)
    end
  end
  if not labels[tostring(current)] then labels[tostring(current)]="Keep current value ("..tostring(current)..")" end
  local ids={};for id in pairs(labels) do ids[#ids+1]=id end
  table.sort(ids,function(a,b)
    if tonumber(a) and tonumber(b) then return tonumber(a)<tonumber(b) end
    return a<b
  end)
  return ids,labels
end
function M.help(step)
  local op=step.op
  if op=="pokemartdecoration" or op=="pokemartdecoration2" then return "Decoration shops are not supported by the current game. These settings are saved, but the shop will not open." end
  if op=="setfieldeffectargument" then return "The current game does not use this effect setting. You can save it, but changing it will not change the effect yet." end
  if op=="special" or op=="specialvar" then
    local id=op=="special" and (step.id or step[1]) or step[2]
    return M.specialHelp[id] or "This is a built-in game action. Some actions use values prepared by earlier steps."
  end
  if op=="setflag" or op=="clearflag" or op=="checkflag" then return "A saved switch remembers yes or no. Use the same switch number wherever you check that event." end
  if op=="setvar" or op=="addvar" or op=="subvar" or op=="compare_var_to_value" then return "A saved number can track a quest stage or a count. Its number identifies which value to use." end
  if op=="setorcopyvar" then return "Numbers below 16384 are used directly. Higher numbers refer to a stored game value to copy." end
  if op=="goto_if" or op=="call_if" then return "This uses the result of the previous check. Choose when it should run the other event." end
  if op=="setwildbattle" then return "Choose the opponent. The Start the prepared wild battle action begins the fight." end
  if op=="givemon" or op=="giveegg" then return "Choose what the player receives. Leave reserved game values unchanged." end
  if op=="setweather" then return "Choose the weather. Apply the chosen weather makes the change visible." end
  if op=="setmetatile" then return "Replace the tile at this map position and choose whether characters can walk on it." end
  if op=="random" then return "For example, 4 chooses 0, 1, 2, or 3. A later check can use the answer." end
  return "Choose the settings for this action. Hover over a shortened label to read it in full."
end
function M.draw(S,key,step,x,y,w,changed)
  local K=require("Kit");local s=K.scale;local color=require("Theme").PAL.text
  local help=M.help(step)
  K.text("small",K.ellipsize("small",help,w),x,y,color);K.offerTooltip(x,y,w,24*s,help);y=y+30*s
  local fields=M.fields(step)
  if #fields==0 then K.text("small","This action always does the same thing. You can remove it or replace it with another action.",x,y,color);return true,y+30*s end
  for _,field in ipairs(fields) do
    local old=step[field.key]
    K.text("small",K.ellipsize("small",field.label,w),x,y,color);K.offerTooltip(x,y,w,24*s,field.label);y=y+25*s
    local function pick(value) if value~=old then M.set(step,field,value);changed() end end
    if field.choices=="destination" then
      require("Gen3ActionContent").drawDestination(S,old,step[field.second],x,y,w,function(group,number)
        if group~=old or number~=step[field.second] then M.set(step,field,group);step[field.second]=number;changed() end
      end)
    elseif field.choices=="dialogue" then
      y=require("Gen3ActionContent").drawDialogue(S,key.."/"..tostring(field.key),old,x,y,w,pick)
    elseif field.choices=="shop" then
      y=require("Gen3ActionContent").drawShop(S,key,old,x,y,w,pick)
    elseif field.choices=="item" then
      local _,id=require("Gen3EventStory").itemName(S,old)
      require("ItemPicker").field(S,{x=x,y=y,w=w,h=29*s,current=id or "",emptyLabel="Item or saved value "..tostring(old),title="CHOOSE ITEM",onPick=function(itemId)
        local index=require("ItemPicker").indexForId(S,itemId);if index then pick(index) end
      end})
    elseif field.choices then
      local ids,labels=M.choiceData(S,field.choices,old)
      require("ChoicePicker").field(S,{x=x,y=y,w=w,h=29*s,current=tostring(old),ids=ids,labels=labels,title=field.label,onPick=function(value) pick(tonumber(value) or value) end})
    elseif type(old)=="number" or type(old)=="string" then
      local value=K.textfield(key.."/setting/"..tostring(field.key),x,y,w,29*s,tostring(old),"")
      if type(old)=="number" then
        local n=tonumber(value);if M.validNumber(step,field,n) then pick(n) end
      else pick(value) end
    elseif type(old)=="boolean" then
      local value,edited=K.checkbox(x,y,w,29*s,old,"Enabled");if edited then pick(value) end
    elseif type(old)=="table" then
      local _,bottom=M.draw(S,key.."/list/"..tostring(field.key),old,x+12*s,y,math.max(80*s,w-12*s),changed)
      y=bottom
    else
      K.text("small","This setting has no editable value.",x,y,color)
    end
    y=y+42*s
  end
  return true,y
end
return M
