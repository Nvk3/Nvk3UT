Nvk3UT = Nvk3UT or {}

local Tracker = {}
Nvk3UT.QuestTracker = Tracker

local EM = EVENT_MANAGER
local WM = WINDOW_MANAGER
local SCENE_MANAGER = SCENE_MANAGER
local GuiRoot = GuiRoot

local TEXTURE_ARROW_COLLAPSED = "/esoui/art/tree/tree_icon_closed.dds"
local TEXTURE_ARROW_EXPANDED = "/esoui/art/tree/tree_icon_open.dds"
local BACKDROP_EDGE_TEXTURE = "/esoui/art/chatwindow/chat_window_edge.dds"
local LIST_ENTRY_HEIGHT = 30
local INDENT_ZONE = 0
local INDENT_QUEST = 16
local INDENT_OBJECTIVE = 32

local TRACKER_NAME = "Nvk3UTQuestTracker"
local EVENT_NAMESPACE = "Nvk3UT_QuestTracker"

local function safeCall(func, ...)
    if type(func) ~= "function" then
        return
    end
    local results = { pcall(func, ...) }
    if results[1] then
        table.remove(results, 1)
        return unpack(results)
    end
end

local function defaultColor(color)
    if type(color) ~= "table" then
        return 1, 1, 1, 1
    end
    local r = tonumber(color.r) or tonumber(color[1]) or 1
    local g = tonumber(color.g) or tonumber(color[2]) or 1
    local b = tonumber(color.b) or tonumber(color[3]) or 1
    local a = tonumber(color.a) or tonumber(color[4]) or 1
    return r, g, b, a
end

local function applyFont(control, fontConfig)
    if not control then
        return
    end
    local face = fontConfig and fontConfig.face or "ZoFontGame"
    local size = fontConfig and tonumber(fontConfig.size) or 18
    local effect = fontConfig and fontConfig.effect or "soft-shadow-thin"
    if effect == "" or not effect then
        control:SetFont(string.format("%s|%d", face, size))
    else
        control:SetFont(string.format("%s|%d|%s", face, size, effect))
    end
    local r, g, b, a = defaultColor(fontConfig and fontConfig.color)
    control:SetColor(r, g, b, a)
end

local function isQuestTracked(journalIndex)
    local anyKnown = false
    local anyTracked = false

    local function evaluate(ok, value)
        if not ok then
            return
        end
        if value ~= nil then
            anyKnown = true
            if value == true or value == 1 then
                anyTracked = true
            end
        end
    end

    if type(IsJournalQuestInTracker) == "function" then
        evaluate(pcall(IsJournalQuestInTracker, journalIndex))
    end

    if type(GetJournalQuestIsTracked) == "function" then
        evaluate(pcall(GetJournalQuestIsTracked, journalIndex))
    end

    if type(GetJournalQuestIsPinned) == "function" then
        evaluate(pcall(GetJournalQuestIsPinned, journalIndex))
    end

    if type(GetIsTracked) == "function" and type(TRACK_TYPE_QUEST) == "number" then
        evaluate(pcall(GetIsTracked, TRACK_TYPE_QUEST, journalIndex))
    end

    if type(GetTrackedIsAssisted) == "function" and type(TRACK_TYPE_QUEST) == "number" then
        evaluate(pcall(GetTrackedIsAssisted, TRACK_TYPE_QUEST, journalIndex))
    end

    if anyTracked then
        return true
    end

    if anyKnown then
        return false
    end

    return true
end

local function getZoneKey(zoneName, zoneId)
    if zoneId and zoneId ~= 0 then
        return string.format("%d:%s", zoneId, zoneName or "")
    end
    return tostring(zoneName or "Unknown")
end

local function sanitizeText(text)
    if type(text) ~= "string" then
        return ""
    end
    return zo_strformat("<<1>>", text)
end

local function buildQuestKey(questId, stepKey)
    return string.format("%d:%s", questId or 0, tostring(stepKey or 0))
end

local function getActiveStepIndex(journalIndex)
    local numSteps = safeCall(GetJournalQuestNumSteps, journalIndex) or 0
    for stepIndex = 1, numSteps do
        local _, _, _, _, stepCompleted = safeCall(GetJournalQuestStepInfo, journalIndex, stepIndex)
        if stepCompleted == false then
            return stepIndex
        end
    end
    return 1
end

local function getQuestStepKey(journalIndex)
    local stepIndex = getActiveStepIndex(journalIndex)
    local _, _, stepType = safeCall(GetJournalQuestStepInfo, journalIndex, stepIndex)
    return string.format("%d:%d", stepIndex or 0, stepType or 0)
end

