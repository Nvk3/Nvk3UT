local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}
Nvk3UT.UI = Nvk3UT.UI or {}

local TrackerHost = {}
TrackerHost.__index = TrackerHost

local ROOT_CONTROL_NAME = addonName .. "_UI_Root"
local QUEST_CONTAINER_NAME = addonName .. "_QuestContainer"
local ACHIEVEMENT_CONTAINER_NAME = addonName .. "_AchievementContainer"
local SCROLL_CONTAINER_NAME = addonName .. "_ScrollContainer"
local SCROLL_CONTENT_NAME = SCROLL_CONTAINER_NAME .. "_Content"
local SCROLLBAR_NAME = SCROLL_CONTAINER_NAME .. "_ScrollBar"

local DEFAULT_APPEARANCE = {
    enabled = true,
    alpha = 0.35,
    edgeEnabled = true,
    edgeAlpha = 0.5,
    padding = 0,
    cornerRadius = 0,
    theme = "dark",
}

local THEME_COLORS = {
    dark = {
        center = { 0, 0, 0 },
        edge = { 0, 0, 0 },
    },
    light = {
        center = { 1, 1, 1 },
        edge = { 1, 1, 1 },
    },
    transparent = {
        center = { 0, 0, 0 },
        edge = { 0, 0, 0 },
    },
}

local DEFAULT_BACKDROP_TEXTURE = {
    texture = "EsoUI/Art/Tooltips/UI-Border.dds",
    tileSize = 64,
    edgeWidth = 16,
}

local DEFAULT_WINDOW = {
    left = 200,
    top = 200,
    width = 360,
    height = 640,
    locked = false,
}

local MIN_WIDTH = 260
local MIN_HEIGHT = 240
local RESIZE_HANDLE_SIZE = 12
local SCROLLBAR_WIDTH = 18

local LEFT_MOUSE_BUTTON = _G.MOUSE_BUTTON_INDEX_LEFT or 1

local state = {
    initialized = false,
    root = nil,
    scrollContainer = nil,
    scrollContent = nil,
    scrollbar = nil,
    scrollContentRightOffset = 0,
    questContainer = nil,
    achievementContainer = nil,
    backdrop = nil,
    window = nil,
    appearance = nil,
    anchorWarnings = {
        questMissing = false,
        achievementMissing = false,
    },
}

