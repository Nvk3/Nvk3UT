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

local MIN_WIDTH = 260
local MIN_HEIGHT = 240
local RESIZE_HANDLE_SIZE = 12
local SCROLLBAR_WIDTH = 18

local DEFAULT_APPEARANCE = {
    enabled = true,
    alpha = 0.6,
    edgeEnabled = true,
    edgeAlpha = 0.65,
    edgeThickness = 2,
    padding = 12,
    cornerRadius = 0,
    theme = "dark",
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
    visible = true,
    clamp = true,
    onTop = false,
}

local DEFAULT_LAYOUT = {
    autoGrowV = true,
    autoGrowH = false,
    minWidth = MIN_WIDTH,
    minHeight = MIN_HEIGHT,
    maxWidth = 640,
    maxHeight = 900,
}

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
    layout = nil,
    appearance = nil,
    features = nil,
    anchorWarnings = {
        questMissing = false,
        achievementMissing = false,
    },
    previousDefaultQuestTrackerHidden = nil,
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
    local thickness = tonumber(appearance.edgeThickness)
    if thickness == nil then
        thickness = DEFAULT_APPEARANCE.edgeThickness
    end
    appearance.edgeThickness = math.max(1, math.floor(thickness + 0.5))
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

local function migrateHostSettings(general)
    local sv = getSavedVars()
    if not sv or type(general) ~= "table" then
        return
    end

    if general._hostMigrated then
        return
    end

    general.window = general.window or {}
    general.features = general.features or {}
    general.layout = general.layout or {}

    local quest = sv.QuestTracker
    local achievement = sv.AchievementTracker

    if general.window.locked == nil then
        if quest and quest.lock ~= nil then
            general.window.locked = quest.lock and true or false
        elseif achievement and achievement.lock ~= nil then
            general.window.locked = achievement.lock and true or false
        end
    end

    if general.features.hideDefaultQuestTracker == nil and quest and quest.hideDefault ~= nil then
        general.features.hideDefaultQuestTracker = quest.hideDefault and true or false
    end

    if general.layout.autoGrowV == nil then
        if quest and quest.autoGrowV ~= nil then
            general.layout.autoGrowV = quest.autoGrowV ~= false
        elseif achievement and achievement.autoGrowV ~= nil then
            general.layout.autoGrowV = achievement.autoGrowV ~= false
        end
    end

    if general.layout.autoGrowH == nil then
        if quest and quest.autoGrowH ~= nil then
            general.layout.autoGrowH = quest.autoGrowH and true or false
        elseif achievement and achievement.autoGrowH ~= nil then
            general.layout.autoGrowH = achievement.autoGrowH and true or false
        end
    end

    general._hostMigrated = true
end

local function ensureFeatureSettings()
    local sv = getSavedVars()
    if not sv then
        return { hideDefaultQuestTracker = false }
    end

    sv.General = sv.General or {}
    migrateHostSettings(sv.General)
    sv.General.features = sv.General.features or {}

    local features = sv.General.features
    if features.hideDefaultQuestTracker == nil then
        features.hideDefaultQuestTracker = false
    else
        features.hideDefaultQuestTracker = features.hideDefaultQuestTracker == true
    end

    return features
end

local function ensureLayoutSettings()
    local sv = getSavedVars()
    if not sv then
        return cloneTable(DEFAULT_LAYOUT)
    end

    sv.General = sv.General or {}
    migrateHostSettings(sv.General)
    sv.General.layout = sv.General.layout or {}

    local layout = sv.General.layout

    if layout.autoGrowV == nil then
        layout.autoGrowV = DEFAULT_LAYOUT.autoGrowV
    else
        layout.autoGrowV = layout.autoGrowV ~= false
    end

    if layout.autoGrowH == nil then
        layout.autoGrowH = DEFAULT_LAYOUT.autoGrowH
    else
        layout.autoGrowH = layout.autoGrowH == true
    end

    local minWidth = tonumber(layout.minWidth)
    if not minWidth then
        minWidth = DEFAULT_LAYOUT.minWidth
    end
    minWidth = math.max(MIN_WIDTH, math.floor(minWidth + 0.5))

    local maxWidth = tonumber(layout.maxWidth)
    if not maxWidth then
        maxWidth = DEFAULT_LAYOUT.maxWidth
    end
    maxWidth = math.max(minWidth, math.floor(maxWidth + 0.5))

    local minHeight = tonumber(layout.minHeight)
    if not minHeight then
        minHeight = DEFAULT_LAYOUT.minHeight
    end
    minHeight = math.max(MIN_HEIGHT, math.floor(minHeight + 0.5))

    local maxHeight = tonumber(layout.maxHeight)
    if not maxHeight then
        maxHeight = DEFAULT_LAYOUT.maxHeight
    end
    maxHeight = math.max(minHeight, math.floor(maxHeight + 0.5))

    layout.minWidth = minWidth
    layout.maxWidth = maxWidth
    layout.minHeight = minHeight
    layout.maxHeight = maxHeight

    return layout
