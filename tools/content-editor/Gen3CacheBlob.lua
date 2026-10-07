-- Cache bytes are deflated by newer runtimes; mod asset bytes remain raw.
local M = {}
local function compressedHeader(bytes)
  local cmf, flg = bytes:byte(1, 2)
  return cmf and flg and ((cmf % 16 == 8 and cmf < 128 and (cmf * 256 + flg) % 31 == 0)
    or (cmf == 31 and flg == 139))
end
function M.decode(path, bytes)
  if bytes == nil then return nil end
  -- Older imports stored native indexed atlases directly. Their SVMI header
  -- identifies the format unambiguously; native_pack validates the contents
  -- when the tileset is loaded. Do not swallow failed compressed decodes.
  if type(path) == "string" and path:match("%.idx$")
      and type(bytes) == "string" and bytes:sub(1, 4) == "SVMI" then
    return bytes
  end
  local ok, Blob = pcall(require, "src.import.CacheBlob")
  if ok then
    local decoded, result = pcall(Blob.decode, path, bytes)
    if decoded then return result end
    -- Legacy imports also stored RGBA pixels directly, four bytes per pixel.
    -- A recognizable compressed header must still fail if decompression fails.
    if type(path) == "string" and path:match("%.rgba$")
        and type(bytes) == "string" and #bytes > 0 and #bytes % 4 == 0
        and not compressedHeader(bytes) then
      return bytes
    end
    -- Legacy animation banks have no SVMI header: each frame/metatile is
    -- exactly 256 palette indices. Only accept those native bank paths and
    -- never reinterpret a damaged zlib stream as raw pixels.
    if type(path) == "string" and path:match("/native/[^/]+/anim_[^/]+%.idx$")
        and type(bytes) == "string" and #bytes > 0 and #bytes % 256 == 0 then
      if not compressedHeader(bytes) then return bytes end
    end
    error(result, 2)
  end
  return bytes
end
return M
