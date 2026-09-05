-- Friendly names + edit fields for Gold script opcodes.
-- Storage stays { kind = "opcode", cmd = { op = "checkevent", ... } }.

local OpcodeHelp = {}

local function F(key, caption, ph, numeric, kind)
  return { key = key, caption = caption, ph = ph, numeric = numeric, kind = kind }
end

local EV = { F("event", "story flag #", "0", true) }
local FLAG = { F("flag", "engine flag", "0", true) }
local ITEM = {
  F("item", "item", "POTION", false, "item"),
  F("quantity", "count", "1", true),
}
local SCRIPT = { F("script", "which talk", "", false, "script") }
local TEXT = { F("text", "text", "") }
local SPEC = { F("id", "special #", "0", true) }
local SPECIES = { F("species", "pokemon", "", false, "pokemon") }
local MAP = { F("map", "map", "") }

local function I(label, fields, hint)
  return { label = label, fields = fields, hint = hint }
end

local INFO = {
  scall = I("Run another talk", SCRIPT,
    "Does those lines, then comes back and continues here."),
  farscall = I("Run another talk", SCRIPT,
    "Does those lines, then comes back and continues here."),
  memcall = I("Run another talk", SCRIPT,
    "Does those lines, then comes back and continues here."),
  sjump = I("Go to other talk", SCRIPT, "Leaves this talk and does not come back."),
  farsjump = I("Go to other talk", SCRIPT, "Leaves this talk and does not come back."),
  memjump = I("Go to other talk", SCRIPT, "Leaves this talk and does not come back."),
  ifequal = I("If value equals", {
    F("value", "value", "0", true),
    F("script", "then go to", "", false, "script"),
  }),
  ifnotequal = I("If value is not", {
    F("value", "value", "0", true),
    F("script", "then go to", "", false, "script"),
  }),
  iffalse = I("If no", SCRIPT, "Uses the last yes/no or flag check."),
  iftrue = I("If yes", SCRIPT, "Uses the last yes/no or flag check."),
  ifgreater = I("If value greater", {
    F("value", "value", "0", true),
    F("script", "then go to", "", false, "script"),
  }),
  ifless = I("If value less", {
    F("value", "value", "0", true),
    F("script", "then go to", "", false, "script"),
  }),
  jumpstd = I("Jump to standard script", { F("std", "standard", "") }),
  callstd = I("Call standard script", { F("std", "standard", "") }),
  callasm = I("Run assembly", { F("addr", "address", "") }),
  special = I("Special effect", SPEC),
  memcallasm = I("Run assembly (memory)", { F("addr", "address", "") }),
  checkmapscene = I("Check map scene", MAP),
  setmapscene = I("Set map scene", { F("map", "map", ""), F("scene", "scene", "0", true) }),
  checkscene = I("Check this map's scene"),
  setscene = I("Set this map's scene", { F("scene", "scene", "0", true) }),
  setval = I("Set value", { F("value", "value", "0", true) }),
  addval = I("Add to value", { F("value", "amount", "1", true) }),
  random = I("Random number", { F("value", "max", "2", true) }),
  checkver = I("Check game version"),
  readmem = I("Read memory", { F("addr", "address", "") }),
  writemem = I("Write memory", { F("addr", "address", "") }),
  loadmem = I("Load memory", { F("addr", "address", ""), F("value", "value", "0", true) }),
  readvar = I("Read variable", { F("var", "variable", "0", true) }),
  writevar = I("Write variable", { F("var", "variable", "0", true) }),
  loadvar = I("Set variable", { F("var", "variable", "0", true), F("value", "value", "0", true) }),
  giveitem = I("Give item", ITEM),
  takeitem = I("Take item", ITEM),
  checkitem = I("Check item", { F("item", "item", "POTION", false, "item") }),
  givemoney = I("Give money", { F("amount", "amount", "0", true) }),
  takemoney = I("Take money", { F("amount", "amount", "0", true) }),
  checkmoney = I("Check money", { F("amount", "amount", "0", true) }),
  givecoins = I("Give coins", { F("amount", "amount", "0", true) }),
  takecoins = I("Take coins", { F("amount", "amount", "0", true) }),
  checkcoins = I("Check coins", { F("amount", "amount", "0", true) }),
  addcellnum = I("Add phone number", { F("contact", "contact", "") }),
  delcellnum = I("Remove phone number", { F("contact", "contact", "") }),
  checkcellnum = I("Check phone number", { F("contact", "contact", "") }),
  checktime = I("Check time of day", { F("time", "time", "") }),
  checkpoke = I("Check party for pokemon", SPECIES),
  givepoke = I("Give pokemon", { F("species", "pokemon", "", false, "pokemon"), F("level", "level", "5", true) }),
  giveegg = I("Give egg", SPECIES),
  givepokemail = I("Give mail", { F("mail", "mail", "") }),
  checkpokemail = I("Check mail", { F("mail", "mail", "") }),
  checkevent = I("Check story flag", EV,
    "Remembers yes/no. The next If yes / If no uses this."),
  clearevent = I("Clear story flag", EV),
  setevent = I("Set story flag", EV),
  checkflag = I("Check engine flag", FLAG,
    "Badges, Pokédex, fly points — not story flags."),
  clearflag = I("Clear engine flag", FLAG),
  setflag = I("Set engine flag", FLAG),
  wildon = I("Enable wild battles"),
  wildoff = I("Disable wild battles"),
  xycompare = I("Check player position"),
  warpmod = I("Set fallback warp", MAP),
  blackoutmod = I("Set blackout map", MAP),
  warp = I("Warp", { F("map", "map", ""), F("x", "x", "0", true), F("y", "y", "0", true) }),
  getmoney = I("Copy money to buffer"),
  getcoins = I("Copy coins to buffer"),
  getnum = I("Copy number to buffer"),
  getmonname = I("Copy pokemon name", SPECIES),
  getitemname = I("Copy item name", { F("item", "item", "", false, "item") }),
  getcurlandmarkname = I("Copy landmark name"),
  gettrainername = I("Copy trainer name", { F("class", "class", "1", true) }),
  getstring = I("Copy string", TEXT),
  itemnotify = I("Show item received"),
  pocketisfull = I("Show pack is full"),
  opentext = I("Open text box"),
  reanchormap = I("Refresh the screen"),
  closetext = I("Close text box"),
  writeunusedbyte = I("Write unused byte", { F("value", "value", "0", true) }),
  farwritetext = I("Show text (other bank)", TEXT),
  writetext = I("Show text", TEXT),
  repeattext = I("Repeat last text"),
  yesorno = I("Ask yes or no"),
  loadmenu = I("Open menu"),
  closewindow = I("Close menu"),
  jumptextfaceplayer = I("Say, face player, and end", TEXT),
  farjumptext = I("Say far text and end", TEXT, "Crystal: jump to a text in another bank."),
  jumptext = I("Say and end", TEXT),
  waitbutton = I("Wait for button"),
  promptbutton = I("Prompt button"),
  pokepic = I("Show pokemon picture", SPECIES),
  closepokepic = I("Close pokemon picture"),
  _2dmenu = I("Show 2D menu"),
  verticalmenu = I("Show vertical menu"),
  loadpikachudata = I("Load Pikachu data"),
  randomwildmon = I("Random wild pokemon"),
  loadtemptrainer = I("Load temp trainer"),
  loadwildmon = I("Load wild pokemon", { F("species", "pokemon", "", false, "pokemon"), F("level", "level", "5", true) }),
  loadtrainer = I("Load trainer", { F("class", "class", "1", true), F("member", "member", "1", true) }),
  startbattle = I("Start battle"),
  reloadmapafterbattle = I("Reload map after battle"),
  catchtutorial = I("Catch tutorial"),
  trainertext = I("Show trainer text", { F("which", "which", "") }),
  trainerflagaction = I("Trainer flag action"),
  winlosstext = I("Set win/lose text", { F("win", "win text", ""), F("lose", "lose text", "") }),
  scripttalkafter = I("Talk after battle"),
  endifjustbattled = I("Stop if not after a battle",
    nil, "Ends here unless the player just finished a fight."),
  checkjustbattled = I("Check if just battled"),
  setlasttalked = I("Set last talked person", { F("object", "person", "0", true) }),
  applymovement = I("Move person", { F("object", "person", ""), F("movement", "movement", "") }),
  applymovementlasttalked = I("Move last talked", { F("movement", "movement", "") }),
  faceplayer = I("Face player"),
  faceobject = I("Face a person", { F("object", "person", ""), F("target", "face toward", "") }),
  variablesprite = I("Set variable sprite", { F("slot", "slot", ""), F("sprite", "sprite", "") }),
  disappear = I("Hide person", { F("object", "person", "") }),
  appear = I("Show person", { F("object", "person", "") }),
  follow = I("Start follow", { F("leader", "leader", ""), F("follower", "follower", "") }),
  stopfollow = I("Stop follow"),
  moveobject = I("Place person", { F("object", "person", ""), F("x", "x", "0", true), F("y", "y", "0", true) }),
  writeobjectxy = I("Save person position", { F("object", "person", "") }),
  loademote = I("Load emote", { F("emote", "emote", "") }),
  showemote = I("Show emote", { F("emote", "emote", ""), F("object", "person", "") }),
  turnobject = I("Turn person", { F("object", "person", ""), F("facing", "facing", "down") }),
  follownotexact = I("Follow loosely"),
  earthquake = I("Earthquake", { F("duration", "duration", "1", true) }),
  changemapblocks = I("Change map blocks"),
  changeblock = I("Change block", { F("x", "x", "0", true), F("y", "y", "0", true), F("block", "block", "0", true) }),
  reloadmap = I("Reload map"),
  refreshmap = I("Refresh map"),
  writecmdqueue = I("Write command queue"),
  delcmdqueue = I("Delete command queue"),
  playmusic = I("Play music", { F("music", "song", "", false, "song") }),
  encountermusic = I("Play encounter music"),
  musicfadeout = I("Fade out music"),
  playmapmusic = I("Play map music"),
  dontrestartmapmusic = I("Keep current music"),
  cry = I("Play cry", SPECIES),
  playsound = I("Play sound", { F("sound", "sound", "") }),
  waitsfx = I("Wait for sound"),
  warpsound = I("Play warp sound"),
  specialsound = I("Play special sound"),
  autoinput = I("Auto input"),
  newloadmap = I("Load map", MAP),
  pause = I("Pause", { F("length", "frames", "1", true) }),
  deactivatefacing = I("Stop facing"),
  sdefer = I("Do this talk later", SCRIPT),
  warpcheck = I("Check warp"),
  stopandsjump = I("Stop and go to other talk", SCRIPT),
  endcallback = I("End callback"),
  ["end"] = I("End script"),
  reloadend = I("Reload and end"),
  endall = I("End all scripts"),
  pokemart = I("Open mart", { F("mart", "mart", "") }),
  elevator = I("Elevator"),
  trade = I("In-game trade", { F("index", "trade #", "1", true) }),
  askforphonenumber = I("Ask for phone number"),
  phonecall = I("Phone call"),
  hangup = I("Hang up"),
  describedecoration = I("Describe decoration"),
  fruittree = I("Berry tree", { F("tree", "tree", "") }),
  specialphonecall = I("Special phone call"),
  checkphonecall = I("Check phone call"),
  verbosegiveitem = I("Give item and announce", ITEM),
  swarm = I("Set swarm", MAP),
  halloffame = I("Hall of Fame"),
  credits = I("Credits"),
  warpfacing = I("Warp and face", {
    F("map", "map", ""), F("x", "x", "0", true), F("y", "y", "0", true),
    F("facing", "facing", "down"),
  }),
  modcommand = I("Mod command"),
}