end

local function ensureWindowSettings()
    local sv = getSavedVars()
    if not sv then
        return cloneTable(DEFAULT_WINDOW)
    end

    sv.General = sv.General or {}
    migrateHostSettings(sv.General)
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
    if window.visible == nil then
        window.visible = DEFAULT_WINDOW.visible
    end
    if window.clamp == nil then
        window.clamp = DEFAULT_WINDOW.clamp
    end
    if window.onTop == nil then
        window.onTop = DEFAULT_WINDOW.onTop
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

    if window.clamp == false then
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

    state.layout = ensureLayoutSettings()
    local layout = state.layout

    local minWidth = layout.minWidth or MIN_WIDTH
    local minHeight = layout.minHeight or MIN_HEIGHT
    local maxWidth = layout.maxWidth or math.max(minWidth, state.root:GetWidth() or minWidth)
    local maxHeight = layout.maxHeight or math.max(minHeight, state.root:GetHeight() or minHeight)

    local width = clamp(state.root:GetWidth() or state.window.width or minWidth, minWidth, maxWidth)
    local height = clamp(state.root:GetHeight() or state.window.height or minHeight, minHeight, maxHeight)

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

local function measureTrackerContent(container, trackerModule)
    if not container or (container.IsHidden and container:IsHidden()) then
        return 0, 0
    end

    local width = 0
    local height = 0

    if trackerModule and trackerModule.GetContentSize then
        local ok, trackerWidth, trackerHeight = pcall(trackerModule.GetContentSize)
        if ok then
            width = tonumber(trackerWidth) or 0
            height = tonumber(trackerHeight) or 0
        end
    end

    if (width <= 0 or height <= 0) then
        local holder = container.holder
        if holder and holder.GetWidth then
            width = math.max(width, holder:GetWidth() or 0)
            height = math.max(height, holder:GetHeight() or 0)
        else
            width = math.max(width, container.GetWidth and container:GetWidth() or 0)
            height = math.max(height, container.GetHeight and container:GetHeight() or 0)
        end
    end

    if width < 0 then
        width = 0
    end
    if height < 0 then
        height = 0
    end

    return width, height
end

local function measureContentSize()
    local totalHeight = 0
    local maxWidth = 0

    local questWidth, questHeight = measureTrackerContent(state.questContainer, Nvk3UT and Nvk3UT.QuestTracker)
    local achievementWidth, achievementHeight = measureTrackerContent(
        state.achievementContainer,
        Nvk3UT and Nvk3UT.AchievementTracker
    )

    if questHeight > 0 then
        totalHeight = totalHeight + questHeight
    end

    if achievementHeight > 0 then
        totalHeight = totalHeight + achievementHeight
    end

    maxWidth = math.max(maxWidth, questWidth, achievementWidth)

    return maxWidth, totalHeight
end

local function applyLayoutConstraints()
    if not (state.root and state.root.SetDimensionConstraints) then
        return
    end

    local layout = state.layout or ensureLayoutSettings()
    state.layout = layout

    local minWidth = layout.minWidth or MIN_WIDTH
    local minHeight = layout.minHeight or MIN_HEIGHT
    local maxWidth = layout.maxWidth
    local maxHeight = layout.maxHeight

    if maxWidth and maxHeight then
        state.root:SetDimensionConstraints(minWidth, minHeight, maxWidth, maxHeight)
    else
        state.root:SetDimensionConstraints(minWidth, minHeight)
    end
