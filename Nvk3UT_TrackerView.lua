Nvk3UT = Nvk3UT or {}
local M = Nvk3UT

M.TrackerView = M.TrackerView or {}
local Module = M.TrackerView

local WM = WINDOW_MANAGER
local EM = EVENT_MANAGER
local GuiRoot = GuiRoot

local ROW_TYPES = {
    QUEST_TITLE = 1,
    QUEST_STEP = 2,
    DIVIDER = 3,
    ACHIEVEMENT = 4,
}

local REFRESH_HANDLE = "Nvk3UT_TrackerViewRefresh"
local DEFAULT_REFRESH_DELAY_MS = 100

local QUEST_ROW_HEIGHT = 32
local QUEST_STEP_ROW_HEIGHT = 24
local DIVIDER_ROW_HEIGHT = 2
local ACHIEVEMENT_ROW_HEIGHT = 32

local MIN_WIDTH = 260
local MIN_HEIGHT = 220
local PADDING_X = 12
local PADDING_Y = 12
local TRACKER_SCENES = { "hud", "hudui" }

local LEFT_BUTTON = (_G and _G.MOUSE_BUTTON_INDEX_LEFT) or MOUSE_BUTTON_INDEX_LEFT or 1

local CARET_TEXTURE_OPEN = "EsoUI/Art/Buttons/tree_open_up.dds"
local CARET_TEXTURE_CLOSED = "EsoUI/Art/Buttons/tree_closed_up.dds"

local DEFAULT_TRACKER_REASON = "Nvk3UT_TrackerView"
local DEFAULT_TRACKER_FRAGMENTS = {
    "FOCUSED_QUEST_TRACKER_FRAGMENT",
    "FOCUSED_QUEST_TRACKER_ALWAYS_SHOW_FRAGMENT",
    "FOCUSED_QUEST_TRACKER_TRACKED_FRAGMENT",
    "FOCUSED_QUEST_TRACKER_FOCUSED_FRAGMENT",
    "GAMEPAD_QUEST_TRACKER_FRAGMENT",
}

local COMBAT_EVENT_NAMESPACE = "Nvk3UT_TrackerViewCombat"

Module.isInCombat = Module.isInCombat == true

local DEFAULT_FONTS = {
    quest = { face = "ZoFontGameBold", size = 20, effect = "soft-shadow-thin" },
    task = { face = "ZoFontGame", size = 18, effect = "soft-shadow-thin" },
    achieve = { face = "ZoFontGameBold", size = 20, effect = "soft-shadow-thin" },
    achieveTask = { face = "ZoFontGame", size = 18, effect = "soft-shadow-thin" },
}

local DEFAULT_COLORS = {
    quest = { r = 1, g = 0.82, b = 0.1, a = 1 },
    task = { r = 0.9, g = 0.9, b = 0.9, a = 1 },
    achieve = { r = 1, g = 0.82, b = 0.1, a = 1 },
    achieveTask = { r = 0.9, g = 0.9, b = 0.9, a = 1 },
}

local function debugLog(message)
    if d then
        d(string.format("[Nvk3UT] TrackerView: %s", tostring(message)))
    end
end

local function getTrackerSV()
    local sv = M and M.sv and M.sv.tracker
    if not sv then
        return nil
    end

    sv.collapseState = sv.collapseState or {}
    sv.collapseState.quests = sv.collapseState.quests or {}
    sv.collapseState.achieves = sv.collapseState.achieves or {}

    return sv
end

local function buildFontString(config, defaults)
    local face = defaults.face
    if config and type(config.face) == "string" and config.face ~= "" then
        face = config.face
    end

    local size = tonumber(defaults.size) or 18
    if config and tonumber(config.size) then
        size = tonumber(config.size)
    end

    local effect = defaults.effect or "none"
    if config and type(config.effect) == "string" and config.effect ~= "" then
        effect = config.effect
    end

    return string.format("%s|%d|%s", face, size, effect)
end

