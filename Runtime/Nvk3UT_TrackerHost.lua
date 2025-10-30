-- Runtime/Nvk3UT_TrackerHost.lua
-- NOTE:
-- ESO event registration (ADD_ON_LOADED, PLAYER_ACTIVATED, HUD visibility,
-- cursor mode, combat state, etc.) is owned by Events/Nvk3UT_EventHandlerBase.lua.
-- TrackerHost is a pure UI container; do not register events here.
local Host = {}

local ADDON_NAME = "Nvk3UT"
local ROOT_CONTROL_NAME = ADDON_NAME .. "_UI_Root"
local HEADER_CONTROL_NAME = ROOT_CONTROL_NAME .. "_Header"
local FOOTER_CONTROL_NAME = ROOT_CONTROL_NAME .. "_Footer"
local SCROLL_CONTAINER_NAME = ROOT_CONTROL_NAME .. "_ScrollContainer"
local SCROLL_CHILD_NAME = SCROLL_CONTAINER_NAME .. "_ScrollChild"
local SCROLLBAR_NAME = SCROLL_CONTAINER_NAME .. "_ScrollBar"
local BACKDROP_CONTROL_NAME = ROOT_CONTROL_NAME .. "_Backdrop"
local QUEST_SECTION_NAME = ROOT_CONTROL_NAME .. "_QuestSection"
local ACHIEVEMENT_SECTION_NAME = ROOT_CONTROL_NAME .. "_AchievementSection"

local MIN_WIDTH = 260
local MIN_HEIGHT = 240
local RESIZE_HANDLE_SIZE = 12
local MAX_BAR_HEIGHT = 250

local DEFAULT_LAYOUT = {
    autoGrowV = false,
    autoGrowH = false,
    minWidth = MIN_WIDTH,
    minHeight = MIN_HEIGHT,
    maxWidth = 640,
    maxHeight = 900,
}

local DEFAULT_APPEARANCE = {
    enabled = true,
    alpha = 0.6,
    edgeEnabled = true,
    edgeAlpha = 0.65,
    edgeThickness = 2,
    padding = 12,
    cornerRadius = 0,
}

local DEFAULT_TRACKER_COLORS = {
    questTracker = {
        colors = {
            categoryTitle = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
            objectiveText = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
            entryTitle = { r = 1, g = 1, b = 0, a = 1 },
            activeTitle = { r = 1, g = 1, b = 1, a = 1 },
        },
    },
    achievementTracker = {
        colors = {
            categoryTitle = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
            objectiveText = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
            entryTitle = { r = 1, g = 1, b = 0, a = 1 },
            activeTitle = { r = 1, g = 1, b = 1, a = 1 },
        },
    },
}

local DEFAULT_COLOR_FALLBACK = { r = 1, g = 1, b = 1, a = 1 }

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

local DEFAULT_WINDOW_BARS = {
    headerHeightPx = 40,
    footerHeightPx = 100,
}

local LEFT_MOUSE_BUTTON = _G.MOUSE_BUTTON_INDEX_LEFT or 1

local function normalizeColorComponent(value, fallback)
    local numeric = tonumber(value)
    if numeric == nil then
        numeric = fallback ~= nil and fallback or 1
    end

    if numeric < 0 then
        numeric = 0
    elseif numeric > 1 then
        numeric = 1
    end

    return numeric
end

local function ensureColorComponents(color, defaults)
    local target = type(color) == "table" and color or {}
    local defaultColor = defaults or DEFAULT_COLOR_FALLBACK

    target.r = normalizeColorComponent(target.r, defaultColor.r)
    target.g = normalizeColorComponent(target.g, defaultColor.g)
    target.b = normalizeColorComponent(target.b, defaultColor.b)
    target.a = normalizeColorComponent(target.a, defaultColor.a)

    return target
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

local function clamp(value, minimum, maximum)
    if type(value) ~= "number" then
        value = minimum
    end

    if maximum then
        if value > maximum then
            value = maximum
        end
    end

    if value < minimum then
        value = minimum
    end

    return value
end

local function round(numberValue)
    if type(numberValue) ~= "number" then
        return nil
    end

    return math.floor(numberValue + 0.5)
end

function Host:Init()
    self.sv = self.sv or nil
    self.windowSettings = nil
    self.windowBarSettings = nil
    self.layoutSettings = nil
    self.appearanceSettings = nil
    self.trackerColorSettings = nil

    self.window = self.window or nil
    self.headerControl = self.headerControl or nil
    self.footerControl = self.footerControl or nil
    self.scrollArea = self.scrollArea or nil
    self.scrollChild = self.scrollChild or nil
    self.scrollbar = self.scrollbar or nil
    self.backdrop = self.backdrop or nil
    self.questSectionControl = self.questSectionControl or nil
    self.achievementSectionControl = self.achievementSectionControl or nil

    self.locked = self.locked or false
    self._trackersInitialized = self._trackersInitialized or false
    self._lamPreviewVisible = nil
