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

local DEFAULT_ICONS = {
  zone = "EsoUI/Art/Journal/journal_tabIcon_locations_up.dds",
  quest = "EsoUI/Art/Journal/journal_tabIcon_quests_up.dds",
  achievement = "EsoUI/Art/Journal/journal_tabIcon_achievements_up.dds",
  objective = "EsoUI/Art/Journal/journal_tabIcon_achievements_up.dds",
}

local ARROW_TEXTURE_COLLAPSED = "EsoUI/Art/Miscellaneous/listSort_up.dds"
local ARROW_TEXTURE_EXPANDED = "EsoUI/Art/Miscellaneous/listSort_down.dds"
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

local function isQuestTracked(questIndex)
  if type(GetIsJournalQuestTracked) == "function" then
    local ok, tracked = pcall(GetIsJournalQuestTracked, questIndex)
    if ok then
      return tracked
    end
  end
  if type(IsJournalQuestStepTracked) == "function" and type(GetJournalQuestNumSteps) == "function" then
    local steps = GetJournalQuestNumSteps(questIndex)
    for stepIndex = 1, steps do
      if IsJournalQuestStepTracked(questIndex, stepIndex) then
        return true
      end
    end
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
  local steps = GetJournalQuestNumSteps(questIndex)
  local seenSteps = {}
  for stepIndex = 1, steps do
    local stepText, visibility, stepType, trackerComplete, _, _, stepOverride = GetJournalQuestStepInfo(questIndex, stepIndex)
    local summary = stepOverride ~= "" and stepOverride or stepText or ""
    summary = sanitizeText(summary)
    if not trackerComplete and summary ~= "" and not seenSteps[summary] then
      stepSummaries[#stepSummaries + 1] = summary
      seenSteps[summary] = true
    end
    if not trackerComplete then
      local numConditions = GetJournalQuestNumConditions(questIndex, stepIndex) or 0
      for conditionIndex = 1, numConditions do
        local conditionText, cur, max, isFail, isComplete = GetJournalQuestConditionInfo(questIndex, stepIndex, conditionIndex)
        if conditionText ~= "" and not isFail and not isComplete then
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
  return objectives, stepSummaries
end

local function collectQuests()
  local results = {}
  local order = {}
  if type(GetNumJournalQuests) ~= "function" then
    return order
  end
  local zonesByKey = {}
  local questCount = GetNumJournalQuests()
  for journalIndex = 1, questCount do
    if isQuestTracked(journalIndex) then
      local questName = sanitizeText(GetJournalQuestName(journalIndex))
      local questId = safeCall(GetJournalQuestId, journalIndex) or 0
      local zoneName = sanitizeText(GetJournalQuestZoneName(journalIndex))
      local zoneId = safeCall(GetJournalQuestZoneId, journalIndex)
      local zoneKey = zoneId and string.format("%d", zoneId) or zoneName
      if zoneKey == nil or zoneKey == "" then
        zoneKey = zoneName ~= "" and zoneName or "unknown"
      end
      local zoneEntry = zonesByKey[zoneKey]
      if not zoneEntry then
        zoneEntry = {
          key = zoneKey,
          name = zoneName ~= "" and zoneName or LABELS.generalZone,
          icon = DEFAULT_ICONS.zone,
          quests = {},
        }
        zonesByKey[zoneKey] = zoneEntry
        order[#order + 1] = zoneEntry
      end
      local objectives, stepSummaries = gatherQuestObjectives(journalIndex)
      local stepText = stepSummaries[1] or ""
      local questEntry = {
        type = ROW_TYPES.QUEST,
        name = questName,
        questId = questId,
        journalIndex = journalIndex,
        zoneKey = zoneKey,
        objectives = objectives,
        steps = stepSummaries,
        stepText = stepText,
        key = questStepKey(journalIndex, questId),
        icon = DEFAULT_ICONS.quest,
      }
      zoneEntry.quests[#zoneEntry.quests + 1] = questEntry
    end
  end
  table.sort(order, function(a, b)
    return a.name < b.name
  end)
  for _, zoneEntry in ipairs(order) do
    table.sort(zoneEntry.quests, function(a, b)
      return a.name < b.name
    end)
  end
  return order
end

local function getFavoriteScope()
  local sv = Nvk3UT and Nvk3UT.sv
  return (sv and sv.ui and sv.ui.favScope) or "account"
end

local function collectFavoriteAchievements()
  local favorites = {}
  local Fav = Nvk3UT and Nvk3UT.FavoritesData
  if not Fav or not Fav.Iterate then
    return favorites
  end
  local scope = getFavoriteScope()
  local seen = {}
  local playerGender
  if type(GetUnitGender) == "function" then
    local okGender, gender = pcall(GetUnitGender, "player")
    if okGender then
      playerGender = gender
    end
  end
  for achievementId, flagged in Fav.Iterate(scope) do
    if flagged and type(achievementId) == "number" and achievementId ~= 0 and not seen[achievementId] then
      seen[achievementId] = true
      local okInfo, name, description, points, iconPath, completed = pcall(GetAchievementInfo, achievementId)
      if not okInfo then
        name, description, iconPath, completed = "", "", "", false
      end
      if playerGender and type(zo_strformat) == "function" and name and name ~= "" then
        local okFormat, formatted = pcall(zo_strformat, name, playerGender)
        if okFormat and formatted and formatted ~= "" then
          name = formatted
        end
      end
      local objectives = {}
      local totalCurrent, totalRequired = 0, 0
      local numCriteria = GetAchievementNumCriteria and GetAchievementNumCriteria(achievementId) or 0
      for criterionIndex = 1, numCriteria do
        local okCrit, criterionDescription, numCompleted, numRequired = pcall(GetAchievementCriterion, achievementId, criterionIndex)
        if okCrit and criterionDescription ~= "" and numCompleted < numRequired then
          objectives[#objectives + 1] = {
            text = sanitizeText(criterionDescription),
            current = numCompleted,
            max = numRequired,
          }
        end
        if okCrit then
          totalCurrent = totalCurrent + (numCompleted or 0)
          totalRequired = totalRequired + (numRequired or 0)
        end
      end
      local normalizedIcon = iconPath
      if Utils and Utils.ResolveTexturePath then
        normalizedIcon = Utils.ResolveTexturePath(iconPath)
      end
      local cleanedName = sanitizeText(name)
      local lowerName
      if cleanedName and cleanedName ~= "" then
        if type(zo_strlower) == "function" then
          lowerName = zo_strlower(cleanedName)
        else
          lowerName = string.lower(cleanedName)
        end
      else
        lowerName = ""
      end
      favorites[#favorites + 1] = {
        id = achievementId,
        name = cleanedName,
        description = sanitizeText(description),
        icon = normalizedIcon ~= "" and normalizedIcon or DEFAULT_ICONS.achievement,
        objectives = objectives,
        completed = completed,
        sortKey = lowerName,
        progressCurrent = totalCurrent,
        progressMax = totalRequired,
      }
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
  row.data = nil
  row.zoneName = nil
  row.questName = nil
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
    if button == MOUSE_BUTTON_INDEX_LEFT then
      QT:OnRowLeftClick(control)
    elseif button == MOUSE_BUTTON_INDEX_RIGHT then
      QT:OnRowRightClick(control)
    end
  end)
  row:SetHandler("OnMouseEnter", function(control)
    QT:OnRowEnter(control)
  end)
  row:SetHandler("OnMouseExit", function(control)
    clearTooltip()
  end)

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

  return row
end

local function configureRow(self, row, rowType, text, iconPath, isCollapsible, expanded)
  local height = ROW_HEIGHT[rowType] or 24
  row:SetHeight(height)
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
    row.icon:SetTexture(iconPath)
    row.icon:SetHidden(false)
  else
    row.icon:SetHidden(true)
  end
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
  configureRow(self, row, ROW_TYPES.QUEST_OBJECTIVE, text, DEFAULT_ICONS.objective, false, false)
  self.activeRows[#self.activeRows + 1] = row
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
  configureRow(self, row, ROW_TYPES.ACH_OBJECTIVE, progress, DEFAULT_ICONS.objective, false, false)
  self.activeRows[#self.activeRows + 1] = row
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

local function renderQuests(self, zones)
  for _, zoneEntry in ipairs(zones) do
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
    self.activeRows[#self.activeRows + 1] = row
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
        configureRow(self, questRow, ROW_TYPES.QUEST, questEntry.name, questEntry.icon, true, questExpanded)
        self.activeRows[#self.activeRows + 1] = questRow
        if questExpanded and questEntry.objectives then
          for _, objective in ipairs(questEntry.objectives) do
            addQuestObjectiveRow(self, questEntry, objective, questRow)
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
  self.activeRows[#self.activeRows + 1] = row
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
    self.activeRows[#self.activeRows + 1] = achRow
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
    if self.pendingRefresh then
      return
    end
    self.pendingRefresh = true
    local delay = tonumber(self.sv.throttleMs) or 150
    zo_callLater(function()
      self.pendingRefresh = false
      self:Refresh(false)
    end, delay)
    return
  end
  if not self.control then
    self:EnsureControl()
  end
  ensureCollapseTables(self)
  releaseAllRows(self)
  local zones = {}
  if self.sv.showQuests ~= false then
    zones = collectQuests()
  end
  local achievements = nil
  if self.sv.showAchievements ~= false then
    achievements = collectFavoriteAchievements()
  end
  renderQuests(self, zones)
  if achievements and #achievements > 0 then
    renderAchievements(self, achievements)
    self.hasAchievements = true
  else
    self.hasAchievements = false
  end
  updateFonts(self)
  applyAutoDimensions(self)
  self:ApplyVisibility()
end

function QT:ApplyVisibility()
  if not self.control then
    return
  end
  local shouldShow = self.enabled and (self.sv.enabled ~= false)
  if shouldShow and self.sv.behavior.hideInCombat and self.isInCombat then
    shouldShow = false
  end
  self.control:SetHidden(not shouldShow)
  self:SetDefaultTrackerHidden(self.sv.behavior.hideDefault)
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
    self:Refresh(true)
  elseif data.type == ROW_TYPES.QUEST then
    local quest = data.quest
    local expanded = isQuestExpanded(self, quest.key)
    setQuestExpanded(self, quest.key, not expanded)
    self:Refresh(true)
  elseif data.type == ROW_TYPES.ACHIEVEMENT then
    local achievement = data.achievement
    local expanded = isAchievementExpanded(self, achievement.id)
    setAchievementExpanded(self, achievement.id, not expanded)
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
    AddMenuItem(LABELS.achievementsOpen, function()
      if SCENE_MANAGER then
        SCENE_MANAGER:Show("achievements")
      end
      if ACHIEVEMENTS and ACHIEVEMENTS.BrowseToAchievement then
        zo_callLater(function()
          ACHIEVEMENTS:BrowseToAchievement(entry.id)
        end, 50)
      end
      if ACHIEVEMENTS_MANAGER and ACHIEVEMENTS_MANAGER.PushAchievement then
        ACHIEVEMENTS_MANAGER:PushAchievement(entry.id)
      end
    end)
  AddMenuItem(LABELS.achievementsRemoveFavorite, function()
    if Nvk3UT and Nvk3UT.Favorites and Nvk3UT.Favorites.Remove then
      Nvk3UT.Favorites.Remove(entry.id)
    end
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
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_QuestAdvanced", EVENT_QUEST_ADVANCED, function()
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_ConditionChanged", EVENT_QUEST_CONDITION_COUNTER_CHANGED, function()
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_ObjectiveCompleted", EVENT_OBJECTIVE_COMPLETED, function()
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_AchUpdated", EVENT_ACHIEVEMENT_UPDATED, function()
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_AchAwarded", EVENT_ACHIEVEMENT_AWARDED, function()
    self:Refresh(true)
  end)
  EM:RegisterForEvent("Nvk3UT_QT_CombatState", EVENT_PLAYER_COMBAT_STATE, function(_, inCombat)
    self.isInCombat = inCombat
    self:ApplyVisibility()
  end)
  self.eventsRegistered = true
  if CM and not self.favoritesCallback then
    self.favoritesCallback = function()
      self:Refresh(true)
    end
    CM:RegisterCallback("NVK3UT_FAVORITES_CHANGED", self.favoritesCallback)
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
    EM:UnregisterForEvent("Nvk3UT_QT_ObjectiveCompleted", EVENT_OBJECTIVE_COMPLETED)
    EM:UnregisterForEvent("Nvk3UT_QT_AchUpdated", EVENT_ACHIEVEMENT_UPDATED)
    EM:UnregisterForEvent("Nvk3UT_QT_AchAwarded", EVENT_ACHIEVEMENT_AWARDED)
    EM:UnregisterForEvent("Nvk3UT_QT_CombatState", EVENT_PLAYER_COMBAT_STATE)
  end
  if CM and self.favoritesCallback then
    CM:UnregisterCallback("NVK3UT_FAVORITES_CHANGED", self.favoritesCallback)
    self.favoritesCallback = nil
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
  QT.pendingRefresh = false
  QT.enabled = false
  QT.pendingQuestExpand = {}
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
  if QT.control then
    QT.control:SetHidden(true)
  end
  QT:SetDefaultTrackerHidden(false)
end

function QT.Destroy()
  QT:Disable()
  if QT.control then
    QT.control:SetHidden(true)
    QT.control = nil
  end
  QT.backdrop = nil
  QT.scroll = nil
  QT.scrollChild = nil
  QT.rowPool = nil
  QT.activeRows = nil
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
  QT:Refresh(true)
end

function QT.SetShowAchievements(value)
  QT.sv = QT.sv or {}
  QT.sv.showAchievements = value and true or false
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
    QT:Refresh(true)
  elseif key == "alwaysExpandAchievements" then
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
    QT.pendingRefresh = false
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
