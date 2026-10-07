-- The plain-data half of the map builder's fullscreen preview (MapPopout):
-- what changed between two copies of a table, applying that to another copy,
-- and message framing.
--
-- The preview is a separate program with its own copy of the project. A
-- change is sent as a list of { p = path, v = value } (or d = true: gone);
-- nothing here knows about sockets, LÖVE or the editor.
local M = {}

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end
M.copy = copy

--- Only what can be sent: numbers, strings, booleans and tables of them.
-- Anything else (images, functions) is left out; so are keys that aren't a
-- number or a string. Returns nil when the value itself can't be sent.
local function plain(v, depth)
  local t = type(v)
  if t == "number" or t == "string" or t == "boolean" then return v end
  if t ~= "table" then return nil end
  depth = depth or 0
  if depth > 24 then return nil end
  local out = {}
  for k, x in pairs(v) do
    local kt = type(k)
    if kt == "number" or kt == "string" then
      local p = plain(x, depth + 1)
      if p ~= nil then out[k] = p end
    end
  end
  return out
end
M.plain = plain

local function pathTo(path, n, key)
  local out = {}
  for i = 1, n do out[i] = path[i] end
  out[n + 1] = key
  return out
end

-- A small table of plain values (a map cell's { source, tile }, a point) is
-- one value: it is sent whole and put in place whole, never changed field by
-- field. The editor shares one such table between every cell that shows the
-- same tile, so changing it in place would repaint them all.
local RECORD_MAX = 8
local function record(t)
  local n = 0
  for _, v in pairs(t) do
    if type(v) == "table" then return false end
    n = n + 1
    if n > RECORD_MAX then return false end
  end
  return true
end
local function same(a, b)
  for k, v in pairs(a) do
    if b[k] ~= v then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function walk(a, b, path, n, out)
  for k, v in pairs(b) do
    local o = a[k]
    if v ~= o then
      if type(v) == "table" and type(o) == "table" then
        local rv, ro = record(v), record(o)
        if rv or ro then
          if not (rv and ro and same(o, v)) then
            out[#out + 1] = { p = pathTo(path, n, k), v = v }
          end
        else
          path[n + 1] = k
          walk(o, v, path, n + 1, out)
        end
      else
        out[#out + 1] = { p = pathTo(path, n, k), v = v }
      end
    end
  end
  for k in pairs(a) do
    if b[k] == nil then out[#out + 1] = { p = pathTo(path, n, k), d = true } end
  end
end

--- What turns `old` into `new`: a list of changes (empty when they match).
-- Values are the ones in `new`, not copies.
function M.diff(old, new, out)
  out = out or {}
  walk(old, new, {}, 0, out)
  return out
end

--- Apply changes to `root`. With `copies`, table values are copied in, so
-- `root` shares nothing with where the changes came from. Tables already in
-- `root` are changed in place, never replaced, unless a change names them
-- (which is how a small record changes: see `record` above).
function M.apply(root, ops, copies)
  for i = 1, #ops do
    local op = ops[i]
    local path = op.p
    local node = root
    local n = #path
    for j = 1, n - 1 do
      local child = node[path[j]]
      if type(child) ~= "table" then
        child = {}
        node[path[j]] = child
      end
      node = child
    end
    if n > 0 then
      if op.d then node[path[n]] = nil
      elseif copies then node[path[n]] = copy(op.v)
      else node[path[n]] = op.v end
    end
  end
  return root
end

--- One message on the wire: ten digits of length, then the text.
function M.frame(text)
  return ("%010d"):format(#text) .. text
end

--- Take whole messages off the front of `buffer`: returns the texts and
-- what is left. A length that isn't ten digits returns nil, "bad frame".
function M.unframe(buffer)
  local out = {}
  local at = 1
  while #buffer - at + 1 >= 10 do
    local head = buffer:sub(at, at + 9)
    local n = tonumber(head)
    if not (n and head:match("^%d+$")) then return nil, "bad frame" end
    if #buffer - at + 1 - 10 < n then break end
    out[#out + 1] = buffer:sub(at + 10, at + 9 + n)
    at = at + 10 + n
  end
  return out, at > 1 and buffer:sub(at) or buffer
end

--- Is every change a cell inside a map that is already there? Those need no
-- rebuilding in the preview; anything else does.
function M.cellsOnly(ops)
  for i = 1, #ops do
    local p = ops[i].p
    if not (p[1] == "layeredMaps" and #p >= 4) then return false end
  end
  return true
end

return M