end

local function updateWindowGeometry()
    if not (state.root and state.window) then
        return
    end

    state.layout = ensureLayoutSettings()
    local layout = state.layout
    local appearance = state.appearance or ensureAppearanceSettings()
    state.appearance = appearance

    local padding = math.max(0, tonumber(appearance and appearance.padding) or 0)
    local contentWidth, contentHeight = measureContentSize()

    local minWidth = layout.minWidth or MIN_WIDTH
    local minHeight = layout.minHeight or MIN_HEIGHT
    local maxWidth = layout.maxWidth or minWidth
    local maxHeight = layout.maxHeight or minHeight

    local targetWidth = tonumber(state.window.width) or DEFAULT_WINDOW.width
    local targetHeight = tonumber(state.window.height) or DEFAULT_WINDOW.height

    targetWidth = clamp(targetWidth, minWidth, maxWidth)
    targetHeight = clamp(targetHeight, minHeight, maxHeight)

    if layout.autoGrowH then
        local desiredWidth = math.floor((contentWidth + (padding * 2)) + 0.5)
        targetWidth = clamp(desiredWidth, minWidth, maxWidth)
    end

    if layout.autoGrowV then
        local desiredHeight = math.floor((contentHeight + (padding * 2)) + 0.5)
        targetHeight = clamp(desiredHeight, minHeight, maxHeight)
    end

    state.window.width = targetWidth
    state.window.height = targetHeight

    applyLayoutConstraints()

    clampWindowToScreen(targetWidth, targetHeight)

    local anchorParent = GuiRoot or state.root:GetParent()
    state.root:ClearAnchors()
    state.root:SetAnchor(TOPLEFT, anchorParent, TOPLEFT, state.window.left or 0, state.window.top or 0)
    state.root:SetDimensions(targetWidth, targetHeight)
    state.root:SetClampedToScreen(state.window.clamp ~= false)
end

local function applyFeatureSettings()
    state.features = ensureFeatureSettings()
    local features = state.features

    if not (ZO_QuestTracker and ZO_QuestTracker.SetHidden) then
        return
    end

    if state.previousDefaultQuestTrackerHidden == nil then
        state.previousDefaultQuestTrackerHidden = ZO_QuestTracker:IsHidden()
    end

    if features.hideDefaultQuestTracker then
        ZO_QuestTracker:SetHidden(true)
    else
        if state.previousDefaultQuestTrackerHidden ~= nil then
            ZO_QuestTracker:SetHidden(state.previousDefaultQuestTrackerHidden)
        else
            ZO_QuestTracker:SetHidden(false)
        end
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

local function applyWindowVisibility()
    if not (state.root and state.window) then
        return
    end

    local shouldHide = state.window.visible == false
    state.root:SetHidden(shouldHide)
end

local function notifyContentChanged()
    if not state.root then
        return
    end

    updateWindowGeometry()
    applyWindowVisibility()
    refreshScroll()
end

local function applyWindowClamp()
    if not (state.root and state.window) then
        return
    end

    local clampToScreen = state.window.clamp ~= false
    state.root:SetClampedToScreen(clampToScreen)

    if clampToScreen then
        clampWindowToScreen(state.window.width or DEFAULT_WINDOW.width, state.window.height or DEFAULT_WINDOW.height)
    end
end

local function applyWindowTopmost()
    if not (state.root and state.window) then
        return
    end

    local onTop = state.window.onTop == true
    if state.root.SetTopmostWindow then
        state.root:SetTopmostWindow(onTop)
    end
    if state.root.SetTopmost then
        state.root:SetTopmost(onTop)
    end
    if state.root.SetDrawLayer then
        state.root:SetDrawLayer(onTop and DL_OVERLAY or DL_BACKGROUND)
    end
    if state.root.SetDrawTier then
        state.root:SetDrawTier(onTop and DT_HIGH or DT_LOW)
    end

    if state.backdrop then
        if state.backdrop.SetDrawLayer then
            state.backdrop:SetDrawLayer(onTop and DL_OVERLAY or DL_BACKGROUND)
        end
        if state.backdrop.SetDrawTier then
            state.backdrop:SetDrawTier(onTop and DT_HIGH or DT_LOW)
        end
    end

    if state.scrollbar then
        if state.scrollbar.SetDrawLayer then
            state.scrollbar:SetDrawLayer(onTop and DL_OVERLAY or DL_BACKGROUND)
        end
        if state.scrollbar.SetDrawTier then
            state.scrollbar:SetDrawTier(onTop and DT_HIGH or DT_LOW)
        end
    end