local function resolveColor(config, defaults)
    local source = defaults
    if config and type(config.color) == "table" then
        source = config.color
    end
    local r = tonumber(source.r) or defaults.r or 1
    local g = tonumber(source.g) or defaults.g or 1
    local b = tonumber(source.b) or defaults.b or 1
    local a = tonumber(source.a) or defaults.a or 1
    return r, g, b, a
end

local function applyFontAndColor(label, section)
    if not label or not section then
        return
    end

    local sv = getTrackerSV()
    local fonts = (sv and sv.fonts) or {}
    local config = fonts[section]
    local defaults = DEFAULT_FONTS[section] or DEFAULT_FONTS.task
    local fontString = buildFontString(config, defaults)
    label:SetFont(fontString)

    local defaultColor = DEFAULT_COLORS[section] or DEFAULT_COLORS.task
    local r, g, b, a = resolveColor(config, defaultColor)
    label:SetColor(r, g, b, a)
end

local function areTooltipsEnabled()
    local sv = getTrackerSV()
    if not sv then
        return true
    end
    local behavior = sv.behavior
    if behavior and behavior.tooltips ~= nil then
        return behavior.tooltips
    end
    return true
end

local function isTrackerEnabled()
    local sv = getTrackerSV()
    if not sv then
        return true
    end
    if sv.enabled == nil then
        return true
    end
    return sv.enabled
end

local function shouldShowQuests()
    local sv = getTrackerSV()
    if not sv then
        return true
    end
    if sv.showQuests == nil then
        return true
    end
    return sv.showQuests
end

local function shouldShowAchievements()
    local sv = getTrackerSV()
    if not sv then
        return true
    end
    if sv.showAchievements == nil then
        return true
    end
    return sv.showAchievements
end

local function getThrottleDelay()
    local sv = getTrackerSV()
    if not sv then
        return DEFAULT_REFRESH_DELAY_MS
    end
    return tonumber(sv.throttleMs) or DEFAULT_REFRESH_DELAY_MS
end

local function isQuestCollapsed(questKey)
    local sv = getTrackerSV()
    if not sv or not questKey then
        return false
    end
    return sv.collapseState.quests[questKey] == true
end

local function setQuestCollapsed(questKey, collapsed)
    local sv = getTrackerSV()
    if not sv or not questKey then
        return
    end
    if collapsed then
        sv.collapseState.quests[questKey] = true
    else
        sv.collapseState.quests[questKey] = nil
    end
end

local function isAchievementCollapsed(achievementId)
    local sv = getTrackerSV()
    if not sv or not achievementId then
        return false
    end
    return sv.collapseState.achieves[achievementId] == true
end

local function setAchievementCollapsed(achievementId, collapsed)
    local sv = getTrackerSV()
    if not sv or not achievementId then
        return
    end
    if collapsed then
        sv.collapseState.achieves[achievementId] = true
    else
        sv.collapseState.achieves[achievementId] = nil
    end
end

local function formatProgressValue(current, maximum)
    local maxValue = tonumber(maximum) or 0
    if maxValue <= 0 then
        return ""
    end
    local currentValue = tonumber(current) or 0
    if currentValue > maxValue then
        currentValue = maxValue
    elseif currentValue < 0 then
        currentValue = 0
    end
    return string.format("%d/%d", currentValue, maxValue)
end

local function calculateQuestProgress(quest)
    if not quest or not quest.objectives then
        return ""
    end
    local totalCurrent = 0
    local totalMax = 0
    for _, objective in ipairs(quest.objectives) do
        local maxValue = tonumber(objective.max) or 0
        if maxValue > 0 then
            local currentValue = tonumber(objective.current) or 0
            if currentValue > maxValue then
                currentValue = maxValue
            elseif currentValue < 0 then
                currentValue = 0
            end
            totalCurrent = totalCurrent + currentValue
            totalMax = totalMax + maxValue
        end
    end
    if totalMax > 0 then
        return string.format("%d/%d", totalCurrent, totalMax)
    end
    return ""
end

local function shouldHideDefaultTracker()
    local sv = getTrackerSV()
    local behavior = sv and sv.behavior
    return behavior and behavior.hideDefault == true
