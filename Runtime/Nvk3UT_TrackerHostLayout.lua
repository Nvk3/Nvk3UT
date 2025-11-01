-- Runtime/Nvk3UT_TrackerHostLayout.lua
-- Layout helper that applies stacking and sizing for the tracker host.

local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}
local Addon = Nvk3UT

Addon.TrackerHostLayout = Addon.TrackerHostLayout or {}
local Layout = Addon.TrackerHostLayout

local QUEST_CONTAINER_NAME = addonName .. "_QuestContainer"
local ACHIEVEMENT_CONTAINER_NAME = addonName .. "_AchievementContainer"
local HEADER_BAR_NAME = addonName .. "_ScrollContainer_Content_HeaderBar"
local FOOTER_BAR_NAME = addonName .. "_ScrollContainer_Content_FooterBar"
local CONTENT_STACK_NAME = addonName .. "_ScrollContainer_Content_ContentStack"
local SCROLL_CONTAINER_NAME = addonName .. "_ScrollContainer"
local SCROLL_CONTENT_NAME = addonName .. "_ScrollContainer_Content"
local SCROLLBAR_NAME = addonName .. "_ScrollContainer_ScrollBar"

local MIN_WIDTH = 260
local MIN_HEIGHT = 240
local MAX_BAR_HEIGHT = 250
local SCROLLBAR_WIDTH = 18
local SCROLL_OVERSHOOT_PADDING = 100