end

function Host:OnPlayerActivated()
    self:EnsureWindow()
    self:ApplySavedSettings()
    self:ApplyAppearance()
    self:ApplyWindowBars()
    self:_EnsureTrackersInitialized()
    self:NotifyContentChanged()

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug("TrackerHost.OnPlayerActivated() complete")
    end
end

function Host:_EnsureSavedVars()
    if self.sv then
        return self.sv
    end

    local addon = Nvk3UT
    if not (addon and addon.sv) then
        return nil
    end

    local general = addon.sv.General
    if type(general) ~= "table" then
        general = {}
        addon.sv.General = general
    end

    self.sv = general
    return general
end

function Host:_EnsureWindowSettings()
    if self.windowSettings then
        return self.windowSettings
    end

    local general = self:_EnsureSavedVars()
    local window = general and general.window
    if type(window) ~= "table" then
        window = {}
        if general then
            general.window = window
        end
    end

    window.left = tonumber(window.left) or DEFAULT_WINDOW.left
    window.top = tonumber(window.top) or DEFAULT_WINDOW.top
    window.width = tonumber(window.width) or DEFAULT_WINDOW.width
    window.height = tonumber(window.height) or DEFAULT_WINDOW.height
    window.locked = window.locked == true
    if window.visible == nil then
        window.visible = DEFAULT_WINDOW.visible
    else
        window.visible = window.visible ~= false
    end
    if window.clamp == nil then
        window.clamp = DEFAULT_WINDOW.clamp
    else
        window.clamp = window.clamp ~= false
    end
    if window.onTop == nil then
        window.onTop = DEFAULT_WINDOW.onTop
    else
        window.onTop = window.onTop == true
    end

    self.windowSettings = window
    return window
end

function Host:_EnsureLayoutSettings()
    if self.layoutSettings then
        return self.layoutSettings
    end

    local general = self:_EnsureSavedVars()
    local layout = general and general.layout
    if type(layout) ~= "table" then
        layout = {}
        if general then
            general.layout = layout
        end
    end

    layout.autoGrowV = layout.autoGrowV ~= false and layout.autoGrowV or DEFAULT_LAYOUT.autoGrowV
    layout.autoGrowH = layout.autoGrowH == true

    local minWidth = tonumber(layout.minWidth)
    if not minWidth then
        minWidth = DEFAULT_LAYOUT.minWidth
    end
    layout.minWidth = clamp(math.floor(minWidth + 0.5), MIN_WIDTH)

    local minHeight = tonumber(layout.minHeight)
    if not minHeight then
        minHeight = DEFAULT_LAYOUT.minHeight
    end
    layout.minHeight = clamp(math.floor(minHeight + 0.5), MIN_HEIGHT)

    local maxWidth = tonumber(layout.maxWidth)
    if not maxWidth then
        maxWidth = DEFAULT_LAYOUT.maxWidth
    end
    layout.maxWidth = math.max(layout.minWidth, math.floor(maxWidth + 0.5))

    local maxHeight = tonumber(layout.maxHeight)
    if not maxHeight then
        maxHeight = DEFAULT_LAYOUT.maxHeight
    end
    layout.maxHeight = math.max(layout.minHeight, math.floor(maxHeight + 0.5))

    self.layoutSettings = layout
    return layout
end

function Host:_EnsureWindowBarSettings()
    if self.windowBarSettings then
        return self.windowBarSettings
    end

    local general = self:_EnsureSavedVars()
    local bars = general and general.WindowBars
    if type(bars) ~= "table" then
        bars = {}
        if general then
            general.WindowBars = bars
        end
    end

    local header = round(bars.headerHeightPx)
    if not header then
        header = DEFAULT_WINDOW_BARS.headerHeightPx
    end
    bars.headerHeightPx = clamp(header, 0, MAX_BAR_HEIGHT)

    local footer = round(bars.footerHeightPx)
    if not footer then
        footer = DEFAULT_WINDOW_BARS.footerHeightPx
    end
    bars.footerHeightPx = clamp(footer, 0, MAX_BAR_HEIGHT)

    self.windowBarSettings = bars
    return bars
end