end

local function shouldHideInCombat()
    local sv = getTrackerSV()
    local behavior = sv and sv.behavior
    return behavior and behavior.hideInCombat == true
end

local function applyDefaultTrackerVisibility()
    local hidden = shouldHideDefaultTracker()
    for _, fragmentName in ipairs(DEFAULT_TRACKER_FRAGMENTS) do
        local fragment = _G and _G[fragmentName]
        if fragment and fragment.SetHiddenForReason then
            fragment:SetHiddenForReason(DEFAULT_TRACKER_REASON, hidden)
        end
    end

    local focusedTracker = _G and _G.FOCUSED_QUEST_TRACKER
    if focusedTracker then
        if focusedTracker.SetHiddenForReason then
            focusedTracker.SetHiddenForReason(DEFAULT_TRACKER_REASON, hidden)
        elseif focusedTracker.SetHidden then
            focusedTracker:SetHidden(hidden)
        end
        local control = focusedTracker.control
        if control and control.SetHidden then
            control:SetHidden(hidden)
        end
    end
end

local function shouldHideTracker()
    if not isTrackerEnabled() then
        return true
    end
    if shouldHideInCombat() and Module.isInCombat then
        return true
    end
    return false
end

local function applyRootHiddenState()
    if not Module.rootControl then
        return
    end
    Module.rootControl:SetHidden(shouldHideTracker())
end

local function applyLockState()
    if not Module.rootControl then
        return
    end
    local sv = getTrackerSV()
    local behavior = sv and sv.behavior or {}
    local locked = behavior.locked == true
    Module.rootControl:SetMovable(not locked)
    Module.rootControl:SetResizeHandleSize(locked and 0 or 8)
end

local function applyScaleAndPosition()
    if not Module.rootControl then
        return
    end
    local sv = getTrackerSV()
    local pos = sv and sv.pos or {}
    local scale = tonumber(pos.scale) or 1
    Module.rootControl:SetScale(scale)

    local x = tonumber(pos.x) or 400
    local y = tonumber(pos.y) or 200
    Module.rootControl:ClearAnchors()
    Module.rootControl:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, x, y)

    local width = math.max(MIN_WIDTH, tonumber(pos.width) or MIN_WIDTH)
    local height = math.max(MIN_HEIGHT, tonumber(pos.height) or MIN_HEIGHT)
    Module.rootControl:SetDimensions(width, height)
end

local function applyBackground()
    if not (Module.backdrop and Module.rootControl) then
        return
    end
    local sv = getTrackerSV()
    local background = sv and sv.background or {}
    local behavior = sv and sv.behavior or {}

    if not background.enabled or (background.hideWhenLocked and behavior.locked) then
        Module.backdrop:SetHidden(true)
        return
    end

    local alpha = tonumber(background.alpha) or 60
    local normalized = math.max(0, math.min(100, alpha)) / 100
    Module.backdrop:SetCenterColor(0, 0, 0, normalized)
    if background.border then
        Module.backdrop:SetEdgeTexture(nil, 1, 1, 1, 1)
        Module.backdrop:SetEdgeColor(1, 1, 1, normalized)
    else
        Module.backdrop:SetEdgeTexture(nil, 1, 1, 0, 0)
        Module.backdrop:SetEdgeColor(0, 0, 0, 0)
    end
    Module.backdrop:SetHidden(false)
end

local function saveDimensions()
    if not Module.rootControl then
        return
    end
    local sv = getTrackerSV()
    if not sv then
        return
    end
    sv.pos = sv.pos or {}
    local behavior = sv.behavior or {}
    if behavior.autoGrowV then
        return
    end
    sv.pos.width = math.max(MIN_WIDTH, Module.rootControl:GetWidth())
    sv.pos.height = math.max(MIN_HEIGHT, Module.rootControl:GetHeight())
end