end

local function applyWindowSettings()
    state.window = ensureWindowSettings()
    state.appearance = ensureAppearanceSettings()
    state.layout = ensureLayoutSettings()
    state.features = ensureFeatureSettings()

    if not state.root then
        return
    end

    applyLayoutConstraints()
    updateSectionLayout()
    applyWindowClamp()
    updateWindowGeometry()
    applyWindowLock()
    applyWindowTopmost()
    applyWindowVisibility()
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
        local appearance = state.appearance or ensureAppearanceSettings()
        local thickness = math.max(1, appearance.edgeThickness or DEFAULT_APPEARANCE.edgeThickness)
        control:SetEdgeTexture(
            DEFAULT_BACKDROP_TEXTURE.texture,
            DEFAULT_BACKDROP_TEXTURE.tileSize,
            thickness
        )
        control._nvk3utEdgeThickness = thickness
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
        updateSectionLayout()
        notifyContentChanged()
    end)

    control:SetHandler("OnMouseWheel", function(_, delta)
        adjustScroll(delta)
    end)

    state.root = control
    Nvk3UT.UI.Root = control

    applyLayoutConstraints()
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
        if questContainer.SetResizeToFitDescendents then
            questContainer:SetResizeToFitDescendents(true)
        end
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
        if achievementContainer.SetResizeToFitDescendents then
            achievementContainer:SetResizeToFitDescendents(true)
        end
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
        local backgroundEnabled = appearance.enabled ~= false
        local alpha = clamp(appearance.alpha, 0, 1)
        local edgeAlpha = clamp(appearance.edgeAlpha, 0, 1)
        local edgeThickness = math.max(1, appearance.edgeThickness or DEFAULT_APPEARANCE.edgeThickness)
        local borderEnabled = appearance.edgeEnabled ~= false and edgeAlpha > 0

        local shouldShow = backgroundEnabled or borderEnabled
        backdrop:SetHidden(not shouldShow)

        if backdrop.SetEdgeTexture then
            local currentThickness = backdrop._nvk3utEdgeThickness or 0
            if currentThickness ~= edgeThickness then
                backdrop:SetEdgeTexture(
                    DEFAULT_BACKDROP_TEXTURE.texture,
                    DEFAULT_BACKDROP_TEXTURE.tileSize,
                    edgeThickness
                )
                backdrop._nvk3utEdgeThickness = edgeThickness
            end
        end

        if backdrop.SetCenterColor then
            local centerAlpha = backgroundEnabled and alpha or 0
            backdrop:SetCenterColor(0, 0, 0, centerAlpha)
        end

        if backdrop.SetEdgeColor then
            local effectiveEdgeAlpha = borderEnabled and edgeAlpha or 0
            backdrop:SetEdgeColor(0, 0, 0, effectiveEdgeAlpha)
        end

        if backdrop.SetCornerRadius then
            backdrop:SetCornerRadius(appearance.cornerRadius or 0)
        end
    end

    applyViewportPadding()
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
    state.layout = ensureLayoutSettings()
    state.features = ensureFeatureSettings()

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
    applyFeatureSettings()

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
    notifyContentChanged()
end

function TrackerHost.ApplyAppearance()
    if not state.root then
        return
    end

    applyAppearance()
    notifyContentChanged()
end

function TrackerHost.Shutdown()
    if state.previousDefaultQuestTrackerHidden ~= nil and ZO_QuestTracker and ZO_QuestTracker.SetHidden then
        ZO_QuestTracker:SetHidden(state.previousDefaultQuestTrackerHidden)
    end

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
    state.layout = nil
    state.features = nil
    state.initialized = false
    state.previousDefaultQuestTrackerHidden = nil
end

Nvk3UT.TrackerHost = TrackerHost

TrackerHost.RefreshScroll = refreshScroll
TrackerHost.NotifyContentChanged = notifyContentChanged

return TrackerHost