local function buildQuestObjectives(journalIndex)
    local objectives = {}
    local numSteps = safeCall(GetJournalQuestNumSteps, journalIndex) or 0
    for stepIndex = 1, numSteps do
        local stepText, _, _, trackerOverride, stepCompleted = safeCall(GetJournalQuestStepInfo, journalIndex, stepIndex)
        if stepCompleted == false then
            local stepLabel = trackerOverride and trackerOverride ~= "" and trackerOverride or stepText
            local numConditions = safeCall(GetJournalQuestNumConditions, journalIndex, stepIndex) or 0
            for conditionIndex = 1, numConditions do
                local condText, cur, max, _, conditionComplete =
                    safeCall(GetJournalQuestConditionInfo, journalIndex, stepIndex, conditionIndex)
                if conditionComplete == false then
                    local formatted = sanitizeText(condText)
                    if (max or 0) > 1 then
                        formatted = string.format("%s (%d/%d)", formatted, tonumber(cur) or 0, tonumber(max) or 0)
                    elseif (cur or 0) > 0 and (max or 0) == 0 then
                        formatted = string.format("%s (%d)", formatted, tonumber(cur) or 0)
                    end
                    objectives[#objectives + 1] = formatted
                end
            end
            if numConditions == 0 then
                local formatted = sanitizeText(stepLabel)
                if formatted ~= "" then
                    objectives[#objectives + 1] = formatted
                end
            end
        end
    end
    return objectives
end

local function getQuestData()
    local questZones = {}
    local zoneOrder = {}
    local showQuest = true
    local trackerSv = Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.tracker
    if trackerSv and trackerSv.showQuests == false then
        showQuest = false
    end
    if not showQuest then
        return zoneOrder, questZones
    end
    local total = safeCall(GetNumJournalQuests) or 0
    for journalIndex = 1, total do
        local questName, backgroundText, stepText, trackerOverrideText, completed = safeCall(GetJournalQuestInfo, journalIndex)
        if questName and questName ~= "" and completed ~= true then
            local zoneName, _, zoneId = safeCall(GetJournalQuestLocationInfo, journalIndex)
            local questId = safeCall(GetJournalQuestId, journalIndex) or 0
            local zoneKey = getZoneKey(zoneName, zoneId)
            if not questZones[zoneKey] then
                questZones[zoneKey] = {
                    key = zoneKey,
                    zoneName = sanitizeText(zoneName),
                    zoneId = zoneId,
                    quests = {},
                    order = {},
                }
                zoneOrder[#zoneOrder + 1] = zoneKey
            end
            local stepKey = getQuestStepKey(journalIndex)
            local questKey = buildQuestKey(questId, stepKey)
            local questEntry = {
                key = questKey,
                questId = questId,
                journalIndex = journalIndex,
                name = sanitizeText(questName),
                background = sanitizeText(backgroundText),
                stepText = sanitizeText(stepText),
                trackerText = sanitizeText(trackerOverrideText),
                objectives = buildQuestObjectives(journalIndex),
                zoneName = sanitizeText(zoneName),
                zoneKey = zoneKey,
                isTracked = isQuestTracked(journalIndex),
            }
            questZones[zoneKey].quests[questKey] = questEntry
            questZones[zoneKey].order[#questZones[zoneKey].order + 1] = questKey
        end
    end
    return zoneOrder, questZones
end

local function buildAchievementList()
    local trackerSv = Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.tracker
    if trackerSv and trackerSv.showAchievements == false then
        return {}
    end
    local FavData = Nvk3UT and Nvk3UT.FavoritesData
    if not FavData or not FavData.Iterate then
        return {}
    end
    local scope = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.ui and Nvk3UT.sv.ui.favScope) or "account"
    local iterator, data, key = FavData.Iterate(scope)
    if type(iterator) ~= "function" then
        return {}
    end
    local list = {}
    local gender = safeCall(GetUnitGender, "player")
    local function localizedName(id)
        local name = select(1, safeCall(GetAchievementInfo, id)) or ""
        if gender then
            name = zo_strformat("<<1>>", name)
        else
            name = sanitizeText(name)
        end
        return name
    end
    local current = key
    while true do
        local achievementId, isFavorite = iterator(data, current)
        current = achievementId
        if not achievementId then
            break
        end
        if isFavorite then
            local name = localizedName(achievementId)
            list[#list + 1] = {
                id = achievementId,
                name = name,
            }
        end
    end
    table.sort(list, function(a, b)
        return (a.name or "") < (b.name or "")
    end)
    return list
end

local function buildAchievementObjectives(achievementId)
    local result = {}
    local Utils = Nvk3UT and Nvk3UT.Utils
    local state = Utils and Utils.GetAchievementCriteriaState and Utils.GetAchievementCriteriaState(achievementId, true)
    local numCriteria = safeCall(GetAchievementNumCriteria, achievementId) or 0
    for index = 1, numCriteria do
        local description, numCompleted, numRequired = safeCall(GetAchievementCriterion, achievementId, index)
        local completed = false
        if state and state.stages and state.stages[index] ~= nil then
            completed = state.stages[index]
        elseif numRequired and numRequired > 0 then
            completed = (numCompleted or 0) >= numRequired
        else
            completed = (numCompleted or 0) > 0
        end
        if not completed then
            local text = sanitizeText(description)
            if (numRequired or 0) > 1 then
                text = string.format("%s (%d/%d)", text, tonumber(numCompleted) or 0, tonumber(numRequired) or 0)
            end
            result[#result + 1] = text
        end
    end
    return result
end

local function computeTooltipAnchor(control)
    if not control or not control.GetCenter then
        return TOPRIGHT, TOPLEFT, 0
    end
    local centerX = select(1, control:GetCenter())
    local rootWidth = GuiRoot and select(3, GuiRoot:GetBounds()) or 0
    if rootWidth == 0 then
        rootWidth = GuiRoot and GuiRoot:GetWidth() or 0
    end
    if centerX and rootWidth and centerX > (rootWidth / 2) then
        return TOPLEFT, TOPRIGHT, -20
    end
    return TOPRIGHT, TOPLEFT, 20
end

function Tracker:Init()
    if self.initialized then
        return
    end
    self.sv = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.tracker) or {}
    self.state = {
        enabled = false,
        pending = false,
        questKeyHistory = {},
        zoneOrder = {},
        questZones = {},
        achievements = {},
        inCombat = false,
        lamOpen = false,
    }
    self.controls = {
        zones = {},
    }
    self.initialized = true
    self:AttachFavoritesHooks()
    self:EnsureLamCallbacks()
    if self.sv.enabled ~= false then
        self:Enable()
    else
        self:Disable()
    end
    self:ApplyDefaultTrackerVisibility()
end

function Tracker:IsEnabled()
    return self.state and self.state.enabled == true
end

function Tracker:EnsureControl()
    if self.control then
        return
    end
    local ctl = WM:CreateTopLevelWindow(TRACKER_NAME)
    ctl:SetHidden(true)
    ctl:SetClampedToScreen(true)
    ctl:SetMouseEnabled(true)
    ctl:SetMovable(true)
    ctl:SetDrawLayer(DL_BACKGROUND)
    ctl:SetDrawLevel(1)
    ctl:SetResizeToFitDescendents(false)
    ctl:SetDimensionConstraints(260, 160, 900, 1000)
    if ctl.SetResizeHandleSize then
        ctl:SetResizeHandleSize(0)
    end

    ctl:SetHandler("OnMoveStop", function(window)
        if window == self.control then
            self:SavePosition()
        end
    end)
    ctl:SetHandler("OnResizeStart", function(window)
        if not self:IsUnlocked() then
            window:StopMovingOrResizing()
        end
    end)
    ctl:SetHandler("OnResizeStop", function(window)
        window:StopMovingOrResizing()
        self:SavePosition()
    end)

    local bg = CreateControl(nil, ctl, CT_BACKDROP)
    bg:SetAnchorFill(ctl)
    bg:SetCenterColor(0, 0, 0, 0.45)
    bg:SetEdgeTexture(BACKDROP_EDGE_TEXTURE, 128, 16, 16)
    bg:SetEdgeColor(0.8, 0.8, 0.8, 0.6)
    bg:SetHidden(true)
    ctl.background = bg

    local dragHandle = CreateControl(nil, ctl, CT_CONTROL)
    dragHandle:SetAnchor(TOPLEFT, ctl, TOPLEFT, 0, 0)
    dragHandle:SetAnchor(TOPRIGHT, ctl, TOPRIGHT, 0, 0)
    dragHandle:SetHeight(16)
    dragHandle:SetMouseEnabled(true)
    dragHandle:SetAlpha(0)
    dragHandle:SetHandler("OnMouseDown", function(_, button)
        if button == MOUSE_BUTTON_INDEX_LEFT and self:IsUnlocked() then
            ctl:StartMoving()
        end
    end)
    dragHandle:SetHandler("OnMouseUp", function(_, button)
        if button == MOUSE_BUTTON_INDEX_LEFT then
            ctl:StopMovingOrResizing()
            self:SavePosition()
        end
    end)
    ctl.dragHandle = dragHandle
    self.dragHandle = dragHandle

    local scroll = CreateControlFromVirtual(TRACKER_NAME .. "Scroll", ctl, "ZO_ScrollContainer")
    scroll:SetAnchor(TOPLEFT, ctl, TOPLEFT, 8, 16)
    scroll:SetAnchor(BOTTOMRIGHT, ctl, BOTTOMRIGHT, -8, -8)
    scroll.scrollChild = scroll:GetNamedChild("ScrollChild")
    scroll.scrollChild:SetResizeToFitDescendents(true)
    scroll.scrollChild:SetAnchor(TOPLEFT, scroll, TOPLEFT, 0, 0)
    self.scroll = scroll

    self.control = ctl
    self:RegisterSceneCallbacks()
    self:ApplyPosition()
    self:ApplyLockState()
    self:ApplyBackground()
end

function Tracker:IsUnlocked()
    local behavior = self.sv and self.sv.behavior
    return not (behavior and behavior.locked)
end

function Tracker:IsTooltipsEnabled()
    local behavior = self.sv and self.sv.behavior
    if behavior and behavior.tooltips == false then
        return false
    end
    return true
end

function Tracker:HideTooltips()
    if ClearTooltip then
        if InformationTooltip then
            ClearTooltip(InformationTooltip)
        end
        if AchievementTooltip then
            ClearTooltip(AchievementTooltip)
        end
    end
end

function Tracker:SavePosition()
    if not self.control or not self.sv then
        return
    end
    local left, top = self.control:GetLeft(), self.control:GetTop()
    self.sv.pos = self.sv.pos or {}
    self.sv.pos.x = left or self.sv.pos.x
    self.sv.pos.y = top or self.sv.pos.y
    self.sv.pos.width = self.control:GetWidth()
    self.sv.pos.height = self.control:GetHeight()
    self.sv.pos.scale = self.control:GetScale()
end

function Tracker:ApplyPosition()
    if not self.control or not self.sv or not self.sv.pos then
        return
    end
    local pos = self.sv.pos
    self.control:ClearAnchors()
    self.control:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, pos.x or 200, pos.y or 200)
    self.control:SetDimensions(pos.width or 360, pos.height or 420)
    self.control:SetScale(pos.scale or 1)
end

function Tracker:ApplyBackground()
    if not self.control then
        return
    end
    local bg = self.control.background
    if not bg then
        return
    end
    local settings = self.sv and self.sv.background or {}
    local enabled = settings.enabled == true
    local hidden = not enabled
    if enabled and settings.hideWhenLocked and not self:IsUnlocked() then
        hidden = true
    end
    bg:SetHidden(hidden)

    local alpha = zo_clamp((tonumber(settings.alpha) or 60) / 100, 0, 1)
    if enabled then
        bg:SetCenterColor(0, 0, 0, alpha)
    else
        bg:SetCenterColor(0, 0, 0, 0)
    end

    bg:SetEdgeTexture(BACKDROP_EDGE_TEXTURE, 128, 16, 16)
    if enabled then
        local edgeAlpha = math.min(alpha + 0.35, 1)
        bg:SetEdgeColor(1, 1, 1, edgeAlpha)
    else
        bg:SetEdgeColor(0, 0, 0, 0)
    end
end

function Tracker:ApplyLockState()
    if not self.control then
        return
    end
    local unlocked = self:IsUnlocked()
    self.control:SetMovable(unlocked)
    if self.control.SetResizeHandleSize then
        self.control:SetResizeHandleSize(unlocked and 12 or 0)
    end
    if self.dragHandle then
        self.dragHandle:SetHidden(not unlocked)
        self.dragHandle:SetMouseEnabled(unlocked)
    end
end

function Tracker:RegisterSceneCallbacks()
    if not SCENE_MANAGER or self.sceneCallbackRegistered then
        return
    end
    local function onSceneStateChange(_, newState)
        if newState == SCENE_SHOWN or newState == SCENE_HIDING or newState == SCENE_HIDDEN then
            self:UpdateVisibility()
        end
    end
    self.sceneCallback = onSceneStateChange
    SCENE_MANAGER:RegisterCallback("SceneStateChanged", self.sceneCallback)
    self.sceneCallbackRegistered = true
    self:UpdateVisibility()
end

function Tracker:UnregisterSceneCallbacks()
    if not SCENE_MANAGER or not self.sceneCallbackRegistered then
        return
    end
    if SCENE_MANAGER.UnregisterCallback and self.sceneCallback then
        SCENE_MANAGER:UnregisterCallback("SceneStateChanged", self.sceneCallback)
    end
    self.sceneCallback = nil
    self.sceneCallbackRegistered = false
end

local HUD_SCENES = {
    hud = true,
    hudui = true,
    gamepad_hud = true,
    gamepad_hud_ui = true,
}

local function getSceneName(scene)
    if not scene then
        return nil
    end
    if scene.GetName then
        local ok, name = pcall(scene.GetName, scene)
        if ok and name then
            return tostring(name)
        end
    end
    if scene.name then
        return tostring(scene.name)
    end
    return nil
end

function Tracker:IsSceneAllowed()
    if not SCENE_MANAGER then
        return true
    end
    if self.state and self.state.lamOpen then
        return true
    end
    if SCENE_MANAGER.IsShowing then
        for name in pairs(HUD_SCENES) do
            local ok, showing = pcall(SCENE_MANAGER.IsShowing, SCENE_MANAGER, name)
            if ok and showing then
                return true
            end
        end
    end
    local scene = SCENE_MANAGER:GetCurrentScene()
    local currentName = getSceneName(scene)
    if currentName and HUD_SCENES[currentName] then
        return true
    end
    return false
end

function Tracker:UpdateVisibility()
    if not self.control then
        return
    end
    local shouldShow = self.state and self.state.enabled == true
    if shouldShow then
        shouldShow = self:IsSceneAllowed()
        if shouldShow then
            local hideInCombat = self.sv and self.sv.behavior and self.sv.behavior.hideInCombat
            if hideInCombat and self.state and self.state.inCombat then
                shouldShow = false
            end
        end
    end
    self.control:SetHidden(not shouldShow)
    if not shouldShow then
        self:HideTooltips()
    end
end

function Tracker:GetLamPanelControl()
    if not self.lamPanelName then
        return nil
    end
    local control = self.lamPanelControl
    if control and control.GetName then
        local ok, name = pcall(control.GetName, control)
        if ok and name == self.lamPanelName then
            return control
        end
    end
    if type(LibAddonMenu2) == "table" then
        local util = LibAddonMenu2.util
        if util and util.GetAddonPanelControl then
            local ok, panel = pcall(util.GetAddonPanelControl, util, self.lamPanelName)
            if ok and panel then
                self.lamPanelControl = panel
                return panel
            end
        end
        if LibAddonMenu2.GetPanelControlByName then
            local ok, panel = pcall(LibAddonMenu2.GetPanelControlByName, LibAddonMenu2, self.lamPanelName)
            if ok and panel then
                self.lamPanelControl = panel
                return panel
            end
        end
    end
    local globalControl = _G and _G[self.lamPanelName]
    if globalControl then
        self.lamPanelControl = globalControl
        return globalControl
    end
    return nil
end

function Tracker:IsLamPanel(panel)
    if not panel or not self.lamPanelName then
        return false
    end
    if panel == self:GetLamPanelControl() then
        return true
    end
    if panel.GetName then
        local ok, name = pcall(panel.GetName, panel)
        if ok and name == self.lamPanelName then
            return true
        end
    end
    if panel.name and panel.name == self.lamPanelName then
        return true
    end
    if panel.panelId and panel.panelId == self.lamPanelName then
        return true
    end
    if panel.data then
        if panel.data.panelId == self.lamPanelName or panel.data.name == self.lamPanelName then
            return true
        end
    end
    return false
end

function Tracker:EnsureLamCallbacks()
    if not CALLBACK_MANAGER or self.lamCallbacksRegistered then
        return
    end
    local function onPanelOpened(panel)
        if not self.state then
            return
        end
        if self:IsLamPanel(panel) then
            self.state.lamOpen = true
        elseif self.state.lamOpen then
            self.state.lamOpen = false
        end
        self:UpdateVisibility()
    end
    local function onPanelClosed(panel)
        if not self.state then
            return
        end
        if self:IsLamPanel(panel) then
            self.state.lamOpen = false
            self:UpdateVisibility()
        end
    end
    CALLBACK_MANAGER:RegisterCallback("LAM-PanelOpened", onPanelOpened)
    CALLBACK_MANAGER:RegisterCallback("LAM-PanelClosed", onPanelClosed)
    self.lamOpenCallback = onPanelOpened
    self.lamClosedCallback = onPanelClosed
    self.lamCallbacksRegistered = true
end

function Tracker:UnregisterLamCallbacks()
    if not CALLBACK_MANAGER or not self.lamCallbacksRegistered then
        return
    end
    if self.lamOpenCallback then
        CALLBACK_MANAGER:UnregisterCallback("LAM-PanelOpened", self.lamOpenCallback)
    end
    if self.lamClosedCallback then
        CALLBACK_MANAGER:UnregisterCallback("LAM-PanelClosed", self.lamClosedCallback)
    end
    self.lamOpenCallback = nil
    self.lamClosedCallback = nil
    self.lamCallbacksRegistered = false
end

function Tracker:SetLamPanelName(panelName)
    if panelName and panelName ~= "" then
        self.lamPanelName = panelName
    else
        self.lamPanelName = nil
        self.lamPanelControl = nil
        if self.state then
            self.state.lamOpen = false
        end
        self:UpdateVisibility()
        return
    end
    self.lamPanelControl = nil
    self:EnsureLamCallbacks()
end

function Tracker:ApplyDefaultTrackerVisibility()
    local hideDefault = self.sv and self.sv.behavior and self.sv.behavior.hideDefault
    local tracker = _G["ZO_QuestTracker"]
    if tracker then
        tracker:SetHidden(hideDefault == true)
    end
end

function Tracker:Enable()
    self:EnsureControl()
    self:RegisterSceneCallbacks()
    self:EnsureLamCallbacks()
    if self.state.enabled then
        self:RegisterEvents()
        self:Refresh(false)
        self:ApplyCombatVisibility()
        self:UpdateVisibility()
        return
    end
    self.state.enabled = true
    self:RegisterEvents()
    self:Refresh(false)
    self:ApplyCombatVisibility()
end

function Tracker:Disable()
    if not self.state.enabled then
        if self.control then
            self:UpdateVisibility()
        end
        self:UnregisterEvents()
        self:HideTooltips()
        return
    end
    self.state.enabled = false
    self:UnregisterEvents()
    self:HideTooltips()
    self:UpdateVisibility()
end

function Tracker:Destroy()
    self:Disable()
    self:UnregisterSceneCallbacks()
    self:UnregisterLamCallbacks()
    if self.control then
        self.control:SetHidden(true)
        self.control:SetHandler("OnMouseDown", nil)
        self.control:SetHandler("OnMouseUp", nil)
        self.control = nil
        self.scroll = nil
    end
    self.dragHandle = nil
    self.lamPanelControl = nil
    self.controls = { zones = {} }
    self.initialized = false
end

local QUEST_EVENTS = {}

local function registerQuestEvent(eventCode)
    if type(eventCode) == "number" then
        QUEST_EVENTS[#QUEST_EVENTS + 1] = eventCode
    end
end

registerQuestEvent(EVENT_QUEST_ADDED)
registerQuestEvent(EVENT_QUEST_REMOVED)
registerQuestEvent(EVENT_QUEST_ADVANCED)
registerQuestEvent(EVENT_QUEST_STEP_INFO_CHANGED)
registerQuestEvent(EVENT_QUEST_CONDITION_COUNTER_CHANGED)
registerQuestEvent(EVENT_OBJECTIVE_COMPLETED)

function Tracker:RegisterEvents()
    if not EM or self.eventsRegistered then
        return
    end
    for _, eventCode in ipairs(QUEST_EVENTS) do
        EM:RegisterForEvent(EVENT_NAMESPACE .. eventCode, eventCode, function(_, ...)
            self:OnQuestChanged(eventCode, ...)
        end)
    end
    EM:RegisterForEvent(EVENT_NAMESPACE .. "ACH_UPDATED", EVENT_ACHIEVEMENT_UPDATED, function(_, achievementId)
        self:OnAchievementChanged(achievementId)
    end)
    EM:RegisterForEvent(EVENT_NAMESPACE .. "ACH_AWARDED", EVENT_ACHIEVEMENT_AWARDED, function(_, _, _, achievementId)
        self:OnAchievementChanged(achievementId)
    end)
    EM:RegisterForEvent(EVENT_NAMESPACE .. "PLAYER_ACTIVATED", EVENT_PLAYER_ACTIVATED, function()
        self:Refresh(false)
        self:ApplyCombatVisibility()
    end)
    EM:RegisterForEvent(EVENT_NAMESPACE .. "COMBAT_STATE", EVENT_PLAYER_COMBAT_STATE, function(_, inCombat)
        self:ApplyCombatVisibility(inCombat)
    end)
    self.eventsRegistered = true
end

function Tracker:UnregisterEvents()
    if not EM then
        return
    end
    if not self.eventsRegistered then
        return
    end
    for _, eventCode in ipairs(QUEST_EVENTS) do
        EM:UnregisterForEvent(EVENT_NAMESPACE .. eventCode, eventCode)
    end
    EM:UnregisterForEvent(EVENT_NAMESPACE .. "ACH_UPDATED", EVENT_ACHIEVEMENT_UPDATED)
    EM:UnregisterForEvent(EVENT_NAMESPACE .. "ACH_AWARDED", EVENT_ACHIEVEMENT_AWARDED)
    EM:UnregisterForEvent(EVENT_NAMESPACE .. "PLAYER_ACTIVATED", EVENT_PLAYER_ACTIVATED)
    EM:UnregisterForEvent(EVENT_NAMESPACE .. "COMBAT_STATE", EVENT_PLAYER_COMBAT_STATE)
    self.eventsRegistered = false
end

function Tracker:ApplyCombatVisibility(inCombat)
    if inCombat == nil and type(IsUnitInCombat) == "function" then
        inCombat = IsUnitInCombat("player")
    end
    if self.state then
        self.state.inCombat = inCombat == true
    end
    self:UpdateVisibility()
end

function Tracker:OnQuestChanged(eventCode, ...)
    if eventCode == EVENT_QUEST_ADDED and self.sv and self.sv.behavior and self.sv.behavior.autoExpandNewQuests then
        local journalIndex = select(1, ...)
        local questId = safeCall(GetJournalQuestId, journalIndex)
        local zoneName, _, zoneId = safeCall(GetJournalQuestLocationInfo, journalIndex)
        local zoneKey = getZoneKey(zoneName, zoneId)
        if zoneKey then
            self:SetCollapsed("zones", zoneKey, false)
        end
        local stepKey = getQuestStepKey(journalIndex)
        local questKey = buildQuestKey(questId, stepKey)
        self:SetCollapsed("quests", questKey, false)
    end
    self:Refresh(true)
end

function Tracker:OnAchievementChanged(achievementId)
    if achievementId then
        if self.sv and self.sv.behavior and self.sv.behavior.alwaysExpandAchievements then
            self:SetCollapsed("achieves", tostring(achievementId), false)
        end
    end
    self:Refresh(true)
end

function Tracker:SetCollapsed(bucket, key, collapsed)
    if not (self.sv and bucket and key) then
        return
    end
    self:EnsureCollapseState()
    local map = self.sv.collapseState[bucket]
    if type(map) ~= "table" then
        map = {}
        self.sv.collapseState[bucket] = map
    end
    map[key] = collapsed and true or false
end

function Tracker:IsCollapsed(bucket, key)
    if not (self.sv and bucket and key) then
        return true
    end
    self:EnsureCollapseState()
    local map = self.sv.collapseState[bucket]
    if type(map) ~= "table" then
        return true
    end
    local value = map[key]
    if value == nil then
        return true
    end
    return value == true
end

function Tracker:EnsureCollapseState()
    if not self.sv then
        return
    end
    self.sv.collapseState = self.sv.collapseState or {}
    local cs = self.sv.collapseState
    cs.zones = cs.zones or {}
    cs.quests = cs.quests or {}
    cs.achieves = cs.achieves or {}
end

function Tracker:ToggleCollapsed(bucket, key)
    if not (bucket and key) then
        return
    end
    local collapsed = not self:IsCollapsed(bucket, key)
    self:SetCollapsed(bucket, key, collapsed)
    self:Refresh(false)
end

function Tracker:Refresh(throttled)
    if not self.control then
        self:EnsureControl()
    end
    if throttled then
        if self.refreshHandle then
            return
        end
        local delay = (self.sv and tonumber(self.sv.throttleMs)) or 150
        self.refreshHandle = zo_callLater(function()
            self.refreshHandle = nil
            self:Rebuild()
        end, delay)
    else
        if self.refreshHandle then
            zo_removeCallLater(self.refreshHandle)
            self.refreshHandle = nil
        end
        self:Rebuild()
    end
end

local function ensureHeader(control)
    if control.header then
        return control.header
    end
    local header = CreateControl(nil, control, CT_CONTROL)
    header:SetAnchor(TOPLEFT)
    header:SetAnchor(TOPRIGHT)
    header:SetHeight(LIST_ENTRY_HEIGHT)
    header:SetMouseEnabled(true)

    local arrow = CreateControl(nil, header, CT_TEXTURE)
    arrow:SetDimensions(18, 18)
    arrow:SetAnchor(LEFT, header, LEFT, 4, 0)
    arrow:SetDrawLayer(DL_CONTROLS)
    arrow:SetDrawLevel(2)
    arrow:SetMouseEnabled(false)
    arrow:SetTexture(TEXTURE_ARROW_COLLAPSED)
    arrow:SetColor(1, 1, 1, 1)

    local label = CreateControl(nil, header, CT_LABEL)
    label:SetAnchor(LEFT, arrow, RIGHT, 10, 0)
    label:SetAnchor(RIGHT, header, RIGHT, -8, 0)
    label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)

    header.arrow = arrow
    header.label = label
    control.header = header
    return header
end

local function ensureBody(control)
    if control.body then
        return control.body
    end
    local body = CreateControl(nil, control, CT_CONTROL)
    body:SetAnchor(TOPLEFT, control.header, BOTTOMLEFT, INDENT_OBJECTIVE - INDENT_QUEST, 0)
    body:SetAnchor(TOPRIGHT, control.header, BOTTOMRIGHT, 0, 0)
    body:SetResizeToFitDescendents(true)
    body:SetHidden(true)
    control.body = body
    return body
end

local function ensureObjective(control, index)
    control.objectiveControls = control.objectiveControls or {}
    local row = control.objectiveControls[index]
    if not row then
        row = CreateControl(nil, control, CT_LABEL)
        row:SetAnchor(TOPLEFT, control, TOPLEFT, INDENT_OBJECTIVE, (index - 1) * (LIST_ENTRY_HEIGHT - 10))
        row:SetAnchor(RIGHT, control, RIGHT, -10, 0)
        row:SetHeight(LIST_ENTRY_HEIGHT - 6)
        row:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        row:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
        control.objectiveControls[index] = row
    end
    row:SetHidden(false)
    return row
end

function Tracker:SetupZoneControl(zoneControl, zoneData)
    local header = ensureHeader(zoneControl)
    header.arrow:SetTexture(self:IsCollapsed("zones", zoneData.key) and TEXTURE_ARROW_COLLAPSED or TEXTURE_ARROW_EXPANDED)
    header.label:SetText(zoneData.zoneName or "")
    header:SetHandler("OnMouseUp", function(_, button)
        if button == MOUSE_BUTTON_INDEX_LEFT then
            self:ToggleCollapsed("zones", zoneData.key)
        elseif button == MOUSE_BUTTON_INDEX_RIGHT then
            self:ShowZoneContextMenu(zoneData)
        end
    end)
    applyFont(header.label, self.sv and self.sv.fonts and self.sv.fonts.category)

    local collapsed = self:IsCollapsed("zones", zoneData.key)
    local body = ensureBody(zoneControl)
    body:SetHidden(collapsed)
    if not collapsed then
        self:PopulateQuests(body, zoneData)
    else
        self:ReleaseQuestControls(body)
    end
end

function Tracker:CreateZoneControl(zoneKey)
    local ctl = CreateControl(nil, self.scroll.scrollChild, CT_CONTROL)
    ctl:SetResizeToFitDescendents(true)
    ctl.zoneKey = zoneKey
    ctl:SetAnchor(TOPLEFT, self.scroll.scrollChild, TOPLEFT, 0, 0)
    ctl:SetAnchor(TOPRIGHT, self.scroll.scrollChild, TOPRIGHT, 0, 0)
    self.controls.zones[zoneKey] = ctl
    return ctl
end

function Tracker:PopulateZones(zoneOrder, zoneData)
    local previous
    local activeZones = {}
    for _, zoneKey in ipairs(zoneOrder) do
        local zone = zoneData[zoneKey]
        if zone then
            local ctl = self.controls.zones[zoneKey] or self:CreateZoneControl(zoneKey)
            ctl:SetHidden(false)
            ctl:ClearAnchors()
            if not previous then
                ctl:SetAnchor(TOPLEFT, self.scroll.scrollChild, TOPLEFT, 0, 0)
                ctl:SetAnchor(TOPRIGHT, self.scroll.scrollChild, TOPRIGHT, 0, 0)
            else
                ctl:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, 8)
                ctl:SetAnchor(TOPRIGHT, previous, BOTTOMRIGHT, 0, 8)
            end
            previous = ctl
            self:SetupZoneControl(ctl, zone)
            activeZones[zoneKey] = true
        end
    end
    for key, ctl in pairs(self.controls.zones) do
        if not activeZones[key] then
            ctl:SetHidden(true)
            if ctl.body then
                self:ReleaseQuestControls(ctl.body)
                ctl.body:SetHidden(true)
            end
        end
    end
    return previous
end

function Tracker:ReleaseQuestControls(body)
    if not body or not body.questControls then
        return
    end
    for _, questCtl in ipairs(body.questControls) do
        questCtl:SetHidden(true)
        if questCtl.body and questCtl.body.objectiveControls then
            for _, obj in ipairs(questCtl.body.objectiveControls) do
                obj:SetHidden(true)
            end
        end
    end
end

local function createQuestControl(parent)
    local container = CreateControl(nil, parent, CT_CONTROL)
    container:SetResizeToFitDescendents(true)
    container:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, 0)
    container:SetAnchor(TOPRIGHT, parent, TOPRIGHT, 0, 0)

    local header = ensureHeader(container)
    header:ClearAnchors()
    header:SetAnchor(TOPLEFT, container, TOPLEFT, INDENT_QUEST, 0)
    header:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, 0)

    local body = ensureBody(container)
    body:ClearAnchors()
    body:SetAnchor(TOPLEFT, header, BOTTOMLEFT, 0, 0)
    body:SetAnchor(TOPRIGHT, header, BOTTOMRIGHT, 0, 0)

    container.header = header
    container.body = body
    return container
