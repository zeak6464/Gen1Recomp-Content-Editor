local M={limit=65535}
M.source=[=[
do
  local schema=require("src.mods.Schemas")
  local field=schema.REGISTRIES.pokemon.gen3Fields.index
  local expanded=schema.f.int(1,65535)
  -- Change the shared descriptor, including cached Gen 3 schema shapes.
  field.inner=expanded;field.desc=expanded.desc
end
]=]
function M.install() assert(loadstring(M.source))() end
return M
