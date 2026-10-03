-- The other game's tilesets and maps in a Gen 3 project: FireRed maps in an
-- Emerald project (Gen3FrLink) or Emerald maps in a FireRed / LeafGreen
-- project (Gen3EmLink). The two never apply to the same project, so the
-- places that read tilesets, layouts and template maps ask here and get the
-- answer of whichever the id belongs to.
local M = {}

local function fr() return require("Gen3FrLink") end
local function em() return require("Gen3EmLink") end
local function both() return { fr(), em() } end

local function owner(id)
  for _, link in ipairs(both()) do
    if link.isPair(id) or link.isMap(id) then return link end
  end
end

--- The link the project is using (its patch is on), or nil.
function M.host(project)
  for _, link in ipairs(both()) do
    if link.enabled(project) then return link end
  end
end

function M.enabled(project) return M.host(project) ~= nil end

--- The link's name for the other game ("FireRed" / "Emerald"), for texts.
function M.name(project)
  local h = M.host(project)
  return h and h.NAME or "FireRed"
end

--- The other game's import the editor can use, or nil. With a project, the
-- one its patch needs.
function M.editor(project)
  local h = project and M.host(project)
  if h then return h.editor() end
  return fr().editor() or em().editor()
end

function M.isPair(id) return owner(id) ~= nil and owner(id).isPair(id) end
function M.isMap(id) return owner(id) ~= nil and owner(id).isMap(id) end
function M.label(p)
  local link = owner(p)
  return link and link.label(p) or fr().label(p)
end
function M.redirect(path)
  return fr().redirect(path) or em().redirect(path)
end
function M.read(path)
  if em().redirect(path) then return em().read(path) end
  return fr().read(path)
end
function M.layout(source)
  local link = owner(source)
  if not link then return nil, "Not a map of the other game" end
  return link.layout(source)
end
function M.behaviors(pair)
  local link = owner(pair)
  return link and link.behaviors(pair) or nil
end
function M.templateSource(S, source)
  local link = owner(source)
  if not link then return nil, "Not a map of the other game" end
  return link.templateSource(S, source)
end
function M.templateMaps(project)
  local h = M.host(project)
  if not h then return {}, {} end
  return h.templateMaps(project)
end
--- The map's own name from a template id: "frlg:FR_ROUTE_1" -> "ROUTE_1".
function M.templateName(source)
  local link = owner(source)
  if not link then return tostring(source) end
  local id = source:sub(#link.MAP + 1)
  return (id:gsub("^FR_", ""):gsub("^EM_", ""))
end
function M.header(source)
  local link = owner(source)
  return link and link.header(source:sub(#link.MAP + 1)) or nil
end
--- The other game's tilesets as editor ids (only when the patch is on).
function M.pairs(project)
  local h = M.host(project)
  if not (h and h.editor()) then return {}, {} end
  return h.pairs()
end
function M.used(project)
  return fr().used(project) or em().used(project)
end
function M.emit(project, encode, out)
  fr().emit(project, encode, out)
  em().emit(project, encode, out)
end
function M.reset()
  fr().reset(); em().reset()
end

return M