end

function Tracker:PopulateQuests(body, zoneData)
    body.questControls = body.questControls or {}
    local previous
    local usedCount = 0
    for _, questKey in ipairs(zoneData.order) do
        local questInfo = zoneData.quests[questKey]
        if questInfo then
            usedCount = usedCount + 1
            local questCtl = body.questControls[usedCount]
            if not questCtl then
                questCtl = createQuestControl(body)
                body.questControls[usedCount] = questCtl
            end
            questCtl:SetHidden(false)
            questCtl.questKey = questKey
            questCtl.questInfo = questInfo
            questCtl.header.label:SetText(questInfo.name or "")
            applyFont(questCtl.header.label, self.sv and self.sv.fonts and self.sv.fonts.quest)

            questCtl.header:SetHandler("OnMouseUp", function(_, button)
                if button == MOUSE_BUTTON_INDEX_LEFT then
                    self:ToggleCollapsed("quests", questKey)
                elseif button == MOUSE_BUTTON_INDEX_RIGHT then
                    self:ShowQuestContextMenu(questInfo)
                end
            end)
            questCtl.header:SetHandler("OnMouseEnter", function()
                self:ShowQuestTooltip(questCtl.header, questInfo)
            end)
            questCtl.header:SetHandler("OnMouseExit", function()
                self:HideQuestTooltip()
            end)

            local collapsed = self:IsCollapsed("quests", questKey)
            questCtl.body:SetHidden(collapsed)
            questCtl.header.arrow:SetTexture(collapsed and TEXTURE_ARROW_COLLAPSED or TEXTURE_ARROW_EXPANDED)

            if not collapsed then
                self:PopulateObjectives(questCtl.body, questInfo.objectives)
            else
                self:ReleaseObjectives(questCtl.body)
            end

            if previous then
                questCtl:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, 4)
                questCtl:SetAnchor(TOPRIGHT, previous, BOTTOMRIGHT, 0, 4)
            else
                questCtl:SetAnchor(TOPLEFT, body, TOPLEFT, 0, 0)
                questCtl:SetAnchor(TOPRIGHT, body, TOPRIGHT, 0, 0)
            end
            previous = questCtl
        end
    end
    for index = usedCount + 1, #body.questControls do
        local questCtl = body.questControls[index]
        questCtl:SetHidden(true)
        self:ReleaseObjectives(questCtl.body)
    end
