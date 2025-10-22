Nvk3UT = Nvk3UT or {}
local M = Nvk3UT

M.TrackerView = M.TrackerView or {}
local Module = M.TrackerView

M.QuestSection = M.QuestSection or {}
local QuestSection = M.QuestSection

M.AchSection = M.AchSection or {}
local AchSection = M.AchSection

local WM = WINDOW_MANAGER
local EM = EVENT_MANAGER
local GuiRoot = GuiRoot
local SCENE_MANAGER = SCENE_MANAGER

local LIST_CONTROL_NAME = "Nvk3UT_TrackerList"
local ROOT_CONTROL_NAME = "Nvk3UT_TrackerRoot"
local REFRESH_HANDLE = "Nvk3UT_TrackerViewRefresh"
local DEFAULT_REFRESH_DELAY_MS = 100
local DIVIDER_DATA_TYPE = 9000
local DIVIDER_ROW_HEIGHT = 2
local MIN_WIDTH = 260
local MIN_HEIGHT = 220
local PADDING_X = 12
local PADDING_Y = 12
local TRACKER_SCENES = { "hud", "hudui" }
local LEFT_BUTTON = (_G and _G.MOUSE_BUTTON_INDEX_LEFT) or MOUSE_BUTTON_INDEX_LEFT or 1

local CARET_TEXTURE_OPEN = "EsoUI/Art/Buttons/tree_open_up.dds"
local CARET_TEXTURE_CLOSED = "EsoUI/Art/Buttons/tree_closed_up.dds"

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
    local root = M and M.sv and M.sv.tracker
    if not root then
        return nil
    end

    root.behavior = root.behavior or {}
    root.background = root.background or {}
    root.fonts = root.fonts or {}
    root.pos = root.pos or {}
    root.collapseState = root.collapseState or { zones = {}, quests = {}, achieves = {} }

    return root
end

local function getSettingsNamespace(key)
    local sv = M and M.sv and M.sv.settings
    if not sv then
        return nil
    end
    sv[key] = sv[key] or {}
    return sv[key]
end

local function getQuestSettings()
    return getSettingsNamespace("quest") or {}
end

local function getAchievementSettings()
    return getSettingsNamespace("ach") or {}
end

local function getTrackerSettings()
    return getSettingsNamespace("tracker") or {}
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

local function beginTooltip()
    local questSettings = getQuestSettings()
    local achSettings = getAchievementSettings()
    if Module.activeTooltipNamespace == "quest" and questSettings.tooltips == false then
        return false
    end
    if Module.activeTooltipNamespace == "ach" and achSettings.tooltips == false then
        return false
    end
    if not Module.rootControl or not InformationTooltip then
        return false
    end
    InitializeTooltip(InformationTooltip, Module.rootControl, LEFT, -16, 0, RIGHT)
    InformationTooltip:ClearLines()
    return true
end

function Module.ShowTooltip(namespace, buildFn)
    Module.activeTooltipNamespace = namespace
    if not beginTooltip() then
        Module.activeTooltipNamespace = nil
        return
    end
    if type(buildFn) == "function" then
        buildFn(InformationTooltip)
    end
end

function Module.HideTooltip()
    Module.activeTooltipNamespace = nil
    if InformationTooltip then
        ClearTooltip(InformationTooltip)
    end
end

local function shouldHideInCombat()
    local trackerSettings = getTrackerSettings()
    if trackerSettings and trackerSettings.hideInCombat then
        local tracker = M and M.Tracker
        if tracker and tracker.IsCombatHidden then
            return tracker.IsCombatHidden()
        end
    end
    return false
end

local function savePosition()
    if not Module.rootControl then
        return
    end
    local sv = getTrackerSV()
    if not sv then
        return
    end

    local pos = sv.pos
    pos.x = math.floor(Module.rootControl:GetLeft())
    pos.y = math.floor(Module.rootControl:GetTop())
end

local function saveDimensions()
    if not Module.rootControl then
        return
    end
    local sv = getTrackerSV()
    if not sv then
        return
    end

    local behavior = (sv.behavior or {})
    if behavior.autoGrowV then
        return
    end

    sv.pos.width = math.max(MIN_WIDTH, Module.rootControl:GetWidth())
    sv.pos.height = math.max(MIN_HEIGHT, Module.rootControl:GetHeight())
