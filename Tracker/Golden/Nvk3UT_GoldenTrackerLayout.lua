local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Layout = {}
Layout.__index = Layout

local MODULE_TAG = addonName .. ".GoldenTrackerLayout"

local CATEGORY_HEADER_HEIGHT = 26
local ROW_HEIGHT = 24
local HEADER_TO_ROWS_GAP = 3
local ROW_GAP = 3
local SECTION_BOTTOM_GAP = 3
local SECTION_BOTTOM_GAP_COLLAPSED = 3
local BOTTOM_PIXEL_NUDGE = 3

local function safeDebug(message, ...)
    local debugFn = Nvk3UT and Nvk3UT.Debug
    if type(debugFn) ~= "function" then
        return
    end

    local payload = message
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, message, ...)
        if ok then
            payload = formatted
        end
    end

    pcall(debugFn, string.format("%s: %s", MODULE_TAG, tostring(payload)))
end

local function clearChildren(control)
    if not control then
        return
    end

    local getNumChildren = control.GetNumChildren
    local getChild = control.GetChild
    if type(getNumChildren) ~= "function" or type(getChild) ~= "function" then
        return
    end

    local okCount, childCount = pcall(getNumChildren, control)
    if not okCount or type(childCount) ~= "number" or childCount <= 0 then
        return
    end

    for index = childCount - 1, 0, -1 do
        local okChild, child = pcall(getChild, control, index)
        if okChild and child then
            if child.ClearAnchors then
                child:ClearAnchors()
            end
            if child.SetParent then
                child:SetParent(nil)
            end
            if child.SetHidden then
                child:SetHidden(true)
            end
        end
    end
end

local function getParentWidth(control)
    if not control or type(control.GetWidth) ~= "function" then
        return 0
    end

    local ok, width = pcall(control.GetWidth, control)
    if ok and type(width) == "number" then
        return width
    end

    return 0
end

local function applyDimensions(row, parentWidth)
    if not row then
        return
    end

    local height = tonumber(row and row.__height) or 0
    if height < 0 then
        height = 0
    end

    if row.SetDimensions then
        row:SetDimensions(parentWidth, height)
        return
    end

    if row.SetHeight then
        row:SetHeight(height)
    end
end

function Layout.ApplyLayout(parentControl, rows)
    if not parentControl then
        safeDebug("ApplyLayout abort: parent missing")
        return 0
    end

    if type(rows) ~= "table" then
        rows = {}
    end

    if parentControl.SetResizeToFitDescendents then
        parentControl:SetResizeToFitDescendents(false)
    end
    if parentControl.SetInsets then
        parentControl:SetInsets(0, 0, 0, 0)
    end

    safeDebug(
        "ApplyLayout parent=%s parentParent=%s rows=%d",
        parentControl.GetName and parentControl:GetName() or "<nil>",
        parentControl.GetParent and parentControl:GetParent() and parentControl:GetParent():GetName() or "<nil>",
        #rows
    )

    local totalHeight = 0
    local previousRow = nil
    local previousKind = nil
    local parentWidth = getParentWidth(parentControl)
    local visibleCount = 0
    local rowCount = 0

    local function anchor(control, gap)
        if control == nil then
            return
        end

        if control.ClearAnchors then
            control:ClearAnchors()
        end

        if previousRow then
            local resolvedGap = gap or ROW_GAP
            control:SetAnchor(TOPLEFT, previousRow, BOTTOMLEFT, 0, resolvedGap)
            control:SetAnchor(TOPRIGHT, previousRow, BOTTOMRIGHT, 0, resolvedGap)
        else
            control:SetAnchor(TOPLEFT, parentControl, TOPLEFT, 0, 0)
            control:SetAnchor(TOPRIGHT, parentControl, TOPRIGHT, 0, 0)
        end

        previousRow = control
    end

    for index = 1, #rows do
        local row = rows[index]
        if row and (type(row) == "userdata" or type(row) == "table") then
            local rowKind = row.__rowKind or (index == 1 and "header" or "row")
            local fallbackHeight = rowKind == "header" and CATEGORY_HEADER_HEIGHT or ROW_HEIGHT

            if type(row.SetParent) == "function" then
                row:SetParent(parentControl)
            end

            if type(row.SetHidden) == "function" then
                row:SetHidden(false)
            end

            local gap
            if visibleCount > 0 then
                if previousKind == "header" then
                    gap = HEADER_TO_ROWS_GAP
                else
                    gap = ROW_GAP
                end
            end

            anchor(row, gap)
            applyDimensions(row, parentWidth)

            local height = tonumber(row.__height) or 0
            if type(row.GetHeight) == "function" then
                local ok, measured = pcall(row.GetHeight, row)
                if ok and type(measured) == "number" then
                    height = measured
                end
            end

            if height ~= height or height < 0 then
                height = fallbackHeight
            elseif height == 0 then
                height = fallbackHeight
            end

            if visibleCount > 0 then
                totalHeight = totalHeight + (gap or 0)
            end

            totalHeight = totalHeight + height
            visibleCount = visibleCount + 1
            previousKind = rowKind
            if rowKind ~= "header" then
                rowCount = rowCount + 1
            end
        end
    end

    local categoryExpanded = rowCount > 0
    if categoryExpanded and rowCount > 0 then
        totalHeight = totalHeight + SECTION_BOTTOM_GAP
    elseif visibleCount > 0 then
        totalHeight = totalHeight + SECTION_BOTTOM_GAP_COLLAPSED
    end

    if visibleCount > 0 then
        totalHeight = totalHeight + BOTTOM_PIXEL_NUDGE
    end

    safeDebug("ApplyLayout rows=%d height=%d", #rows, totalHeight)

    return totalHeight
end

Nvk3UT.GoldenTrackerLayout = Layout

return Layout
