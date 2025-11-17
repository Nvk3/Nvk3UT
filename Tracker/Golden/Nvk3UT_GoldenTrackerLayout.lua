local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Layout = {}
Layout.__index = Layout

local MODULE_TAG = addonName .. ".GoldenTrackerLayout"

local ROW_GAP = 3

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
    if not parentControl or type(rows) ~= "table" then
        return 0
    end

    local totalHeight = 0
    local previousRow = nil
    local parentWidth = getParentWidth(parentControl)

    for index = 1, #rows do
        local row = rows[index]
        if row and (type(row) == "userdata" or type(row) == "table") then
            if type(row.ClearAnchors) == "function" then
                row:ClearAnchors()
            end

            if type(row.SetParent) == "function" then
                row:SetParent(parentControl)
            end

            if type(row.SetHidden) == "function" then
                row:SetHidden(false)
            end

            if type(row.SetAnchor) == "function" then
                if previousRow and type(previousRow.SetAnchor) == "function" then
                    row:SetAnchor(TOPLEFT, previousRow, BOTTOMLEFT, 0, ROW_GAP)
                else
                    row:SetAnchor(TOPLEFT, parentControl, TOPLEFT, 0, 0)
                end
            end

            applyDimensions(row, parentWidth)

            local height = tonumber(row.__height) or 0
            if type(row.GetHeight) == "function" then
                local ok, measured = pcall(row.GetHeight, row)
                if ok and type(measured) == "number" then
                    height = measured
                end
            end

            if height ~= height or height < 0 then
                height = 0
            end

            if previousRow ~= nil then
                totalHeight = totalHeight + ROW_GAP
            end

            totalHeight = totalHeight + height
            previousRow = row
        end
    end

    safeDebug("ApplyLayout rows=%d height=%d", #rows, totalHeight)

    return totalHeight
end

Nvk3UT.GoldenTrackerLayout = Layout

return Layout