end

local function applyLockState()
    if not Module.rootControl then
        return
    end
    local trackerSettings = getTrackerSettings()
    local locked = trackerSettings and trackerSettings.locked == true
    Module.rootControl:SetMovable(not locked)
    Module.rootControl:SetMouseEnabled(true)
    Module.rootControl:SetResizeHandleSize(locked and 0 or 8)
end

local function applyScaleAndPosition()
    if not Module.rootControl then
        return
    end
    local sv = getTrackerSV()
    if not sv then
        return
    end

    local pos = sv.pos or {}
    Module.rootControl:SetScale(tonumber(pos.scale) or 1)
    Module.rootControl:ClearAnchors()
    Module.rootControl:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, tonumber(pos.x) or 400, tonumber(pos.y) or 200)

    local width = math.max(MIN_WIDTH, tonumber(pos.width) or MIN_WIDTH)
    local height = math.max(MIN_HEIGHT, tonumber(pos.height) or MIN_HEIGHT)
    Module.rootControl:SetDimensions(width, height)
end

local function applyBackground()
    if not Module.backdrop then
        return
    end

    local sv = getTrackerSV()
    local background = sv and sv.background or {}
    local trackerSettings = getTrackerSettings() or {}

    if not background.enabled or (background.hideWhenLocked and trackerSettings.locked) then
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

local function applyAutoSize()
    if not Module.scrollList or not Module.rootControl then
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

    local scrollControl = ZO_ScrollList_GetScrollControl(Module.scrollList)
    local contentWidth = scrollControl and scrollControl:GetWidth() or Module.rootControl:GetWidth()
    local contentHeight = scrollControl and scrollControl:GetHeight() or Module.rootControl:GetHeight()

    local width = math.max(MIN_WIDTH, tonumber(sv.pos.width) or MIN_WIDTH)
    local height = math.max(MIN_HEIGHT, tonumber(sv.pos.height) or MIN_HEIGHT)

    if behavior.autoGrowH then
        width = math.max(MIN_WIDTH, contentWidth + (PADDING_X * 2))
        sv.pos.width = width
    end

    if behavior.autoGrowV then
        height = math.max(MIN_HEIGHT, contentHeight + (PADDING_Y * 2))
        sv.pos.height = height
    end

    Module.rootControl:SetDimensions(width, height)
end

local function shouldHideTracker()
    local tracker = M and M.Tracker
    if tracker and tracker.ShouldHideTracker then
        return tracker.ShouldHideTracker()
    end
    if shouldHideInCombat() then
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

local function getQuestCollapseTable()
    local sv = getTrackerSV()
    if not sv then
        return {}
    end
    sv.collapseState = sv.collapseState or {}
    sv.collapseState.quests = sv.collapseState.quests or {}
    return sv.collapseState.quests
end

local function scheduleRefresh()
    if Module.refreshPending then
        return
    end

    Module.refreshPending = true
    local delay = DEFAULT_REFRESH_DELAY_MS
    local sv = getTrackerSV()
    if sv and sv.throttleMs then
        delay = tonumber(sv.throttleMs) or delay
    end

    if EM and EM.RegisterForUpdate then
        EM:RegisterForUpdate(REFRESH_HANDLE, delay, function()
            if EM.UnregisterForUpdate then
                EM:UnregisterForUpdate(REFRESH_HANDLE)
            end
            Module.RefreshNow()
        end)
    else
        zo_callLater(Module.RefreshNow, delay)
    end
end

local function registerDividerDataType()
    if not Module.scrollList then
        return
    end

    ZO_ScrollList_AddDataType(
        Module.scrollList,
        DIVIDER_DATA_TYPE,
        "Nvk3UT_RowDividerTemplate",
        DIVIDER_ROW_HEIGHT,
        function(control)
            if not control.line then
                control.line = control:GetNamedChild("Line")
                if control.line then
                    control.line:SetColor(1, 1, 1, 0.1)
                end
            end
        end
    )
end

---------------------------------------------------------------------
-- Quest Section
---------------------------------------------------------------------