local function applyAutoSize()
    if not (Module.rootControl and Module.scrollList) then
        return
    end

    local sv = getTrackerSV()
    if not sv then
        return
    end

    local behavior = sv.behavior or {}
    if not behavior.autoGrowH and not behavior.autoGrowV then
        return
    end

    local pos = sv.pos or {}
    local scrollControl = ZO_ScrollList_GetScrollControl(Module.scrollList)
    local contentWidth = scrollControl and scrollControl:GetWidth() or Module.rootControl:GetWidth()
    local contentHeight = scrollControl and scrollControl:GetHeight() or Module.rootControl:GetHeight()

    local width = math.max(MIN_WIDTH, tonumber(pos.width) or MIN_WIDTH)
    local height = math.max(MIN_HEIGHT, tonumber(pos.height) or MIN_HEIGHT)

    if behavior.autoGrowH then
        width = math.max(MIN_WIDTH, contentWidth + (PADDING_X * 2))
        pos.width = width
    end

    if behavior.autoGrowV then
        height = math.max(MIN_HEIGHT, contentHeight + (PADDING_Y * 2))
        pos.height = height
    end

    Module.rootControl:SetDimensions(width, height)
end

local function onCombatState(_, inCombat)
    Module.isInCombat = inCombat == true
    applyRootHiddenState()
end

local function anchorTooltip()
    if not areTooltipsEnabled() then
        return false
    end
    if not InformationTooltip or not Module.rootControl then
        return false
    end

    InitializeTooltip(InformationTooltip, Module.rootControl, LEFT, -16, 0, RIGHT)
    return true
end

local function showQuestTooltip(control)
    if not control or not control.data or not anchorTooltip() then
        return
    end

    local quest = control.data.quest
    if not quest then
        return
    end

    InformationTooltip:ClearLines()
    InformationTooltip:AddLine(quest.title or "", "ZoFontGameBold")
    if quest.zoneName and quest.zoneName ~= "" then
        InformationTooltip:AddLine(quest.zoneName, "ZoFontGame")
    end
    if quest.stepText and quest.stepText ~= "" then
        InformationTooltip:AddLine(quest.stepText, "ZoFontGame")
    end
end

local function showQuestStepTooltip(control)
    if not control or not control.data or not anchorTooltip() then
        return
    end

    local quest = control.data.quest
    local objective = control.data.objective
    if not quest or not objective then
        return
    end

    InformationTooltip:ClearLines()
    InformationTooltip:AddLine(quest.title or "", "ZoFontGameBold")
    local text = objective.text or ""
    if text ~= "" then
        if objective.max and objective.max > 0 then
            text = string.format("%s (%d/%d)", text, objective.current or 0, objective.max)
        end
        InformationTooltip:AddLine(text, "ZoFontGame")
    end
end

local function showAchievementTooltip(control)
    if not control or not control.data or not anchorTooltip() then
        return
    end

    local achievement = control.data.achievement
    if not achievement then
        return
    end

    InformationTooltip:ClearLines()
    InformationTooltip:AddLine(achievement.name or "", "ZoFontGameBold")
    if achievement.progress and achievement.progress.max and achievement.progress.max > 0 then
        local progress = achievement.progress
        local text = string.format("%d / %d", progress.cur or 0, progress.max)
        InformationTooltip:AddLine(text, "ZoFontGame")
    end
end

local function hideTooltip()
    if InformationTooltip then
        ClearTooltip(InformationTooltip)
    end
end

local function toggleQuestCollapsedFor(control)
    if not control or not control.data then
        return
    end

    local questKey = control.data.questKey
    if not questKey then
        return
    end

    local quest = control.data.quest
    local newCollapsed = not (quest and quest.isCollapsed == true)
    setQuestCollapsed(questKey, newCollapsed)
    if quest then
        quest.isCollapsed = newCollapsed
    end
    control.data.collapsed = newCollapsed
    Module.MarkDirty()
end