function Host:_EnsureAppearanceSettings()
    if self.appearanceSettings then
        return self.appearanceSettings
    end

    local general = self:_EnsureSavedVars()
    if not general then
        self.appearanceSettings = {}
        return self.appearanceSettings
    end

    general.Appearance = general.Appearance or {}
    local appearance = general.Appearance

    appearance.enabled = appearance.enabled ~= false
    appearance.alpha = clamp(tonumber(appearance.alpha) or DEFAULT_APPEARANCE.alpha, 0, 1)
    appearance.edgeEnabled = appearance.edgeEnabled ~= false
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

    local radius = tonumber(appearance.cornerRadius)
    if radius == nil then
        radius = DEFAULT_APPEARANCE.cornerRadius
    end
    appearance.cornerRadius = math.max(0, math.floor(radius + 0.5))

    if type(appearance.theme) ~= "string" or appearance.theme == "" then
        appearance.theme = DEFAULT_APPEARANCE.theme
    else
        appearance.theme = string.lower(appearance.theme)
    end

    self.appearanceSettings = appearance
    return appearance
end

function Host:_EnsureTrackerColorSettings()
    if self.trackerColorSettings then
        return self.trackerColorSettings
    end

    local sv = Nvk3UT and Nvk3UT.sv
    if not sv then
        self.trackerColorSettings = {}
        return self.trackerColorSettings
    end

    sv.appearance = sv.appearance or {}
    local trackerAppearance = sv.appearance

    for trackerType, defaults in pairs(DEFAULT_TRACKER_COLORS) do
        trackerAppearance[trackerType] = trackerAppearance[trackerType] or {}
        local tracker = trackerAppearance[trackerType]
        tracker.colors = tracker.colors or {}

        if defaults and defaults.colors then
            for role, defaultColor in pairs(defaults.colors) do
                tracker.colors[role] = ensureColorComponents(tracker.colors[role], defaultColor)
            end
        end
    end

    self.trackerColorSettings = trackerAppearance
    return trackerAppearance
end

function Host:_ApplyViewportPadding()
    local scroll = self.scrollArea
    local window = self.window
    if not (scroll and window) then
        return
    end

    local appearance = self:_EnsureAppearanceSettings()
    local padding = appearance and tonumber(appearance.padding) or DEFAULT_APPEARANCE.padding
    padding = math.max(0, padding or 0)

    local topAnchor = self.headerControl and not self.headerControl:IsHidden() and self.headerControl or window
    local bottomAnchor = self.footerControl and not self.footerControl:IsHidden() and self.footerControl or window

    local topOffsetY = padding
    local bottomOffsetY = -padding
    if topAnchor ~= window then
        topOffsetY = 0
    end
    if bottomAnchor ~= window then
        bottomOffsetY = 0
    end

    scroll:ClearAnchors()
    scroll:SetAnchor(TOPLEFT, topAnchor, topAnchor == window and TOPLEFT or BOTTOMLEFT, padding, topOffsetY)
    scroll:SetAnchor(BOTTOMRIGHT, bottomAnchor, bottomAnchor == window and BOTTOMRIGHT or TOPRIGHT, -padding, bottomOffsetY)

    if self.scrollChild then
        self.scrollChild:ClearAnchors()
        self.scrollChild:SetAnchor(TOPLEFT, scroll, TOPLEFT, 0, 0)
        self.scrollChild:SetAnchor(TOPRIGHT, scroll, TOPRIGHT, 0, 0)
    end
end

function Host:_MeasureContentSize()
    local totalHeight = 0
    local maxWidth = MIN_WIDTH

    local function accumulate(control)
        if not control then
            return
        end

        if control.IsHidden and control:IsHidden() then
            return
        end

        if control.GetHeight then
            local h = control:GetHeight() or 0
            if h > 0 then
                totalHeight = totalHeight + h
            end
        end

        if control.GetWidth then
            local w = control:GetWidth() or 0
            if w > maxWidth then
                maxWidth = w
            end
        end
    end

    accumulate(self.headerControl)
    accumulate(self.questSectionControl)
    accumulate(self.achievementSectionControl)
    accumulate(self.footerControl)

    return maxWidth, totalHeight
end

