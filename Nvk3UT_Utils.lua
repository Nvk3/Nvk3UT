Nvk3UT = Nvk3UT or {}
local M = {}
Nvk3UT.Utils = M

function M.d(...)
  local sv = Nvk3UT and Nvk3UT.sv
  if not (sv and sv.debug) then
    return
  end
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  local msg = table.concat(parts, " ")
  msg = msg:gsub("^%s*", "")
  if msg:find("^%[Nvk3UT%]") then
    msg = msg:gsub("^%[Nvk3UT%]", "", 1)
  end
  msg = "[Nvk3UT]" .. msg
  if d then
    d(msg)
  end
end

-- timestamp helper
function M.now()
  return GetTimeStamp()
end

local function isValidTexture(path)
  if not path or path == "" then
    return false
  end
  if type(GetInterfaceTextureInfo) == "function" then
    local ok, width, height = pcall(GetInterfaceTextureInfo, path)
    if not ok then
      return false
    end
    if type(width) == "number" and type(height) == "number" then
      return (width > 0) and (height > 0)
    end
    return false
  end
  return true
end

local function normalizeTexturePath(path)
  if not path or path == "" then
    return nil
  end
  if isValidTexture(path) then
    return path
  end
  local fallback = path:gsub("_64%.dds$", ".dds")
  if fallback ~= path and isValidTexture(fallback) then
    return fallback
  end
  return path
end

function M.GetIconTagForTexture(path, size)
  local normalized = normalizeTexturePath(path)
  if not normalized or normalized == "" then
    return ""
  end
  local iconSize = tonumber(size) or 32
  return string.format("|t%d:%d:%s|t ", iconSize, iconSize, normalized)
end

function M.GetAchievementCategoryIconTag(topCategoryId, size)
  if type(GetAchievementCategoryKeyboardIcons) ~= "function" then
    return ""
  end
  if type(topCategoryId) ~= "number" then
    return ""
  end
  local ok, icon = pcall(GetAchievementCategoryKeyboardIcons, topCategoryId)
  if not ok then
    return ""
  end
  if type(icon) ~= "string" or icon == "" then
    return ""
  end
  return M.GetIconTagForTexture(icon, size)
end