local function setupQuestTitleRow(control, data)
    control.data = data
    local label = control.label
    if not label then
        label = control:GetNamedChild("Label")
        if not label then
            label = WM:CreateControl(nil, control, CT_LABEL)
            label:SetFont("ZoFontGameBold")
            label:SetAnchorFill(control)
            label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
            label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        end
        control.label = label
    end

    local caret = control.caret
    if not caret then
        caret = control:GetNamedChild("Caret")
        if not caret then
            caret = WM:CreateControl(nil, control, CT_TEXTURE)
            caret:SetDimensions(18, 18)
            caret:SetAnchor(LEFT, control, LEFT, 6, 0)
        end
        caret:SetMouseEnabled(true)
        caret:SetHandler("OnMouseEnter", function()
            showQuestTooltip(control)
        end)
        caret:SetHandler("OnMouseExit", hideTooltip)
        caret:SetHandler("OnMouseUp", function(_, button, upInside)
            if not upInside or button ~= LEFT_BUTTON then
                return
            end
            toggleQuestCollapsedFor(control)
        end)
        control.caret = caret
    end

    local progressLabel = control.progress
    if not progressLabel then
        progressLabel = control:GetNamedChild("Progress")
        if not progressLabel then
            progressLabel = WM:CreateControl(nil, control, CT_LABEL)
            progressLabel:SetFont("ZoFontGame")
            progressLabel:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
            progressLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
            progressLabel:SetAnchor(RIGHT, control, RIGHT, -8, 0)
        end
        control.progress = progressLabel
    end

    if not control.handlersRegistered then
        control:SetMouseEnabled(true)
        control:SetHandler("OnMouseEnter", showQuestTooltip)
        control:SetHandler("OnMouseExit", hideTooltip)
        control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
            if not upInside or button ~= LEFT_BUTTON then
                return
            end
            toggleQuestCollapsedFor(ctrl)
        end)
        control.handlersRegistered = true
    end

    local quest = data.quest
    local collapsed = data.collapsed == true
    if quest then
        quest.isCollapsed = collapsed
    end
    if caret then
        caret:SetTexture(collapsed and CARET_TEXTURE_CLOSED or CARET_TEXTURE_OPEN)
    end

    if label then
        label:ClearAnchors()
        label:SetAnchor(TOPLEFT, caret or control, caret and RIGHT or LEFT, caret and 8 or 24, 0)
        if progressLabel then
            label:SetAnchor(BOTTOMRIGHT, progressLabel, BOTTOMLEFT, -8, 0)
        else
            label:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, -8, 0)
        end
    end

    local text = quest and (quest.displayName or quest.title) or ""
    if quest and quest.stepText and quest.stepText ~= "" then
        text = string.format("%s — %s", text, quest.stepText)
    end
    label:SetText(text)
    applyFontAndColor(label, "quest")
    if progressLabel then
        progressLabel:SetText(calculateQuestProgress(quest))
        applyFontAndColor(progressLabel, "task")
    end
end

local function resetRow(control)
    control.data = nil
    if control.label then
        control.label:SetText("")
    end
    if control.progress then
        control.progress:SetText("")
    end
end

local function setupQuestStepRow(control, data)
    control.data = data
    local label = control.label
    if not label then
        label = control:GetNamedChild("Label")
        if not label then
            label = WM:CreateControl(nil, control, CT_LABEL)
            label:SetFont("ZoFontGame")
            label:SetAnchorFill(control)
            label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
            label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        end
        control.label = label
        control:SetMouseEnabled(true)
        control:SetHandler("OnMouseEnter", showQuestStepTooltip)
        control:SetHandler("OnMouseExit", hideTooltip)
    end

    local indentLevel = data.depth or 0
    if indentLevel < 0 then
        indentLevel = 0
    end
    local indent = indentLevel * 20
    local progressLabel = control.progress
    if not progressLabel then
        progressLabel = control:GetNamedChild("Progress")
        if not progressLabel then
            progressLabel = WM:CreateControl(nil, control, CT_LABEL)
            progressLabel:SetFont("ZoFontGame")
            progressLabel:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
            progressLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
            progressLabel:SetAnchor(RIGHT, control, RIGHT, -8, 0)
        end
        control.progress = progressLabel
    end

    label:ClearAnchors()
    label:SetAnchor(TOPLEFT, control, TOPLEFT, 24 + indent, 0)
    if progressLabel then
        label:SetAnchor(BOTTOMRIGHT, progressLabel, BOTTOMLEFT, -8, 0)
    else
        label:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, -8, 0)
    end

    local text = ""
    local objective = data.objective
    local progressText = ""
    if objective then
        text = objective.text or ""
        progressText = formatProgressValue(objective.current, objective.max)
        if text ~= "" then
            text = string.format("• %s", text)
        end
    elseif data.text and data.text ~= "" then
        text = string.format("• %s", data.text)
    end

    label:SetText(text)
    applyFontAndColor(label, "task")
    if progressLabel then
        progressLabel:SetText(progressText or "")
        applyFontAndColor(progressLabel, "task")
    end
