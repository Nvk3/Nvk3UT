Nvk3UT = Nvk3UT or {}
local Addon = Nvk3UT

Addon.TrackerHostLayout = Addon.TrackerHostLayout or {}
local Layout = Addon.TrackerHostLayout

local function debugLog(fmt, ...)
    local diagnostics = Addon and Addon.Diagnostics
    if diagnostics and type(diagnostics.DebugIfEnabled) == "function" then
        diagnostics:DebugIfEnabled("TrackerHostLayout", fmt, ...)
        return
    end

    local debugFn = Addon and Addon.Debug
    if debugFn and ((Addon.IsDebugEnabled and Addon:IsDebugEnabled() == true) or Addon.debugEnabled == true) then
        debugFn("[TrackerHostLayout] " .. tostring(fmt), ...)
    end
end

local DEFAULT_SECTION_ORDER = { "quest", "achievement" }
local ANCHOR_TOLERANCE = 0.01

local function getHost(host)
    if type(host) == "table" then
        return host
    end

    if type(Addon.TrackerHost) == "table" then
        return Addon.TrackerHost
    end

    return nil
end

local function getSectionOrder(host)
    if host and type(host.GetSectionOrder) == "function" then
        local order = host.GetSectionOrder()
        if type(order) == "table" and #order > 0 then
            return order
        end
    end

    return DEFAULT_SECTION_ORDER
end

local function getSectionGap(host)
    if host and type(host.GetSectionGap) == "function" then
        local gap = host.GetSectionGap()
        gap = tonumber(gap)
        if gap then
            if gap < 0 then
                gap = 0
            end
            return gap
        end
    end

    return 0
end

local function getSectionParent(host)
    if host and type(host.GetSectionParent) == "function" then
        local parent = host.GetSectionParent()
        if parent ~= nil then
            return parent
        end
    end

    return nil
end

local function getSectionContainer(host, sectionId)
    if host and type(host.GetSectionContainer) == "function" then
        return host.GetSectionContainer(sectionId)
    end

    return nil
end

local function getSectionTracker(host, sectionId)
    if host and type(host.GetSectionTracker) == "function" then
        return host.GetSectionTracker(sectionId)
    end

    return nil
end

local function getLayoutSettings(host)
    if host and type(host.GetLayoutSettings) == "function" then
        return host.GetLayoutSettings()
    end

    return nil
end

local function getWindowBars(host)
    if host and type(host.GetWindowBarSettings) == "function" then
        return host.GetWindowBarSettings()
    end

    return nil
end

local function getHeaderControl(host)
    if host and type(host.GetHeaderControl) == "function" then
        return host.GetHeaderControl()
    end

    return nil
end

local function getFooterControl(host)
    if host and type(host.GetFooterControl) == "function" then
        return host.GetFooterControl()
    end

    return nil
end

local function getContentStack(host)
    if host and type(host.GetContentStack) == "function" then
        return host.GetContentStack()
    end

    return nil
end

local function getScrollContent(host)
    if host and type(host.GetScrollContent) == "function" then
        return host.GetScrollContent()
    end

    return nil
end

local function getScrollContainer(host)
    if host and type(host.GetScrollContainer) == "function" then
        return host.GetScrollContainer()
    end

    return nil
end

local function getScrollbar(host)
    if host and type(host.GetScrollbar) == "function" then
        return host.GetScrollbar()
    end

    return nil
end

local function getScrollbarWidth(host)
    if host and type(host.GetScrollbarWidth) == "function" then
        local width = host.GetScrollbarWidth()
        if width ~= nil then
            width = tonumber(width)
            if width then
                return width
            end
        end
    end

    local scrollbar = getScrollbar(host)
    if scrollbar and type(scrollbar.GetWidth) == "function" then
        local ok, measured = pcall(scrollbar.GetWidth, scrollbar)
        if ok then
            measured = tonumber(measured)
            if measured then
                return measured
            end
        end
    end

    return 0
end

local function getScrollOvershootPadding(host)
    if host and type(host.GetScrollOvershootPadding) == "function" then
        local padding = host.GetScrollOvershootPadding()
        padding = tonumber(padding)
        if padding then
            if padding < 0 then
                padding = 0
            end
            return padding
        end
    end

    return 0
end

local function getScrollContentRightOffset(host)
    if host and type(host.GetScrollContentRightOffset) == "function" then
        local offset = host.GetScrollContentRightOffset()
        offset = tonumber(offset)
        if offset then
            return offset
        end
    end

    return 0