local DEFAULT_LAYOUT = {
    autoGrowV = false,
    autoGrowH = false,
    minWidth = MIN_WIDTH,
    minHeight = MIN_HEIGHT,
    maxWidth = 640,
    maxHeight = 900,
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

local DEFAULT_WINDOW_BARS = {
    headerHeightPx = 40,
    footerHeightPx = 100,
}

local DEFAULT_APPEARANCE_PADDING = 12

Layout._lastComputedContentHeight = Layout._lastComputedContentHeight or 0
Layout._lastMeasuredWidth = Layout._lastMeasuredWidth or 0
Layout._lastVisibleSections = Layout._lastVisibleSections or ""
Layout._lastHeaderHeight = Layout._lastHeaderHeight or 0
Layout._lastFooterHeight = Layout._lastFooterHeight or 0
Layout._lastQuestHeight = Layout._lastQuestHeight or 0
Layout._lastAchievementHeight = Layout._lastAchievementHeight or 0
Layout._lastContentStackHeight = Layout._lastContentStackHeight or 0
Layout._scrollOffset = Layout._scrollOffset or 0

local function debug(fmt, ...)
    if Addon and type(Addon.Debug) == "function" then
        Addon.Debug(fmt, ...)
    end
end

local function safeCall(fn, ...)
    if not fn then
        return
    end

    if Addon and type(Addon.SafeCall) == "function" then
        return Addon.SafeCall(fn, ...)
    end

    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end

    return nil
end

local function getSavedVars()
    return Addon and Addon.sv
end

local function clamp(value, minimum, maximum)
    if value == nil then
        return minimum
    end

    if minimum ~= nil and value < minimum then
        return minimum
    end

    if maximum ~= nil and value > maximum then
        return maximum
    end

    return value
end

local function ensureLayoutSettings()
    local sv = getSavedVars()
    if not sv then
        return {
            autoGrowV = DEFAULT_LAYOUT.autoGrowV,
            autoGrowH = DEFAULT_LAYOUT.autoGrowH,
            minWidth = DEFAULT_LAYOUT.minWidth,
            maxWidth = DEFAULT_LAYOUT.maxWidth,
            minHeight = DEFAULT_LAYOUT.minHeight,
            maxHeight = DEFAULT_LAYOUT.maxHeight,
        }
    end

    sv.General = sv.General or {}
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
        return {
            left = DEFAULT_WINDOW.left,
            top = DEFAULT_WINDOW.top,
            width = DEFAULT_WINDOW.width,
            height = DEFAULT_WINDOW.height,
            locked = DEFAULT_WINDOW.locked,
            visible = DEFAULT_WINDOW.visible,
            clamp = DEFAULT_WINDOW.clamp,
            onTop = DEFAULT_WINDOW.onTop,
        }
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
    else
        window.locked = window.locked == true
    end

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

    return window
end

local function ensureWindowBarSettings()
    local sv = getSavedVars()
    if not sv then
        return {
            headerHeightPx = DEFAULT_WINDOW_BARS.headerHeightPx,
            footerHeightPx = DEFAULT_WINDOW_BARS.footerHeightPx,
        }
    end

    sv.General = sv.General or {}
    sv.General.WindowBars = sv.General.WindowBars or {}

    local bars = sv.General.WindowBars

    local headerHeight = tonumber(bars.headerHeightPx)
    if headerHeight == nil then
        headerHeight = DEFAULT_WINDOW_BARS.headerHeightPx
    end
    headerHeight = clamp(math.floor(headerHeight + 0.5), 0, MAX_BAR_HEIGHT)
    bars.headerHeightPx = headerHeight

    local footerHeight = tonumber(bars.footerHeightPx)
    if footerHeight == nil then
        footerHeight = DEFAULT_WINDOW_BARS.footerHeightPx
    end
    footerHeight = clamp(math.floor(footerHeight + 0.5), 0, MAX_BAR_HEIGHT)
    bars.footerHeightPx = footerHeight

    return bars
end

local function getAppearancePadding()
    local sv = getSavedVars()
    if not sv then
        return DEFAULT_APPEARANCE_PADDING
    end

    sv.General = sv.General or {}
    sv.General.Appearance = sv.General.Appearance or {}

    local appearance = sv.General.Appearance
    local padding = tonumber(appearance.padding)
    if padding == nil then
        padding = DEFAULT_APPEARANCE_PADDING
    end

    return math.max(0, math.floor(padding + 0.5))
end

local function getControl(hostRoot, name)
    if type(name) ~= "string" then
        return nil
    end

    local control = _G[name]
    if control then
        return control
    end

    if hostRoot and hostRoot.GetNamedChild then
        control = hostRoot:GetNamedChild(name)
        if control then
            return control
        end
    end

    if hostRoot and hostRoot.GetNamedChild then
        local prefix = addonName .. "_"
        if name:find(prefix, 1, true) == 1 then
            local trimmed = name:sub(#prefix + 1)
            control = hostRoot:GetNamedChild(trimmed)
            if control then
                return control
            end
        end
    end

    return nil
end

local function getScrollControls(hostRoot)
    local scrollContainer = getControl(hostRoot, SCROLL_CONTAINER_NAME)
    local scrollContent = getControl(hostRoot, SCROLL_CONTENT_NAME)
    local scrollbar = getControl(hostRoot, SCROLLBAR_NAME)

    if not scrollContent and scrollContainer and scrollContainer.GetNamedChild then
        scrollContent = scrollContainer:GetNamedChild("ScrollChild")
    end

    if not scrollbar and scrollContainer and scrollContainer.GetNamedChild then
        scrollbar = scrollContainer:GetNamedChild("ScrollBar")
    end

    return scrollContainer, scrollContent, scrollbar
end

local function isControlVisible(control)
    if not control then
        return false
    end

    if control.IsHidden and control:IsHidden() then
        return false
    end

    return true
end

local function getVisibleHeight(control)
    if not isControlVisible(control) then
        return 0
    end

    if control.GetHeight then
        local height = control:GetHeight()
        if height then
            return math.max(0, tonumber(height) or 0)
        end
    end

    return 0
end

local function getControlWidth(control)
    if not isControlVisible(control) then
        return 0
    end

    if control.GetWidth then
        local width = control:GetWidth()
        if width then
            return math.max(0, tonumber(width) or 0)
        end
    end

    return 0
end

local function measureTrackerContent(container, trackerModule)
    if not container or not isControlVisible(container) then
        return 0, 0
    end

    local width = 0
    local height = 0

    if trackerModule then
        local measure
        if type(trackerModule.GetContentSize) == "function" then
            measure = function()
                return trackerModule:GetContentSize()
            end
        elseif type(trackerModule.GetSize) == "function" then
            measure = function()
                return trackerModule:GetSize()
            end
        end

        if measure then
            local ok, contentWidth, contentHeight = pcall(measure)
            if ok then
                width = math.max(width, tonumber(contentWidth) or 0)
                height = math.max(height, tonumber(contentHeight) or 0)
            end
        end
    end

    if (width <= 0 or height <= 0) then
        local holder = container.holder
        if holder and holder.GetWidth and holder.GetHeight then
            width = math.max(width, holder:GetWidth() or 0)
            height = math.max(height, holder:GetHeight() or 0)
        else
            if container.GetWidth then
                width = math.max(width, container:GetWidth() or 0)
            end
            if container.GetHeight then
                height = math.max(height, container:GetHeight() or 0)
            end
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

local function summarizeSections(sections)
    if not sections or #sections == 0 then
        return "none"
    end

    return table.concat(sections, ",")
end

local function measureLayout(hostRoot)
    local headerBar = getControl(hostRoot, HEADER_BAR_NAME)
    local footerBar = getControl(hostRoot, FOOTER_BAR_NAME)
    local questContainer = getControl(hostRoot, QUEST_CONTAINER_NAME)
    local achievementContainer = getControl(hostRoot, ACHIEVEMENT_CONTAINER_NAME)

    local headerHeight = getVisibleHeight(headerBar)
    local footerHeight = getVisibleHeight(footerBar)
    local headerWidth = getControlWidth(headerBar)
    local footerWidth = getControlWidth(footerBar)

    local questTracker = rawget(Addon, "QuestTracker")
    local achievementTracker = rawget(Addon, "AchievementTracker")

    local questWidth, questHeight = measureTrackerContent(questContainer, questTracker)
    local achievementWidth, achievementHeight = measureTrackerContent(achievementContainer, achievementTracker)

    local totalHeight = headerHeight + footerHeight
    local sections = {}

    if questHeight > 0 and isControlVisible(questContainer) then
        totalHeight = totalHeight + questHeight
        table.insert(sections, "quest")
    end

    if achievementHeight > 0 and isControlVisible(achievementContainer) then
        totalHeight = totalHeight + achievementHeight
        table.insert(sections, "achievement")
    end

    local maxWidth = math.max(headerWidth, footerWidth, questWidth, achievementWidth)

    return {
        totalHeight = totalHeight,
        headerHeight = headerHeight,
        footerHeight = footerHeight,
        questHeight = questHeight,
        achievementHeight = achievementHeight,
        maxWidth = maxWidth,
        sections = sections,
    }
end

local function getTrackerHost()
    local host = rawget(Addon, "TrackerHost")
    if type(host) ~= "table" then
        return nil
    end
    return host
end

local function getHostRoot(hostRoot)
    if hostRoot then
        return hostRoot
    end

    local host = getTrackerHost()
    if host and type(host.GetRootWindow) == "function" then
        local ok, root = pcall(host.GetRootWindow, host)
        if ok and root then
            return root
        end
    end

    return _G[addonName .. "_UI_Root"]
end

local function applyViewportPadding(hostRoot)
    local scrollContainer, _, scrollbar = getScrollControls(hostRoot)
    local padding = getAppearancePadding()

    if scrollContainer and scrollContainer.ClearAnchors and hostRoot then
        scrollContainer:ClearAnchors()
        scrollContainer:SetAnchor(TOPLEFT, hostRoot, TOPLEFT, padding, padding)
        scrollContainer:SetAnchor(BOTTOMRIGHT, hostRoot, BOTTOMRIGHT, -padding, -padding)
    end

    if scrollbar and scrollbar.ClearAnchors then
        local parent = scrollContainer or hostRoot
        scrollbar:ClearAnchors()
        scrollbar:SetAnchor(TOPRIGHT, parent, TOPRIGHT, 0, 0)
        scrollbar:SetAnchor(BOTTOMRIGHT, parent, BOTTOMRIGHT, 0, 0)
        if scrollbar.SetWidth then
            scrollbar:SetWidth(SCROLLBAR_WIDTH)
        end
    end
end

local function clampWindowToScreen(window, width, height)
    if not (window and window.clamp ~= false and GuiRoot) then
        return
    end

    local rootWidth = GuiRoot.GetWidth and GuiRoot:GetWidth() or 0
    local rootHeight = GuiRoot.GetHeight and GuiRoot:GetHeight() or 0

    local maxLeft = math.max(0, rootWidth - width)
    local maxTop = math.max(0, rootHeight - height)

    window.left = clamp(tonumber(window.left) or 0, 0, maxLeft)
    window.top = clamp(tonumber(window.top) or 0, 0, maxTop)
end

local function applyWindowGeometry(hostRoot, measurement)
    if not hostRoot then
        return
    end

    local window = ensureWindowSettings()
    local layout = ensureLayoutSettings()
    local padding = getAppearancePadding()

    local minWidth = layout.minWidth or MIN_WIDTH
    local minHeight = layout.minHeight or MIN_HEIGHT
    local maxWidth = layout.maxWidth or minWidth
    local maxHeight = layout.maxHeight or minHeight

    local contentWidth = measurement.maxWidth or 0
    local contentHeight = measurement.totalHeight or 0

    local targetWidth = tonumber(window.width) or DEFAULT_WINDOW.width
    local targetHeight = tonumber(window.height) or DEFAULT_WINDOW.height

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

    window.width = targetWidth
    window.height = targetHeight

    clampWindowToScreen(window, targetWidth, targetHeight)

    if hostRoot.ClearAnchors then
        local parent = hostRoot:GetParent() or GuiRoot
        hostRoot:ClearAnchors()
        hostRoot:SetAnchor(TOPLEFT, parent, TOPLEFT, window.left or 0, window.top or 0)
    end

    if hostRoot.SetDimensions then
        hostRoot:SetDimensions(targetWidth, targetHeight)
    end

    if hostRoot.SetClampedToScreen then
        hostRoot:SetClampedToScreen(window.clamp ~= false)
    end
end

local function applyScrollLayout(hostRoot, measurement)
    local scrollContainer, scrollContent, scrollbar = getScrollControls(hostRoot)
    if not (scrollContainer and scrollContent and scrollbar) then
        return
    end

    if scrollContent.SetResizeToFitDescendents then
        scrollContent:SetResizeToFitDescendents(false)
    end

    if scrollContent.SetHeight then
        scrollContent:SetHeight(measurement.totalHeight)
    end

    local viewportHeight = 0
    if scrollContainer.GetHeight then
        viewportHeight = scrollContainer:GetHeight() or 0
    end

    local overshoot = 0
    if viewportHeight > 0 and measurement.totalHeight > viewportHeight then
        overshoot = SCROLL_OVERSHOOT_PADDING
    end

    local maxOffset = math.max((measurement.totalHeight - viewportHeight) + overshoot, 0)
    local showScrollbar = maxOffset > 0.5

    local currentOffset = Layout._scrollOffset or 0
    if scrollbar.GetValue then
        local value = scrollbar:GetValue()
        if type(value) == "number" then
            currentOffset = value
        end
    end

    if scrollbar.SetMinMax then
        safeCall(function()
            scrollbar:SetMinMax(0, maxOffset)
        end)
    end

    if scrollbar.SetHidden then
        scrollbar:SetHidden(not showScrollbar)
    end

    local desiredRightOffset = 0
    if showScrollbar then
        desiredRightOffset = -(scrollbar.GetWidth and scrollbar:GetWidth() or SCROLLBAR_WIDTH)
    end

    currentOffset = clamp(currentOffset, 0, maxOffset)
    Layout._scrollOffset = currentOffset

    if scrollContent.ClearAnchors then
        local offsetY = -currentOffset
        scrollContent:ClearAnchors()
        scrollContent:SetAnchor(TOPLEFT, scrollContainer, TOPLEFT, 0, offsetY)
        scrollContent:SetAnchor(TOPRIGHT, scrollContainer, TOPRIGHT, desiredRightOffset, offsetY)
    end

    if showScrollbar and scrollbar.SetValue then
        local current = scrollbar.GetValue and scrollbar:GetValue() or 0
        if math.abs(current - currentOffset) > 0.1 then
            safeCall(function()
                scrollbar:SetValue(currentOffset)
            end)
        end
    end
end

local function anchorSections(hostRoot)
    local scrollContainer, scrollContent = getScrollControls(hostRoot)
    local contentStack = getControl(hostRoot, CONTENT_STACK_NAME)
    local headerBar = getControl(hostRoot, HEADER_BAR_NAME)
    local footerBar = getControl(hostRoot, FOOTER_BAR_NAME)
    local questContainer = getControl(hostRoot, QUEST_CONTAINER_NAME)
    local achievementContainer = getControl(hostRoot, ACHIEVEMENT_CONTAINER_NAME)

    local contentParent = contentStack or scrollContent or hostRoot

    if headerBar and scrollContent and headerBar.ClearAnchors then
        headerBar:ClearAnchors()
        headerBar:SetAnchor(TOPLEFT, scrollContent, TOPLEFT, 0, 0)
        headerBar:SetAnchor(TOPRIGHT, scrollContent, TOPRIGHT, 0, 0)
    end

    if contentStack and contentStack.ClearAnchors then
        contentStack:ClearAnchors()
        if headerBar and isControlVisible(headerBar) then
            contentStack:SetAnchor(TOPLEFT, headerBar, BOTTOMLEFT, 0, 0)
            contentStack:SetAnchor(TOPRIGHT, headerBar, BOTTOMRIGHT, 0, 0)
        else
            contentStack:SetAnchor(TOPLEFT, scrollContent or hostRoot, TOPLEFT, 0, 0)
            contentStack:SetAnchor(TOPRIGHT, scrollContent or hostRoot, TOPRIGHT, 0, 0)
        end
    end

    if footerBar and footerBar.ClearAnchors then
        footerBar:ClearAnchors()
        if contentStack then
            footerBar:SetAnchor(TOPLEFT, contentStack, BOTTOMLEFT, 0, 0)
            footerBar:SetAnchor(TOPRIGHT, contentStack, BOTTOMRIGHT, 0, 0)
        elseif headerBar then
            footerBar:SetAnchor(TOPLEFT, headerBar, BOTTOMLEFT, 0, 0)
            footerBar:SetAnchor(TOPRIGHT, headerBar, BOTTOMRIGHT, 0, 0)
        else
            footerBar:SetAnchor(TOPLEFT, scrollContent or hostRoot, TOPLEFT, 0, 0)
            footerBar:SetAnchor(TOPRIGHT, scrollContent or hostRoot, TOPRIGHT, 0, 0)
        end
    end

    local previous = nil
    local function anchorSection(control)
        if not (control and control.ClearAnchors) then
            return
        end

        control:ClearAnchors()
        if previous then
            control:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, 0)
            control:SetAnchor(TOPRIGHT, previous, BOTTOMRIGHT, 0, 0)
        else
            control:SetAnchor(TOPLEFT, contentParent, TOPLEFT, 0, 0)
            control:SetAnchor(TOPRIGHT, contentParent, TOPRIGHT, 0, 0)
        end
        previous = control
    end

    anchorSection(questContainer)
    anchorSection(achievementContainer)
end

local function updateSectionHeights(hostRoot, measurement)
    local questContainer = getControl(hostRoot, QUEST_CONTAINER_NAME)
    local achievementContainer = getControl(hostRoot, ACHIEVEMENT_CONTAINER_NAME)
    local contentStack = getControl(hostRoot, CONTENT_STACK_NAME)

    if questContainer and questContainer.SetHeight then
        local previous = Layout._lastQuestHeight or 0
        if math.abs(previous - measurement.questHeight) > 0.1 then
            questContainer:SetHeight(measurement.questHeight)
            Layout._lastQuestHeight = measurement.questHeight
        end
    end

    if achievementContainer and achievementContainer.SetHeight then
        local previous = Layout._lastAchievementHeight or 0
        if math.abs(previous - measurement.achievementHeight) > 0.1 then
            achievementContainer:SetHeight(measurement.achievementHeight)
            Layout._lastAchievementHeight = measurement.achievementHeight
        end
    end

    if contentStack and contentStack.SetHeight then
        local newHeight = measurement.questHeight + measurement.achievementHeight
        local previous = Layout._lastContentStackHeight or 0
        if math.abs(previous - newHeight) > 0.1 then
            contentStack:SetHeight(newHeight)
            Layout._lastContentStackHeight = newHeight
        end
    end
end

local function applyHeaderFooterVisibility(hostRoot, headerHeight, footerHeight)
    local headerBar = getControl(hostRoot, HEADER_BAR_NAME)
    if headerBar then
        if headerBar.SetHeight and math.abs(Layout._lastHeaderHeight - headerHeight) > 0.1 then
            headerBar:SetHeight(headerHeight)
        end
        if headerBar.SetHidden then
            headerBar:SetHidden(headerHeight <= 0)
        end
        if headerBar.SetMouseEnabled then
            headerBar:SetMouseEnabled(headerHeight > 0)
        end
    end

    local footerBar = getControl(hostRoot, FOOTER_BAR_NAME)
    if footerBar then
        if footerBar.SetHeight and math.abs(Layout._lastFooterHeight - footerHeight) > 0.1 then
            footerBar:SetHeight(footerHeight)
        end
        if footerBar.SetHidden then
            footerBar:SetHidden(footerHeight <= 0)
        end
        if footerBar.SetMouseEnabled then
            footerBar:SetMouseEnabled(footerHeight > 0)
        end
    end

    Layout._lastHeaderHeight = headerHeight
    Layout._lastFooterHeight = footerHeight
end

function Layout.UpdateHeaderFooterSizes(hostRoot)
    hostRoot = getHostRoot(hostRoot)

    if not hostRoot then
        Layout._lastHeaderHeight = 0
        Layout._lastFooterHeight = 0
        return 0, 0
    end

    local host = getTrackerHost()
    if host and type(host.ApplyWindowBars) == "function" then
        safeCall(function()
            host.ApplyWindowBars()
        end)
    else
        local bars = ensureWindowBarSettings()
        applyHeaderFooterVisibility(hostRoot, bars.headerHeightPx or 0, bars.footerHeightPx or 0)
    end

    local measurement = measureLayout(hostRoot)
    applyHeaderFooterVisibility(hostRoot, measurement.headerHeight, measurement.footerHeight)

    return measurement.headerHeight, measurement.footerHeight
end

function Layout.ApplyLayout(hostRoot)
    hostRoot = getHostRoot(hostRoot)

    if not hostRoot then
        Layout._lastComputedContentHeight = 0
        Layout._lastMeasuredWidth = 0
        Layout._lastVisibleSections = ""
        return 0
    end

    Layout.UpdateHeaderFooterSizes(hostRoot)

    local host = getTrackerHost()
    local performedByHost = false
    if host then
        if type(host.NotifyContentChanged) == "function" then
            safeCall(function()
                host.NotifyContentChanged()
            end)
            performedByHost = true
        elseif type(host.RefreshScroll) == "function" then
            safeCall(function()
                host.RefreshScroll()
            end)
            performedByHost = true
        end
    end

    local measurement = measureLayout(hostRoot)

    if not performedByHost then
        updateSectionHeights(hostRoot, measurement)
        anchorSections(hostRoot)
        applyViewportPadding(hostRoot)
        applyWindowGeometry(hostRoot, measurement)
        applyScrollLayout(hostRoot, measurement)
    else
        Layout._lastQuestHeight = measurement.questHeight
        Layout._lastAchievementHeight = measurement.achievementHeight
        Layout._lastContentStackHeight = measurement.questHeight + measurement.achievementHeight
        applyViewportPadding(hostRoot)
    end

    Layout._lastComputedContentHeight = measurement.totalHeight
    Layout._lastMeasuredWidth = measurement.maxWidth
    Layout._lastVisibleSections = summarizeSections(measurement.sections)

    debug(
        "TrackerHostLayout.ApplyLayout width=%s height=%s sections=%s",
        string.format("%0.1f", measurement.maxWidth or 0),
        string.format("%0.1f", measurement.totalHeight or 0),
        Layout._lastVisibleSections
    )

    return measurement.totalHeight
end

function Layout.GetLastComputedContentHeight()
    return Layout._lastComputedContentHeight or 0
end

return Layout
