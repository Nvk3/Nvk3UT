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

function M.ResolveTexturePath(path)
  return normalizeTexturePath(path)
end

function M.GetIconTagForTexture(path, size)
  local normalized = normalizeTexturePath(path)
  if not normalized or normalized == "" then
    return ""
  end
  local iconSize = tonumber(size) or 32
  return string.format("|t%d:%d:%s|t ", iconSize, iconSize, normalized)
end

local function stripLeadingIcon(text)
  if type(text) ~= "string" or text == "" then
    return text
  end
  local previous
  local stripped = text
  repeat
    previous = stripped
    stripped = stripped:gsub("^|t[^|]-|t%s*", "")
  until stripped == previous
  if stripped ~= text then
    stripped = stripped:gsub("^%s+", "")
  end
  return stripped
end

function M.StripLeadingIconTag(text)
  return stripLeadingIcon(text)
end

function M.GetAchievementCategoryIconTextures(topCategoryId)
  if type(GetAchievementCategoryKeyboardIcons) ~= "function" then
    return nil
  end
  if type(topCategoryId) ~= "number" then
    return nil
  end
  local ok, normal, pressed, mouseover, selected = pcall(GetAchievementCategoryKeyboardIcons, topCategoryId)
  if not ok then
    return nil
  end

  local textures
  local function assign(key, value)
    local normalized = normalizeTexturePath(value)
    if normalized and normalized ~= "" then
      textures = textures or {}
      textures[key] = normalized
    end
  end

  assign("normal", normal)
  assign("pressed", pressed)
  assign("mouseover", mouseover)
  assign("selected", selected)

  if not textures then
    return nil
  end

  local base = textures.normal or textures.pressed or textures.mouseover or textures.selected
  if not base then
    return nil
  end

  textures.normal = textures.normal or base
  textures.pressed = textures.pressed or base
  textures.mouseover = textures.mouseover or textures.pressed or base
  textures.selected = textures.selected or textures.mouseover or base

  return textures
end

function M.GetAchievementCategoryIconPath(topCategoryId)
  local textures = M.GetAchievementCategoryIconTextures(topCategoryId)
  if not textures then
    return nil
  end
  return textures.normal
end

function M.GetAchievementCategoryIconTag(topCategoryId, size)
  local textures = M.GetAchievementCategoryIconTextures(topCategoryId)
  if not textures or not textures.normal then
    return ""
  end
  return M.GetIconTagForTexture(textures.normal, size)
end

local function safeAchievementInfo(id)
  if type(GetAchievementInfo) ~= "function" then
    return false
  end
  local ok, _, _, _, completed = pcall(GetAchievementInfo, id)
  if not ok then
    return false
  end
  return completed == true
end

local function getBaseAchievementId(id)
  if type(id) ~= "number" then
    return nil
  end
  if type(ACHIEVEMENTS) == "table" and type(ACHIEVEMENTS.GetBaseAchievementId) == "function" then
    local ok, baseId = pcall(ACHIEVEMENTS.GetBaseAchievementId, ACHIEVEMENTS, id)
    if ok and type(baseId) == "number" and baseId ~= 0 then
      return baseId
    end
  end
  return id
end

local function getNextAchievementId(id)
  if type(GetNextAchievementInLine) ~= "function" then
    return nil
  end
  local ok, nextId = pcall(GetNextAchievementInLine, id)
  if ok and type(nextId) == "number" and nextId ~= 0 then
    return nextId
  end
  return nil
end

local function buildAchievementChain(id)
  if type(id) ~= "number" then
    return nil
  end

  local startId = getBaseAchievementId(id) or id
  if not startId or startId == 0 then
    return nil
  end

  local visited = {}
  local stages = {}
  local stageId = startId

  while type(stageId) == "number" and stageId ~= 0 and not visited[stageId] do
    visited[stageId] = true
    stages[#stages + 1] = stageId
    stageId = getNextAchievementId(stageId)
  end

  local looped = stageId and stageId ~= 0 and visited[stageId] == true

  return {
    startId = startId,
    stages = stages,
    looped = looped,
  }
end

function M.NormalizeAchievementId(id)
  local baseId = getBaseAchievementId(id)
  if baseId and baseId ~= 0 then
    return baseId
  end
  return id
end

function M.IsMultiStageAchievement(id)
  local chain = buildAchievementChain(id)
  if not chain then
    return false
  end
  return #chain.stages > 1
end

function M.IsAchievementFullyComplete(id)
  if type(id) ~= "number" then
    return false
  end

  local chain = buildAchievementChain(id)
  if not chain then
    return safeAchievementInfo(id)
  end

  if #chain.stages <= 1 then
    return safeAchievementInfo(chain.startId)
  end

  local utilsDebug = M.d
  local satisfiedUpstream = false
  for index = #chain.stages, 1, -1 do
    local stageId = chain.stages[index]
    local stageComplete = safeAchievementInfo(stageId) == true
    local satisfied = stageComplete or satisfiedUpstream
    if not satisfied then
      if utilsDebug and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug then
        utilsDebug(
          "[Nvk3UT][Utils][Stage] pending",
          string.format("data={id:%d,stage:%d,index:%d}", id, stageId, index)
        )
      end
      return false
    end
    satisfiedUpstream = satisfied
  end

  if chain.looped then
    return safeAchievementInfo(id)
  end

  return satisfiedUpstream
end