end

function Tracker:PopulateObjectives(body, objectives)
    body.objectiveControls = body.objectiveControls or {}
    local previous
    local used = 0
    for _, text in ipairs(objectives or {}) do
        used = used + 1
        local row = body.objectiveControls[used]
        if not row then
            row = CreateControl(nil, body, CT_LABEL)
            row:SetAnchor(TOPLEFT, body, TOPLEFT, INDENT_OBJECTIVE, (used - 1) * (LIST_ENTRY_HEIGHT - 10))
            row:SetAnchor(RIGHT, body, RIGHT, -12, 0)
            row:SetHeight(LIST_ENTRY_HEIGHT - 6)
            row:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
            row:SetVerticalAlignment(TEXT_ALIGN_CENTER)
            body.objectiveControls[used] = row
        end
        row:SetHidden(false)
        row:SetText(string.format("• %s", text))
        applyFont(row, self.sv and self.sv.fonts and self.sv.fonts.task)
        if previous then
            row:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, 2)
            row:SetAnchor(TOPRIGHT, previous, BOTTOMRIGHT, 0, 2)
        else
            row:SetAnchor(TOPLEFT, body, TOPLEFT, INDENT_OBJECTIVE, 4)
            row:SetAnchor(TOPRIGHT, body, TOPRIGHT, -12, 4)
        end
        previous = row
    end
    for index = used + 1, #body.objectiveControls do
        body.objectiveControls[index]:SetHidden(true)
    end