end

local function setupDividerRow(control, data)
    control.data = data
    if not control.line then
        control.line = control:GetNamedChild("Line")
        if control.line then
            control.line:SetColor(1, 1, 1, 0.1)
        end
    end
end

local function setupAchievementRow(control, data)
    control.data = data
    local label = control.label
    if not label then
        label = control:GetNamedChild("Label")
        if not label then
            label = WM:CreateControl(nil, control, CT_LABEL)
            label:SetFont("ZoFontGameBold")
            label:SetAnchorFill(control)
            label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
            label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        end
        control.label = label
        control:SetMouseEnabled(true)
        control:SetHandler("OnMouseEnter", showAchievementTooltip)
        control:SetHandler("OnMouseExit", hideTooltip)
    end

    local progressLabel = control.progress
    if not progressLabel then
        progressLabel = control:GetNamedChild("Progress")
        if not progressLabel then
            progressLabel = WM:CreateControl(nil, control, CT_LABEL)
            progressLabel:SetFont("ZoFontGame")
            progressLabel:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
            progressLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
            progressLabel:SetAnchor(RIGHT, control, RIGHT, -8, 0)
        end
        control.progress = progressLabel
    end

    local achievement = data.achievement
    local name = achievement and achievement.name or ""
    local progressText = ""
    if achievement and achievement.progress then
        progressText = formatProgressValue(achievement.progress.cur, achievement.progress.max)
    end
    label:SetText(name)
    applyFontAndColor(label, "achieve")
    if progressLabel then
        progressLabel:SetText(progressText or "")
        applyFontAndColor(progressLabel, "achieveTask")
    end
end

local function registerDataTypes()
    if not Module.scrollList then
        return
    end

    ZO_ScrollList_AddDataType(
        Module.scrollList,
        ROW_TYPES.QUEST_TITLE,
        "Nvk3UT_RowQuestTitleTemplate",
        QUEST_ROW_HEIGHT,
        setupQuestTitleRow,
        nil,
        nil,
        nil,
        resetRow
    )

    ZO_ScrollList_AddDataType(
        Module.scrollList,
        ROW_TYPES.QUEST_STEP,
        "Nvk3UT_RowQuestStepTemplate",
        QUEST_STEP_ROW_HEIGHT,
        setupQuestStepRow,
        nil,
        nil,
        nil,
        resetRow
    )

    ZO_ScrollList_AddDataType(
        Module.scrollList,
        ROW_TYPES.DIVIDER,
        "Nvk3UT_RowDividerTemplate",
        DIVIDER_ROW_HEIGHT,
        setupDividerRow
    )

    ZO_ScrollList_AddDataType(
        Module.scrollList,
        ROW_TYPES.ACHIEVEMENT,
        "Nvk3UT_RowAchievementTemplate",
        ACHIEVEMENT_ROW_HEIGHT,
        setupAchievementRow,
        nil,
        nil,
        nil,
        resetRow
    )
end