function Host:_ApplyLayoutConstraints()
    if not self.window then
        return
    end

    local layout = self:_EnsureLayoutSettings()
    if not layout then
        return
    end

    local minWidth = layout.minWidth or MIN_WIDTH
    local minHeight = layout.minHeight or MIN_HEIGHT
    local maxWidth = layout.maxWidth or minWidth
    local maxHeight = layout.maxHeight or minHeight

    if self.window.SetDimensionConstraints then
        self.window:SetDimensionConstraints(minWidth, minHeight, maxWidth, maxHeight)
    end

    if not (layout.autoGrowH or layout.autoGrowV) then
        return
    end

    local contentWidth, contentHeight = self:_MeasureContentSize()
    local appearance = self:_EnsureAppearanceSettings()
    local padding = appearance and appearance.padding or DEFAULT_APPEARANCE.padding
    padding = math.max(0, padding)

    local targetWidth = self.windowSettings and self.windowSettings.width or DEFAULT_WINDOW.width
    local targetHeight = self.windowSettings and self.windowSettings.height or DEFAULT_WINDOW.height

    if layout.autoGrowH then
        local desiredWidth = math.floor((contentWidth + (padding * 2)) + 0.5)
        targetWidth = clamp(desiredWidth, minWidth, maxWidth)
        self.windowSettings.width = targetWidth
    end

    if layout.autoGrowV then
        local desiredHeight = math.floor((contentHeight + (padding * 2)) + 0.5)
        targetHeight = clamp(desiredHeight, minHeight, maxHeight)
        self.windowSettings.height = targetHeight
    end

    self.window:SetDimensions(targetWidth, targetHeight)
end

function Host:_EnsureTrackersInitialized()
    if self._trackersInitialized then
        return
    end

    if not (self.questSectionControl and self.achievementSectionControl) then
        return
    end

    local addon = Nvk3UT
    local safeCall = addon and addon.SafeCall

    local function initQuest()
        local tracker = addon and addon.QuestTracker
        if tracker and tracker.Init then
            local opts = cloneTable(addon and addon.sv and addon.sv.QuestTracker or {})
            tracker.Init(self.questSectionControl, opts)
        end
    end

    local function initAchievement()
        local tracker = addon and addon.AchievementTracker
        if tracker and tracker.Init then
            local opts = cloneTable(addon and addon.sv and addon.sv.AchievementTracker or {})
            tracker.Init(self.achievementSectionControl, opts)
        end
    end

    if safeCall then
        safeCall(addon, initQuest)
        safeCall(addon, initAchievement)
    else
        pcall(initQuest)
        pcall(initAchievement)
    end

    self._trackersInitialized = true
end

function Host:_StartWindowMove()
    if not self.window or self:IsLocked() then
        return
    end

    self.window:StartMoving()
end

function Host:_StopWindowMove()
    if not self.window then
        return
    end

    self.window:StopMovingOrResizing()
    self:SaveWindowPosition()
end