end

function Tracker:ReleaseObjectives(body)
    if not body or not body.objectiveControls then
        return
    end
    for _, row in ipairs(body.objectiveControls) do
        row:SetHidden(true)
    end
end

function Tracker:PopulateAchievementBlock(previousAnchor)
    if not self.achievementBlock then
        local block = CreateControl(nil, self.scroll.scrollChild, CT_CONTROL)
        block:SetResizeToFitDescendents(true)
        block:SetAnchor(TOPLEFT, self.scroll.scrollChild, TOPLEFT, 0, 0)
        block:SetAnchor(TOPRIGHT, self.scroll.scrollChild, TOPRIGHT, 0, 0)
        block.header = ensureHeader(block)
        block.header:ClearAnchors()
        block.header:SetAnchor(TOPLEFT, block, TOPLEFT, INDENT_ZONE, 0)
        block.header:SetAnchor(TOPRIGHT, block, TOPRIGHT, 0, 0)
        block.body = ensureBody(block)
        block.body:ClearAnchors()
        block.body:SetAnchor(TOPLEFT, block.header, BOTTOMLEFT, 0, 0)
        block.body:SetAnchor(TOPRIGHT, block.header, BOTTOMRIGHT, 0, 0)
        self.achievementBlock = block
    end

    local block = self.achievementBlock
    local favorites = buildAchievementList()
    if #favorites == 0 then
        block:SetHidden(true)
        self:ReleaseAchievements(block.body)
        return previousAnchor
    end

    block:SetHidden(false)
    block:ClearAnchors()
    if previousAnchor then
        block:SetAnchor(TOPLEFT, previousAnchor, BOTTOMLEFT, 0, 12)
        block:SetAnchor(TOPRIGHT, previousAnchor, BOTTOMRIGHT, 0, 12)
    else
        block:SetAnchor(TOPLEFT, self.scroll.scrollChild, TOPLEFT, 0, 0)
        block:SetAnchor(TOPRIGHT, self.scroll.scrollChild, TOPRIGHT, 0, 0)
    end

    block.header.label:SetText("Errungenschaften")
    applyFont(block.header.label, self.sv and self.sv.fonts and self.sv.fonts.category)
    block.header:SetHandler("OnMouseUp", function(_, button)
        if button == MOUSE_BUTTON_INDEX_LEFT then
            self:ToggleCollapsed("zones", "achievements")
        end
    end)
    local collapsed = self:IsCollapsed("zones", "achievements")
    block.header.arrow:SetTexture(collapsed and TEXTURE_ARROW_COLLAPSED or TEXTURE_ARROW_EXPANDED)
    block.body:SetHidden(collapsed)
    if not collapsed then
        self:PopulateAchievements(block.body, favorites)
    else
        self:ReleaseAchievements(block.body)
    end
    return block