QuestSection.dataTypes = {
    TITLE = 9101,
    STEP = 9102,
}

function QuestSection:Init(listControl)
    self.listControl = listControl
    self.dirty = true
    self.knownKeys = {}
    self.subscriptions = {}

    local subscribe = M.Subscribe or (M.Core and M.Core.Subscribe)
    if subscribe then
        local questsChanged = subscribe("quests:changed", function()
            self:HandleEvent("quests:changed")
        end)
        table.insert(self.subscriptions, { topic = "quests:changed", fn = questsChanged })

        local settingsChanged = subscribe("settings:changed", function(key)
            self:OnSettingsChanged(key)
        end)
        table.insert(self.subscriptions, { topic = "settings:changed", fn = settingsChanged })
    end
end

function QuestSection:RegisterRowTypes(listControl)
    ZO_ScrollList_AddDataType(
        listControl,
        self.dataTypes.TITLE,
        "Nvk3UT_RowQuestTitleTemplate",
        32,
        function(control, data)
            self:SetupQuestTitleRow(control, data)
        end,
        nil,
        nil,
        nil,
        function(control)
            control.data = nil
            Module.HideTooltip()
        end
    )

    ZO_ScrollList_AddDataType(
        listControl,
        self.dataTypes.STEP,
        "Nvk3UT_RowQuestStepTemplate",
        24,
        function(control, data)
            self:SetupQuestStepRow(control, data)
        end,
        nil,
        nil,
        nil,
        function(control)
            control.data = nil
            Module.HideTooltip()
        end
    )
end

function QuestSection:OnSettingsChanged(key)
    if type(key) ~= "string" then
        return
    end
    if not key:match("^quest%.") then
        return
    end
    self.dirty = true
    Module.MarkDirty()
end

function QuestSection:HandleEvent(topic)
    if topic ~= "quests:changed" then
        return
    end
    self.dirty = true

    local order, byId = M.QuestModel and M.QuestModel.GetList and M.QuestModel.GetList()
    if type(order) ~= "table" or type(byId) ~= "table" then
        Module.MarkDirty()
        return
    end

    local known = self.knownKeys or {}
    local collapse = getQuestCollapseTable()
    local settings = getQuestSettings()
    local autoExpand = settings.autoExpandNew == true

    local newKeys = {}
    for _, questKey in ipairs(order) do
        newKeys[questKey] = true
        if autoExpand and not known[questKey] then
            collapse[questKey] = nil
        end
    end

    for key in pairs(known) do
        if not newKeys[key] then
            known[key] = nil
        end
    end

    for key in pairs(newKeys) do
        known[key] = true
    end

    Module.MarkDirty()
end

function QuestSection:IsVisible()
    local settings = getQuestSettings()
    if settings.enabled == false then
        return false
    end

    if shouldHideInCombat() then
        return false
    end

    return true
end

function QuestSection:IsDirty()
    return self.dirty == true
end

function QuestSection:ClearDirty()
    self.dirty = false
end

function QuestSection:GetCollapseLookup()
    return getQuestCollapseTable()
end

function QuestSection:BuildFeed()
    local feed = {}
    if not self:IsVisible() then
        return feed
    end

    local order, byId = M.QuestModel and M.QuestModel.GetList and M.QuestModel.GetList()
    if type(order) ~= "table" or type(byId) ~= "table" then
        return feed
    end

    local collapse = self:GetCollapseLookup()

    for _, questKey in ipairs(order) do
        local quest = byId[questKey]
        if quest then
            local isCollapsed = collapse[questKey] == true
            feed[#feed + 1] = {
                dataType = self.dataTypes.TITLE,
                questKey = questKey,
                quest = quest,
                collapsed = isCollapsed,
            }

            if not isCollapsed then
                local objectives = quest.objectives or {}
                if #objectives > 0 then
                    for _, objective in ipairs(objectives) do
                        feed[#feed + 1] = {
                            dataType = self.dataTypes.STEP,
                            questKey = questKey,
                            quest = quest,
                            objective = objective,
                        }
                    end
                else
                    local steps = quest.steps or {}
                    for _, step in ipairs(steps) do
                        if step.text and step.text ~= "" then
                            feed[#feed + 1] = {
                                dataType = self.dataTypes.STEP,
                                questKey = questKey,
                                quest = quest,
                                text = step.text,
                            }
                        end
                    end
                end
            end
        end
    end

    return feed