local function clamp(value, minimum, maximum)
    if value == nil then
        return minimum
    end
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function cloneTable(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = cloneTable(entry)
    end
    return copy
end

local function getSavedVars()
    return Nvk3UT and Nvk3UT.sv
end

local function migrateAppearanceSettings(target)
    local sv = getSavedVars()
    if not sv then
        return
    end

    local quest = sv.QuestTracker and sv.QuestTracker.background
    local achievement = sv.AchievementTracker and sv.AchievementTracker.background

    local function applySource(source)
        if type(source) ~= "table" then
            return false
        end

        local used = false
        if source.enabled ~= nil and target.enabled == nil then
            target.enabled = source.enabled ~= false
            used = true
        end
        if source.alpha ~= nil and target.alpha == nil then
            target.alpha = clamp(tonumber(source.alpha) or DEFAULT_APPEARANCE.alpha, 0, 1)
            used = true
        end
        if source.edgeAlpha ~= nil and target.edgeAlpha == nil then
            target.edgeAlpha = clamp(tonumber(source.edgeAlpha) or DEFAULT_APPEARANCE.edgeAlpha, 0, 1)
            used = true
        end
        if source.padding ~= nil and target.padding == nil then
            local padding = tonumber(source.padding) or DEFAULT_APPEARANCE.padding
            target.padding = math.max(0, math.floor(padding + 0.5))
            used = true
        end
        return used
    end

    local migrated = false
    migrated = applySource(quest) or migrated
    migrated = applySource(achievement) or migrated

    if migrated then
        target.edgeEnabled = target.edgeEnabled ~= false and (target.edgeAlpha or DEFAULT_APPEARANCE.edgeAlpha) > 0
    end
end

local function ensureAppearanceSettings()
    local sv = getSavedVars()
    if not sv then
        return cloneTable(DEFAULT_APPEARANCE)
    end

    sv.General = sv.General or {}
    sv.General.Appearance = sv.General.Appearance or {}

    local appearance = sv.General.Appearance
    if not appearance._migrated then
        migrateAppearanceSettings(appearance)
        appearance._migrated = true
    end

    if appearance.enabled == nil then
        appearance.enabled = DEFAULT_APPEARANCE.enabled
    end
    appearance.alpha = clamp(tonumber(appearance.alpha) or DEFAULT_APPEARANCE.alpha, 0, 1)
    if appearance.edgeEnabled == nil then
        appearance.edgeEnabled = DEFAULT_APPEARANCE.edgeEnabled
    else
        appearance.edgeEnabled = appearance.edgeEnabled ~= false
    end
    appearance.edgeAlpha = clamp(tonumber(appearance.edgeAlpha) or DEFAULT_APPEARANCE.edgeAlpha, 0, 1)
    local padding = tonumber(appearance.padding)
    if padding == nil then
        padding = DEFAULT_APPEARANCE.padding
    end
    appearance.padding = math.max(0, math.floor(padding + 0.5))
    local cornerRadius = tonumber(appearance.cornerRadius)
    if cornerRadius == nil then
        cornerRadius = DEFAULT_APPEARANCE.cornerRadius
    end
    appearance.cornerRadius = math.max(0, math.floor(cornerRadius + 0.5))
    if type(appearance.theme) ~= "string" or appearance.theme == "" then
        appearance.theme = DEFAULT_APPEARANCE.theme
    else
        appearance.theme = string.lower(appearance.theme)
    end

    return appearance
end

local function ensureWindowSettings()
    local sv = getSavedVars()
    if not sv then
        return cloneTable(DEFAULT_WINDOW)
    end

    sv.General = sv.General or {}
    sv.General.window = sv.General.window or {}

    local window = sv.General.window
    if type(window.left) ~= "number" then
        window.left = tonumber(window.left) or DEFAULT_WINDOW.left
    end
    if type(window.top) ~= "number" then
        window.top = tonumber(window.top) or DEFAULT_WINDOW.top
    end
    if type(window.width) ~= "number" then
        window.width = tonumber(window.width) or DEFAULT_WINDOW.width
    end
    if type(window.height) ~= "number" then
        window.height = tonumber(window.height) or DEFAULT_WINDOW.height
    end
    if window.locked == nil then
        window.locked = DEFAULT_WINDOW.locked
    end

    return window
end

local function clampWindowToScreen(width, height)
    if not GuiRoot then
        return
    end

    local rootWidth = GuiRoot:GetWidth() or 0
    local rootHeight = GuiRoot:GetHeight() or 0

    local window = state.window
    if not window then
        return
    end

    local maxLeft = math.max(0, rootWidth - width)
    local maxTop = math.max(0, rootHeight - height)

    window.left = math.min(math.max(window.left or 0, 0), maxLeft)
    window.top = math.min(math.max(window.top or 0, 0), maxTop)
end

local function saveWindowPosition()
    if not (state.root and state.window) then
        return
    end

    local left = state.root:GetLeft() or state.window.left or 0
    local top = state.root:GetTop() or state.window.top or 0

    state.window.left = math.floor(left + 0.5)
    state.window.top = math.floor(top + 0.5)
end

local function saveWindowSize()
    if not (state.root and state.window) then
        return
    end

    local width = math.max(state.root:GetWidth() or state.window.width or MIN_WIDTH, MIN_WIDTH)
    local height = math.max(state.root:GetHeight() or state.window.height or MIN_HEIGHT, MIN_HEIGHT)

    state.window.width = math.floor(width + 0.5)
    state.window.height = math.floor(height + 0.5)
end

local function debugLog(...)
    local sv = getSavedVars()
    if not (sv and sv.debug) then
        return
    end

    local prefix = string.format("[%s]", addonName .. ".TrackerHost")
    if d then
        d(prefix, ...)
    elseif print then
        print(prefix, ...)
    end
end

local function adjustScroll(delta)
    local scrollbar = state.scrollbar
    if not (scrollbar and scrollbar.GetMinMax and scrollbar.SetValue) then
        return
    end

    local minValue, maxValue = scrollbar:GetMinMax()
    if not (minValue and maxValue) then
        return
    end

    local current = scrollbar.GetValue and scrollbar:GetValue() or 0
    local step = 48
    local target = current - (delta * step)
    if target < minValue then
        target = minValue
    elseif target > maxValue then
        target = maxValue
    end

    scrollbar:SetValue(target)
end

local function refreshScroll()
    local scrollContainer = state.scrollContainer
    local scrollContent = state.scrollContent
    local scrollbar = state.scrollbar

    if not (scrollContainer and scrollContent and scrollbar) then
        return
    end

    if scrollContent.SetResizeToFitDescendents then
        scrollContent:SetResizeToFitDescendents(true)
    end

    local viewportHeight = scrollContainer:GetHeight() or 0
    local contentHeight = scrollContent:GetHeight() or 0
    local maxOffset = math.max((contentHeight or 0) - viewportHeight, 0)
    local showScrollbar = maxOffset > 0
    local desiredRightOffset = showScrollbar and -SCROLLBAR_WIDTH or 0

    if scrollContainer.SetScrollExtents then
        scrollContainer:SetScrollExtents(0, 0, 0, maxOffset)
    end

    if scrollbar.SetMinMax then
        scrollbar:SetMinMax(0, maxOffset)
    end

    local current = scrollbar.GetValue and scrollbar:GetValue() or 0
    current = math.max(0, math.min(current, maxOffset))

    if scrollbar.SetHidden then
        scrollbar:SetHidden(not showScrollbar)
    end

    if state.scrollContentRightOffset ~= desiredRightOffset then
        state.scrollContentRightOffset = desiredRightOffset
        applyViewportPadding()
    end

    if not showScrollbar then
        current = 0
    end

    if scrollbar.SetValue then
        scrollbar:SetValue(current)
    end

    if scrollContainer.SetVerticalScroll then
        scrollContainer:SetVerticalScroll(current)
    end
end

local function anchorContainers()
    local parent = state.scrollContent or state.root
    local questContainer = state.questContainer
    local achievementContainer = state.achievementContainer

    if not (parent and questContainer) then
        if not questContainer and not state.anchorWarnings.questMissing then
            debugLog("Quest container not ready for anchoring")
            state.anchorWarnings.questMissing = true
        end
        return
    end

    questContainer:ClearAnchors()
    questContainer:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, 0)
    questContainer:SetAnchor(TOPRIGHT, parent, TOPRIGHT, 0, 0)
    state.anchorWarnings.questMissing = false

    if achievementContainer then
        achievementContainer:ClearAnchors()
        achievementContainer:SetAnchor(TOPLEFT, questContainer, BOTTOMLEFT, 0, 0)
        achievementContainer:SetAnchor(TOPRIGHT, questContainer, BOTTOMRIGHT, 0, 0)
        state.anchorWarnings.achievementMissing = false
    elseif not state.anchorWarnings.achievementMissing then
        debugLog("Achievement container not ready for anchoring")
        state.anchorWarnings.achievementMissing = true
    end