end

local function setScrollContentRightOffset(host, offset)
    if host and type(host.SetScrollContentRightOffset) == "function" then
        host.SetScrollContentRightOffset(offset)
    end
end

local function updateScrollbarRange(host, minimum, maximum)
    if host and type(host.UpdateScrollbarRange) == "function" then
        host.UpdateScrollbarRange(minimum, maximum)
        return
    end

    local scrollbar = getScrollbar(host)
    if not (scrollbar and type(scrollbar.SetMinMax) == "function") then
        return
    end

    pcall(scrollbar.SetMinMax, scrollbar, minimum or 0, maximum or 0)
end

local function setScrollbarHidden(host, hidden)
    if host and type(host.SetScrollbarHidden) == "function" then
        host.SetScrollbarHidden(hidden)
        return
    end

    local scrollbar = getScrollbar(host)
    if scrollbar and type(scrollbar.SetHidden) == "function" then
        scrollbar:SetHidden(hidden)
    end
end

local function setScrollMaxOffset(host, maxOffset)
    if host and type(host.SetScrollMaxOffset) == "function" then
        host.SetScrollMaxOffset(maxOffset)
    end
end

local function getScrollState(host)
    if host and type(host.GetScrollState) == "function" then
        local state = host.GetScrollState()
        if type(state) == "table" then
            return state
        end
    end

    local actual = 0
    local desired

    if host and type(host.GetScrollOffset) == "function" then
        actual = tonumber(host.GetScrollOffset()) or 0
    end

    return { actual = actual, desired = desired }
end

local function setScrollOffset(host, offset, skipScrollbarUpdate)
    if host and type(host.SetScrollOffset) == "function" then
        host.SetScrollOffset(offset, skipScrollbarUpdate)
    end
end

local function isControlHidden(control)
    if not control then
        return true
    end

    local isHidden = control.IsHidden
    if type(isHidden) == "function" then
        local hidden = isHidden(control)
        if hidden ~= nil then
            return hidden == true
        end
    end

    return false
end

local function measureSection(host, sectionId, container)
    local width = 0
    local height = 0

    if host and type(host.GetSectionMeasurements) == "function" then
        local measuredWidth, measuredHeight = host.GetSectionMeasurements(sectionId)
        width = tonumber(measuredWidth) or 0
        height = tonumber(measuredHeight) or 0
    end

    if (width <= 0 or height <= 0) and container then
        local holder = container.holder
        if holder and holder.GetWidth and holder.GetHeight then
            width = math.max(width, tonumber(holder:GetWidth()) or 0)
            height = math.max(height, tonumber(holder:GetHeight()) or 0)
        else
            if container.GetWidth then
                width = math.max(width, tonumber(container:GetWidth()) or 0)
            end
            if container.GetHeight then
                height = math.max(height, tonumber(container:GetHeight()) or 0)
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

local function resolveSectionHeight(host, sectionId, container)
    local tracker = getSectionTracker(host, sectionId)
    local height = 0

    if tracker then
        local getHeight = tracker.GetHeight or tracker.GetContentHeight
        if type(getHeight) == "function" then
            local ok, measured = pcall(getHeight, tracker)
            if ok and measured ~= nil then
                height = tonumber(measured) or height
            end
        end

        if height <= 0 then
            local getSize = tracker.GetContentSize or tracker.GetSize
            if type(getSize) == "function" then
                local ok, widthOrHeight, maybeHeight = pcall(getSize, tracker)
                if ok then
                    if maybeHeight ~= nil then
                        height = tonumber(maybeHeight) or height
                    else
                        height = tonumber(widthOrHeight) or height
                    end
                end
            end
        end
    end

    if height <= 0 and container and type(container.GetHeight) == "function" then
        local ok, measuredHeight = pcall(container.GetHeight, container)
        if ok and measuredHeight ~= nil then
            height = tonumber(measuredHeight) or height
        end
    end

    if height <= 0 then
        local _, fallbackHeight = measureSection(host, sectionId, container)
        height = fallbackHeight
    end

    if height < 0 or height ~= height then
        height = 0
    end

    return height
end

local function getAnchor(control, index)
    if type(control.GetAnchor) ~= "function" then
        return nil
    end

    local ok, point, relativeTo, relativePoint, offsetX, offsetY = pcall(control.GetAnchor, control, index)
    if not ok then
        return nil
    end

    return point, relativeTo, relativePoint, offsetX or 0, offsetY or 0