function Host:EnsureWindow()
    if self.window and self.scrollChild then
        return
    end

    local wm = WINDOW_MANAGER
    if not wm then
        return
    end

    local window = self.window
    if not window then
        window = wm:CreateTopLevelWindow(ROOT_CONTROL_NAME)
        if not window then
            return
        end

        window:SetHidden(true)
        window:SetMouseEnabled(true)
        window:SetMovable(true)
        window:SetClampedToScreen(true)
        window:SetResizeHandleSize(RESIZE_HANDLE_SIZE)
        window:SetDimensionConstraints(MIN_WIDTH, MIN_HEIGHT)
        window:SetDrawLayer(DL_BACKGROUND)
        window:SetDrawTier(DT_LOW)
        window:SetDrawLevel(0)

        window:SetHandler("OnMouseDown", function(_, button)
            if button ~= LEFT_MOUSE_BUTTON then
                return
            end

            local header = self.headerControl
            if header and header.SetHidden then
                local isHidden = header:IsHidden()
                local height = header:GetHeight() or 0
                if not isHidden and height > 0 then
                    return
                end
            end

            self:_StartWindowMove()
        end)

        window:SetHandler("OnMouseUp", function(_, button)
            if button == LEFT_MOUSE_BUTTON then
                self:_StopWindowMove()
            end
        end)

        window:SetHandler("OnMoveStop", function()
            self:SaveWindowPosition()
        end)

        window:SetHandler("OnResizeStop", function()
            self:SaveWindowSize()
            self:NotifyContentChanged()
        end)

        self.window = window
    end

    if not self.backdrop then
        local backdrop = wm:CreateControl(BACKDROP_CONTROL_NAME, window, CT_BACKDROP)
        backdrop:SetAnchorFill(window)
        backdrop:SetHidden(true)
        backdrop:SetAlpha(0)
        backdrop:SetMouseEnabled(false)
        self.backdrop = backdrop
    else
        self.backdrop:SetParent(window)
        self.backdrop:SetAnchorFill(window)
    end

    local header = self.headerControl
    if not header then
        header = wm:CreateControl(HEADER_CONTROL_NAME, window, CT_CONTROL)
        header:SetAnchor(TOPLEFT, window, TOPLEFT, 0, 0)
        header:SetAnchor(TOPRIGHT, window, TOPRIGHT, 0, 0)
        header:SetHeight(DEFAULT_WINDOW_BARS.headerHeightPx)
        header:SetMouseEnabled(true)
        header:SetHandler("OnMouseDown", function(_, button)
            if button == LEFT_MOUSE_BUTTON then
                self:_StartWindowMove()
            end
        end)
        header:SetHandler("OnMouseUp", function(_, button)
            if button == LEFT_MOUSE_BUTTON then
                self:_StopWindowMove()
            end
        end)

        local headerBackdrop = wm:CreateControl(nil, header, CT_BACKDROP)
        headerBackdrop:SetAnchorFill(header)
        headerBackdrop:SetCenterColor(0.15, 0.15, 0.15, 0.85)
        headerBackdrop:SetEdgeColor(0, 0, 0, 0.9)
        headerBackdrop:SetEdgeTexture("EsoUI/Art/Tooltips/UI_Border.dds", 128, 16)

        self.headerControl = header
    end

    local footer = self.footerControl
    if not footer then
        footer = wm:CreateControl(FOOTER_CONTROL_NAME, window, CT_CONTROL)
        footer:SetAnchor(BOTTOMLEFT, window, BOTTOMLEFT, 0, 0)
        footer:SetAnchor(BOTTOMRIGHT, window, BOTTOMRIGHT, 0, 0)
        footer:SetHeight(DEFAULT_WINDOW_BARS.footerHeightPx)
        footer:SetMouseEnabled(true)

        local footerBackdrop = wm:CreateControl(nil, footer, CT_BACKDROP)
        footerBackdrop:SetAnchorFill(footer)
        footerBackdrop:SetCenterColor(0.15, 0.15, 0.15, 0.85)
        footerBackdrop:SetEdgeColor(0, 0, 0, 0.9)
        footerBackdrop:SetEdgeTexture("EsoUI/Art/Tooltips/UI_Border.dds", 128, 16)

        self.footerControl = footer
    end

    local scroll = self.scrollArea
    if not scroll then
        scroll = wm:CreateControlFromVirtual(SCROLL_CONTAINER_NAME, window, "ZO_ScrollContainer")
        if not scroll then
            scroll = wm:CreateControl(SCROLL_CONTAINER_NAME, window, CT_SCROLL)
        end
        if not scroll then
            return
        end
    end

    scroll:SetParent(window)
    scroll:ClearAnchors()
    scroll:SetMouseEnabled(true)
    scroll:SetClampedToScreen(false)
    self.scrollArea = scroll

    local scrollChild = self.scrollChild
    if not scrollChild then
        scrollChild = scroll:GetNamedChild("ScrollChild")
        if not scrollChild then
            scrollChild = wm:CreateControl(SCROLL_CHILD_NAME, scroll, CT_CONTROL)
            if scroll.SetScrollChild then
                scroll:SetScrollChild(scrollChild)
            end
        else
            if scrollChild.SetName then
                scrollChild:SetName(SCROLL_CHILD_NAME)
            end
        end
    end

    scrollChild:SetParent(scroll)
    scrollChild:ClearAnchors()
    scrollChild:SetAnchor(TOPLEFT, scroll, TOPLEFT, 0, 0)
    scrollChild:SetAnchor(TOPRIGHT, scroll, TOPRIGHT, 0, 0)
    if scrollChild.SetResizeToFitDescendents then
        scrollChild:SetResizeToFitDescendents(true)
    end
    scrollChild:SetMouseEnabled(false)
    self.scrollChild = scrollChild

    if not self.scrollbar then
        local scrollbar = scroll:GetNamedChild("ScrollBar")
        if not scrollbar then
            scrollbar = wm:CreateControl(SCROLLBAR_NAME, scroll, CT_SLIDER)
            scrollbar:SetAnchor(TOPRIGHT, scroll, TOPRIGHT, 0, 0)
            scrollbar:SetAnchor(BOTTOMRIGHT, scroll, BOTTOMRIGHT, 0, 0)
            scrollbar:SetWidth(18)
        end
        self.scrollbar = scrollbar
    end

    if not self.questSectionControl then
        local questSection = wm:CreateControl(QUEST_SECTION_NAME, scrollChild, CT_CONTROL)
        questSection:SetAnchor(TOPLEFT, scrollChild, TOPLEFT, 0, 0)
        questSection:SetAnchor(TOPRIGHT, scrollChild, TOPRIGHT, 0, 0)
        questSection:SetResizeToFitDescendents(true)
        self.questSectionControl = questSection
    end

    if not self.achievementSectionControl then
        local achievementSection = wm:CreateControl(ACHIEVEMENT_SECTION_NAME, scrollChild, CT_CONTROL)
        achievementSection:SetAnchor(TOPLEFT, self.questSectionControl, BOTTOMLEFT, 0, 0)
        achievementSection:SetAnchor(TOPRIGHT, self.questSectionControl, BOTTOMRIGHT, 0, 0)
        achievementSection:SetResizeToFitDescendents(true)
        self.achievementSectionControl = achievementSection
    end

    self:_ApplyViewportPadding()
    self:ApplyWindowBars()