end

local function updateSectionLayout()
    if not state.root then
        return
    end

    anchorContainers()
end

local function applyWindowLock()
    if not (state.root and state.window) then
        return
    end

    local locked = state.window.locked == true
    state.root:SetMovable(not locked)
    state.root:SetResizeHandleSize(locked and 0 or RESIZE_HANDLE_SIZE)
end

local function applyWindowGeometry()
    if not (state.root and state.window) then
        return
    end

    local width = math.max(tonumber(state.window.width) or DEFAULT_WINDOW.width, MIN_WIDTH)
    local height = math.max(tonumber(state.window.height) or DEFAULT_WINDOW.height, MIN_HEIGHT)
    clampWindowToScreen(width, height)

    local left = tonumber(state.window.left) or DEFAULT_WINDOW.left
    local top = tonumber(state.window.top) or DEFAULT_WINDOW.top

    state.window.left = left
    state.window.top = top
    state.window.width = width
    state.window.height = height

    state.root:ClearAnchors()
    state.root:SetAnchor(TOPLEFT, GuiRoot or state.root:GetParent(), TOPLEFT, left, top)
    state.root:SetDimensions(width, height)
    state.root:SetHidden(false)
    state.root:SetClampedToScreen(true)
end

local function applyWindowSettings()
    state.window = ensureWindowSettings()
    state.appearance = ensureAppearanceSettings()

    if not state.root then
        return
    end

    applyWindowGeometry()
    applyWindowLock()
    updateSectionLayout()
    refreshScroll()