local FALLBACK_FIELDS = {
  F("event", "story flag #", "0", true),
  F("flag", "flag", ""),
  F("item", "item", "", false, "item"),
  F("quantity", "count", "1", true),
  F("script", "script", ""),
  F("text", "text", ""),
  F("id", "id", ""),
  F("species", "pokemon", "", false, "pokemon"),
  F("map", "map", ""),
  F("x", "x", "0", true),
  F("y", "y", "0", true),
  F("value", "value", ""),
  F("var", "variable", ""),
  F("sound", "sound", ""),
  F("music", "song", "", false, "song"),
  F("object", "person", ""),
}

function OpcodeHelp.info(op)
  return INFO[op]
end

function OpcodeHelp.label(op)
  local rec = INFO[op]
  if rec then return rec.label end
  if type(op) == "string" and op ~= "" then
    return op:sub(1, 1):upper() .. op:sub(2)
  end
  return "Command"
end

function OpcodeHelp.hint(op)
  local rec = INFO[op]
  return rec and rec.hint or nil
end

function OpcodeHelp.fields(op, cmd)
  local rec = INFO[op]
  if rec and rec.fields then return rec.fields end
  local out = {}
  if type(cmd) ~= "table" then return out end
  local seen = { op = true }
  for _, f in ipairs(FALLBACK_FIELDS) do
    if cmd[f.key] ~= nil then
      out[#out + 1] = f
      seen[f.key] = true
    end
  end
  return out
end

function OpcodeHelp.preview(cmd)
  if type(cmd) ~= "table" then return "" end
  local parts = {}
  for _, f in ipairs(OpcodeHelp.fields(cmd.op, cmd)) do
    local v = cmd[f.key]
    if v ~= nil and v ~= "" then
      parts[#parts + 1] = tostring(v)
    end
  end
  return table.concat(parts, " · ")
end

function OpcodeHelp.ops()
  local ids = {}
  for op in pairs(INFO) do
    ids[#ids + 1] = op
  end
  table.sort(ids, function(a, b)
    return OpcodeHelp.label(a) < OpcodeHelp.label(b)
  end)
  return ids
end

function OpcodeHelp.labels()
  local labels = {}
  for op in pairs(INFO) do
    labels[op] = OpcodeHelp.label(op)
  end
  return labels
end

return OpcodeHelp