end

local function anchorsMatch(control, anchors)
    if type(control.GetNumAnchors) ~= "function" then
        return false
    end

    local numAnchors = control:GetNumAnchors()
    if numAnchors ~= #anchors then
        return false
    end

    for index, expected in ipairs(anchors) do
        local anchorIndex = index - 1
        local point, relativeTo, relativePoint, offsetX, offsetY = getAnchor(control, anchorIndex)
        if not point then
            return false
        end

        if point ~= expected.point or relativeTo ~= expected.relativeTo or relativePoint ~= expected.relativePoint then
            return false
        end

        if math.abs((offsetX or 0) - (expected.offsetX or 0)) > ANCHOR_TOLERANCE then
            return false
        end

        if math.abs((offsetY or 0) - (expected.offsetY or 0)) > ANCHOR_TOLERANCE then
            return false
        end
    end

    return true
end

local function applyAnchors(control, anchors)
    if not control or type(control.ClearAnchors) ~= "function" or type(control.SetAnchor) ~= "function" then
        return false
    end

    if anchorsMatch(control, anchors) then
        return false
    end

    control:ClearAnchors()

    for _, anchor in ipairs(anchors) do
        control:SetAnchor(anchor.point, anchor.relativeTo, anchor.relativePoint, anchor.offsetX or 0, anchor.offsetY or 0)
    end

    return true
end

local function reportAnchored(host, sectionId)
    if host and type(host.ReportSectionAnchored) == "function" then
        host.ReportSectionAnchored(sectionId)
    end
end

local function reportMissing(host, sectionId)
    if host and type(host.ReportSectionMissing) == "function" then
        host.ReportSectionMissing(sectionId)
    end
end

local function sanitizeLength(value)
    local number = tonumber(value)
    if not number then
        return 0
    end

    if number < 0 then
        number = 0
    end

    return number
end

local function resolvePadding(layout, keys)
    if type(layout) ~= "table" then
        return 0
    end

    for _, key in ipairs(keys) do
        local value = layout[key]
        if value ~= nil then
            local number = tonumber(value)
            if number then
                if number < 0 then
                    number = 0
                end
                return number
            end
        end
    end

    return 0
end

local function numbersDiffer(a, b, tolerance)
    if a == b then
        return false
    end

    if a == nil or b == nil then
        return true
    end

    if a == math.huge or b == math.huge then
        return a ~= b
    end

    tolerance = tolerance or ANCHOR_TOLERANCE
    return math.abs(a - b) > tolerance
end

local function copyTable(source)
    if type(source) ~= "table" then
        return source
    end

    local target = {}
    for key, value in pairs(source) do
        target[key] = value
    end

    return target
end

Layout._lastSizes = Layout._lastSizes or nil
Layout._lastScrollMetrics = Layout._lastScrollMetrics or setmetatable({}, { __mode = "k" })