local function acquireFeedEntry(feed, dataType, payload)
    local entry = payload
    entry.dataType = dataType
    feed[#feed + 1] = entry
end

local function appendQuestRows(feed)
    if not shouldShowQuests() then
        return
    end

    if not M.QuestModel or not M.QuestModel.GetList then
        return
    end

    local order, byId = M.QuestModel.GetList()
    for _, questKey in ipairs(order) do
        local quest = byId[questKey]
        if quest then
            local collapsed = quest.isCollapsed
            if collapsed == nil then
                collapsed = isQuestCollapsed(quest.key or questKey)
            end
            quest.isCollapsed = collapsed == true
            acquireFeedEntry(feed, ROW_TYPES.QUEST_TITLE, {
                questKey = quest.key or questKey,
                quest = quest,
                collapsed = quest.isCollapsed,
            })

            if not quest.isCollapsed then
                local objectives = quest.objectives or {}
                if #objectives == 0 then
                    local steps = quest.steps or {}
                    for _, step in ipairs(steps) do
                        if step.text and step.text ~= "" then
                            acquireFeedEntry(feed, ROW_TYPES.QUEST_STEP, {
                                questKey = quest.key or questKey,
                                quest = quest,
                                text = step.text,
                                depth = 0,
                            })
                        end
                    end
                else
                    for _, objective in ipairs(objectives) do
                        acquireFeedEntry(feed, ROW_TYPES.QUEST_STEP, {
                            questKey = quest.key or questKey,
                            quest = quest,
                            objective = objective,
                            depth = objective.depth or 1,
                        })
                    end
                end
            end
        end
    end
end

local function appendAchievementRows(feed)
    if not shouldShowAchievements() then
        return
    end

    if not M.AchievementModel or not M.AchievementModel.GetList then
        return
    end

    local list = select(1, M.AchievementModel.GetList())
    if not list or #list == 0 then
        return
    end

    if #feed > 0 then
        acquireFeedEntry(feed, ROW_TYPES.DIVIDER, {})
    end

    for _, achievement in ipairs(list) do
        acquireFeedEntry(feed, ROW_TYPES.ACHIEVEMENT, {
            achievementId = achievement.id,
            achievement = achievement,
            collapsed = isAchievementCollapsed(achievement.id),
        })
    end
end

local function buildFeed()
    local feed = {}
    appendQuestRows(feed)
    appendAchievementRows(feed)
    return feed
end

local function commitFeed(feed)
    if not Module.scrollList then
        return
    end

    local dataList = ZO_ScrollList_GetDataList(Module.scrollList)
    ZO_ClearNumericallyIndexedTable(dataList)

    for index = 1, #feed do
        local entry = feed[index]
        dataList[#dataList + 1] = ZO_ScrollList_CreateDataEntry(entry.dataType, entry)
    end

    ZO_ScrollList_Commit(Module.scrollList)
    applyAutoSize()
end

local function refreshNow()
    Module.refreshPending = false
    if EM and EM.UnregisterForUpdate then
        EM:UnregisterForUpdate(REFRESH_HANDLE)
    end

    if not Module.initialized then
        return
    end

    if isTrackerEnabled() then
        local feed = buildFeed()
        commitFeed(feed)
    end

    applyRootHiddenState()
end

local function scheduleRefresh()
    if Module.refreshPending then
        return
    end

    Module.refreshPending = true
    local delay = getThrottleDelay()

    if EM and EM.RegisterForUpdate then
        EM:RegisterForUpdate(REFRESH_HANDLE, delay, refreshNow)
    else
        zo_callLater(refreshNow, delay)
    end
end

local function onQuestsChanged()
    Module.MarkDirty()
end

local function onAchievementsChanged()
    Module.MarkDirty()
end

local function onSettingsChanged(_)
    applyDefaultTrackerVisibility()
    Module.ApplySettingsFromSV()
    Module.MarkDirty()
end

local function createTrackerControls()
    if Module.rootControl then
        return
    end

    local root = WM:CreateTopLevelWindow("Nvk3UT_TrackerRoot")
    root:SetClampedToScreen(true)
    root:SetMouseEnabled(true)
    root:SetMovable(true)
    root:SetResizeHandleSize(8)
    root:SetHidden(true)

    local trackerSV = getTrackerSV() or {}
    local pos = trackerSV.pos or {}
    local width = pos.width or 320
    local height = pos.height or 360
    local x = pos.x or 400
    local y = pos.y or 200

    root:SetDimensions(width, height)
    root:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, x, y)

    root:SetHandler("OnMoveStop", function()
        local sv = getTrackerSV()
        if not sv or not root then
            return
        end
        sv.pos = sv.pos or {}
        local posTable = sv.pos
        posTable.x = root:GetLeft()
        posTable.y = root:GetTop()
    end)

    root:SetHandler("OnResizeStop", function()
        saveDimensions()
    end)
    root:SetHandler("OnHide", function()
        hideTooltip()
    end)

    local backdrop = WM:CreateControl(nil, root, CT_BACKDROP)
    backdrop:SetAnchorFill(root)
    backdrop:SetHidden(true)

    local list = WM:CreateControlFromVirtual("Nvk3UT_TrackerList", root, "ZO_ScrollList")
    list:ClearAnchors()
    list:SetAnchor(TOPLEFT, root, TOPLEFT, PADDING_X, PADDING_Y)
    list:SetAnchor(BOTTOMRIGHT, root, BOTTOMRIGHT, -PADDING_X, -PADDING_Y)

    Module.rootControl = root
    Module.backdrop = backdrop
    Module.scrollList = list

    registerDataTypes()

    if SCENE_MANAGER then
        Module.sceneFragments = Module.sceneFragments or {}
        if not Module.fragment then
            local fragmentClass = ZO_HUDFadeSceneFragment or ZO_SimpleSceneFragment
            if fragmentClass then
                Module.fragment = fragmentClass:New(root)
                if Module.fragment.SetHideOnSceneHidden then
                    Module.fragment:SetHideOnSceneHidden(true)
                end
            end
        end

        if Module.fragment then
            for _, sceneName in ipairs(TRACKER_SCENES) do
                if not Module.sceneFragments[sceneName] then
                    local scene = SCENE_MANAGER:GetScene(sceneName)
                    if scene and scene.AddFragment then
                        scene:AddFragment(Module.fragment)
                        Module.sceneFragments[sceneName] = true
                    end
                end
            end
        end
    end
end

function Module.MarkDirty()
    scheduleRefresh()
end

function Module.Init()
    if Module.initialized then
        return
    end

    createTrackerControls()

    if EM and EM.RegisterForEvent then
        EM:RegisterForEvent(COMBAT_EVENT_NAMESPACE, EVENT_PLAYER_COMBAT_STATE, onCombatState)
    end

    if type(IsUnitInCombat) == "function" then
        local okCombat, inCombat = pcall(IsUnitInCombat, "player")
        if okCombat then
            Module.isInCombat = inCombat == true
        else
            Module.isInCombat = false
        end
    else
        Module.isInCombat = false
    end

    if M.Subscribe then
        M.Subscribe("quests:changed", onQuestsChanged)
        M.Subscribe("ach:changed", onAchievementsChanged)
        M.Subscribe("settings:changed", onSettingsChanged)
    elseif M.Core and M.Core.Subscribe then
        M.Core.Subscribe("quests:changed", onQuestsChanged)
        M.Core.Subscribe("ach:changed", onAchievementsChanged)
        M.Core.Subscribe("settings:changed", onSettingsChanged)
    end

    applyDefaultTrackerVisibility()
    Module.ApplySettingsFromSV()

    Module.initialized = true
    Module.MarkDirty()

    if M and M.Tracker and M.Tracker.NotifyViewReady then
        M.Tracker.NotifyViewReady()
    end
end

function Module.ApplyDefaultTrackerVisibility()
    applyDefaultTrackerVisibility()
end

function Module.ApplySettingsFromSV()
    applyScaleAndPosition()
    applyLockState()
    applyBackground()
    applyRootHiddenState()
    applyAutoSize()
end

function Module.ApplyLockState()
    applyLockState()
end

function Module.ApplyBackground()
    applyBackground()
end

function Module.ApplyScaleFromSettings()
    applyScaleAndPosition()
end

function Module.ForceRefresh()
    refreshNow()
end

return
