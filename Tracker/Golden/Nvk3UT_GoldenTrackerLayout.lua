local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Layout = {}
Layout.__index = Layout

local MODULE_TAG = addonName .. ".GoldenTrackerLayout"
local MIN_HEIGHT = 86

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

local function isControl(candidate)
    if type(candidate) ~= "userdata" then
        return false
    end

    if type(candidate.GetName) == "function" then
        return true
    end

    if type(candidate.GetType) == "function" then
        return true
    end

    if type(candidate.SetParent) == "function" then
        return true
    end

    return false
end

local function clearChildren(control)
    if not isControl(control) then
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
        if okChild and isControl(child) then
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

local function applyRowDimensions(control, height)
    if not isControl(control) then
        return
    end

    local numericHeight = tonumber(height) or 0
    if numericHeight < 0 then
        numericHeight = 0
    end

    if control.SetHeight then
        control:SetHeight(numericHeight)
    end

    control.__height = numericHeight
end

function Layout.ApplyLayout(parentControl, rows)
    if not isControl(parentControl) or type(rows) ~= "table" then
        return 0
    end

    clearChildren(parentControl)

    local totalHeight = 0
    local previousControl = nil
    local rowCount = #rows

    for index = 1, rowCount do
        local row = rows[index]
        local control = row and row.control
        local height = row and row.height

        if isControl(control) then
            if control.ClearAnchors then
                control:ClearAnchors()
            end
            if control.SetParent then
                control:SetParent(parentControl)
            end
            if control.SetHidden then
                control:SetHidden(false)
            end

            if control.SetAnchor then
                if isControl(previousControl) then
                    control:SetAnchor(TOPLEFT, previousControl, BOTTOMLEFT, 0, 0)
                    control:SetAnchor(TOPRIGHT, previousControl, BOTTOMRIGHT, 0, 0)
                else
                    control:SetAnchor(TOPLEFT, parentControl, TOPLEFT, 0, 0)
                    control:SetAnchor(TOPRIGHT, parentControl, TOPRIGHT, 0, 0)
                end
            end

            applyRowDimensions(control, height)

            totalHeight = totalHeight + (tonumber(height) or 0)
            previousControl = control
        end
    end

    if rowCount == 0 then
        totalHeight = MIN_HEIGHT
    end

    if parentControl.SetHeight then
        parentControl:SetHeight(totalHeight)
    end

    if parentControl.SetHidden then
        parentControl:SetHidden(false)
    end

    safeDebug("ApplyLayout rows=%d height=%d", rowCount, totalHeight)

    return totalHeight
end

Nvk3UT.GoldenTrackerLayout = Layout

return Layout