end

function Tracker:PopulateAchievements(body, list)
    body.achievementControls = body.achievementControls or {}
    local previous
    local used = 0
    for _, entry in ipairs(list) do
        used = used + 1
        local ctl = body.achievementControls[used]
        if not ctl then
            ctl = createQuestControl(body)
            body.achievementControls[used] = ctl
        end
        ctl:SetHidden(false)
        ctl.header.label:SetText(entry.name or "")
        applyFont(ctl.header.label, self.sv and self.sv.fonts and self.sv.fonts.achieve)
        ctl.header:SetHandler("OnMouseUp", function(_, button)
            if button == MOUSE_BUTTON_INDEX_LEFT then
                self:ToggleCollapsed("achieves", tostring(entry.id))
            elseif button == MOUSE_BUTTON_INDEX_RIGHT then
                self:ShowAchievementContextMenu(entry.id)
            end
        end)
        ctl.header:SetHandler("OnMouseEnter", function()
            self:ShowAchievementTooltip(ctl.header, entry.id)
        end)
        ctl.header:SetHandler("OnMouseExit", function()
            self:HideAchievementTooltip()
        end)
        local collapsed = self:IsCollapsed("achieves", tostring(entry.id))
        if self.sv and self.sv.behavior and self.sv.behavior.alwaysExpandAchievements then
            collapsed = false
            self:SetCollapsed("achieves", tostring(entry.id), false)
        end
        ctl.header.arrow:SetTexture(collapsed and TEXTURE_ARROW_COLLAPSED or TEXTURE_ARROW_EXPANDED)
        ctl.body:SetHidden(collapsed)
        if not collapsed then
            local objectives = buildAchievementObjectives(entry.id)
            self:PopulateAchievementObjectives(ctl.body, objectives)
        else
            self:ReleaseObjectives(ctl.body)
        end
        if previous then
            ctl:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, 4)
            ctl:SetAnchor(TOPRIGHT, previous, BOTTOMRIGHT, 0, 4)
        else
            ctl:SetAnchor(TOPLEFT, body, TOPLEFT, 0, 0)
            ctl:SetAnchor(TOPRIGHT, body, TOPRIGHT, 0, 0)
        end
        previous = ctl
    end
    for index = used + 1, #body.achievementControls do
        local ctl = body.achievementControls[index]
        ctl:SetHidden(true)
        self:ReleaseObjectives(ctl.body)
    end
end

function Tracker:PopulateAchievementObjectives(body, objectives)
    body.objectiveControls = body.objectiveControls or {}
    local previous
    local used = 0
    for _, text in ipairs(objectives or {}) do
        used = used + 1
        local row = body.objectiveControls[used]
        if not row then
            row = CreateControl(nil, body, CT_LABEL)
            body.objectiveControls[used] = row
        end
        row:SetHidden(false)
        row:SetAnchor(TOPLEFT, previous or body, previous and BOTTOMLEFT or TOPLEFT, previous and 0 or INDENT_OBJECTIVE, previous and 2 or 4)
        row:SetAnchor(TOPRIGHT, previous or body, previous and BOTTOMRIGHT or TOPRIGHT, previous and 0 or -12, previous and 2 or 4)
        row:SetHeight(LIST_ENTRY_HEIGHT - 6)
        row:SetText(string.format("• %s", text))
        applyFont(row, self.sv and self.sv.fonts and self.sv.fonts.achieveTask)
        previous = row
    end
    for index = used + 1, #body.objectiveControls do
        body.objectiveControls[index]:SetHidden(true)
    end
