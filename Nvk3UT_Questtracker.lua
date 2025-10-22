Nvk3UT = Nvk3UT or {}

local QT = {}
Nvk3UT.Questtracker = QT

local WM = WINDOW_MANAGER
local EM = EVENT_MANAGER
local CM = CALLBACK_MANAGER
local GuiRoot = GuiRoot
local Utils = Nvk3UT and Nvk3UT.Utils

local ROW_TYPES = {
  ZONE = "zone",
  QUEST = "quest",
  QUEST_OBJECTIVE = "questObjective",
  ACH_ROOT = "achRoot",
  ACHIEVEMENT = "achievement",
  ACH_OBJECTIVE = "achObjective",
}

local SCENE_ATTACH_NAMES = { "hud", "hudui", "siegeBar", "siegeBarUI", "gameMenuInGame" }
local REFRESH_HANDLE = "Nvk3UT_QT_Refresh"

local DEFAULT_ICONS = {
  zone = "EsoUI/Art/Journal/journal_tabIcon_locations_up.dds",
  quest = "EsoUI/Art/Journal/journal_tabIcon_quests_up.dds",
  achievement = "EsoUI/Art/Journal/journal_tabIcon_achievements_up.dds",
  objective = "EsoUI/Art/Journal/journal_tabIcon_achievements_up.dds",
}

local GLOBALS = _G or {}
local MODIFY_NONE = GLOBALS.MODIFY_TEXT_TYPE_NONE or 0
local MODIFY_UPPERCASE = GLOBALS.MODIFY_TEXT_TYPE_UPPERCASE or 1
local WRAP_ELLIPSIS = GLOBALS.TEXT_WRAP_MODE_ELLIPSIS or (type(TEXT_WRAP_MODE_ELLIPSIS) == "number" and TEXT_WRAP_MODE_ELLIPSIS)
  or 1
local TEX_BLEND_ALPHA = GLOBALS.TEX_BLEND_MODE_ALPHA or 1
local SETTING_TYPE_UI = GLOBALS.SETTING_TYPE_UI or (_G and _G.SETTING_TYPE_UI) or 1

local LEFT_MOUSE_BUTTON = (_G and _G.MOUSE_BUTTON_INDEX_LEFT) or MOUSE_BUTTON_INDEX_LEFT or 1
local RIGHT_MOUSE_BUTTON = (_G and _G.MOUSE_BUTTON_INDEX_RIGHT) or MOUSE_BUTTON_INDEX_RIGHT or 2

local ARROW_TEXTURE_COLLAPSED = "EsoUI/Art/Miscellaneous/toggle_right.dds"
local ARROW_TEXTURE_EXPANDED = "EsoUI/Art/Miscellaneous/toggle_down.dds"
local ROW_HEIGHT = {
  [ROW_TYPES.ZONE] = 28,
  [ROW_TYPES.QUEST] = 26,
  [ROW_TYPES.ACH_ROOT] = 28,
  [ROW_TYPES.ACHIEVEMENT] = 26,
  [ROW_TYPES.QUEST_OBJECTIVE] = 22,
  [ROW_TYPES.ACH_OBJECTIVE] = 22,
}

local INDENT = {
  [ROW_TYPES.ZONE] = 0,
  [ROW_TYPES.QUEST] = 20,
  [ROW_TYPES.QUEST_OBJECTIVE] = 44,
  [ROW_TYPES.ACH_ROOT] = 0,
  [ROW_TYPES.ACHIEVEMENT] = 20,
  [ROW_TYPES.ACH_OBJECTIVE] = 44,
}

local ICON_SIZE = {
  [ROW_TYPES.ZONE] = 20,
  [ROW_TYPES.QUEST] = 20,
  [ROW_TYPES.ACH_ROOT] = 20,
  [ROW_TYPES.ACHIEVEMENT] = 20,
  [ROW_TYPES.QUEST_OBJECTIVE] = 18,
  [ROW_TYPES.ACH_OBJECTIVE] = 18,
}

local TOOLTIP_OFFSET_X = 12
local PADDING_X = 12
local PADDING_Y = 12
local MIN_WIDTH = 260
local MIN_HEIGHT = 220

local function debugLog(...)
  if Utils and Utils.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug then
    Utils.d("[Questtracker]", ...)
  end
end

local function safeString(id, fallback)
  if type(GetString) == "function" and id then
    local ok, text = pcall(GetString, id)
    if ok and text and text ~= "" then
      return text
    end
  end
  return fallback
end

local LABELS = {
  questOpenJournal = safeString(SI_QUEST_JOURNAL_OPEN_JOURNAL, "Im Questlog öffnen"),
  questShare = safeString(SI_QUEST_JOURNAL_QUEST_SHARING_HEADER, "Teilen"),
  questShowOnMap = safeString(SI_QUEST_TRACKER_SHOW_QUEST_ON_MAP, "Auf der Karte anzeigen"),
  questAbandon = safeString(SI_QUEST_JOURNAL_ABANDON, "Abbrechen"),
  achievementsHeader = "Errungenschaften",
  achievementsOpen = safeString(SI_ACHIEVEMENTS_OPEN_JOURNAL, "Im Errungenschaftsmenü anzeigen"),
  achievementsRemoveFavorite = safeString(SI_REMOVE_FROM_FAVORITES, "Aus Favoriten entfernen"),
  achievementComplete = safeString(SI_ACHIEVEMENTS_PROGRESS_COMPLETE, "Vollständig"),
  generalZone = safeString(SI_QUEST_JOURNAL_GENERAL_CATEGORY, "Allgemein"),
}

local function round(value)
  if type(zo_round) == "function" then
    return zo_round(value)
  end
  return math.floor((value or 0) + 0.5)
end

local function safeCall(func, ...)
  if type(func) ~= "function" then
    return nil
  end
  local ok, result = pcall(func, ...)
  if not ok then
    return nil
  end
  return result
end

local function pack(...)
  return { n = select("#", ...), ... }
end

local function copyTable(source)
  if type(source) ~= "table" then
    return source
  end
  local result = {}
  for key, value in pairs(source) do
    if type(value) == "table" then
      result[key] = copyTable(value)
    else
      result[key] = value
    end
  end
  return result
end

local function getAchievementLineStart(achievementId)
  if type(GetPreviousAchievementInLine) ~= "function" then
    return achievementId
  end
  local visited = {}
  local current = achievementId
  while type(current) == "number" and current ~= 0 and not visited[current] do
    visited[current] = true
    local okPrev, prevId = pcall(GetPreviousAchievementInLine, current)
    if not okPrev or not prevId or prevId == 0 or visited[prevId] then
      break
    end
    current = prevId
  end
  return current
end

