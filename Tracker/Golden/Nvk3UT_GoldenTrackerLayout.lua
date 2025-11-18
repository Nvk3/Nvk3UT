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

local function isDebugEnabled()
    local root = rawget(_G, addonName)
    if type(root) ~= "table" then
        return false
    end

    if type(root.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return root:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local diagnostics = rawget(root, "Diagnostics")
    if type(diagnostics) == "table" and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return diagnostics:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    return false
end

local function safeDebug(message, ...)
    if not isDebugEnabled() then
        return
    end

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
    local visibleCount = 0
    local rowCount = 0

    local function getControlHeight(control, fallback)
        if control and type(control.GetHeight) == "function" then
            local ok, height = pcall(control.GetHeight, control)
            if ok and type(height) == "number" and height > 0 then
                return height
            end
        end

        return fallback or 0
    end

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

            local height = getControlHeight(row, fallbackHeight)

            if visibleCount > 0 then
                totalHeight = totalHeight + (gap or 0)
            end

            totalHeight = totalHeight + height
            safeDebug(
                "Row %d '%s' parent=%s hidden=%s height=%s",
                index,
                row.GetName and row:GetName() or "<unnamed>",
                row.GetParent and row:GetParent() and row:GetParent():GetName() or "<nil>",
                tostring(row.IsHidden and row:IsHidden()),
                tostring(height)
            )
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