function Layout.UpdateHeaderFooterSizes(host)
    host = getHost(host)

    local result = {
        headerHeight = 0,
        footerHeight = 0,
        headerTargetHeight = 0,
        footerTargetHeight = 0,
        headerVisible = false,
        footerVisible = false,
        headerPadding = 0,
        footerPadding = 0,
        contentTopPadding = 0,
        contentBottomPadding = 0,
        contentTopY = 0,
        contentBottomY = math.huge,
        headerChanged = false,
        footerChanged = false,
        changed = false,
    }

    if not host then
        Layout._lastSizes = copyTable(result)
        return result
    end

    local layout = getLayoutSettings(host)
    local headerPadding = resolvePadding(layout, { "headerPadding", "contentPaddingTop", "contentPadding" })
    local footerPadding = resolvePadding(layout, { "footerPadding", "contentPaddingBottom", "contentPadding" })

    local bars = getWindowBars(host) or {}
    local headerTargetHeight = sanitizeLength(bars.headerHeightPx)
    local footerTargetHeight = sanitizeLength(bars.footerHeightPx)

    local headerVisible = headerTargetHeight > 0
    local footerVisible = footerTargetHeight > 0

    local headerControl = getHeaderControl(host)
    local footerControl = getFooterControl(host)

    local headerEffectiveHeight = headerTargetHeight
    if headerControl and type(headerControl.GetHeight) == "function" then
        local ok, measured = pcall(headerControl.GetHeight, headerControl)
        if ok then
            measured = sanitizeLength(measured)
            if measured > 0 then
                headerEffectiveHeight = measured
            end
        end
    end
    if not headerVisible then
        headerEffectiveHeight = 0
    end

    local footerEffectiveHeight = footerTargetHeight
    if footerControl and type(footerControl.GetHeight) == "function" then
        local ok, measured = pcall(footerControl.GetHeight, footerControl)
        if ok then
            measured = sanitizeLength(measured)
            if measured > 0 then
                footerEffectiveHeight = measured
            end
        end
    end
    if not footerVisible then
        footerEffectiveHeight = 0
    end

    local parent = getSectionParent(host)
    local contentStack = getContentStack(host)
    local scrollContent = getScrollContent(host)
    local scrollContainer = getScrollContainer(host)

    local contentTopY
    if parent and contentStack and parent == contentStack then
        contentTopY = headerPadding
    else
        contentTopY = headerEffectiveHeight + headerPadding
    end
    contentTopY = sanitizeLength(contentTopY)

    local contentBottomY

    if scrollContainer and type(scrollContainer.GetHeight) == "function" then
        local ok, height = pcall(scrollContainer.GetHeight, scrollContainer)
        if ok then
            height = sanitizeLength(height)
            if height > 0 then
                contentBottomY = contentTopY + height
            end
        end
    end

    if not contentBottomY then
        if parent and contentStack and parent == contentStack then
            local parentHeight = parent.GetHeight and parent:GetHeight()
            parentHeight = tonumber(parentHeight)
            if parentHeight and parentHeight > 0 then
                contentBottomY = math.max(contentTopY, sanitizeLength(parentHeight) - footerPadding)
            end
        else
            local container = scrollContent or parent
            local totalHeight = container and container.GetHeight and container:GetHeight()
            totalHeight = tonumber(totalHeight)
            if totalHeight and totalHeight > 0 then
                local candidate = sanitizeLength(totalHeight) - (footerEffectiveHeight + footerPadding)
                contentBottomY = math.max(contentTopY, candidate)
            end
        end
    end

    if not contentBottomY or contentBottomY <= contentTopY then
        contentBottomY = math.huge
    end

    local last = Layout._lastSizes
    local headerChanged = not last
        or numbersDiffer(last.headerTargetHeight, headerTargetHeight)
        or numbersDiffer(last.headerHeight, headerEffectiveHeight)
        or (last.headerVisible ~= headerVisible)
        or numbersDiffer(last.headerPadding or 0, headerPadding)
    local footerChanged = not last
        or numbersDiffer(last.footerTargetHeight, footerTargetHeight)
        or numbersDiffer(last.footerHeight, footerEffectiveHeight)
        or (last.footerVisible ~= footerVisible)
        or numbersDiffer(last.footerPadding or 0, footerPadding)

    local topChanged = not last or numbersDiffer(last.contentTopY, contentTopY)
    local bottomChanged = not last or numbersDiffer(last.contentBottomY, contentBottomY)
    local changed = headerChanged or footerChanged or topChanged or bottomChanged

    result.headerHeight = headerEffectiveHeight
    result.footerHeight = footerEffectiveHeight
    result.headerTargetHeight = headerTargetHeight
    result.footerTargetHeight = footerTargetHeight
    result.headerVisible = headerVisible
    result.footerVisible = footerVisible
    result.headerPadding = headerPadding
    result.footerPadding = footerPadding
    result.contentTopPadding = headerPadding
    result.contentBottomPadding = footerPadding
    result.contentTopY = contentTopY
    result.contentBottomY = contentBottomY
    result.headerChanged = headerChanged
    result.footerChanged = footerChanged
    result.changed = changed

    Layout._lastSizes = {
        headerHeight = headerEffectiveHeight,
        footerHeight = footerEffectiveHeight,
        headerTargetHeight = headerTargetHeight,
        footerTargetHeight = footerTargetHeight,
        headerVisible = headerVisible,
        footerVisible = footerVisible,
        headerPadding = headerPadding,
        footerPadding = footerPadding,
        contentTopY = contentTopY,
        contentBottomY = contentBottomY,
    }

    return result
end