end

function Tracker:ReleaseAchievements(body)
    if not body or not body.achievementControls then
        return
    end
    for _, ctl in ipairs(body.achievementControls) do
        ctl:SetHidden(true)
        self:ReleaseObjectives(ctl.body)
    end
end

function Tracker:ShowQuestTooltip(control, questInfo)
    if not self:IsTooltipsEnabled() then
        return
    end
    if not (InformationTooltip and InitializeTooltip and ClearTooltip and questInfo) then
        return
    end
    local anchor, relative, offsetX = computeTooltipAnchor(control)
    ClearTooltip(InformationTooltip)
    InitializeTooltip(InformationTooltip, control, anchor, offsetX, 0, relative)
    if questInfo.name and questInfo.name ~= "" then
        InformationTooltip:AddLine(questInfo.name, "ZoFontHeader2")
    end
    local stepText = questInfo.trackerText ~= "" and questInfo.trackerText or questInfo.stepText
    if stepText and stepText ~= "" then
        InformationTooltip:AddLine(stepText, "ZoFontGame")
    end
    for _, objective in ipairs(questInfo.objectives or {}) do
        InformationTooltip:AddLine(string.format("• %s", objective), "ZoFontGameSmall")
    end
    if questInfo.zoneName and questInfo.zoneName ~= "" then
        if ZO_Tooltip_AddDivider then
            ZO_Tooltip_AddDivider(InformationTooltip)
        end
        InformationTooltip:AddLine(string.format("Zone: %s", questInfo.zoneName), "ZoFontGameSmall")
    end
end

function Tracker:HideQuestTooltip()
    if InformationTooltip and ClearTooltip then
        ClearTooltip(InformationTooltip)
    end
end

function Tracker:ShowAchievementTooltip(control, achievementId)
    if not self:IsTooltipsEnabled() then
        return
    end
    if AchievementTooltip and InitializeTooltip and ClearTooltip then
        local anchor, relative, offsetX = computeTooltipAnchor(control)
        ClearTooltip(AchievementTooltip)
        InitializeTooltip(AchievementTooltip, control, anchor, offsetX, 0, relative)
        if AchievementTooltip.SetAchievement then
            AchievementTooltip:SetAchievement(achievementId)
        elseif AchievementTooltip.SetAchievementId then
            AchievementTooltip:SetAchievementId(achievementId)
        else
            local name, description = safeCall(GetAchievementInfo, achievementId)
            AchievementTooltip:AddLine(sanitizeText(name or ""), "ZoFontHeader2")
            AchievementTooltip:AddLine(sanitizeText(description or ""), "ZoFontGame")
        end
    elseif InformationTooltip and InitializeTooltip and ClearTooltip then
        local anchor, relative, offsetX = computeTooltipAnchor(control)
        ClearTooltip(InformationTooltip)
        InitializeTooltip(InformationTooltip, control, anchor, offsetX, 0, relative)
        local name, description = safeCall(GetAchievementInfo, achievementId)
        InformationTooltip:AddLine(sanitizeText(name or ""), "ZoFontHeader2")
        InformationTooltip:AddLine(sanitizeText(description or ""), "ZoFontGame")
    end
end

function Tracker:HideAchievementTooltip()
    if AchievementTooltip and ClearTooltip then
        ClearTooltip(AchievementTooltip)
    elseif InformationTooltip and ClearTooltip then
        ClearTooltip(InformationTooltip)
    end
end

function Tracker:Rebuild()
    if not self:IsEnabled() then
        self:ApplyCombatVisibility()
        return
    end
    local zoneOrder, zoneData = getQuestData()
    local nextQuestHistory = {}
    if self.sv then
        self:EnsureCollapseState()
        local questStates = self.sv.collapseState and self.sv.collapseState.quests
        for _, zone in pairs(zoneData) do
            if zone and zone.quests then
                for _, questKey in ipairs(zone.order) do
                    local questInfo = zone.quests[questKey]
                    local questId = questInfo and questInfo.questId
                    if questId and questId ~= 0 then
                        local previousKey = self.state.questKeyHistory and self.state.questKeyHistory[questId]
                        nextQuestHistory[questId] = questKey
                        if questStates and previousKey and previousKey ~= questKey then
                            if questStates[questKey] == nil and questStates[previousKey] ~= nil then
                                questStates[questKey] = questStates[previousKey]
                            end
                            questStates[previousKey] = nil
                        end
                    end
                end
            end
        end
    end
    local lastControl = self:PopulateZones(zoneOrder, zoneData)
    lastControl = self:PopulateAchievementBlock(lastControl)
    self.state.questKeyHistory = nextQuestHistory
    self:UpdateSizing()
    self:ApplyCombatVisibility()
end

function Tracker:UpdateSizing()
    if not self.control then
        return
    end
    local pos = self.sv and self.sv.pos
    if not pos then
        return
    end
    local autoV = self.sv and self.sv.behavior and self.sv.behavior.autoGrowV
    local autoH = self.sv and self.sv.behavior and self.sv.behavior.autoGrowH
    if autoV or autoH then
        local contentHeight = (self.scroll.scrollChild:GetHeight() or 0) + 16
        local contentWidth = self:MeasureContentWidth() + 16
        if autoV then
            local screenHeight = GuiRoot and GuiRoot:GetHeight() or 0
            if screenHeight == 0 then
                screenHeight = 1080
            end
            local newHeight = math.min(contentHeight, math.max(screenHeight - 40, 300))
            self.control:SetHeight(newHeight)
            pos.height = newHeight
        end
        if autoH then
            local screenWidth = GuiRoot and GuiRoot:GetWidth() or 0
            if screenWidth == 0 then
                screenWidth = 1920
            end
            local newWidth = math.min(contentWidth, math.max(screenWidth - 40, 280))
            self.control:SetWidth(newWidth)
            pos.width = newWidth
        end
    else
        self.control:SetDimensions(pos.width or 360, pos.height or 420)
    end
end

function Tracker:MeasureContentWidth()
    if not (self.scroll and self.scroll.scrollChild) then
        return 0
    end
    local child = self.scroll.scrollChild
    local count = child:GetNumChildren() or 0
    local maxWidth = 0
    for index = 1, count do
        local ctrl = child:GetChild(index)
        if ctrl and not ctrl:IsHidden() then
            maxWidth = math.max(maxWidth, ctrl:GetWidth())
        end
    end
    return math.max(maxWidth, self.control and self.control:GetWidth() or 0)
end

function Tracker:AttachFavoritesHooks()
    local data = Nvk3UT and Nvk3UT.FavoritesData
    if not data or data._nvk3ut_trackerHooked then
        return
    end
    local function wrap(methodName)
        local base = data[methodName]
        if type(base) ~= "function" then
            return
        end
        data[methodName] = function(...)
            local before = base(...)
            zo_callLater(function()
                self:Refresh(true)
            end, 10)
            return before
        end
    end
    wrap("Add")
    wrap("Remove")
    wrap("Toggle")
    wrap("MigrateScope")
    data._nvk3ut_trackerHooked = true
end

