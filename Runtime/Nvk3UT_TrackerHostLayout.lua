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

function Layout.ApplyLayout(host)
    host = getHost(host)
    if not host then
        return 0
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

    local totalHeight = 0
    local previousVisible
    local visibleCount = 0

    for _, sectionId in ipairs(order) do
        local container = getSectionContainer(host, sectionId)
        if not container then
            reportMissing(host, sectionId)
        else
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

            applyAnchors(container, anchors)
            reportAnchored(host, sectionId)

            local _, height = measureSection(host, sectionId, container)
            local sectionVisible = not isControlHidden(container)

            if sectionVisible then
                if visibleCount > 0 then
                    totalHeight = totalHeight + gap
                end

                totalHeight = totalHeight + height
                previousVisible = container
                visibleCount = visibleCount + 1
            end
        end
    end

    return totalHeight
end

Layout.Apply = Layout.ApplyLayout

return Layout