function Layout.UpdateScrollAreaHeight(host, scrollChildHeight, sizes, viewportHeight)
    host = getHost(host)
    if not host then
        return 0
    end

    if type(sizes) ~= "table" then
        sizes = Layout.UpdateHeaderFooterSizes(host)
    end

    local scrollContainer = getScrollContainer(host)
    local scrollContent = getScrollContent(host)
    if not (scrollContainer and scrollContent) then
        return 0
    end

    local metrics = Layout._lastScrollMetrics
    local last = metrics[host]
    if not last then
        last = {}
        metrics[host] = last
    end

    local targetHeight = sanitizeLength(scrollChildHeight)
    if targetHeight < 0 then
        targetHeight = 0
    end

    if type(scrollContent.SetResizeToFitDescendents) == "function" then
        scrollContent:SetResizeToFitDescendents(false)
    end

    if type(scrollContent.SetHeight) == "function" then
        if not last.scrollChildHeight or numbersDiffer(last.scrollChildHeight, targetHeight) then
            scrollContent:SetHeight(targetHeight)
            last.scrollChildHeight = targetHeight
        end
    else
        last.scrollChildHeight = targetHeight
    end

    local topY = sizes and sanitizeLength(sizes.contentTopY) or 0
    local bottomY = sizes and tonumber(sizes.contentBottomY)
    local resolvedViewport = viewportHeight

    if not resolvedViewport or resolvedViewport <= 0 then
        if type(scrollContainer.GetHeight) == "function" then
            local ok, height = pcall(scrollContainer.GetHeight, scrollContainer)
            if ok then
                resolvedViewport = height
            end
        end
    end

    if (not resolvedViewport or resolvedViewport <= 0) and bottomY and bottomY ~= math.huge then
        resolvedViewport = bottomY - topY
    end

    resolvedViewport = sanitizeLength(resolvedViewport or 0)
    if resolvedViewport < 0 then
        resolvedViewport = 0
    end

    last.viewportHeight = resolvedViewport

    local maxOffset = math.max(targetHeight - resolvedViewport, 0)

    if not last.maxOffset or numbersDiffer(last.maxOffset, maxOffset) then
        setScrollMaxOffset(host, maxOffset)
        updateScrollbarRange(host, 0, maxOffset)
        last.maxOffset = maxOffset
    else
        setScrollMaxOffset(host, maxOffset)
    end

    local showScrollbar = maxOffset > 0.5
    local desiredRightOffset = 0

    if showScrollbar then
        local width = getScrollbarWidth(host)
        width = sanitizeLength(width)
        desiredRightOffset = -width
    end

    if not last.scrollbarHidden or last.scrollbarHidden ~= (not showScrollbar) then
        setScrollbarHidden(host, not showScrollbar)
        last.scrollbarHidden = not showScrollbar
    end

    local previousRightOffset = getScrollContentRightOffset(host)
    if numbersDiffer(previousRightOffset, desiredRightOffset) then
        setScrollContentRightOffset(host, desiredRightOffset)
        last.rightOffset = desiredRightOffset
    else
        last.rightOffset = previousRightOffset
    end

    local state = getScrollState(host)
    local actual = state and tonumber(state.actual) or 0
    if actual > maxOffset then
        setScrollOffset(host, maxOffset, true)
    end

    return resolvedViewport
end