end

function QuestSection:ToggleCollapsed(questKey)
    if not questKey then
        return
    end
    local collapse = self:GetCollapseLookup()
    local current = collapse[questKey] == true
    if current then
        collapse[questKey] = nil
    else
        collapse[questKey] = true
    end
    self.dirty = true
    Module.MarkDirty()
end

local function questProgressText(quest)
    if not quest or not quest.objectives then
        return ""
    end
    local totalCurrent = 0
    local totalMax = 0
    for _, objective in ipairs(quest.objectives) do
        local maxValue = tonumber(objective.max) or 0
        if maxValue > 0 then
            local currentValue = tonumber(objective.current) or 0
            currentValue = math.max(0, math.min(maxValue, currentValue))
            totalCurrent = totalCurrent + currentValue
            totalMax = totalMax + maxValue
        end
    end
    if totalMax > 0 then
        return string.format("%d/%d", totalCurrent, totalMax)
    end
    return ""
end

function QuestSection:SetupQuestTitleRow(control, data)
    control.data = data
    control:SetMouseEnabled(true)

    if not control.caret then
        control.caret = control:GetNamedChild("Caret")
        if not control.caret then
            control.caret = WM:CreateControl(nil, control, CT_TEXTURE)
            control.caret:SetAnchor(LEFT, control, LEFT, 0, 0)
            control.caret:SetDimensions(16, 16)
        end
        control.caret:SetMouseEnabled(true)
    end

    if not control.label then
        control.label = control:GetNamedChild("Label")
        if not control.label then
            control.label = WM:CreateControl(nil, control, CT_LABEL)
            control.label:SetAnchor(LEFT, control, LEFT, 20, 0)
            control.label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
            control.label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        end
    end

    if not control.progress then
        control.progress = control:GetNamedChild("Progress")
        if not control.progress then
            control.progress = WM:CreateControl(nil, control, CT_LABEL)
            control.progress:SetAnchor(RIGHT, control, RIGHT, -8, 0)
            control.progress:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
            control.progress:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        end
    end

    local quest = data.quest
    local name = quest and (quest.displayName or quest.title or quest.name) or ""
    local progress = questProgressText(quest)
    control.label:SetText(name)
    applyFontAndColor(control.label, "quest")
    control.progress:SetText(progress)
    applyFontAndColor(control.progress, "task")

    local collapsed = data.collapsed == true
    control.caret:SetTexture(collapsed and CARET_TEXTURE_CLOSED or CARET_TEXTURE_OPEN)

    control.caret:SetHandler("OnMouseUp", function(_, button, upInside)
        if button == LEFT_BUTTON and upInside then
            self:ToggleCollapsed(data.questKey)
        end
    end)

    control:SetHandler("OnMouseEnter", function()
        Module.ShowTooltip("quest", function(tt)
            if quest then
                tt:AddLine(quest.title or "", "ZoFontGameBold")
                if quest.zoneName and quest.zoneName ~= "" then
                    tt:AddLine(quest.zoneName, "ZoFontGame")
                end
                if quest.stepText and quest.stepText ~= "" then
                    tt:AddLine(quest.stepText, "ZoFontGame")
                end
            end
        end)
    end)

    control:SetHandler("OnMouseExit", function()
        Module.HideTooltip()
    end)

    control:SetHandler("OnMouseUp", function(_, button, upInside)
        if button == LEFT_BUTTON and upInside then
            self:ToggleCollapsed(data.questKey)
        end
    end)
end

