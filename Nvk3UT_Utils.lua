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

local function resolveShowCategoryCountsOverride(override)
  if type(override) == "boolean" then
    return override
  end

  local sv = Nvk3UT and Nvk3UT.sv
  local general = sv and sv.General

  if type(override) == "string" then
    local key
    if override == "quest" then
      key = "showQuestCategoryCounts"
    elseif override == "achievement" then
      key = "showAchievementCategoryCounts"
    end
    if key and general and general[key] ~= nil then
      return general[key] ~= false
    end
  elseif override ~= nil then
    return override ~= false
  end

  if sv and sv.showCategoryCounts ~= nil then
    return sv.showCategoryCounts ~= false
  end

  if general then
    if general.showQuestCategoryCounts ~= nil then
      return general.showQuestCategoryCounts ~= false
    end
    if general.showAchievementCategoryCounts ~= nil then
      return general.showAchievementCategoryCounts ~= false
    end
    if general.showCategoryCounts ~= nil then
      return general.showCategoryCounts ~= false
    end
  end

  return true
end

function M.ShouldShowCategoryCounts(context)
  return resolveShowCategoryCountsOverride(context)
end

local function extractLeadingIcons(text)
  if type(text) ~= "string" or text == "" then
    return "", text
  end

  local prefix = ""
  local remainder = text

  while true do
    local iconTag, after = remainder:match("^(|t[^|]-|t%s*)(.*)$")
    if not iconTag then
      break
    end

    prefix = prefix .. iconTag
    remainder = after
  end

  return prefix, remainder
end

function M.FormatCategoryHeaderText(baseText, count, showCounts)
  local text = baseText or ""
  local iconPrefix = ""

  if type(text) == "string" and text ~= "" then
    iconPrefix, text = extractLeadingIcons(text)

    if text ~= "" then
      if type(zo_strupper) == "function" then
        text = zo_strupper(text)
      else
        text = string.upper(text)
      end
    end

    text = iconPrefix .. text
  end

  local show = resolveShowCategoryCountsOverride(showCounts)
  local numericCount = tonumber(count)
  if show and numericCount and numericCount >= 0 then
    numericCount = math.floor(numericCount + 0.5)
    return string.format("%s (%d)", text, numericCount)
  end
  return text
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

local stageCache = {}

local function currentTimestamp()
  if type(GetTimeStamp) == "function" then
    local ok, stamp = pcall(GetTimeStamp)
    if ok and type(stamp) == "number" then
      return stamp
    end
  end
  if M and M.now then
    local ok, stamp = pcall(M.now)
    if ok and type(stamp) == "number" then
      return stamp
    end
  end
  return 0
end

local function computeCriteriaState(id)
  if type(id) ~= "number" then
    return nil
  end
  if type(GetAchievementNumCriteria) ~= "function" or type(GetAchievementCriterion) ~= "function" then
    return nil
  end

  local okCount, numCriteria = pcall(GetAchievementNumCriteria, id)
  if not okCount or type(numCriteria) ~= "number" or numCriteria <= 0 then
    stageCache[id] = {
      total = 0,
      completed = 0,
      stages = {},
      allComplete = safeAchievementInfo(id) == true,
      refreshedAt = currentTimestamp(),
    }
    return stageCache[id]
  end

  local completedCount = 0
  local stageFlags = {}

  for index = 1, numCriteria do
    local okCrit, _, numCompleted, numRequired = pcall(GetAchievementCriterion, id, index)
    if okCrit then
      local achieved = false
      local completedValue = tonumber(numCompleted) or 0
      local requiredValue = tonumber(numRequired) or 0

      if requiredValue > 0 then
        achieved = completedValue >= requiredValue
      else
        achieved = completedValue > 0
      end

      stageFlags[index] = achieved == true
      if stageFlags[index] then
        completedCount = completedCount + 1
      end
    else
      stageFlags[index] = false
    end
  end

  local allComplete = numCriteria > 0 and completedCount >= numCriteria

  stageCache[id] = {
    total = numCriteria,
    completed = completedCount,
    stages = stageFlags,
    allComplete = allComplete,
    refreshedAt = currentTimestamp(),
  }

  return stageCache[id]
end

function M.GetAchievementCriteriaState(id, forceRefresh)
  if forceRefresh then
    stageCache[id] = nil
  end
  if not stageCache[id] then
    stageCache[id] = computeCriteriaState(id)
  end
  return stageCache[id]
end

local function isCriteriaComplete(id)
  local state = M.GetAchievementCriteriaState(id, true)
  if not state then
    return false
  end
  if state.total <= 0 then
    return state.allComplete == true
  end
  return state.allComplete == true
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
  if type(id) ~= "number" then
    return false
  end

  local chain = buildAchievementChain(id)
  if chain and #chain.stages > 1 then
    return true
  end

  local criteria = M.GetAchievementCriteriaState(id)
  if criteria and criteria.total and criteria.total > 1 then
    return true
  end

  if chain and chain.startId and chain.startId ~= id then
    local baseCriteria = M.GetAchievementCriteriaState(chain.startId)
    if baseCriteria and baseCriteria.total and baseCriteria.total > 1 then
      return true
    end
  end

  return false
end

function M.IsAchievementFullyComplete(id)
  if type(id) ~= "number" then
    return false
  end

  local chain = buildAchievementChain(id)
  if not chain or #chain.stages <= 1 then
    if isCriteriaComplete(id) then
      return true
    end
    local normalized = chain and chain.startId or id
    if normalized ~= id and isCriteriaComplete(normalized) then
      return true
    end
    return safeAchievementInfo(normalized)
  end

  local utilsDebug = M.d
  local satisfiedUpstream = false
  for index = #chain.stages, 1, -1 do
    local stageId = chain.stages[index]
    local stageComplete = isCriteriaComplete(stageId) or safeAchievementInfo(stageId) == true
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
    return isCriteriaComplete(id) or safeAchievementInfo(id)
  end

  return satisfiedUpstream
end

