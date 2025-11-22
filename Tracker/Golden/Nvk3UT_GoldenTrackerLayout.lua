local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Layout = {}
Layout.__index = Layout

local MODULE_TAG = addonName .. ".GoldenTrackerLayout"

local ROW_GAP = 3
local Rows = Nvk3UT and Nvk3UT.GoldenTrackerRows

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

local function getRowsModule()
    if type(Rows) == "table" then
        return Rows
    end

    Rows = Nvk3UT and Nvk3UT.GoldenTrackerRows
    if type(Rows) == "table" then
        return Rows
    end

    return nil
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

local function coerceHeight(value)
    local numeric = tonumber(value)
    if numeric == nil or numeric ~= numeric then
        return 0
    end

    if numeric < 0 then
        numeric = 0
    end

    return numeric
end

local function getControlHeight(control, fallback)
    if control and type(control.GetHeight) == "function" then
        local ok, height = pcall(control.GetHeight, control)
        if ok then
            local measured = coerceHeight(height)
            if measured > 0 then
                return measured
            end
        end
    end

    return coerceHeight(fallback)
end

local function resolveRowKind(control, rowData)
    if type(rowData) == "table" and rowData.__rowKind then
        return rowData.__rowKind
    end

    if type(rowData) == "table" and rowData.control and rowData.control.__rowKind then
        return rowData.control.__rowKind
    end

    if control and control.__rowKind then
        return control.__rowKind
    end

    return nil
end

local function resolveRowHeight(control, rowData)
    local rowsModule = getRowsModule()
    local kind = resolveRowKind(control, rowData)
    local fallback

    if rowsModule then
        if kind == "category" and type(rowsModule.GetCategoryRowHeight) == "function" then
            fallback = rowsModule.GetCategoryRowHeight()
        elseif kind == "entry" and type(rowsModule.GetEntryRowHeight) == "function" then
            fallback = rowsModule.GetEntryRowHeight()
        end
    end

    if fallback == nil then
        fallback = (rowData and rowData.__height) or (control and control.__height) or 0
    end

    return getControlHeight(control, fallback)
end

local function applyDimensions(row, parentWidth, resolvedHeight)
    if not row then
        return
    end

    local height = coerceHeight(resolvedHeight or (row and row.__height))

    if row.SetDimensions then
        row:SetDimensions(parentWidth, height)
        return
    end

    if row.SetHeight then
        row:SetHeight(height)
    end
end

local function resolveControl(row)
    if type(row) == "table" and row.control then
        return row.control, row
    end

    return row, row
end

function Layout.ApplyLayout(parentControl, rows)
    if not parentControl then
        safeDebug("ApplyLayout abort: parent missing")
        return 0
    end

    if type(rows) ~= "table" then
        rows = {}
    end

    safeDebug(
        "ApplyLayout parent=%s parentParent=%s rows=%d",
        parentControl.GetName and parentControl:GetName() or "<nil>",
        parentControl.GetParent and parentControl:GetParent() and parentControl:GetParent():GetName() or "<nil>",
        #rows
    )

    local totalHeight = 0
    local previousRow = nil
    local parentWidth = getParentWidth(parentControl)

    local rowsModule = getRowsModule()
    if rowsModule and type(rowsModule.GetCategoryRowHeight) == "function" and type(rowsModule.GetEntryRowHeight) == "function" then
        safeDebug(
            "ApplyLayout heights category=%s entry=%s",
            tostring(rowsModule.GetCategoryRowHeight()),
            tostring(rowsModule.GetEntryRowHeight())
        )
    end

    for index = 1, #rows do
        local row = rows[index]
        local control, rowData = resolveControl(row)
        if control and (type(control) == "userdata" or type(control) == "table") then
            if type(control.ClearAnchors) == "function" then
                control:ClearAnchors()
            end

            if type(control.SetParent) == "function" then
                control:SetParent(parentControl)
            end

            if type(control.SetHidden) == "function" then
                control:SetHidden(false)
            end

            if type(control.SetAnchor) == "function" then
                if previousRow and type(previousRow.SetAnchor) == "function" then
                    control:SetAnchor(TOPLEFT, previousRow, BOTTOMLEFT, 0, ROW_GAP)
                else
                    control:SetAnchor(TOPLEFT, parentControl, TOPLEFT, 0, 0)
                end
            end

            local height = resolveRowHeight(control, rowData)
            if control then
                control.__height = height
            end

            applyDimensions(control, parentWidth, height)

            if previousRow ~= nil then
                totalHeight = totalHeight + ROW_GAP
            end

            totalHeight = totalHeight + height
            previousRow = control
        end
    end

    safeDebug("ApplyLayout rows=%d height=%d", #rows, totalHeight)

    return totalHeight
end

Nvk3UT.GoldenTrackerLayout = Layout

return Layout