function QuestSection:SetupQuestStepRow(control, data)
    control.data = data
    control:SetMouseEnabled(true)

    if not control.label then
        control.label = control:GetNamedChild("Label")
        if not control.label then
            control.label = WM:CreateControl(nil, control, CT_LABEL)
            control.label:SetAnchor(LEFT, control, LEFT, 32, 0)
            control.label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
            control.label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        end
    end

    if not control.progress then
        control.progress = control:GetNamedChild("Progress")
        if not control.progress then
            control.progress = WM:CreateControl(nil, control, CT_LABEL)
            control.progress:SetAnchor(RIGHT, control, RIGHT, -8, 0)
            control.progress:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
            control.progress:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        end
    end

    local text = ""
    local progress = ""
    if data.objective then
        local objective = data.objective
        text = objective.text or ""
        if text ~= "" then
            text = string.format("• %s", text)
        end
        if objective.max and objective.max > 0 then
            progress = string.format("%d/%d", objective.current or 0, objective.max)
        end
    elseif data.text and data.text ~= "" then
        text = string.format("• %s", data.text)
    end

    control.label:SetText(text)
    applyFontAndColor(control.label, "task")
    control.progress:SetText(progress)
    applyFontAndColor(control.progress, "task")

    control:SetHandler("OnMouseEnter", function()
        local quest = data.quest
        local objective = data.objective
        Module.ShowTooltip("quest", function(tt)
            if quest then
                tt:AddLine(quest.title or "", "ZoFontGameBold")
            end
            if objective then
                local line = objective.text or ""
                if objective.max and objective.max > 0 then
                    line = string.format("%s (%d/%d)", line, objective.current or 0, objective.max)
                end
                if line ~= "" then
                    tt:AddLine(line, "ZoFontGame")
                end
            elseif data.text and data.text ~= "" then
                tt:AddLine(data.text, "ZoFontGame")
            end
        end)
    end)

    control:SetHandler("OnMouseExit", function()
        Module.HideTooltip()
    end)
end

function QuestSection:Dispose()
    local unsubscribe = M.Unsubscribe or (M.Core and M.Core.Unsubscribe)
    if unsubscribe then
        for _, entry in ipairs(self.subscriptions or {}) do
            unsubscribe(entry.topic, entry.fn)
        end
    end
    self.subscriptions = {}
    self.listControl = nil
end

---------------------------------------------------------------------
-- Achievement Section
---------------------------------------------------------------------

AchSection.dataTypes = {
    ROW = 9201,
}

function AchSection:Init(listControl)
    self.listControl = listControl
    self.dirty = true
    self.subscriptions = {}

    local subscribe = M.Subscribe or (M.Core and M.Core.Subscribe)
    if subscribe then
        local achChanged = subscribe("ach:changed", function()
            self:HandleEvent("ach:changed")
        end)
        table.insert(self.subscriptions, { topic = "ach:changed", fn = achChanged })

        local settingsChanged = subscribe("settings:changed", function(key)
            self:OnSettingsChanged(key)
        end)
        table.insert(self.subscriptions, { topic = "settings:changed", fn = settingsChanged })
    end
end

function AchSection:RegisterRowTypes(listControl)
    ZO_ScrollList_AddDataType(
        listControl,
        self.dataTypes.ROW,
        "Nvk3UT_RowAchievementTemplate",
        32,
        function(control, data)
            self:SetupAchievementRow(control, data)
        end,
        nil,
        nil,
        nil,
        function(control)
            control.data = nil
            Module.HideTooltip()
        end
    )
end

function AchSection:OnSettingsChanged(key)
    if type(key) ~= "string" then
        return
    end
    if not key:match("^ach%.") then
        return
    end
    self.dirty = true
    Module.MarkDirty()
end

function AchSection:HandleEvent(topic)
    if topic ~= "ach:changed" then
        return
    end
    self.dirty = true
    Module.MarkDirty()
end

function AchSection:IsVisible()
    local settings = getAchievementSettings()
    if settings.enabled == false then
        return false
    end

    if shouldHideInCombat() then
        return false
    end

    return true
end

function AchSection:IsDirty()
    return self.dirty == true
end

function AchSection:ClearDirty()
    self.dirty = false
end

function AchSection:BuildFeed()
    local feed = {}
    if not self:IsVisible() then
        return feed
    end

    local list = M.AchievementModel and M.AchievementModel.GetList and select(1, M.AchievementModel.GetList())
    if type(list) ~= "table" or #list == 0 then
        return feed
    end

    for _, achievement in ipairs(list) do
        feed[#feed + 1] = {
            dataType = self.dataTypes.ROW,
            achievement = achievement,
        }
    end

    return feed