end

local function createBackdrop()
    if state.backdrop or not (state.root and WINDOW_MANAGER) then
        return
    end

    local control = WINDOW_MANAGER:CreateControl(nil, state.root, CT_BACKDROP)
    control:SetAnchorFill()
    control:SetDrawLayer(DL_BACKGROUND)
    control:SetDrawTier(DT_LOW)
    control:SetDrawLevel(0)
    if control.SetExcludeFromResizeToFitExtents then
        control:SetExcludeFromResizeToFitExtents(true)
    end
    if control.SetEdgeTexture then
        control:SetEdgeTexture(
            DEFAULT_BACKDROP_TEXTURE.texture,
            DEFAULT_BACKDROP_TEXTURE.tileSize,
            DEFAULT_BACKDROP_TEXTURE.edgeWidth
        )
    end

    state.backdrop = control
end

local function createRootControl()
    if state.root or not WINDOW_MANAGER then
        return
    end

    local control = WINDOW_MANAGER:CreateTopLevelWindow(ROOT_CONTROL_NAME)
    if not control then
        return
    end

    control:SetMouseEnabled(true)
    control:SetMovable(true)
    control:SetClampedToScreen(true)
    control:SetResizeHandleSize(RESIZE_HANDLE_SIZE)
    if control.SetDimensionConstraints then
        control:SetDimensionConstraints(MIN_WIDTH, MIN_HEIGHT)
    end
    control:SetDrawLayer(DL_BACKGROUND)
    control:SetDrawTier(DT_LOW)
    control:SetDrawLevel(0)

    control:SetHandler("OnMouseDown", function(ctrl, button)
        if button ~= LEFT_MOUSE_BUTTON then
            return
        end
        if state.window and state.window.locked then
            return
        end
        ctrl:StartMoving()
    end)

    control:SetHandler("OnMouseUp", function(ctrl, button)
        if button == LEFT_MOUSE_BUTTON then
            ctrl:StopMovingOrResizing()
            saveWindowPosition()
        end
    end)

    control:SetHandler("OnMoveStop", function()
        saveWindowPosition()
    end)

    control:SetHandler("OnResizeStop", function()
        saveWindowSize()
        applyWindowGeometry()
        updateSectionLayout()
        refreshScroll()
    end)

    control:SetHandler("OnMouseWheel", function(_, delta)
        adjustScroll(delta)
    end)

    state.root = control
    Nvk3UT.UI.Root = control

    createBackdrop()
end