end

function Host:RestoreWindowPositionFromSV(windowSettings)
    local settings = windowSettings or self:_EnsureWindowSettings()
    if not (self.window and settings) then
        return
    end

    local left = round(settings.left) or DEFAULT_WINDOW.left
    local top = round(settings.top) or DEFAULT_WINDOW.top

    self.window:ClearAnchors()
    if GuiRoot then
        self.window:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, left, top)
    else
        self.window:SetAnchor(TOPLEFT, nil, TOPLEFT, left, top)
    end
end

function Host:RestoreWindowSizeFromSV(windowSettings)
    local settings = windowSettings or self:_EnsureWindowSettings()
    if not (self.window and settings) then
        return
    end

    local width = clamp(tonumber(settings.width) or DEFAULT_WINDOW.width, MIN_WIDTH)
    local height = clamp(tonumber(settings.height) or DEFAULT_WINDOW.height, MIN_HEIGHT)

    self.window:SetDimensions(width, height)
end

function Host:UpdateHeaderFooterSizeFromSV(windowBars)
    local bars = windowBars or self:_EnsureWindowBarSettings()
    if not (self.headerControl and self.footerControl and self.scrollArea) then
        return
    end

    local headerHeight = clamp(tonumber(bars.headerHeightPx) or DEFAULT_WINDOW_BARS.headerHeightPx, 0, MAX_BAR_HEIGHT)
    local footerHeight = clamp(tonumber(bars.footerHeightPx) or DEFAULT_WINDOW_BARS.footerHeightPx, 0, MAX_BAR_HEIGHT)

    self.headerControl:SetHeight(headerHeight)
    self.headerControl:SetHidden(headerHeight <= 0)
    self.headerControl:SetMouseEnabled(headerHeight > 0)

    self.footerControl:SetHeight(footerHeight)
    self.footerControl:SetHidden(footerHeight <= 0)
    self.footerControl:SetMouseEnabled(footerHeight > 0)

    self.scrollArea:ClearAnchors()

    local topAnchorControl = self.window
    local topRelativePoint = TOPLEFT
    if headerHeight > 0 then
        topAnchorControl = self.headerControl
        topRelativePoint = BOTTOMLEFT
    end
    self.scrollArea:SetAnchor(TOPLEFT, topAnchorControl, topRelativePoint, 0, 0)

    local bottomAnchorControl = self.window
    local bottomRelativePoint = BOTTOMRIGHT
    if footerHeight > 0 then
        bottomAnchorControl = self.footerControl
        bottomRelativePoint = TOPRIGHT
    end
    self.scrollArea:SetAnchor(BOTTOMRIGHT, bottomAnchorControl, bottomRelativePoint, 0, 0)
end

function Host:ApplySavedSettings()
    if not self.window then
        return
    end

    self.windowSettings = nil
    self.windowBarSettings = nil
    self.layoutSettings = nil
    self.appearanceSettings = nil

    local windowSettings = self:_EnsureWindowSettings()
    local windowBars = self:_EnsureWindowBarSettings()
    local layout = self:_EnsureLayoutSettings()

    self.locked = windowSettings.locked == true
    self.window:SetMovable(not self.locked)
    self.window:SetResizeHandleSize(self.locked and 0 or RESIZE_HANDLE_SIZE)
    self.window:SetMouseEnabled(true)
    self.window:SetClampedToScreen(windowSettings.clamp ~= false)
    self.window:SetDrawTier(windowSettings.onTop and DT_HIGH or DT_LOW)

    local minWidth = layout.minWidth or MIN_WIDTH
    local minHeight = layout.minHeight or MIN_HEIGHT
    local maxWidth = layout.maxWidth or minWidth
    local maxHeight = layout.maxHeight or minHeight
    if self.window.SetDimensionConstraints then
        self.window:SetDimensionConstraints(minWidth, minHeight, maxWidth, maxHeight)
    end

    self:RestoreWindowSizeFromSV(windowSettings)
    self:RestoreWindowPositionFromSV(windowSettings)
    if Nvk3UT and Nvk3UT.TrackerHostLayout and Nvk3UT.TrackerHostLayout.UpdateHeaderFooterSizes then
        Nvk3UT.TrackerHostLayout:UpdateHeaderFooterSizes()
    else
        self:UpdateHeaderFooterSizeFromSV(windowBars)
    end

    self:_ApplyViewportPadding()
    self:_ApplyLayoutConstraints()

    local visible = windowSettings.visible ~= false
    self.window:SetHidden(not visible)

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug("TrackerHost.ApplySavedSettings() lock=" .. tostring(self.locked))
    end