function Tracker:ShowQuestContextMenu(questInfo)
    if not questInfo then
        return
    end
    ClearMenu()
    AddCustomMenuItem("Im Questlog öffnen", function()
        self:OpenQuestJournal(questInfo.journalIndex)
    end)
    AddCustomMenuItem("Teilen", function()
        if ShareQuest then
            ShareQuest(questInfo.journalIndex)
        end
    end)
    if self:CanShowOnMap(questInfo.journalIndex) then
        AddCustomMenuItem("Auf der Karte anzeigen", function()
            self:ShowQuestOnMap(questInfo.journalIndex)
        end)
    end
    AddCustomMenuItem("Abbrechen", function()
        self:ConfirmAbandon(questInfo.journalIndex)
    end)
    ShowMenu()
end

function Tracker:ShowAchievementContextMenu(achievementId)
    if not achievementId then
        return
    end
    ClearMenu()
    AddCustomMenuItem("Im Errungenschaftsmenü anzeigen", function()
        self:OpenAchievement(achievementId)
    end)
    AddCustomMenuItem("Aus Favoriten entfernen", function()
        local Favorites = Nvk3UT and Nvk3UT.Favorites
        if Favorites and Favorites.Remove then
            Favorites.Remove(achievementId)
        end
        self:Refresh(true)
    end)
    ShowMenu()
end

function Tracker:ShowZoneContextMenu(zoneData)
    -- placeholder for future, currently no specific zone actions
end

function Tracker:OpenQuestJournal(journalIndex)
    if not journalIndex then
        return
    end
    if SCENE_MANAGER then
        SCENE_MANAGER:Show("journal")
    end
    zo_callLater(function()
        if QUEST_JOURNAL_MANAGER then
            if QUEST_JOURNAL_MANAGER.FocusQuestWithIndex then
                QUEST_JOURNAL_MANAGER:FocusQuestWithIndex(journalIndex)
            elseif QUEST_JOURNAL_MANAGER.SelectQuestWithIndex then
                QUEST_JOURNAL_MANAGER:SelectQuestWithIndex(journalIndex)
            elseif QUEST_JOURNAL_MANAGER.SetSelectedQuest then
                QUEST_JOURNAL_MANAGER:SetSelectedQuest(journalIndex)
            end
        end
    end, 100)
end

function Tracker:CanShowOnMap(journalIndex)
    if QUEST_JOURNAL_MANAGER then
        if QUEST_JOURNAL_MANAGER.ShowOnMap then
            return true
        end
        if QUEST_JOURNAL_MANAGER.MapIndex then
            return true
        end
    end
    if type(SetTrackedJournalQuestIndex) == "function" then
        return true
    end
    return false
end

function Tracker:ShowQuestOnMap(journalIndex)
    if QUEST_JOURNAL_MANAGER then
        if QUEST_JOURNAL_MANAGER.ShowOnMap then
            QUEST_JOURNAL_MANAGER:ShowOnMap(journalIndex)
            return
        end
        if QUEST_JOURNAL_MANAGER.ShowOnMapByQuestIndex then
            QUEST_JOURNAL_MANAGER:ShowOnMapByQuestIndex(journalIndex)
            return
        end
    end
    if type(SetTrackedJournalQuestIndex) == "function" then
        SetTrackedJournalQuestIndex(journalIndex)
    end
end

function Tracker:ConfirmAbandon(journalIndex)
    if QUEST_JOURNAL_MANAGER and QUEST_JOURNAL_MANAGER.ConfirmAbandonQuest then
        QUEST_JOURNAL_MANAGER:ConfirmAbandonQuest(journalIndex)
        return
    end
    if ZO_Dialogs and ZO_Dialogs_ShowDialog then
        ZO_Dialogs_ShowDialog("CONFIRM_ABANDON_QUEST", { journalIndex = journalIndex })
    end
end

function Tracker:OpenAchievement(achievementId)
    if SCENE_MANAGER then
        SCENE_MANAGER:Show("achievements")
    end
    zo_callLater(function()
        if ACHIEVEMENTS then
            if ACHIEVEMENTS.ShowAchievement then
                ACHIEVEMENTS:ShowAchievement(achievementId)
            elseif ACHIEVEMENTS.SelectAchievement then
                ACHIEVEMENTS:SelectAchievement(achievementId)
            elseif ACHIEVEMENTS.ForceSelectAchievement then
                ACHIEVEMENTS:ForceSelectAchievement(achievementId)
            end
        end
    end, 100)
end

function Tracker:SetEnabled(value)
    if not self.initialized then
        self:Init()
    end
    if self.sv then
        self.sv.enabled = value and true or false
    end
    if value then
        self:Enable()
    else
        self:Disable()
    end
end

function Tracker:SetShowQuests(value)
    if not self.sv then
        return
    end
    self.sv.showQuests = value and true or false
    self:Refresh(false)
end

function Tracker:SetShowAchievements(value)
    if not self.sv then
        return
    end
    self.sv.showAchievements = value and true or false
    self:Refresh(false)
end

function Tracker:SetHideDefault(value)
    if not self.sv then
        return
    end
    self.sv.behavior = self.sv.behavior or {}
    self.sv.behavior.hideDefault = value and true or false
    self:ApplyDefaultTrackerVisibility()
end

function Tracker:SetHideInCombat(value)
    if not self.sv then
        return
    end
    self.sv.behavior = self.sv.behavior or {}
    self.sv.behavior.hideInCombat = value and true or false
    self:ApplyCombatVisibility()
end

function Tracker:SetLocked(value)
    if not self.sv then
        return
    end
    self.sv.behavior = self.sv.behavior or {}
    self.sv.behavior.locked = value and true or false
    self:ApplyLockState()
    self:ApplyBackground()
end

function Tracker:SetAutoGrowV(value)
    if not self.sv then
        return
    end
    self.sv.behavior = self.sv.behavior or {}
    self.sv.behavior.autoGrowV = value and true or false
    self:UpdateSizing()
end

function Tracker:SetAutoGrowH(value)
    if not self.sv then
        return
    end
    self.sv.behavior = self.sv.behavior or {}
    self.sv.behavior.autoGrowH = value and true or false
    self:UpdateSizing()
end

function Tracker:SetAutoExpandNewQuests(value)
    if not self.sv then
        return
    end
    self.sv.behavior = self.sv.behavior or {}
    self.sv.behavior.autoExpandNewQuests = value and true or false
end

function Tracker:SetAlwaysExpandAchievements(value)
    if not self.sv then
        return
    end
    self.sv.behavior = self.sv.behavior or {}
    self.sv.behavior.alwaysExpandAchievements = value and true or false
    if value then
        self:EnsureCollapseState()
        local achieves = self.sv.collapseState.achieves
        for id, state in pairs(achieves) do
            if state then
                achieves[id] = false
            end
        end
    end
    self:Refresh(false)
end

function Tracker:SetTooltipsEnabled(value)
    if not self.sv then
        return
    end
    self.sv.behavior = self.sv.behavior or {}
    self.sv.behavior.tooltips = value and true or false
    if not value then
        self:HideTooltips()
    end
end

function Tracker:SetBackgroundEnabled(value)
    if not self.sv then
        return
    end
    self.sv.background = self.sv.background or {}
    self.sv.background.enabled = value and true or false
    self:ApplyBackground()
end

function Tracker:SetBackgroundAlpha(value)
    if not self.sv then
        return
    end
    self.sv.background = self.sv.background or {}
    self.sv.background.alpha = value
    self:ApplyBackground()
end

function Tracker:SetBackgroundHideWhenLocked(value)
    if not self.sv then
        return
    end
    self.sv.background = self.sv.background or {}
    self.sv.background.hideWhenLocked = value and true or false
    self:ApplyBackground()
end

function Tracker:SetFontConfig(key, config)
    if not self.sv then
        return
    end
    self.sv.fonts = self.sv.fonts or {}
    self.sv.fonts[key] = config
    self:Refresh(false)
end

function Tracker:SetThrottleMs(value)
    if not self.sv then
        return
    end
    self.sv.throttleMs = math.max(0, tonumber(value) or 0)
end

return Tracker