local function createScrollContainer()
    if state.scrollContainer or not (state.root and WINDOW_MANAGER) then
        return
    end

    local scrollContainer = WINDOW_MANAGER:CreateControl(SCROLL_CONTAINER_NAME, state.root, CT_SCROLL)
    if not scrollContainer then
        return
    end

    scrollContainer:SetMouseEnabled(true)
    scrollContainer:SetClampedToScreen(false)
    scrollContainer:SetAnchor(TOPLEFT, state.root, TOPLEFT, 0, 0)
    scrollContainer:SetAnchor(BOTTOMRIGHT, state.root, BOTTOMRIGHT, 0, 0)

    local scrollContent = WINDOW_MANAGER:CreateControl(SCROLL_CONTENT_NAME, scrollContainer, CT_CONTROL)
    scrollContent:SetMouseEnabled(false)
    scrollContent:SetAnchor(TOPLEFT, scrollContainer, TOPLEFT, 0, 0)
    scrollContent:SetAnchor(TOPRIGHT, scrollContainer, TOPRIGHT, 0, 0)
    scrollContent:SetResizeToFitDescendents(true)

    local scrollbar = WINDOW_MANAGER:CreateControl(SCROLLBAR_NAME, state.root, CT_SCROLLBAR)
    scrollbar:SetMouseEnabled(true)
    scrollbar:SetAnchor(TOPRIGHT, state.root, TOPRIGHT, 0, 0)
    scrollbar:SetAnchor(BOTTOMRIGHT, state.root, BOTTOMRIGHT, 0, 0)
    scrollbar:SetWidth(SCROLLBAR_WIDTH)
    scrollbar:SetHidden(true)
    if scrollbar.SetAllowDragging then
        scrollbar:SetAllowDragging(true)
    end
    if scrollbar.SetValue then
        scrollbar:SetValue(0)
    end
    if scrollbar.SetStep then
        scrollbar:SetStep(32)
    end

    scrollbar:SetHandler("OnValueChanged", function(_, value)
        if state.scrollContainer and state.scrollContainer.SetVerticalScroll then
            state.scrollContainer:SetVerticalScroll(value)
        end
    end)

    scrollContainer:SetHandler("OnMouseWheel", function(_, delta)
        adjustScroll(delta)
    end)

    state.scrollContainer = scrollContainer
    state.scrollContent = scrollContent
    state.scrollbar = scrollbar
    state.scrollContentRightOffset = 0

    state.appearance = ensureAppearanceSettings()
    applyViewportPadding()
end

local function createContainers()
    if not (state.root and WINDOW_MANAGER) then
        return
    end

    createScrollContainer()

    local parent = state.scrollContent or state.root

    if parent and not state.questContainer then
        local questContainer = WINDOW_MANAGER:CreateControl(QUEST_CONTAINER_NAME, parent, CT_CONTROL)
        questContainer:SetMouseEnabled(false)
        questContainer:SetHandler("OnMouseWheel", function(_, delta)
            adjustScroll(delta)
        end)
        state.questContainer = questContainer
        Nvk3UT.UI.QuestContainer = questContainer
    elseif state.questContainer and state.questContainer.GetParent and state.questContainer:GetParent() ~= parent then
        state.questContainer:SetParent(parent)
    end

    if parent and not state.achievementContainer then
        local achievementContainer = WINDOW_MANAGER:CreateControl(ACHIEVEMENT_CONTAINER_NAME, parent, CT_CONTROL)
        achievementContainer:SetMouseEnabled(false)
        achievementContainer:SetHandler("OnMouseWheel", function(_, delta)
            adjustScroll(delta)
        end)
        state.achievementContainer = achievementContainer
        Nvk3UT.UI.AchievementContainer = achievementContainer
    elseif state.achievementContainer and state.achievementContainer.GetParent and state.achievementContainer:GetParent() ~= parent then
        state.achievementContainer:SetParent(parent)
    end

    anchorContainers()
    refreshScroll()
end

local function applyViewportPadding()
    local appearance = state.appearance or ensureAppearanceSettings()
    if not state.root then
        return
    end

    local padding = math.max(0, tonumber(appearance and appearance.padding) or 0)

    if state.scrollContainer then
        state.scrollContainer:ClearAnchors()
        state.scrollContainer:SetAnchor(TOPLEFT, state.root, TOPLEFT, padding, padding)
        state.scrollContainer:SetAnchor(BOTTOMRIGHT, state.root, BOTTOMRIGHT, -padding, -padding)
    end

    if state.scrollbar then
        state.scrollbar:ClearAnchors()
        state.scrollbar:SetAnchor(TOPRIGHT, state.root, TOPRIGHT, -padding, padding)
        state.scrollbar:SetAnchor(BOTTOMRIGHT, state.root, BOTTOMRIGHT, -padding, -padding)
        state.scrollbar:SetWidth(SCROLLBAR_WIDTH)
    end

    if state.scrollContent and state.scrollContainer then
        state.scrollContent:ClearAnchors()
        state.scrollContent:SetAnchor(TOPLEFT, state.scrollContainer, TOPLEFT, 0, 0)
        state.scrollContent:SetAnchor(
            TOPRIGHT,
            state.scrollContainer,
            TOPRIGHT,
            state.scrollContentRightOffset or 0,
            0
        )
        state.scrollContent:SetResizeToFitDescendents(true)
    end
