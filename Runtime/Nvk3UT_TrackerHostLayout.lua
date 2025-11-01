Nvk3UT = Nvk3UT or {}
local Addon = Nvk3UT

Addon.TrackerHostLayout = Addon.TrackerHostLayout or {}
local Layout = Addon.TrackerHostLayout

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

    local contentTopY
    if parent and contentStack and parent == contentStack then
        contentTopY = headerPadding
    else
        contentTopY = headerEffectiveHeight + headerPadding
    end
    contentTopY = sanitizeLength(contentTopY)

    local contentBottomY
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

function Layout.ApplyLayout(host)
    host = getHost(host)
    if not host then
        return 0
    end

    local sizes = Layout.UpdateHeaderFooterSizes(host)

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

    local totalHeight = topPadding
    local previousVisible
    local visibleCount = 0
    local currentTop = startOffset

    for _, sectionId in ipairs(order) do
        local container = getSectionContainer(host, sectionId)
        if not container then
            reportMissing(host, sectionId)
        else
            local _, height = measureSection(host, sectionId, container)
            local sectionVisible = not isControlHidden(container)

            if sectionVisible then
                local predictedBottom = currentTop + height
                if limitBottom and predictedBottom > (limitBottom + ANCHOR_TOLERANCE) then
                    break
                end
            end

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

            if sectionVisible then
                if visibleCount > 0 then
                    totalHeight = totalHeight + gap
                end

                totalHeight = totalHeight + height
                currentTop = currentTop + height + gap
                previousVisible = container
                visibleCount = visibleCount + 1
            end
        end
    end

    totalHeight = totalHeight + bottomPadding

    if totalHeight < 0 then
        totalHeight = 0
    end

    return totalHeight
end

Layout.Apply = Layout.ApplyLayout

return Layout