end

function Host:SaveWindowPosition()
    local windowSettings = self:_EnsureWindowSettings()
    if not (self.window and windowSettings) then
        return
    end

    local left = round(self.window:GetLeft())
    local top = round(self.window:GetTop())
    if left then
        windowSettings.left = left
    end
    if top then
        windowSettings.top = top
    end
end

function Host:SaveWindowSize()
    local windowSettings = self:_EnsureWindowSettings()
    if not (self.window and windowSettings) then
        return
    end

    local width = round(self.window:GetWidth())
    local height = round(self.window:GetHeight())
    if width then
        windowSettings.width = clamp(width, MIN_WIDTH)
    end
    if height then
        windowSettings.height = clamp(height, MIN_HEIGHT)
    end
end

function Host:SetVisible(isVisible)
    local windowSettings = self:_EnsureWindowSettings()
    local shouldShow = isVisible and true or false

    if self.window then
        self.window:SetHidden(not shouldShow)
    end

    windowSettings.visible = shouldShow

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug("TrackerHost.SetVisible(" .. tostring(shouldShow) .. ")")
    end
end

function Host:IsVisible()
    if self.window then
        return not self.window:IsHidden()
    end

    local settings = self.windowSettings or self:_EnsureWindowSettings()
    return settings and settings.visible ~= false
end

function Host:SetLocked(isLocked)
    local locked = isLocked and true or false
    local windowSettings = self:_EnsureWindowSettings()

    self.locked = locked
    windowSettings.locked = locked

    if self.window then
        self.window:SetMovable(not locked)
        self.window:SetResizeHandleSize(locked and 0 or RESIZE_HANDLE_SIZE)
    end

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug("TrackerHost.SetLocked(" .. tostring(locked) .. ")")
    end
end

function Host:IsLocked()
    return self.locked == true
end

function Host:GetBodyContainer()
    return self.scrollChild
end

function Host:GetHeaderControl()
    return self.headerControl
end

function Host:GetFooterControl()
    return self.footerControl
end

function Host:GetWindowControl()
    return self.window
end

function Host.ApplyAppearance(self)
    self = self or Host

    local appearance = self:_EnsureAppearanceSettings()
    if not appearance then
        return
    end

    local backdrop = self.backdrop
    if backdrop then
        local backgroundEnabled = appearance.enabled ~= false
        local borderEnabled = appearance.edgeEnabled ~= false and appearance.edgeAlpha > 0

        backdrop:SetHidden(not (backgroundEnabled or borderEnabled))

        if backdrop.SetEdgeTexture then
            local current = backdrop._nvk3utEdgeThickness or 0
            if current ~= appearance.edgeThickness then
                backdrop:SetEdgeTexture("EsoUI/Art/Tooltips/UI_Border.dds", 128, appearance.edgeThickness)
                backdrop._nvk3utEdgeThickness = appearance.edgeThickness
            end
        end

        if backdrop.SetCenterColor then
            local alpha = backgroundEnabled and appearance.alpha or 0
            backdrop:SetCenterColor(0, 0, 0, alpha)
        end

        if backdrop.SetEdgeColor then
            local edgeAlpha = borderEnabled and appearance.edgeAlpha or 0
            backdrop:SetEdgeColor(0, 0, 0, edgeAlpha)
        end

        if backdrop.SetCornerRadius then
            backdrop:SetCornerRadius(appearance.cornerRadius or 0)
        end
    end

    self:_ApplyViewportPadding()

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug("TrackerHost.ApplyAppearance() theme=" .. tostring(appearance.theme))
    end
end

function Host.ApplyWindowBars(self)
    self = self or Host

    if Nvk3UT and Nvk3UT.TrackerHostLayout and Nvk3UT.TrackerHostLayout.UpdateHeaderFooterSizes then
        Nvk3UT.TrackerHostLayout:UpdateHeaderFooterSizes()
    else
        self:UpdateHeaderFooterSizeFromSV()
    end

    self:_ApplyViewportPadding()
    self:_ApplyLayoutConstraints()
    self:NotifyContentChanged()
