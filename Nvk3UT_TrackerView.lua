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

local LEFT_BUTTON = (_G and _G.MOUSE_BUTTON_INDEX_LEFT) or MOUSE_BUTTON_INDEX_LEFT or 1
local RIGHT_BUTTON = (_G and _G.MOUSE_BUTTON_INDEX_RIGHT) or MOUSE_BUTTON_INDEX_RIGHT or 2

local CARET_TEXTURE_OPEN = "EsoUI/Art/Buttons/tree_open_up.dds"
local CARET_TEXTURE_CLOSED = "EsoUI/Art/Buttons/tree_closed_up.dds"

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

local function openQuestContextMenu(control)
    if type(ClearMenu) ~= "function" or type(AddMenuItem) ~= "function" or type(ShowMenu) ~= "function" then
        return
    end

    local data = control and control.data
    local quest = data and data.quest
    local questKey = data and data.questKey
    if not quest or not questKey then
        return
    end

    ClearMenu()

    local isTracked = quest.isTracked ~= false
    local toggleLabel = isTracked and "Remove from tracker" or "Track in tracker"

    AddMenuItem(
        toggleLabel,
        function()
            if M.QuestModel and M.QuestModel.SetTracked then
                M.QuestModel.SetTracked(questKey, not isTracked)
            end
        end
    )

    ShowMenu(control)
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

    if not control.handlersRegistered then
        control:SetMouseEnabled(true)
        control:SetHandler("OnMouseEnter", showQuestTooltip)
        control:SetHandler("OnMouseExit", hideTooltip)
        control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
            if not upInside or button ~= RIGHT_BUTTON then
                return
            end
            openQuestContextMenu(ctrl)
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

    local text = quest and (quest.displayName or quest.title) or ""
    if quest and quest.stepText and quest.stepText ~= "" then
        text = string.format("%s — %s", text, quest.stepText)
    end
    label:SetText(text)
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
    label:ClearAnchors()
    label:SetAnchor(TOPLEFT, control, TOPLEFT, 24 + indent, 0)
    label:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, -8, 0)

    local text = ""
    local objective = data.objective
    if objective then
        text = objective.text or ""
        if text ~= "" and objective.max and objective.max > 0 then
            text = string.format("• %s (%d/%d)", text, objective.current or 0, objective.max)
        elseif text ~= "" then
            text = string.format("• %s", text)
        end
    elseif data.text and data.text ~= "" then
        text = string.format("• %s", data.text)
    end

    label:SetText(text)
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

    local achievement = data.achievement
    local name = achievement and achievement.name or ""
    if achievement and achievement.progress and achievement.progress.max and achievement.progress.max > 0 then
        name = string.format("%s (%d/%d)", name, achievement.progress.cur or 0, achievement.progress.max)
    end
    label:SetText(name)
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
end

local function refreshNow()
    Module.refreshPending = false
    if EM and EM.UnregisterForUpdate then
        EM:UnregisterForUpdate(REFRESH_HANDLE)
    end

    if not Module.initialized then
        return
    end

    if not isTrackerEnabled() then
        if Module.rootControl then
            Module.rootControl:SetHidden(true)
        end
        return
    end

    local feed = buildFeed()
    commitFeed(feed)

    if Module.rootControl then
        Module.rootControl:SetHidden(false)
    end
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

local function onSettingsChanged()
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
    root:SetResizeHandleSize(0)
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
        local sv = getTrackerSV()
        if not sv or not root then
            return
        end
        sv.pos = sv.pos or {}
        local posTable = sv.pos
        posTable.width = root:GetWidth()
        posTable.height = root:GetHeight()
    end)

    local list = WM:CreateControlFromVirtual("Nvk3UT_TrackerList", root, "ZO_ScrollList")
    list:SetAnchorFill(root)

    Module.rootControl = root
    Module.scrollList = list

    registerDataTypes()
end

function Module.MarkDirty()
    scheduleRefresh()
end

function Module.Init()
    if Module.initialized then
        return
    end

    createTrackerControls()

    if M.Subscribe then
        M.Subscribe("quests:changed", onQuestsChanged)
        M.Subscribe("ach:changed", onAchievementsChanged)
        M.Subscribe("settings:changed", onSettingsChanged)
    elseif M.Core and M.Core.Subscribe then
        M.Core.Subscribe("quests:changed", onQuestsChanged)
        M.Core.Subscribe("ach:changed", onAchievementsChanged)
        M.Core.Subscribe("settings:changed", onSettingsChanged)
    end

    Module.initialized = true
    Module.MarkDirty()
end

function Module.ForceRefresh()
    refreshNow()
end

return