local function getAchievementLineIds(achievementId)
  local ids = {}
  if type(achievementId) ~= "number" or achievementId == 0 then
    return ids
  end
  local startId = getAchievementLineStart(achievementId)
  local visited = {}
  local current = startId
  while type(current) == "number" and current ~= 0 and not visited[current] do
    ids[#ids + 1] = current
    visited[current] = true
    if type(GetNextAchievementInLine) ~= "function" then
      break
    end
    local okNext, nextId = pcall(GetNextAchievementInLine, current)
    if not okNext or not nextId or nextId == 0 or visited[nextId] then
      break
    end
    current = nextId
  end
  return ids
end

local function isAchievementLineCompleted(achievementId)
  local ids = getAchievementLineIds(achievementId)
  local finalId = ids[#ids] or achievementId
  if type(IsAchievementComplete) == "function" then
    local ok, complete = pcall(IsAchievementComplete, finalId)
    if ok then
      return complete == true, finalId, ids
    end
  end
  if type(GetAchievementInfo) == "function" then
    local ok, _, _, _, _, completed = pcall(GetAchievementInfo, finalId)
    if ok then
      return completed == true, finalId, ids
    end
  end
  return false, finalId, ids
end

local function getColor(config, fallback)
  if type(config) ~= "table" then
    return fallback.r, fallback.g, fallback.b, fallback.a
  end
  local r = tonumber(config.r) or fallback.r
  local g = tonumber(config.g) or fallback.g
  local b = tonumber(config.b) or fallback.b
  local a = tonumber(config.a) or fallback.a
  return r, g, b, a
end

local function buildFontDescriptor(config, fallback)
  local face = (config and config.face) or fallback.face
  local size = (config and config.size) or fallback.size
  local effect = (config and config.effect) or fallback.effect
  face = face or fallback.face
  size = tonumber(size) or fallback.size
  effect = effect or fallback.effect
  if face == nil then
    face = "ZoFontGame"
  end
  if effect == nil then
    effect = "soft-shadow-thin"
  end
  if size == nil then
    size = 18
  end
  return string.format("%s|%d|%s", face, size, effect)
end

local function sanitizeText(text)
  if not text or text == "" then
    return ""
  end
  if Utils and Utils.StripLeadingIconTag then
    text = Utils.StripLeadingIconTag(text)
  end
  return zo_strformat("<<1>>", text)
end

local function formatCategoryDisplayName(rawName)
  local sanitized = sanitizeText(rawName)
  if sanitized == "" then
    return LABELS.generalZone
  end
  if type(zo_strformat) == "function" then
    if SI_QUEST_JOURNAL_CATEGORY_NAME then
      local okFmt, formatted = pcall(zo_strformat, SI_QUEST_JOURNAL_CATEGORY_NAME, sanitized)
      if okFmt and formatted and formatted ~= "" then
        return formatted
      end
    end
    local okCaps, capitalized = pcall(zo_strformat, "<<C:1>>", sanitized)
    if okCaps and capitalized and capitalized ~= "" then
      return capitalized
    end
  end
  return sanitized
end

local function getQuestDisplayIcon(displayType)
  if QUEST_JOURNAL_KEYBOARD and QUEST_JOURNAL_KEYBOARD.GetIconTexture then
    local ok, texture = pcall(QUEST_JOURNAL_KEYBOARD.GetIconTexture, QUEST_JOURNAL_KEYBOARD, displayType)
    if ok and texture and texture ~= "" then
      return texture
    end
  end
  return DEFAULT_ICONS.quest
end

local function formatQuestLabel(name, level)
  local questName = sanitizeText(name)
  if level and level > 0 then
    return string.format("[%d] %s", level, questName)
  end
  return questName
end

local function questStepKey(questIndex, questId)
  if type(GetJournalQuestNumSteps) ~= "function" then
    return tostring(questId or questIndex or "")
  end
  local parts = {}
  local steps = safeCall(GetJournalQuestNumSteps, questIndex) or 0
  for stepIndex = 1, steps do
    local stepText, visibility, stepType, trackerComplete, _, _, stepOverride = GetJournalQuestStepInfo(questIndex, stepIndex)
    if not trackerComplete then
      local text = stepOverride ~= "" and stepOverride or stepText or ""
      text = sanitizeText(text)
      parts[#parts + 1] = string.format("%d:%s", stepIndex, text)
    end
  end
  if #parts == 0 then
    parts[#parts + 1] = "complete"
  end
  return string.format("%d:%s", questId or 0, table.concat(parts, "|"))
end

local function gatherTrackedQuestSet()
  if type(GetTrackedQuestIndices) ~= "function" then
    return nil
  end
  local ok, values = pcall(function()
    return pack(GetTrackedQuestIndices())
  end)
  if not ok or type(values) ~= "table" then
    return nil
  end
  local set = {}
  for index = 1, values.n do
    local questIndex = values[index]
    if type(questIndex) == "number" and questIndex > 0 then
      set[questIndex] = true
    end
  end
  if next(set) then
    return set
  end
  return nil
end

local function isQuestTracked(questIndex, trackedLookup)
  if trackedLookup and trackedLookup[questIndex] then
    return true
  end
  local trackers = {
    GetJournalQuestIsTracked,
    GetIsQuestTracked,
    GetIsJournalQuestTracked,
  }
  for _, fn in ipairs(trackers) do
    if type(fn) == "function" then
      local ok, tracked = pcall(fn, questIndex)
      if ok and tracked ~= nil then
        return tracked
      end
    end
  end
  if type(IsJournalQuestStepTracked) == "function" and type(GetJournalQuestNumSteps) == "function" then
    local steps = safeCall(GetJournalQuestNumSteps, questIndex) or 0
    for stepIndex = 1, steps do
      local okStep, trackedStep = pcall(IsJournalQuestStepTracked, questIndex, stepIndex)
      if okStep and trackedStep then
        return true
      end
    end
    return false
  end
  if trackedLookup then
    return false
  end
  return true
end

local function gatherQuestObjectives(questIndex)
  local objectives = {}
  local stepSummaries = {}
  if type(GetJournalQuestNumSteps) ~= "function" then
    return objectives, stepSummaries
  end
  local steps = safeCall(GetJournalQuestNumSteps, questIndex) or 0
  local seenSteps = {}
  for stepIndex = 1, steps do
    local okStep,
      stepText,
      visibility,
      stepType,
      trackerComplete,
      _,
      _,
      stepOverride =
        pcall(GetJournalQuestStepInfo, questIndex, stepIndex)
    if okStep then
      local isHiddenStep = false
      if QUEST_STEP_VISIBILITY_HIDDEN and visibility == QUEST_STEP_VISIBILITY_HIDDEN then
        isHiddenStep = true
      end
      if not trackerComplete and not isHiddenStep then
        local summary = stepOverride ~= "" and stepOverride or stepText or ""
        summary = sanitizeText(summary)
        if summary ~= "" and not seenSteps[summary] then
          stepSummaries[#stepSummaries + 1] = summary
          seenSteps[summary] = true
        end
      end
      if not trackerComplete then
        local numConditions = safeCall(GetJournalQuestNumConditions, questIndex, stepIndex) or 0
        for conditionIndex = 1, numConditions do
          local okCondition,
            conditionText,
            cur,
            max,
            isFail,
            isComplete =
              pcall(GetJournalQuestConditionInfo, questIndex, stepIndex, conditionIndex)
          if okCondition then
            local visible = true
            if type(IsJournalQuestConditionVisible) == "function" then
              local okVisible, isVisible = pcall(IsJournalQuestConditionVisible, questIndex, stepIndex, conditionIndex)
              if okVisible then
                visible = isVisible
              end
            end
            if visible and conditionText ~= "" and not isFail and not isComplete then
              objectives[#objectives + 1] = {
                text = sanitizeText(conditionText),
                current = cur,
                max = max,
                stepIndex = stepIndex,
                conditionIndex = conditionIndex,
              }
            end
          end
        end
      end
    end
  end
  return objectives, stepSummaries
end

local function collectQuests()
  local categories = {}
  if not (QUEST_JOURNAL_MANAGER and QUEST_JOURNAL_MANAGER.GetQuestListData) then
    return categories
  end
  local okData, allQuests, allCategories = pcall(QUEST_JOURNAL_MANAGER.GetQuestListData, QUEST_JOURNAL_MANAGER)
  if not okData or type(allQuests) ~= "table" or type(allCategories) ~= "table" then
    return categories
  end
  local trackedLookup = gatherTrackedQuestSet()
  local categoriesByName = {}
  local orderCounter = 0

  for index, categoryData in ipairs(allCategories) do
    local sanitizedName = formatCategoryDisplayName(categoryData.name)
    orderCounter = orderCounter + 1
    local entry = {
      key = string.format("cat:%d:%d", categoryData.type or 0, index),
      name = sanitizedName ~= "" and sanitizedName or LABELS.generalZone,
      icon = DEFAULT_ICONS.zone,
      quests = {},
      orderType = categoryData.type or 0,
      orderIndex = orderCounter,
    }
    categories[#categories + 1] = entry
    categoriesByName[categoryData.name] = entry
  end

  local function ensureCategory(categoryName, categoryType)
    local lookupKey = categoryName ~= "" and categoryName or LABELS.generalZone
    local existing = categoriesByName[lookupKey]
    if existing then
      return existing
    end
    local displayName = formatCategoryDisplayName(lookupKey)
    orderCounter = orderCounter + 1
    local fallback = {
      key = string.format("cat:%d:%d", categoryType or 999, orderCounter),
      name = displayName,
      icon = DEFAULT_ICONS.zone,
      quests = {},
      orderType = categoryType or 999,
      orderIndex = orderCounter,
    }
    categories[#categories + 1] = fallback
    categoriesByName[lookupKey] = fallback
    return fallback
  end

  for _, questData in ipairs(allQuests) do
    local questIndex = questData.questIndex
    if questIndex and isQuestTracked(questIndex, trackedLookup) then
      local questName = sanitizeText(questData.name or questData.questName or "")
      if questName == "" then
        questName = sanitizeText(safeCall(GetJournalQuestName, questIndex) or "")
      end
      local questId = questData.questId or safeCall(GetJournalQuestId, questIndex) or 0
      local categoryName = questData.categoryName or LABELS.generalZone
      local categoryType = questData.categoryType or 0
      local categoryEntry = ensureCategory(categoryName, categoryType)
      local objectives, stepSummaries = gatherQuestObjectives(questIndex)
      local stepText = stepSummaries[1]
        or sanitizeText(questData.trackerOverrideText or questData.stepText or questData.conditionText or "")
      local displayName = formatQuestLabel(questName, questData.level)
      local questEntry = {
        type = ROW_TYPES.QUEST,
        name = questName ~= "" and questName or LABELS.generalZone,
        displayName = displayName,
        questId = questId,
        journalIndex = questIndex,
        zoneKey = categoryEntry.key,
        objectives = objectives,
        steps = stepSummaries,
        stepText = stepText,
        key = questStepKey(questIndex, questId),
        icon = getQuestDisplayIcon(questData.displayType),
        order = questData.sortOrder or questIndex,
        level = questData.level,
        displayType = questData.displayType,
      }
      categoryEntry.quests[#categoryEntry.quests + 1] = questEntry
    end
  end

  local filtered = {}
  for _, categoryEntry in ipairs(categories) do
    if #categoryEntry.quests > 0 then
      filtered[#filtered + 1] = categoryEntry
    end
  end

  table.sort(filtered, function(left, right)
    if left.orderType ~= right.orderType then
      return left.orderType < right.orderType
    end
    if left.orderIndex ~= right.orderIndex then
      return left.orderIndex < right.orderIndex
    end
    return left.name < right.name
  end)

  for _, categoryEntry in ipairs(filtered) do
    table.sort(categoryEntry.quests, function(left, right)
      if left.order ~= right.order then
        return left.order < right.order
      end
      return left.name < right.name
    end)
  end

  return filtered
end

local function getFavoriteScope()
  local sv = Nvk3UT and Nvk3UT.sv
  return (sv and sv.ui and sv.ui.favScope) or "account"
end

local function isAchievementCompleted(achievementId)
  local complete = false
  if achievementId then
    complete = isAchievementLineCompleted(achievementId)
  end
  return complete == true
end

local function collectFavoriteAchievements()
  local favorites = {}
  local Fav = Nvk3UT and Nvk3UT.FavoritesData
  if not Fav or not Fav.Iterate then
    return favorites
  end
  local scope = getFavoriteScope()
  local seen = {}
  local removals = {}
  local playerGender
  if type(GetUnitGender) == "function" then
    local okGender, gender = pcall(GetUnitGender, "player")
    if okGender then
      playerGender = gender
    end
  end
  for achievementId, flagged in Fav.Iterate(scope) do
    if flagged and type(achievementId) == "number" and achievementId ~= 0 and not seen[achievementId] then
      local completed, finalId, chainIds = isAchievementLineCompleted(achievementId)
      if completed then
        chainIds = chainIds and #chainIds > 0 and chainIds or { achievementId }
        for _, chainId in ipairs(chainIds) do
          removals[#removals + 1] = chainId
          seen[chainId] = true
        end
        if finalId then
          removals[#removals + 1] = finalId
          seen[finalId] = true
        end
      else
        local ids = chainIds and #chainIds > 0 and chainIds or { achievementId }
        for _, chainId in ipairs(ids) do
          seen[chainId] = true
        end
        local displayName, description, iconPath, objectives, totalCurrent, totalRequired = nil, nil, nil, {}, 0, 0
        for _, id in ipairs(ids) do
          local okInfo, stageName, stageDescription, _, stageIcon = pcall(GetAchievementInfo, id)
          if okInfo then
            local sanitizedName = sanitizeText(stageName)
            if playerGender and type(zo_strformat) == "function" and sanitizedName and sanitizedName ~= "" then
              local okFormat, formatted = pcall(zo_strformat, sanitizedName, playerGender)
              if okFormat and formatted and formatted ~= "" then
                sanitizedName = formatted
              end
            end
            if (not displayName or displayName == "") and sanitizedName and sanitizedName ~= "" then
              displayName = sanitizedName
            elseif sanitizedName and sanitizedName ~= "" then
              displayName = sanitizedName
            end
            local sanitizedDescription = sanitizeText(stageDescription)
            if sanitizedDescription ~= "" then
              description = sanitizedDescription
            end
            if stageIcon and stageIcon ~= "" then
              iconPath = stageIcon
            end
          end
          local numCriteria = GetAchievementNumCriteria and GetAchievementNumCriteria(id) or 0
          for criterionIndex = 1, numCriteria do
            local okCrit, criterionDescription, numCompleted, numRequired = pcall(GetAchievementCriterion, id, criterionIndex)
            if okCrit then
              local sanitized = sanitizeText(criterionDescription)
              local currentValue = tonumber(numCompleted) or 0
              local requiredValue = tonumber(numRequired) or 0
              if requiredValue == 0 then
                requiredValue = currentValue
              end
              totalCurrent = totalCurrent + currentValue
              totalRequired = totalRequired + requiredValue
              if sanitized ~= "" and currentValue < requiredValue then
                objectives[#objectives + 1] = {
                  text = sanitized,
                  current = currentValue,
                  max = requiredValue,
                }
              end
            end
          end
        end
        local normalizedIcon = iconPath
        if Utils and Utils.ResolveTexturePath then
          normalizedIcon = Utils.ResolveTexturePath(iconPath)
        end
        local cleanedName = sanitizeText(displayName or "")
        if cleanedName == "" then
          cleanedName = string.format("%d", achievementId)
        end
        local lowerName
        if cleanedName ~= "" then
          if type(zo_strlower) == "function" then
            lowerName = zo_strlower(cleanedName)
          else
            lowerName = string.lower(cleanedName)
          end
        else
          lowerName = string.format("%d", achievementId)
        end
        favorites[#favorites + 1] = {
          id = achievementId,
          favoriteId = achievementId,
          displayId = finalId or achievementId,
          name = cleanedName,
          description = description or "",
          icon = normalizedIcon ~= "" and normalizedIcon or DEFAULT_ICONS.achievement,
          objectives = objectives,
          completed = false,
          sortKey = lowerName,
          progressCurrent = totalCurrent,
          progressMax = totalRequired,
          chainIds = ids,
        }
      end
    end
  end
  if #removals > 0 and Fav and Fav.Remove then
    for _, achievementId in ipairs(removals) do
      if Fav.IsFavorite and Fav.IsFavorite(achievementId, scope) then
        Fav.Remove(achievementId, scope)
      end
    end
  end
  table.sort(favorites, function(a, b)
    local aKey = (a.sortKey ~= "" and a.sortKey) or a.name or ""
    local bKey = (b.sortKey ~= "" and b.sortKey) or b.name or ""
    return aKey < bKey
  end)
  for _, entry in ipairs(favorites) do
    entry.sortKey = nil
  end
  return favorites
end

local function buildObjectiveSignature(list)
  if not list or #list == 0 then
    return "0"
  end
  local parts = {}
  for _, objective in ipairs(list) do
    local text = objective.text or ""
    local current = tonumber(objective.current) or 0
    local max = tonumber(objective.max) or 0
    parts[#parts + 1] = string.format("%s:%d/%d", text, current, max)
  end
  return table.concat(parts, "|")
end

local function buildQuestSignature(quest)
  local components = {
    quest.displayName or quest.name or "",
    quest.stepText or "",
    tostring(#(quest.steps or {})),
    buildObjectiveSignature(quest.objectives),
  }
  return table.concat(components, "||")
end

local function buildAchievementSignature(achievement)
  local components = {
    achievement.name or "",
    tostring(achievement.progressCurrent or 0),
    tostring(achievement.progressMax or 0),
    buildObjectiveSignature(achievement.objectives),
    tostring(achievement.displayId or achievement.id or 0),
  }
  return table.concat(components, "||")
end

function QT:SyncQuestState(zones)
  local previous = self.questState and self.questState.zones or {}
  local newState = { zones = {}, order = {} }
  local changed = false
  local seen = {}
  if type(zones) == "table" then
    for zoneIndex, zone in ipairs(zones) do
      local zoneKey = zone.key or zone.name or tostring(zoneIndex)
      local hashParts = { zone.name or "", tostring(#(zone.quests or {})) }
      local questHashes = {}
      if type(zone.quests) == "table" then
        for questIndex, quest in ipairs(zone.quests) do
          local questKey = quest.key or string.format("%s:%d", zoneKey, questIndex)
          local questHash = buildQuestSignature(quest)
          questHashes[questKey] = questHash
          hashParts[#hashParts + 1] = string.format("%s=%s", questKey, questHash)
        end
      end
      local zoneHash = table.concat(hashParts, "##")
      newState.zones[zoneKey] = { hash = zoneHash, quests = questHashes }
      newState.order[#newState.order + 1] = zoneKey
      seen[zoneKey] = true
      local previousZone = previous[zoneKey]
      if not previousZone or previousZone.hash ~= zoneHash then
        changed = true
      end
    end
  end
  for zoneKey in pairs(previous) do
    if not seen[zoneKey] then
      changed = true
      break
    end
  end
  self.questState = newState
  return changed
end

function QT:ClearQuestState()
  self.questState = { zones = {}, order = {} }
end

function QT:SyncAchievementState(achievements)
  local previous = self.achievementState or {}
  local newState = {}
  local changed = false
  local seen = {}
  if type(achievements) == "table" then
    for index, achievement in ipairs(achievements) do
      local key = achievement.favoriteId or achievement.id or index
      local hash = buildAchievementSignature(achievement)
      newState[key] = hash
      seen[key] = true
      if previous[key] ~= hash then
        changed = true
      end
    end
  end
  for key in pairs(previous) do
    if not seen[key] then
      changed = true
      break
    end
  end
  self.achievementState = newState
  return changed
end

function QT:ClearAchievementState()
  self.achievementState = {}
end

local function ensureLamCallbacks(self)
  if not (CALLBACK_MANAGER and self and self.lamPanelControl) then
    return
  end
  if self.lamCallbacksRegistered then
    return
  end
  self.lamCallbacksRegistered = true
  self.lamPanelOpenedCallback = function(panel)
    if panel == self.lamPanelControl then
      self.lamPanelOpen = true
      self:ApplyVisibility()
    end
  end
  self.lamPanelClosedCallback = function(panel)
    if panel == self.lamPanelControl then
      self.lamPanelOpen = false
      self:ApplyVisibility()
    end
  end
  CALLBACK_MANAGER:RegisterCallback("LAM-PanelOpened", self.lamPanelOpenedCallback)
  CALLBACK_MANAGER:RegisterCallback("LAM-PanelClosed", self.lamPanelClosedCallback)
end

local function removeCompletedFavorite(achievementId)
  if not achievementId then
    return
  end
  local Fav = Nvk3UT and Nvk3UT.FavoritesData
  if not (Fav and Fav.IsFavorite and Fav.Remove) then
    return
  end
  local scope = getFavoriteScope()
  local completed, _, chainIds = isAchievementLineCompleted(achievementId)
  if not completed then
    return
  end
  chainIds = chainIds and #chainIds > 0 and chainIds or { achievementId }
  for _, id in ipairs(chainIds) do
    if Fav.IsFavorite(id, scope) then
      Fav.Remove(id, scope)
    end
  end
end

local function pruneCompletedFavorites()
  local Fav = Nvk3UT and Nvk3UT.FavoritesData
  if not (Fav and Fav.Iterate and Fav.Remove) then
    return
  end
  local scope = getFavoriteScope()
  local removals = {}
  for achievementId, flagged in Fav.Iterate(scope) do
    if flagged then
      local completed, _, chainIds = isAchievementLineCompleted(achievementId)
      if completed then
        chainIds = chainIds and #chainIds > 0 and chainIds or { achievementId }
        for _, id in ipairs(chainIds) do
          removals[#removals + 1] = id
        end
      end
    end
  end
  for _, achievementId in ipairs(removals) do
    Fav.Remove(achievementId, scope)
  end
end

local function applyColorToLabel(label, color)
  if not label then
    return
  end
  local r, g, b, a = getColor(color, { r = 1, g = 1, b = 1, a = 1 })
  label:SetColor(r, g, b, a)
end

local function configureArrow(control, isExpanded)
  if not control.arrow then
    return
  end
  if control.arrowHidden then
    control.arrow:SetHidden(true)
    return
  end
  control.arrow:SetHidden(false)
  if isExpanded then
    control.arrow:SetTexture(ARROW_TEXTURE_EXPANDED)
  else
    control.arrow:SetTexture(ARROW_TEXTURE_COLLAPSED)
  end
end

local function achievementTooltip(control, entry)
  if not (InformationTooltip and InitializeTooltip) then
    return
  end
  clearTooltip()
  local owner = control
  local tracker = QT.control
  if not tracker then
    return
  end
  local centerX = select(1, tracker:GetCenter()) or 0
  local rootCenter = GuiRoot:GetWidth() / 2
  local anchorSide, relativeSide, offset
  if centerX > rootCenter then
    anchorSide = LEFT
    relativeSide = RIGHT
    offset = -TOOLTIP_OFFSET_X
  else
    anchorSide = RIGHT
    relativeSide = LEFT
    offset = TOOLTIP_OFFSET_X
  end
  InitializeTooltip(InformationTooltip, owner, anchorSide, offset, 0, relativeSide)
  InformationTooltip:AddLine(entry.name, "ZoFontGameBold")
  if entry.description and entry.description ~= "" then
    InformationTooltip:AddLine(entry.description, "ZoFontGame")
  end
  if entry.progressMax and entry.progressMax > 0 then
    InformationTooltip:AddLine(string.format("%d/%d", entry.progressCurrent or 0, entry.progressMax), "ZoFontGameSmall")
  end
  if entry.objectives and #entry.objectives > 0 then
    InformationTooltip:AddLine("", "ZoFontGameSmall")
    for _, objective in ipairs(entry.objectives) do
      local progress = string.format("%d/%d", objective.current or 0, objective.max or 0)
      InformationTooltip:AddLine(string.format("• %s (%s)", objective.text, progress), "ZoFontGameSmall")
    end
  end
end

local function questTooltip(control, entry, zoneName)
  if not (InformationTooltip and InitializeTooltip) then
    return
  end
  clearTooltip()
  local tracker = QT.control
  if not tracker then
    return
  end
  local centerX = select(1, tracker:GetCenter()) or 0
  local rootCenter = GuiRoot:GetWidth() / 2
  local anchorSide, relativeSide, offset
  if centerX > rootCenter then
    anchorSide = LEFT
    relativeSide = RIGHT
    offset = -TOOLTIP_OFFSET_X
  else
    anchorSide = RIGHT
    relativeSide = LEFT
    offset = TOOLTIP_OFFSET_X
  end
  InitializeTooltip(InformationTooltip, control, anchorSide, offset, 0, relativeSide)
  InformationTooltip:AddLine(entry.name, "ZoFontGameBold")
  if zoneName and zoneName ~= "" then
    InformationTooltip:AddLine(zoneName, "ZoFontGame")
  end
  if entry.steps and #entry.steps > 0 then
    for _, stepSummary in ipairs(entry.steps) do
      if stepSummary ~= "" then
        InformationTooltip:AddLine(stepSummary, "ZoFontGame")
      end
    end
  elseif entry.stepText and entry.stepText ~= "" then
    InformationTooltip:AddLine(entry.stepText, "ZoFontGame")
  end
  if entry.objectives and #entry.objectives > 0 then
    InformationTooltip:AddLine("", "ZoFontGameSmall")
    for _, objective in ipairs(entry.objectives) do
      local maxValue = objective.max or 0
      local progress = (maxValue > 0) and string.format("%d/%d", objective.current or 0, maxValue) or ""
      if progress ~= "" then
        InformationTooltip:AddLine(string.format("• %s (%s)", objective.text, progress), "ZoFontGameSmall")
      else
        InformationTooltip:AddLine(string.format("• %s", objective.text), "ZoFontGameSmall")
      end
    end
  end
end

local function clearTooltip()
  if type(ClearTooltip) == "function" then
    ClearTooltip(InformationTooltip)
  elseif InformationTooltip and InformationTooltip.ClearLines then
    InformationTooltip:ClearLines()
    InformationTooltip:SetHidden(true)
  end
end

function QT:EnsureControl()
  if self.control then
    return
  end
  local control = WM:CreateTopLevelWindow("Nvk3UT_Questtracker")
  control:SetMouseEnabled(true)
  control:SetMovable(true)
  control:SetResizeHandleSize(8)
  control:SetClampedToScreen(true)
  control:SetHidden(true)
  control:SetDrawLayer(DL_BACKGROUND)
  control:SetDrawTier(DT_LOW)
  control:SetDrawLevel(0)
  control:SetHandler("OnMoveStop", function()
    self:SavePosition()
  end)
  control:SetHandler("OnResizeStop", function()
    self:SaveDimensions()
  end)
  control:SetHandler("OnHide", function()
    clearTooltip()
  end)

  local backdrop = WM:CreateControl(nil, control, CT_BACKDROP)
  backdrop:SetAnchorFill()
  backdrop:SetCenterColor(0, 0, 0, 0.45)
  backdrop:SetEdgeColor(1, 1, 1, 0.35)
  backdrop:SetEdgeTexture(nil, 1, 1, 1, 0)
  backdrop:SetHidden(true)

  local scroll = CreateControlFromVirtual("Nvk3UT_Questtracker_Scroll", control, "ZO_ScrollContainer")
  scroll:SetAnchor(TOPLEFT, control, TOPLEFT, PADDING_X, PADDING_Y)
  scroll:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, -PADDING_X, -PADDING_Y)
  local scrollChild = scroll:GetNamedChild("ScrollChild")
  scrollChild:SetResizeToFitDescendents(true)

  self.control = control
  self.backdrop = backdrop
  self.scroll = scroll
  self.scrollChild = scrollChild
  self.rowPool = {}
  self.activeRows = {}
  if SCENE_MANAGER then
    self.sceneFragments = self.sceneFragments or {}
    if not self.fragment then
      local fragmentClass = ZO_HUDFadeSceneFragment or ZO_SimpleSceneFragment
      if fragmentClass then
        self.fragment = fragmentClass:New(control)
        if self.fragment.SetHideOnSceneHidden then
          self.fragment:SetHideOnSceneHidden(true)
        end
      end
    end
    if self.fragment then
      for _, sceneName in ipairs(SCENE_ATTACH_NAMES) do
        if not self.sceneFragments[sceneName] then
          local scene = SCENE_MANAGER:GetScene(sceneName)
          if scene and scene.AddFragment then
            scene:AddFragment(self.fragment)
            self.sceneFragments[sceneName] = true
          end
        end
      end
    end
  end
  self.fragmentReasons = self.fragmentReasons or {}
end

function QT:SavePosition()
  if not (self.control and self.sv and self.sv.pos) then
    return
  end
  local left = self.control:GetLeft()
  local top = self.control:GetTop()
  self.sv.pos.x = left
  self.sv.pos.y = top
end

function QT:SaveDimensions()
  if not (self.control and self.sv and self.sv.pos) then
    return
  end
  if self.sv.behavior and self.sv.behavior.autoGrowV then
    return
  end
  self.sv.pos.width = math.max(MIN_WIDTH, round(self.control:GetWidth()))
  self.sv.pos.height = math.max(MIN_HEIGHT, round(self.control:GetHeight()))
end

local function applyLockState(self)
  if not self.control then
    return
  end
  local locked = self.sv.behavior.locked == true
  self.control:SetMovable(not locked)
  self.control:SetResizeHandleSize(locked and 0 or 8)
end

local function applyBackground(self)
  if not (self.control and self.backdrop) then
    return
  end
  local cfg = self.sv.background or {}
  if not cfg.enabled or (cfg.hideWhenLocked and self.sv.behavior.locked) then
    self.backdrop:SetHidden(true)
    return
  end
  local alpha = tonumber(cfg.alpha) or 60
  local normalized = math.max(0, math.min(100, alpha)) / 100
  self.backdrop:SetCenterColor(0, 0, 0, normalized)
  if cfg.border then
    self.backdrop:SetEdgeColor(1, 1, 1, normalized)
    self.backdrop:SetEdgeTexture(nil, 1, 1, 1, 1)
  else
    self.backdrop:SetEdgeColor(0, 0, 0, 0)
    self.backdrop:SetEdgeTexture(nil, 1, 1, 0, 0)
  end
  self.backdrop:SetHidden(false)
end

local function applyScaleAndPosition(self)
  if not (self.control and self.sv and self.sv.pos) then
    return
  end
  local pos = self.sv.pos
  local scale = tonumber(pos.scale) or 1
  self.control:SetScale(scale)
  self.control:ClearAnchors()
  local x = tonumber(pos.x) or 200
  local y = tonumber(pos.y) or 150
  self.control:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, x, y)
  local width = math.max(MIN_WIDTH, tonumber(pos.width) or MIN_WIDTH)
  local height = math.max(MIN_HEIGHT, tonumber(pos.height) or MIN_HEIGHT)
  self.control:SetDimensions(width, height)
end

local function releaseRow(self, row)
  if not row then
    return
  end
  row:SetHidden(true)
  row:ClearAnchors()
  row.data = nil
  row.zoneName = nil
  row.questName = nil
  if row.highlight then
    row.highlight:SetAlpha(0)
  end
  self.rowPool[#self.rowPool + 1] = row
end

local function releaseAllRows(self)
  if not self.activeRows then
    return
  end
  for i = 1, #self.activeRows do
    releaseRow(self, self.activeRows[i])
  end
  if ZO_ClearNumericallyIndexedTable then
    ZO_ClearNumericallyIndexedTable(self.activeRows)
  else
    for index = #self.activeRows, 1, -1 do
      self.activeRows[index] = nil
    end
  end
  self.lastRow = nil
end

local function acquireRow(self)
  local row = table.remove(self.rowPool)
  if row then
    row:SetHidden(false)
    return row
  end
  local scrollChild = self.scrollChild
  row = WM:CreateControl(nil, scrollChild, CT_CONTROL)
  row:SetHeight(26)
  row:SetMouseEnabled(true)
  row:SetHandler("OnMouseUp", function(control, button, upInside)
    if not upInside then
      return
    end
    if button == LEFT_MOUSE_BUTTON then
      QT:OnRowLeftClick(control)
    elseif button == RIGHT_MOUSE_BUTTON then
      QT:OnRowRightClick(control)
    end
  end)
  row:SetHandler("OnMouseEnter", function(control)
    if control.highlight then
      control.highlight:SetAlpha(0.18)
    end
    QT:OnRowEnter(control)
  end)
  row:SetHandler("OnMouseExit", function(control)
    if control.highlight then
      control.highlight:SetAlpha(0)
    end
    clearTooltip()
  end)

  local highlight = WM:CreateControl(nil, row, CT_TEXTURE)
  highlight:SetAnchorFill()
  highlight:SetTexture("EsoUI/Art/Miscellaneous/listItem_highlight.dds")
  highlight:SetBlendMode(TEX_BLEND_ALPHA)
  highlight:SetAlpha(0)
  highlight:SetDrawLayer(DL_BACKGROUND)

  local arrow = WM:CreateControl(nil, row, CT_TEXTURE)
  arrow:SetDimensions(16, 16)
  arrow:SetAnchor(LEFT, row, LEFT, 0, 0)

  local icon = WM:CreateControl(nil, row, CT_TEXTURE)
  icon:SetDimensions(20, 20)
  icon:SetAnchor(LEFT, arrow, RIGHT, 4, 0)

  local label = WM:CreateControl(nil, row, CT_LABEL)
  label:SetAnchor(LEFT, icon, RIGHT, 6, 0)
  label:SetAnchor(RIGHT, row, RIGHT, 0, 0)
  label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
  label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)

  row.arrow = arrow
  row.icon = icon
  row.label = label
  row.highlight = highlight

  return row
end

local function appendRow(self, row)
  row:ClearAnchors()
  if self.lastRow then
    row:SetAnchor(TOPLEFT, self.lastRow, BOTTOMLEFT, 0, 2)
    row:SetAnchor(TOPRIGHT, self.lastRow, BOTTOMRIGHT, 0, 2)
  else
    row:SetAnchor(TOPLEFT, self.scrollChild, TOPLEFT, 0, 0)
    row:SetAnchor(TOPRIGHT, self.scrollChild, TOPRIGHT, 0, 0)
  end
  row:SetHidden(false)
  self.activeRows[#self.activeRows + 1] = row
  self.lastRow = row
end

local function configureRow(self, row, rowType, text, iconPath, isCollapsible, expanded)
  local height = ROW_HEIGHT[rowType] or 24
  row:SetHeight(height)
  if row.highlight then
    row.highlight:SetAlpha(0)
  end
  row.arrowHidden = not isCollapsible
  configureArrow(row, expanded)
  if row.arrowHidden then
    row.arrow:SetHidden(true)
  else
    row.arrow:SetHidden(false)
    row.arrow:SetDimensions(16, 16)
  end
  local indent = INDENT[rowType] or 0
  if row.arrowHidden then
    row.icon:SetAnchor(LEFT, row, LEFT, indent, 0)
  else
    row.arrow:SetAnchor(LEFT, row, LEFT, indent, 0)
    row.icon:SetAnchor(LEFT, row.arrow, RIGHT, 4, 0)
  end
  local iconSize = ICON_SIZE[rowType] or 18
  row.icon:SetDimensions(iconSize, iconSize)
  if iconPath and iconPath ~= "" then
    row.icon:SetColor(1, 1, 1, 1)
    row.icon:SetTexture(iconPath)
    row.icon:SetHidden(false)
  else
    row.icon:SetHidden(true)
  end
  if rowType == ROW_TYPES.ZONE or rowType == ROW_TYPES.ACH_ROOT then
    row.label:SetModifyTextType(MODIFY_UPPERCASE)
  else
    row.label:SetModifyTextType(MODIFY_NONE)
  end
  row.label:SetWrapMode(WRAP_ELLIPSIS)
  row.label:SetText(text or "")
end

local function updateFonts(self)
  if not self.activeRows then
    return
  end
  local fonts = self.sv.fonts or {}
  local fontStrings = {
    category = buildFontDescriptor(fonts.category, { face = "ZoFontHeader2", size = 24, effect = "soft-shadow-thin" }),
    quest = buildFontDescriptor(fonts.quest, { face = "ZoFontGameBold", size = 20, effect = "soft-shadow-thin" }),
    task = buildFontDescriptor(fonts.task, { face = "ZoFontGame", size = 18, effect = "soft-shadow-thin" }),
    achieve = buildFontDescriptor(fonts.achieve, { face = "ZoFontGameBold", size = 20, effect = "soft-shadow-thin" }),
    achieveTask = buildFontDescriptor(fonts.achieveTask, { face = "ZoFontGame", size = 18, effect = "soft-shadow-thin" }),
  }
  local colors = {
    category = fonts.category and fonts.category.color or { r = 0.9, g = 0.8, b = 0.6, a = 1 },
    quest = fonts.quest and fonts.quest.color or { r = 1, g = 0.82, b = 0.1, a = 1 },
    task = fonts.task and fonts.task.color or { r = 0.9, g = 0.9, b = 0.9, a = 1 },
    achieve = fonts.achieve and fonts.achieve.color or { r = 1, g = 0.82, b = 0.1, a = 1 },
    achieveTask = fonts.achieveTask and fonts.achieveTask.color or { r = 0.9, g = 0.9, b = 0.9, a = 1 },
  }

  for _, row in ipairs(self.activeRows) do
    local rowType = row.rowType
    local label = row.label
    if rowType == ROW_TYPES.ZONE or rowType == ROW_TYPES.ACH_ROOT then
      label:SetFont(fontStrings.category)
      applyColorToLabel(label, colors.category)
    elseif rowType == ROW_TYPES.QUEST then
      label:SetFont(fontStrings.quest)
      applyColorToLabel(label, colors.quest)
    elseif rowType == ROW_TYPES.QUEST_OBJECTIVE then
      label:SetFont(fontStrings.task)
      applyColorToLabel(label, colors.task)
    elseif rowType == ROW_TYPES.ACHIEVEMENT then
      label:SetFont(fontStrings.achieve)
      applyColorToLabel(label, colors.achieve)
    elseif rowType == ROW_TYPES.ACH_OBJECTIVE then
      label:SetFont(fontStrings.achieveTask)
      applyColorToLabel(label, colors.achieveTask)
    end
  end
end

local function applyAutoDimensions(self)
  if not self.control then
    return
  end
  local contentWidth = 0
  for _, row in ipairs(self.activeRows) do
    local labelWidth = row.label:GetTextWidth() or 0
    local total = labelWidth + INDENT[row.rowType] + (row.arrowHidden and 0 or 20) + 40
    if total > contentWidth then
      contentWidth = total
    end
  end
  contentWidth = contentWidth + PADDING_X * 2
  local contentHeight = self.scrollChild:GetHeight() + PADDING_Y * 2
  local width = math.max(MIN_WIDTH, contentWidth)
  local height = math.max(MIN_HEIGHT, contentHeight)
  if self.sv.behavior.autoGrowH then
    self.control:SetWidth(width)
    self.sv.pos.width = width
  else
    self.control:SetWidth(math.max(MIN_WIDTH, tonumber(self.sv.pos.width) or MIN_WIDTH))
  end
  if self.sv.behavior.autoGrowV then
    self.control:SetHeight(height)
    self.sv.pos.height = height
  else
    self.control:SetHeight(math.max(MIN_HEIGHT, tonumber(self.sv.pos.height) or MIN_HEIGHT))
  end
end

local function addQuestObjectiveRow(self, questEntry, objective, parentRow)
  local row = acquireRow(self)
  row.rowType = ROW_TYPES.QUEST_OBJECTIVE
  row.data = {
    type = ROW_TYPES.QUEST_OBJECTIVE,
    quest = questEntry,
    objective = objective,
  }
  local text = objective.text
  if objective.max and objective.max > 0 then
    text = string.format("%s (%d/%d)", objective.text, objective.current or 0, objective.max)
  end
  text = string.format("• %s", text)
  configureRow(self, row, ROW_TYPES.QUEST_OBJECTIVE, text, DEFAULT_ICONS.objective, false, false)
  appendRow(self, row)
  return row
end

local function addAchievementObjectiveRow(self, achievementEntry, objective)
  local row = acquireRow(self)
  row.rowType = ROW_TYPES.ACH_OBJECTIVE
  row.data = {
    type = ROW_TYPES.ACH_OBJECTIVE,
    achievement = achievementEntry,
    objective = objective,
  }
  local progress = (objective.max and objective.max > 0)
      and string.format("%s (%d/%d)", objective.text, objective.current or 0, objective.max)
      or objective.text
  progress = string.format("• %s", progress)
  configureRow(self, row, ROW_TYPES.ACH_OBJECTIVE, progress, DEFAULT_ICONS.objective, false, false)
  appendRow(self, row)
  return row
end

local function isZoneExpanded(self, zoneKey)
  local state = self.sv.collapseState.zones[zoneKey]
  return state == true
end

local function isQuestExpanded(self, questKey)
  local state = self.sv.collapseState.quests[questKey]
  return state == true
end

local function isAchievementExpanded(self, achievementId)
  if self.sv.behavior.alwaysExpandAchievements then
    return true
  end
  local state = self.sv.collapseState.achieves[tostring(achievementId)]
  return state == true
end

local function setZoneExpanded(self, zoneKey, expanded)
  self.sv.collapseState.zones[zoneKey] = expanded and true or false
end

local function setQuestExpanded(self, questKey, expanded)
  self.sv.collapseState.quests[questKey] = expanded and true or false
end

local function setAchievementExpanded(self, achievementId, expanded)
  self.sv.collapseState.achieves[tostring(achievementId)] = expanded and true or false
end

local function ensureCollapseTables(self)
  local cs = self.sv.collapseState
  cs.zones = cs.zones or {}
  cs.quests = cs.quests or {}
  cs.achieves = cs.achieves or {}
end

function QT:RegisterLamPanel(panelControl)
  self.lamPanelControl = panelControl
  if panelControl and panelControl.IsHidden then
    self.lamPanelOpen = not panelControl:IsHidden()
  end
  ensureLamCallbacks(self)
  self:ApplyVisibility()
end

local function renderQuests(self, zones)
  for _, zoneEntry in ipairs(zones) do
    if zoneEntry.quests and #zoneEntry.quests > 0 then
      local row = acquireRow(self)
      row.rowType = ROW_TYPES.ZONE
      local expanded = isZoneExpanded(self, zoneEntry.key)
      row.data = {
        type = ROW_TYPES.ZONE,
        zone = zoneEntry,
        key = zoneEntry.key,
        expanded = expanded,
      }
      configureRow(self, row, ROW_TYPES.ZONE, zoneEntry.name, zoneEntry.icon, true, expanded)
      appendRow(self, row)
      if expanded then
        for _, questEntry in ipairs(zoneEntry.quests) do
          local questRow = acquireRow(self)
          questRow.rowType = ROW_TYPES.QUEST
          local questExpanded = isQuestExpanded(self, questEntry.key)
          if self.pendingQuestExpand and questEntry.questId and self.pendingQuestExpand[questEntry.questId] then
            questExpanded = true
            setQuestExpanded(self, questEntry.key, true)
            setZoneExpanded(self, zoneEntry.key, true)
            self.pendingQuestExpand[questEntry.questId] = nil
          end
          questRow.zoneName = zoneEntry.name
          questRow.data = {
            type = ROW_TYPES.QUEST,
            quest = questEntry,
            expanded = questExpanded,
          }
          local labelText = questEntry.displayName or questEntry.name
          configureRow(self, questRow, ROW_TYPES.QUEST, labelText, questEntry.icon, true, questExpanded)
          appendRow(self, questRow)
          if questExpanded and questEntry.objectives then
            for _, objective in ipairs(questEntry.objectives) do
              addQuestObjectiveRow(self, questEntry, objective, questRow)
            end
          end
        end
      end
    end
  end
end

local function renderAchievements(self, achievements)
  if not achievements or #achievements == 0 then
    return
  end
  local row = acquireRow(self)
  row.rowType = ROW_TYPES.ACH_ROOT
  local expanded = isZoneExpanded(self, "__achievements__")
  row.data = {
    type = ROW_TYPES.ACH_ROOT,
    key = "__achievements__",
    expanded = expanded,
    achievements = achievements,
  }
  configureRow(self, row, ROW_TYPES.ACH_ROOT, LABELS.achievementsHeader, DEFAULT_ICONS.achievement, true, expanded)
  appendRow(self, row)
  if not expanded then
    return
  end
  for _, achievementEntry in ipairs(achievements) do
    local achRow = acquireRow(self)
    achRow.rowType = ROW_TYPES.ACHIEVEMENT
    local achExpanded = isAchievementExpanded(self, achievementEntry.id)
    achRow.data = {
      type = ROW_TYPES.ACHIEVEMENT,
      achievement = achievementEntry,
      expanded = achExpanded,
    }
    local label = achievementEntry.name
    if achievementEntry.completed then
      label = string.format("%s (%s)", achievementEntry.name, LABELS.achievementComplete)
    end
    configureRow(self, achRow, ROW_TYPES.ACHIEVEMENT, label, achievementEntry.icon, true, achExpanded)
    appendRow(self, achRow)
    if achExpanded and achievementEntry.objectives then
      for _, objective in ipairs(achievementEntry.objectives) do
        addAchievementObjectiveRow(self, achievementEntry, objective)
      end
    end
  end
end

function QT:Refresh(throttled)
  if not self.enabled then
    return
  end
  if throttled then
    if self.refreshQueued then
      return
    end
    self.refreshQueued = true
    local delay = tonumber(self.sv.throttleMs) or 150
    if EM and EM.RegisterForUpdate then
      if EM.UnregisterForUpdate then
        EM:UnregisterForUpdate(REFRESH_HANDLE)
      end
      EM:RegisterForUpdate(REFRESH_HANDLE, delay, function()
        if EM.UnregisterForUpdate then
          EM:UnregisterForUpdate(REFRESH_HANDLE)
        end
        self.refreshQueued = false
        self:Refresh(false)
      end)
    else
      zo_callLater(function()
        self.refreshQueued = false
        self:Refresh(false)
      end, delay)
    end
    return
  end
  self.refreshQueued = false
  if not self.control then
    self:EnsureControl()
  end
  ensureCollapseTables(self)

  local showQuests = self.sv.showQuests ~= false
  local showAchievements = self.sv.showAchievements ~= false
  local zones = showQuests and collectQuests() or {}
  local achievements = showAchievements and collectFavoriteAchievements() or {}

  local zoneCount = zones and #zones or 0
  local questCount, questObjectiveCount = 0, 0
  if zones then
    for _, zoneEntry in ipairs(zones) do
      if zoneEntry.quests then
        questCount = questCount + #zoneEntry.quests
        for _, questEntry in ipairs(zoneEntry.quests) do
          if questEntry.objectives then
            questObjectiveCount = questObjectiveCount + #questEntry.objectives
          end
        end
      end
    end
  end
  local achievementCount = achievements and #achievements or 0
  local achievementObjectiveCount = 0
  if achievements then
    for _, achievementEntry in ipairs(achievements) do
      if achievementEntry.objectives then
        achievementObjectiveCount = achievementObjectiveCount + #achievementEntry.objectives
      end
    end
  end
  debugLog(
    string.format(
      "Refresh collected %d zones, %d quests, %d quest objectives, %d achievements, %d achievement objectives",
      zoneCount,
      questCount,
      questObjectiveCount,
      achievementCount,
      achievementObjectiveCount
    )
  )

  local questsChanged
  if showQuests then
    questsChanged = self:SyncQuestState(zones)
  else
    questsChanged = next(self.questState and self.questState.zones or {}) ~= nil
    self:ClearQuestState()
    zones = {}
  end

  local achievementsChanged
  if showAchievements then
    achievementsChanged = self:SyncAchievementState(achievements)
  else
    achievementsChanged = next(self.achievementState or {}) ~= nil
    self:ClearAchievementState()
    achievements = {}
  end

  local needsRender = self.forceRender or questsChanged or achievementsChanged or not self.renderInitialized

  if needsRender then
    releaseAllRows(self)
    if showQuests then
      renderQuests(self, zones)
    end
    if showAchievements and achievements and #achievements > 0 then
      renderAchievements(self, achievements)
      self.hasAchievements = true
    else
      self.hasAchievements = false
    end
    updateFonts(self)
    applyAutoDimensions(self)
    self.renderInitialized = true
    self.forceRender = false
  else
    if showAchievements and achievements and #achievements > 0 then
      self.hasAchievements = true
    else
      self.hasAchievements = false
    end
  end

  self:ApplyVisibility()
end

function QT:IsSceneAllowed()
  if self.lamPanelOpen then
    return true
  end
  local manager = SCENE_MANAGER
  if manager and manager.IsShowingBaseScene then
    local okBase, isBase = pcall(manager.IsShowingBaseScene, manager)
    if okBase and isBase then
      return true
    end
  end
  if manager and manager.IsShowing then
    local okHud, hud = pcall(manager.IsShowing, manager, "hud")
    if okHud and hud then
      return true
    end
    local okHudUi, hudUi = pcall(manager.IsShowing, manager, "hudui")
    if okHudUi and hudUi then
      return true
    end
  end
  if not manager then
    return true
  end
  return false
end

function QT:ApplyVisibility()
  local behavior = self.sv and self.sv.behavior or {}
  local isEnabled = self.enabled and (self.sv and self.sv.enabled ~= false)
  local sceneAllowed = self:IsSceneAllowed()
  local combatHidden = behavior.hideInCombat and self.isInCombat
  local shouldShow = isEnabled and sceneAllowed and not combatHidden
  if self.fragment and self.fragment.SetHiddenForReason then
    self.fragment:SetHiddenForReason("disabled", not isEnabled, true)
    self.fragment:SetHiddenForReason("scene", not sceneAllowed, true)
    self.fragment:SetHiddenForReason("combat", combatHidden, true)
  end
  if self.control then
    self.control:SetHidden(not shouldShow)
  end
  self:SetDefaultTrackerHidden(behavior.hideDefault)
end

function QT:SetDefaultTrackerHidden(hidden)
  hidden = hidden and true or false
  local names = {
    "ZO_QuestTracker",
    "ZO_QuestTracker_Keyboard",
  }
  for _, name in ipairs(names) do
    local ctl = _G[name]
    if ctl and ctl.SetHidden then
      ctl:SetHidden(hidden)
    end
  end
end

function QT:OnRowLeftClick(control)
  if not control or not control.data then
    return
  end
  local data = control.data
  if data.type == ROW_TYPES.ZONE or data.type == ROW_TYPES.ACH_ROOT then
    local key = data.key
    local expanded = isZoneExpanded(self, key)
    setZoneExpanded(self, key, not expanded)
    self.forceRender = true
    self:Refresh(true)
  elseif data.type == ROW_TYPES.QUEST then
    local quest = data.quest
    local expanded = isQuestExpanded(self, quest.key)
    setQuestExpanded(self, quest.key, not expanded)
    self.forceRender = true
    self:Refresh(true)
  elseif data.type == ROW_TYPES.ACHIEVEMENT then
    local achievement = data.achievement
    local expanded = isAchievementExpanded(self, achievement.id)
    setAchievementExpanded(self, achievement.id, not expanded)
    self.forceRender = true
    self:Refresh(true)
  end
end

local function showQuestContextMenu(entry)
  ClearMenu()
  AddMenuItem(LABELS.questOpenJournal, function()
    if SCENE_MANAGER then
      SCENE_MANAGER:Show("journal")
    end
    if QUEST_JOURNAL_MANAGER and QUEST_JOURNAL_MANAGER.SelectQuestWithJournalIndex then
      QUEST_JOURNAL_MANAGER:SelectQuestWithJournalIndex(entry.journalIndex)
    end
  end)
  AddMenuItem(LABELS.questShare, function()
    if ShareQuest then
      ShareQuest(entry.journalIndex)
    end
  end)
  AddMenuItem(LABELS.questShowOnMap, function()
    if PingMapForQuestIndex then
      PingMapForQuestIndex(entry.journalIndex)
    end
  end)
  AddMenuItem(LABELS.questAbandon, function()
    if ZO_Dialogs_ShowDialog then
      ZO_Dialogs_ShowDialog("CONFIRM_ABANDON_QUEST", { journalIndex = entry.journalIndex }, { mainTextParams = { entry.name } })
    elseif AbandonQuest then
      AbandonQuest(entry.journalIndex)
    end
  end)
  ShowMenu()
end

local function showAchievementContextMenu(entry)
  ClearMenu()
  local openId = entry.displayId or entry.id or entry.favoriteId
  AddMenuItem(LABELS.achievementsOpen, function()
    if SCENE_MANAGER then
      SCENE_MANAGER:Show("achievements")
    end
    if ACHIEVEMENTS and ACHIEVEMENTS.BrowseToAchievement and openId then
      zo_callLater(function()
        ACHIEVEMENTS:BrowseToAchievement(openId)
      end, 50)
    end
    if ACHIEVEMENTS_MANAGER and ACHIEVEMENTS_MANAGER.PushAchievement and openId then
      ACHIEVEMENTS_MANAGER:PushAchievement(openId)
    end
  end)
  AddMenuItem(LABELS.achievementsRemoveFavorite, function()
    if Nvk3UT and Nvk3UT.Favorites and Nvk3UT.Favorites.Remove then
      local removeId = entry.favoriteId or entry.id
      if removeId then
        Nvk3UT.Favorites.Remove(removeId)
      end
    end
    QT.forceRender = true
    QT:Refresh(true)
  end)
  ShowMenu()
end

function QT:OnRowRightClick(control)
  if not control or not control.data then
    return
  end
  local data = control.data
  if data.type == ROW_TYPES.QUEST then
    showQuestContextMenu(data.quest)
  elseif data.type == ROW_TYPES.ACHIEVEMENT then
    showAchievementContextMenu(data.achievement)
  end
end

function QT:OnRowEnter(control)
  if not (control and control.data) then
    return
  end
  if self.sv.behavior.tooltips == false then
    return
  end
  local data = control.data
  if data.type == ROW_TYPES.QUEST then
    questTooltip(control, data.quest, control.zoneName)
  elseif data.type == ROW_TYPES.ACHIEVEMENT then
    achievementTooltip(control, data.achievement)
  else
    clearTooltip()
  end
end

function QT:ApplySettings()
  if not self.control then
    self:EnsureControl()
  end
  self.forceRender = true
  self.renderInitialized = false
  ensureCollapseTables(self)
  if not self.sv.behavior then self.sv.behavior = {} end
  if not self.sv.background then self.sv.background = {} end
  if not self.sv.fonts then self.sv.fonts = {} end
  if not self.sv.pos then self.sv.pos = {} end
  applyScaleAndPosition(self)
  applyLockState(self)
  applyBackground(self)
  self:ApplyVisibility()
  updateFonts(self)
end

local function registerEvents(self)
  if self.eventsRegistered then
    return
  end
  if not EM then
    return
  end
  EM:RegisterForEvent("Nvk3UT_QT_QuestAdded", EVENT_QUEST_ADDED, function(_, journalIndex)
    if self.sv.behavior.autoExpandNewQuests then
      local questId = safeCall(GetJournalQuestId, journalIndex)
      if questId then
        self.pendingQuestExpand = self.pendingQuestExpand or {}
        self.pendingQuestExpand[questId] = true
      end
    end
    self.forceRender = true
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_QuestRemoved", EVENT_QUEST_REMOVED, function(_, isCompleted, journalIndex, questName, zoneName, questId)
    if questId and self.sv.collapseState and self.sv.collapseState.quests then
      for key in pairs(self.sv.collapseState.quests) do
        if key:find(string.format("^%d", questId)) then
          self.sv.collapseState.quests[key] = nil
        end
      end
    end
    self.forceRender = true
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_QuestAdvanced", EVENT_QUEST_ADVANCED, function()
    self.forceRender = true
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_ConditionChanged", EVENT_QUEST_CONDITION_COUNTER_CHANGED, function()
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_QuestListUpdated", EVENT_QUEST_LIST_UPDATED, function()
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_ObjectiveCompleted", EVENT_OBJECTIVE_COMPLETED, function()
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_InterfaceSetting", EVENT_INTERFACE_SETTING_CHANGED, function(_, settingType)
    if settingType == SETTING_TYPE_UI then
      self.forceRender = true
      self:Refresh(true)
    end
  end)
  EM:RegisterForEvent("Nvk3UT_QT_LevelUpdated", EVENT_LEVEL_UPDATE, function(_, unitTag)
    if unitTag == "player" then
      self.forceRender = true
      self:Refresh(true)
    end
  end)
  EM:RegisterForEvent("Nvk3UT_QT_OverrideChanged", EVENT_QUEST_CONDITION_OVERRIDE_TEXT_CHANGED, function()
    self.forceRender = true
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_AchUpdated", EVENT_ACHIEVEMENT_UPDATED, function(_, achievementId)
    removeCompletedFavorite(achievementId)
    self.forceRender = true
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_AchAwarded", EVENT_ACHIEVEMENT_AWARDED, function(_, _, _, achievementId)
    removeCompletedFavorite(achievementId)
    self.forceRender = true
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_AchievementsUpdated", EVENT_ACHIEVEMENTS_UPDATED, function()
    pruneCompletedFavorites()
    self.forceRender = true
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_CombatState", EVENT_PLAYER_COMBAT_STATE, function(_, inCombat)
    self.isInCombat = inCombat
    self:ApplyVisibility()
  end)
  EM:RegisterForEvent("Nvk3UT_QT_PlayerActivated", EVENT_PLAYER_ACTIVATED, function()
    if not self.hasActivated then
      self.hasActivated = true
      pruneCompletedFavorites()
      self:Refresh(false)
      self:ApplyVisibility()
    else
      self:Refresh(true)
    end
  end)
  EM:RegisterForEvent("Nvk3UT_QT_PlayerDeactivated", EVENT_PLAYER_DEACTIVATED, function()
    self.hasActivated = false
    self.forceRender = true
    self:Refresh(true)
  end)
  self.eventsRegistered = true
  if CM and not self.favoritesCallback then
    self.favoritesCallback = function()
      self.forceRender = true
      self:Refresh(true)
    end
    CM:RegisterCallback("NVK3UT_FAVORITES_CHANGED", self.favoritesCallback)
  end
  if QUEST_JOURNAL_MANAGER and not self.questListCallback then
    self.questListCallback = function()
      self.forceRender = true
      self:Refresh(true)
    end
    QUEST_JOURNAL_MANAGER:RegisterCallback("QuestListUpdated", self.questListCallback)
  end
  if SCENE_MANAGER and not self.sceneCallback then
    self.sceneCallback = function(scene, oldState, newState)
      if newState == SCENE_SHOWING or newState == SCENE_SHOWN or newState == SCENE_HIDDEN then
        self:ApplyVisibility()
      end
    end
    SCENE_MANAGER:RegisterCallback("SceneStateChanged", self.sceneCallback)
  end
  if FOCUSED_QUEST_TRACKER then
    if FOCUSED_QUEST_TRACKER.RegisterCallback and not self.focusedQuestCallback then
      self.focusedQuestCallback = function()
        self:Refresh(true)
      end
      FOCUSED_QUEST_TRACKER:RegisterCallback("QuestTrackerAssistStateChanged", self.focusedQuestCallback)
    elseif SecurePostHook and not self.focusedQuestHooked then
      SecurePostHook(FOCUSED_QUEST_TRACKER, "Update", function()
        self:Refresh(true)
      end)
      self.focusedQuestHooked = true
    end
  end
end

local function unregisterEvents(self)
  if not self.eventsRegistered then
    return
  end
  if EM then
    EM:UnregisterForEvent("Nvk3UT_QT_QuestAdded", EVENT_QUEST_ADDED)
    EM:UnregisterForEvent("Nvk3UT_QT_QuestRemoved", EVENT_QUEST_REMOVED)
    EM:UnregisterForEvent("Nvk3UT_QT_QuestAdvanced", EVENT_QUEST_ADVANCED)
    EM:UnregisterForEvent("Nvk3UT_QT_ConditionChanged", EVENT_QUEST_CONDITION_COUNTER_CHANGED)
    EM:UnregisterForEvent("Nvk3UT_QT_QuestListUpdated", EVENT_QUEST_LIST_UPDATED)
    EM:UnregisterForEvent("Nvk3UT_QT_ObjectiveCompleted", EVENT_OBJECTIVE_COMPLETED)
    EM:UnregisterForEvent("Nvk3UT_QT_InterfaceSetting", EVENT_INTERFACE_SETTING_CHANGED)
    EM:UnregisterForEvent("Nvk3UT_QT_LevelUpdated", EVENT_LEVEL_UPDATE)
    EM:UnregisterForEvent("Nvk3UT_QT_OverrideChanged", EVENT_QUEST_CONDITION_OVERRIDE_TEXT_CHANGED)
    EM:UnregisterForEvent("Nvk3UT_QT_AchUpdated", EVENT_ACHIEVEMENT_UPDATED)
    EM:UnregisterForEvent("Nvk3UT_QT_AchAwarded", EVENT_ACHIEVEMENT_AWARDED)
    EM:UnregisterForEvent("Nvk3UT_QT_AchievementsUpdated", EVENT_ACHIEVEMENTS_UPDATED)
    EM:UnregisterForEvent("Nvk3UT_QT_CombatState", EVENT_PLAYER_COMBAT_STATE)
    EM:UnregisterForEvent("Nvk3UT_QT_PlayerActivated", EVENT_PLAYER_ACTIVATED)
    EM:UnregisterForEvent("Nvk3UT_QT_PlayerDeactivated", EVENT_PLAYER_DEACTIVATED)
  end
  if CM and self.favoritesCallback then
    CM:UnregisterCallback("NVK3UT_FAVORITES_CHANGED", self.favoritesCallback)
    self.favoritesCallback = nil
  end
  if QUEST_JOURNAL_MANAGER and self.questListCallback then
    QUEST_JOURNAL_MANAGER:UnregisterCallback("QuestListUpdated", self.questListCallback)
    self.questListCallback = nil
  end
  if SCENE_MANAGER and self.sceneCallback then
    SCENE_MANAGER:UnregisterCallback("SceneStateChanged", self.sceneCallback)
    self.sceneCallback = nil
  end
  if FOCUSED_QUEST_TRACKER and self.focusedQuestCallback and FOCUSED_QUEST_TRACKER.UnregisterCallback then
    FOCUSED_QUEST_TRACKER:UnregisterCallback("QuestTrackerAssistStateChanged", self.focusedQuestCallback)
    self.focusedQuestCallback = nil
  end
  self.eventsRegistered = false
end

function QT.Init()
  QT.sv = Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.tracker or {}
  ensureCollapseTables(QT)
  QT.sv.behavior = QT.sv.behavior or {}
  QT.sv.background = QT.sv.background or {}
  QT.sv.fonts = QT.sv.fonts or {}
  QT.sv.pos = QT.sv.pos or {}
  QT.refreshQueued = false
  QT.enabled = false
  QT.pendingQuestExpand = {}
  QT.lamPanelOpen = QT.lamPanelOpen or false
  QT.hasActivated = false
  QT.questState = QT.questState or { zones = {}, order = {} }
  QT.achievementState = QT.achievementState or {}
  QT.renderInitialized = false
  QT.forceRender = true
  if QT.lamPanelControl then
    ensureLamCallbacks(QT)
  end
end

function QT.Enable()
  if QT.enabled then
    return
  end
  QT.sv = Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.tracker or QT.sv or {}
  if QT.sv.enabled == false then
    QT:ApplyVisibility()
    return
  end
  QT:EnsureControl()
  QT:ApplySettings()
  ensureLamCallbacks(QT)
  registerEvents(QT)
  QT.enabled = true
  QT:Refresh(false)
end

function QT.Disable()
  if not QT.enabled then
    return
  end
  unregisterEvents(QT)
  QT.enabled = false
  QT.pendingQuestExpand = {}
  QT:ClearQuestState()
  QT:ClearAchievementState()
  QT.renderInitialized = false
  QT.forceRender = true
  QT.refreshQueued = false
  if EM and EM.UnregisterForUpdate then
    EM:UnregisterForUpdate(REFRESH_HANDLE)
  end
  if QT.control then
    QT.control:SetHidden(true)
  end
  QT:SetDefaultTrackerHidden(false)
  QT.hasAchievements = false
end

function QT.Destroy()
  QT:Disable()
  if QT.fragment and QT.sceneFragments and SCENE_MANAGER then
    for sceneName in pairs(QT.sceneFragments) do
      local scene = SCENE_MANAGER:GetScene(sceneName)
      if scene and scene.RemoveFragment then
        scene:RemoveFragment(QT.fragment)
      end
      QT.sceneFragments[sceneName] = nil
    end
  end
  QT.sceneFragments = nil
  QT.fragment = nil
  if CALLBACK_MANAGER then
    if QT.lamPanelOpenedCallback then
      CALLBACK_MANAGER:UnregisterCallback("LAM-PanelOpened", QT.lamPanelOpenedCallback)
      QT.lamPanelOpenedCallback = nil
    end
    if QT.lamPanelClosedCallback then
      CALLBACK_MANAGER:UnregisterCallback("LAM-PanelClosed", QT.lamPanelClosedCallback)
      QT.lamPanelClosedCallback = nil
    end
  end
  QT.lamCallbacksRegistered = false
  QT.lamPanelControl = nil
  QT.lamPanelOpen = false
  if QT.control then
    QT.control:SetHidden(true)
    QT.control = nil
  end
  QT.backdrop = nil
  QT.scroll = nil
  QT.scrollChild = nil
  QT.rowPool = nil
  QT.activeRows = nil
  QT.questListCallback = nil
  QT.focusedQuestCallback = nil
  QT:ClearQuestState()
  QT:ClearAchievementState()
  QT.hasAchievements = false
end

function QT.SetEnabled(value)
  QT.sv = QT.sv or {}
  QT.sv.enabled = value and true or false
  if not QT.sv.enabled then
    QT:Disable()
  else
    QT:Enable()
  end
end

function QT.SetShowQuests(value)
  QT.sv = QT.sv or {}
  QT.sv.showQuests = value and true or false
  QT.forceRender = true
  QT.renderInitialized = false
  QT:Refresh(true)
end

function QT.SetShowAchievements(value)
  QT.sv = QT.sv or {}
  QT.sv.showAchievements = value and true or false
  QT.forceRender = true
  QT.renderInitialized = false
  QT:Refresh(true)
end

function QT.SetBehaviorOption(key, value)
  QT.sv = QT.sv or {}
  QT.sv.behavior = QT.sv.behavior or {}
  QT.sv.behavior[key] = value
  if key == "hideDefault" then
    QT:ApplyVisibility()
    QT:SetDefaultTrackerHidden(QT.sv.behavior.hideDefault)
  elseif key == "hideInCombat" then
    QT:ApplyVisibility()
  elseif key == "locked" then
    applyLockState(QT)
    applyBackground(QT)
  elseif key == "autoGrowV" or key == "autoGrowH" then
    QT.forceRender = true
    QT:Refresh(true)
  elseif key == "alwaysExpandAchievements" then
    QT.forceRender = true
    QT:Refresh(true)
  elseif key == "tooltips" then
    clearTooltip()
  end
end

function QT.SetThrottle(value)
  QT.sv = QT.sv or {}
  local numeric = tonumber(value) or QT.sv.throttleMs or 150
  local clamped = math.max(0, round(numeric))
  QT.sv.throttleMs = clamped
  if QT.enabled then
    QT.refreshQueued = false
    if EM and EM.UnregisterForUpdate then
      EM:UnregisterForUpdate(REFRESH_HANDLE)
    end
    QT:Refresh(true)
  end
end

function QT.SetBackgroundOption(key, value)
  QT.sv = QT.sv or {}
  QT.sv.background = QT.sv.background or {}
  QT.sv.background[key] = value
  applyBackground(QT)
  if key == "hideWhenLocked" or key == "enabled" then
    QT:ApplyVisibility()
  end
end

function QT.SetFontOption(section, field, value)
  QT.sv = QT.sv or {}
  local fonts = QT.sv.fonts or {}
  fonts[section] = fonts[section] or {}
  fonts[section][field] = value
  QT.sv.fonts = fonts
  updateFonts(QT)
  QT:Refresh(true)
end

function QT.SetFontColor(section, r, g, b, a)
  QT.sv = QT.sv or {}
  local fonts = QT.sv.fonts or {}
  fonts[section] = fonts[section] or {}
  fonts[section].color = { r = r, g = g, b = b, a = a }
  QT.sv.fonts = fonts
  updateFonts(QT)
  QT:Refresh(true)
end

function QT.SetScale(scale)
  QT.sv = QT.sv or {}
  QT.sv.pos.scale = scale
  QT:EnsureControl()
  applyScaleAndPosition(QT)
end

return QT