end

local function applyAppearance()
    state.appearance = ensureAppearanceSettings()

    local appearance = state.appearance
    local backdrop = state.backdrop

    if backdrop then
        local enabled = appearance.enabled ~= false
        backdrop:SetHidden(not enabled)

        if enabled then
            local themeId = appearance.theme or DEFAULT_APPEARANCE.theme
            local theme = THEME_COLORS[themeId] or THEME_COLORS[DEFAULT_APPEARANCE.theme]
            local centerColor = theme.center
            local edgeColor = theme.edge

            local alpha = clamp(appearance.alpha, 0, 1)
            local edgeAlpha = clamp(appearance.edgeAlpha, 0, 1)
            if backdrop.SetCenterColor and centerColor then
                local r = centerColor[1] or 0
                local g = centerColor[2] or r
                local b = centerColor[3] or r
                backdrop:SetCenterColor(r, g, b, alpha)
            end
            if backdrop.SetEdgeColor and edgeColor then
                local effectiveEdgeAlpha = (appearance.edgeEnabled == false) and 0 or edgeAlpha
                local er = edgeColor[1] or 0
                local eg = edgeColor[2] or er
                local eb = edgeColor[3] or er
                backdrop:SetEdgeColor(er, eg, eb, effectiveEdgeAlpha)
            end
            if backdrop.SetCornerRadius then
                backdrop:SetCornerRadius(appearance.cornerRadius or 0)
            end
        end
    end

    applyViewportPadding()
    refreshScroll()
end

local function initModels(debugEnabled)
    if Nvk3UT.QuestModel and Nvk3UT.QuestModel.Init then
        pcall(Nvk3UT.QuestModel.Init, { debug = debugEnabled })
    end

    if Nvk3UT.AchievementModel and Nvk3UT.AchievementModel.Init then
        pcall(Nvk3UT.AchievementModel.Init, { debug = debugEnabled })
    end
end

local function initTrackers(debugEnabled)
    local sv = getSavedVars()
    if not sv then
        return
    end

    local questOpts = cloneTable(sv.QuestTracker or {})
    questOpts.debug = debugEnabled
    if Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.Init and state.questContainer then
        pcall(Nvk3UT.QuestTracker.Init, state.questContainer, questOpts)
    end

    local achievementOpts = cloneTable(sv.AchievementTracker or {})
    achievementOpts.debug = debugEnabled
    if Nvk3UT.AchievementTracker and Nvk3UT.AchievementTracker.Init and state.achievementContainer then
        pcall(Nvk3UT.AchievementTracker.Init, state.achievementContainer, achievementOpts)
    end
end

function TrackerHost.Init()
    if state.initialized then
        return
    end

    if not getSavedVars() then
        return
    end

    state.window = ensureWindowSettings()
    state.appearance = ensureAppearanceSettings()

    createRootControl()
    createContainers()
    applyWindowSettings()

    local debugEnabled = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug) == true

    initModels(debugEnabled)
    initTrackers(debugEnabled)

    TrackerHost.ApplySettings()
    TrackerHost.ApplyTheme()
    TrackerHost.Refresh()

    if Nvk3UT.UI and Nvk3UT.UI.BuildLAM then
        Nvk3UT.UI.BuildLAM()
    elseif Nvk3UT.LAM and Nvk3UT.LAM.Build then
        Nvk3UT.LAM.Build(addonName)
    end

    state.initialized = true

    TrackerHost.ApplyAppearance()
end

function TrackerHost.ApplySettings()
    if not getSavedVars() then
        return
    end

    applyWindowSettings()

    local sv = getSavedVars()

    if Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.ApplySettings then
        pcall(Nvk3UT.QuestTracker.ApplySettings, cloneTable(sv.QuestTracker or {}))
    end

    if Nvk3UT.AchievementTracker and Nvk3UT.AchievementTracker.ApplySettings then
        pcall(Nvk3UT.AchievementTracker.ApplySettings, cloneTable(sv.AchievementTracker or {}))
    end

    TrackerHost.ApplyAppearance()