end

function Host.ApplySettings(self)
    self = self or Host

    self:EnsureWindow()
    self:ApplySavedSettings()
    self:ApplyAppearance()
    self:ApplyWindowBars()
    self:_EnsureTrackersInitialized()
    self:NotifyContentChanged()
end

function Host.Refresh(self)
    self = self or Host
    self:ApplySettings()
end

function Host.EnsureAppearanceDefaults()
    Host:_EnsureTrackerColorSettings()
end

function Host.GetDefaultTrackerColor(_, trackerType, role)
    local defaults = DEFAULT_TRACKER_COLORS[trackerType]
    local colors = defaults and defaults.colors
    local color = colors and colors[role] or DEFAULT_COLOR_FALLBACK
    return color.r or 1, color.g or 1, color.b or 1, color.a or 1
end

function Host.GetTrackerColor(self, trackerType, role)
    local host = Host
    local typeArg = trackerType
    local roleArg = role

    if type(self) == "table" and (self == Host or self.scrollArea ~= nil or self.window ~= nil) then
        host = self
    else
        typeArg = self
        roleArg = trackerType
    end

    local trackers = host:_EnsureTrackerColorSettings()
    local tracker = trackers[typeArg]
    local colors = tracker and tracker.colors or nil
    local color = colors and colors[roleArg]
    if not color then
        return Host:GetDefaultTrackerColor(typeArg, roleArg)
    end
    return color.r or 1, color.g or 1, color.b or 1, color.a or 1
end

function Host.SetTrackerColor(self, trackerType, role, r, g, b, a)
    local host = Host
    local typeArg = trackerType
    local roleArg = role
    local red, green, blue, alpha = r, g, b, a

    if type(self) == "table" and (self == Host or self.scrollArea ~= nil or self.window ~= nil) then
        host = self
    else
        typeArg, roleArg, red, green, blue, alpha = self, trackerType, role, r, g, b
    end

    local trackers = host:_EnsureTrackerColorSettings()
    trackers[typeArg] = trackers[typeArg] or {}
    local tracker = trackers[typeArg]
    tracker.colors = tracker.colors or {}
    tracker.colors[roleArg] = ensureColorComponents({ r = red, g = green, b = blue, a = alpha }, DEFAULT_COLOR_FALLBACK)

    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT:Debug(
            string.format("TrackerHost.SetTrackerColor(%s, %s)", tostring(typeArg), tostring(roleArg))
        )
    end
end

function Host.NotifyContentChanged(self)
    self = self or Host
    self:_ApplyLayoutConstraints()
    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if runtime and runtime.QueueDirty then
        runtime:QueueDirty("layout")
    end
end

function Host.ScrollControlIntoView(self, control)
    local host = self
    local target = control

    if host ~= Host and (not host or not host.scrollArea) then
        target = host
        host = Host
    end

    if not (host.scrollArea and target and target.GetTop and target.GetBottom) then
        return false
    end

    local scroll = host.scrollArea
    local containerTop = host.scrollChild and host.scrollChild.GetTop and host.scrollChild:GetTop() or 0
    local controlTop = target:GetTop() or 0
    local controlBottom = target:GetBottom() or controlTop
    local height = scroll.GetHeight and scroll:GetHeight() or 0

    if height <= 0 then
        return false
    end

    local current = scroll.GetVerticalScroll and scroll:GetVerticalScroll() or 0
    local offsetTop = controlTop - containerTop
    local offsetBottom = controlBottom - containerTop
    local desired = current

    if offsetTop < current then
        desired = offsetTop
    elseif offsetBottom > current + height then
        desired = offsetBottom - height
    end

    desired = math.max(0, desired)
    if desired ~= current and scroll.SetVerticalScroll then
        scroll:SetVerticalScroll(desired)
    end

    return true
end

function Host.OnLamPanelOpened(self)
    self = self or Host
    if self._lamPreviewVisible == nil then
        self._lamPreviewVisible = self:IsVisible()
    end

    self:SetVisible(true)
    self:NotifyContentChanged()
end

function Host.OnLamPanelClosed(self)
    self = self or Host
    if self._lamPreviewVisible ~= nil then
        if not self._lamPreviewVisible then
            self:SetVisible(false)
        end
        self._lamPreviewVisible = nil
    end

    self:NotifyContentChanged()
end

local addon = Nvk3UT
if not addon then
    error("Nvk3UT_TrackerHost loaded before Nvk3UT_Core. Load order is wrong.")
end

addon.TrackerHost = Host
addon:RegisterModule("TrackerHost", Host)

return Host