end

local function achievementProgress(achievement)
    if not achievement or not achievement.progress then
        return ""
    end
    local cur = tonumber(achievement.progress.cur) or 0
    local max = tonumber(achievement.progress.max) or 0
    if max <= 0 then
        return ""
    end
    cur = math.max(0, math.min(max, cur))
    return string.format("%d/%d", cur, max)
end

function AchSection:SetupAchievementRow(control, data)
    control.data = data
    control:SetMouseEnabled(true)

    if not control.label then
        control.label = control:GetNamedChild("Label")
        if not control.label then
            control.label = WM:CreateControl(nil, control, CT_LABEL)
            control.label:SetAnchor(LEFT, control, LEFT, 4, 0)
            control.label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
            control.label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        end
    end

    if not control.progress then
        control.progress = control:GetNamedChild("Progress")
        if not control.progress then
            control.progress = WM:CreateControl(nil, control, CT_LABEL)
            control.progress:SetAnchor(RIGHT, control, RIGHT, -8, 0)
            control.progress:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
            control.progress:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        end
    end

    local achievement = data.achievement
    control.label:SetText(achievement and achievement.name or "")
    applyFontAndColor(control.label, "achieve")
    control.progress:SetText(achievementProgress(achievement))
    applyFontAndColor(control.progress, "achieveTask")

    control:SetHandler("OnMouseEnter", function()
        local settings = getAchievementSettings()
        if settings.tooltips == false then
            return
        end
        Module.ShowTooltip("ach", function(tt)
            if achievement then
                tt:AddLine(achievement.name or "", "ZoFontGameBold")
                if achievement.progress and achievement.progress.max and achievement.progress.max > 0 then
                    tt:AddLine(string.format("%d / %d", achievement.progress.cur or 0, achievement.progress.max), "ZoFontGame")
                end
                if achievement.stages then
                    for _, stage in ipairs(achievement.stages) do
                        if stage.name and stage.name ~= "" then
                            tt:AddLine(stage.name, "ZoFontGame")
                        end
                    end
                end
            end
        end)
    end)

    control:SetHandler("OnMouseExit", function()
        Module.HideTooltip()
    end)
end

function AchSection:Dispose()
    local unsubscribe = M.Unsubscribe or (M.Core and M.Core.Unsubscribe)
    if unsubscribe then
        for _, entry in ipairs(self.subscriptions or {}) do
            unsubscribe(entry.topic, entry.fn)
        end
    end
    self.subscriptions = {}
    self.listControl = nil
end

---------------------------------------------------------------------
-- Unified View Composition
---------------------------------------------------------------------