end

function TrackerHost.ApplyTheme()
    if not getSavedVars() then
        return
    end

    local sv = getSavedVars()

    if Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.ApplyTheme then
        pcall(Nvk3UT.QuestTracker.ApplyTheme, cloneTable(sv.QuestTracker or {}))
    end

    if Nvk3UT.AchievementTracker and Nvk3UT.AchievementTracker.ApplyTheme then
        pcall(Nvk3UT.AchievementTracker.ApplyTheme, cloneTable(sv.AchievementTracker or {}))
    end

    updateSectionLayout()
    refreshScroll()
    TrackerHost.ApplyAppearance()
end

function TrackerHost.Refresh()
    if Nvk3UT.QuestTracker then
        if Nvk3UT.QuestTracker.RequestRefresh then
            pcall(Nvk3UT.QuestTracker.RequestRefresh)
        elseif Nvk3UT.QuestTracker.Refresh then
            pcall(Nvk3UT.QuestTracker.Refresh)
        end
    end

    if Nvk3UT.AchievementTracker then
        if Nvk3UT.AchievementTracker.RequestRefresh then
            pcall(Nvk3UT.AchievementTracker.RequestRefresh)
        elseif Nvk3UT.AchievementTracker.Refresh then
            pcall(Nvk3UT.AchievementTracker.Refresh)
        end
    end

    updateSectionLayout()
    TrackerHost.RefreshScroll()
end

function TrackerHost.ApplyAppearance()
    if not state.root then
        return
    end

    applyAppearance()
end

function TrackerHost.Shutdown()
    if Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.Shutdown then
        pcall(Nvk3UT.QuestTracker.Shutdown)
    end

    if Nvk3UT.AchievementTracker and Nvk3UT.AchievementTracker.Shutdown then
        pcall(Nvk3UT.AchievementTracker.Shutdown)
    end

    if Nvk3UT.QuestModel and Nvk3UT.QuestModel.Shutdown then
        pcall(Nvk3UT.QuestModel.Shutdown)
    end

    if Nvk3UT.AchievementModel and Nvk3UT.AchievementModel.Shutdown then
        pcall(Nvk3UT.AchievementModel.Shutdown)
    end

    if state.achievementContainer then
        state.achievementContainer:SetHidden(true)
        state.achievementContainer:SetParent(nil)
    end
    state.achievementContainer = nil
    Nvk3UT.UI.AchievementContainer = nil

    if state.questContainer then
        state.questContainer:SetHidden(true)
        state.questContainer:SetParent(nil)
    end
    state.questContainer = nil
    Nvk3UT.UI.QuestContainer = nil

    if state.scrollbar then
        state.scrollbar:SetHidden(true)
        state.scrollbar:SetParent(nil)
    end
    state.scrollbar = nil

    if state.scrollContent then
        state.scrollContent:SetParent(nil)
    end
    state.scrollContent = nil
    state.scrollContentRightOffset = 0

    if state.scrollContainer then
        state.scrollContainer:SetHandler("OnMouseWheel", nil)
        state.scrollContainer:SetParent(nil)
    end
    state.scrollContainer = nil

    if state.backdrop then
        state.backdrop:SetHidden(true)
        state.backdrop:SetParent(nil)
    end
    state.backdrop = nil

    if state.root then
        state.root:SetHandler("OnMouseDown", nil)
        state.root:SetHandler("OnMouseUp", nil)
        state.root:SetHandler("OnMoveStop", nil)
        state.root:SetHandler("OnResizeStop", nil)
        state.root:SetHandler("OnMouseWheel", nil)
        state.root:SetHidden(true)
        state.root:SetParent(nil)
    end
    state.root = nil
    Nvk3UT.UI.Root = nil

    if state.anchorWarnings then
        state.anchorWarnings.questMissing = false
        state.anchorWarnings.achievementMissing = false
    end

    state.appearance = nil
    state.initialized = false
end

Nvk3UT.TrackerHost = TrackerHost

TrackerHost.RefreshScroll = refreshScroll

return TrackerHost