function Layout.ApplyLayout(host, sizes)
    host = getHost(host)
    if not host then
        return 0
    end

    if type(sizes) ~= "table" then
        sizes = Layout.UpdateHeaderFooterSizes(host)
    end

    local order = getSectionOrder(host)
    local firstSection = order[1]

    local parent = getSectionParent(host)
    local firstContainer = getSectionContainer(host, firstSection)

    if not parent or not firstContainer then
        if not firstContainer then
            reportMissing(host, firstSection)
        end
        return 0
    end

    local gap = getSectionGap(host)

    local startOffset = sanitizeLength(sizes and sizes.contentTopY)
    local topPadding = sanitizeLength(sizes and sizes.contentTopPadding)
    local bottomPadding = sanitizeLength(sizes and sizes.contentBottomPadding)
    local limitBottom = sizes and tonumber(sizes.contentBottomY)
    if limitBottom and (limitBottom == math.huge or limitBottom <= startOffset) then
        limitBottom = nil
    end

    local accumulatedSectionHeight = 0
    local measuredGapCount = 0
    local previousVisible
    local measuredVisibleCount = 0
    local currentTop = startOffset
    local anchoringStopped = false

    for _, sectionId in ipairs(order) do
        local container = getSectionContainer(host, sectionId)
        if not container then
            reportMissing(host, sectionId)
        else
            local height = resolveSectionHeight(host, sectionId, container)
            local sectionVisible = not isControlHidden(container)
            local shouldAnchor = not anchoringStopped

            if sectionVisible and shouldAnchor then
                local predictedBottom = currentTop + height
                if limitBottom and predictedBottom > (limitBottom + ANCHOR_TOLERANCE) then
                    shouldAnchor = false
                    anchoringStopped = true
                end
            end

            if shouldAnchor then
                local anchors
                local offsetY = 0
                local anchorTarget

                if previousVisible then
                    anchorTarget = previousVisible
                    offsetY = gap
                    anchors = {
                        { point = TOPLEFT, relativeTo = anchorTarget, relativePoint = BOTTOMLEFT, offsetX = 0, offsetY = offsetY },
                        { point = TOPRIGHT, relativeTo = anchorTarget, relativePoint = BOTTOMRIGHT, offsetX = 0, offsetY = offsetY },
                    }
                else
                    anchorTarget = parent
                    anchors = {
                        { point = TOPLEFT, relativeTo = anchorTarget, relativePoint = TOPLEFT, offsetX = 0, offsetY = offsetY },
                        { point = TOPRIGHT, relativeTo = anchorTarget, relativePoint = TOPRIGHT, offsetX = 0, offsetY = offsetY },
                    }
                end

                if not previousVisible then
                    anchors[1].offsetY = startOffset
                    anchors[2].offsetY = startOffset
                end

                applyAnchors(container, anchors)
                reportAnchored(host, sectionId)
            end

            if sectionVisible then
                if measuredVisibleCount > 0 then
                    measuredGapCount = measuredGapCount + 1
                end

                accumulatedSectionHeight = accumulatedSectionHeight + height
                measuredVisibleCount = measuredVisibleCount + 1

                if shouldAnchor then
                    currentTop = currentTop + height + gap
                    previousVisible = container
                end
            end
        end
    end

    local contentHeight = topPadding + accumulatedSectionHeight + (gap * measuredGapCount) + bottomPadding
    contentHeight = sanitizeLength(contentHeight)
    if contentHeight < 0 then
        contentHeight = 0
    end

    local headerHeight = 0
    if sizes and sizes.headerVisible ~= false then
        headerHeight = sanitizeLength(sizes.headerTargetHeight or sizes.headerHeight)
    end

    local footerHeight = 0
    if sizes and sizes.footerVisible ~= false then
        footerHeight = sanitizeLength(sizes.footerTargetHeight or sizes.footerHeight)
    end

    local scrollOverhang = sanitizeLength(getScrollOvershootPadding(host))
    local viewportHeight
    local scrollContainer = getScrollContainer(host)

    if scrollContainer and type(scrollContainer.GetHeight) == "function" then
        local ok, measured = pcall(scrollContainer.GetHeight, scrollContainer)
        if ok then
            viewportHeight = measured
        end
    end

    if (not viewportHeight or viewportHeight <= 0) and limitBottom and limitBottom ~= math.huge then
        viewportHeight = limitBottom - startOffset
    end

    viewportHeight = sanitizeLength(viewportHeight or 0)
    if viewportHeight < 0 then
        viewportHeight = 0
    end

    local scrollChildHeight = headerHeight + contentHeight + footerHeight + scrollOverhang
    local minScrollChild = viewportHeight + scrollOverhang
    if scrollChildHeight < minScrollChild then
        scrollChildHeight = minScrollChild
    end

    scrollChildHeight = math.ceil(scrollChildHeight)
    if scrollChildHeight < 0 then
        scrollChildHeight = 0
    end

    local resolvedViewport = Layout.UpdateScrollAreaHeight(host, scrollChildHeight, sizes, viewportHeight)
    resolvedViewport = resolvedViewport or viewportHeight

    debugLog(
        "Layout metrics header=%.2f content=%.2f footer=%.2f overhang=%.2f viewport=%.2f scrollChild=%.2f sections=%.2f gaps=%d",
        headerHeight,
        contentHeight,
        footerHeight,
        scrollOverhang,
        resolvedViewport,
        scrollChildHeight,
        accumulatedSectionHeight,
        measuredGapCount
    )

    return contentHeight
end

Layout.Apply = Layout.ApplyLayout

return Layout