function Module.BuildUnifiedFeed()
    local feed = {}

    if QuestSection:IsVisible() then
        local questFeed = QuestSection:BuildFeed()
        for _, entry in ipairs(questFeed) do
            feed[#feed + 1] = entry
        end
    end

    local achievementsFeed = {}
    if AchSection:IsVisible() then
        achievementsFeed = AchSection:BuildFeed()
    end

    if #feed > 0 and #achievementsFeed > 0 then
        feed[#feed + 1] = { dataType = DIVIDER_DATA_TYPE }
    end

    for _, entry in ipairs(achievementsFeed) do
        feed[#feed + 1] = entry
    end

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

function Module.RefreshNow()
    Module.refreshPending = false
    if EM and EM.UnregisterForUpdate then
        EM:UnregisterForUpdate(REFRESH_HANDLE)
    end

    if not Module.initialized then
        return
    end

    local feed = Module.BuildUnifiedFeed()
    commitFeed(feed)

    if QuestSection:IsDirty() then
        QuestSection:ClearDirty()
    end
    if AchSection:IsDirty() then
        AchSection:ClearDirty()
    end

    applyRootHiddenState()
end

function Module.MarkDirty()
    scheduleRefresh()
end

function Module.ForceRefresh()
    Module.RefreshNow()
end

local function onSettingsChanged(key)
    if type(key) ~= "string" then
        return
    end
    if key:match("^tracker%.") or key == "tracker" or key == "throttle" then
        applyLockState()
        applyScaleAndPosition()
        applyBackground()
        applyRootHiddenState()
        Module.MarkDirty()
        return
    end
    if key == "quest.tooltips" or key == "ach.tooltips" then
        Module.MarkDirty()
    end
end

local function attachFragment()
    if not Module.rootControl or not SCENE_MANAGER then
        return
    end

    if not Module.fragment then
        local fragmentClass = ZO_HUDFadeSceneFragment or ZO_SimpleSceneFragment
        if fragmentClass then
            Module.fragment = fragmentClass:New(Module.rootControl)
        end
    end

    if not Module.fragment then
        return
    end

    Module.sceneFragments = Module.sceneFragments or {}
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

local function createControls()
    if Module.rootControl then
        return
    end

    local root = WM:CreateTopLevelWindow(ROOT_CONTROL_NAME)
    root:SetClampedToScreen(true)
    root:SetDrawTier(DT_HIGH)
    root:SetMovable(true)
    root:SetMouseEnabled(true)
    root:SetResizeHandleSize(8)
    root:SetDimensionConstraints(MIN_WIDTH, MIN_HEIGHT, 800, 900)
    root:ClearAnchors()
    root:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, 400, 200)

    root:SetHandler("OnMoveStop", function()
        savePosition()
    end)

    root:SetHandler("OnResizeStop", function()
        saveDimensions()
        Module.MarkDirty()
    end)

    root:SetHandler("OnHide", function()
        Module.HideTooltip()
    end)

    local backdrop = WM:CreateControl(nil, root, CT_BACKDROP)
    backdrop:SetAnchorFill(root)
    backdrop:SetHidden(true)

    local list = WM:CreateControlFromVirtual(LIST_CONTROL_NAME, root, "ZO_ScrollList")
    list:ClearAnchors()
    list:SetAnchor(TOPLEFT, root, TOPLEFT, PADDING_X, PADDING_Y)
    list:SetAnchor(BOTTOMRIGHT, root, BOTTOMRIGHT, -PADDING_X, -PADDING_Y)

    Module.rootControl = root
    Module.backdrop = backdrop
    Module.scrollList = list

    registerDividerDataType()
    attachFragment()
    applyScaleAndPosition()
    applyLockState()
    applyBackground()
    applyRootHiddenState()
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

function Module.SetRootHidden(hidden)
    if Module.rootControl then
        Module.rootControl:SetHidden(hidden)
    end
end

function Module.GetRootControl()
    return Module.rootControl
end

function Module.GetScrollList()
    return Module.scrollList
end

function Module.GetFragment()
    return Module.fragment
end

function Module.Init()
    if Module.initialized then
        return
    end

    createControls()

    QuestSection:Init(Module.scrollList)
    AchSection:Init(Module.scrollList)
    QuestSection:RegisterRowTypes(Module.scrollList)
    AchSection:RegisterRowTypes(Module.scrollList)

    local subscribe = M.Subscribe or (M.Core and M.Core.Subscribe)
    if subscribe then
        Module.settingsSubscription = subscribe("settings:changed", function(key)
            onSettingsChanged(key)
        end)
    end

    Module.initialized = true
    Module.MarkDirty()

    if M and M.Tracker and M.Tracker.NotifyViewReady then
        M.Tracker.NotifyViewReady()
    end
end

function Module.Dispose()
    if Module.settingsSubscription then
        local unsubscribe = M.Unsubscribe or (M.Core and M.Core.Unsubscribe)
        if unsubscribe then
            unsubscribe("settings:changed", Module.settingsSubscription)
        end
        Module.settingsSubscription = nil
    end

    QuestSection:Dispose()
    AchSection:Dispose()

    if Module.fragment and SCENE_MANAGER then
        for sceneName, _ in pairs(Module.sceneFragments or {}) do
            local scene = SCENE_MANAGER:GetScene(sceneName)
            if scene and scene.RemoveFragment then
                scene:RemoveFragment(Module.fragment)
            end
        end
    end

    Module.rootControl = nil
    Module.scrollList = nil
    Module.backdrop = nil
    Module.fragment = nil
    Module.sceneFragments = nil
    Module.initialized = false
end

return
