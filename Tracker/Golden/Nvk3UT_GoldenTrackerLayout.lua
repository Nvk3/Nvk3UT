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

local function resolveDiagnostics()
    local root = Nvk3UT
    if type(root) == "table" then
        local diagnostics = root.Diagnostics
        if type(diagnostics) == "table" then
            return diagnostics
        end
    end

    if type(Nvk3UT_Diagnostics) == "table" then
        return Nvk3UT_Diagnostics
    end

    return nil
end

local function isDiagnosticsDebugEnabled()
    local diagnostics = resolveDiagnostics()
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(diagnostics.IsDebugEnabled, diagnostics)
        if ok and enabled then
            return true
        end
    end

    return false
end

local function diagnosticsDebug(message, ...)
    if not isDiagnosticsDebugEnabled() then
        return
    end

    local diagnostics = resolveDiagnostics()
    if diagnostics and type(diagnostics.Debug) == "function" then
        local payload = message
        if select("#", ...) > 0 then
            local ok, formatted = pcall(string.format, message, ...)
            if ok then
                payload = formatted
            end
        end

        pcall(diagnostics.Debug, diagnostics, payload)
    end
end

function Layout.ApplyLayout(parentControl, rows)
    local debugEnabled = isDiagnosticsDebugEnabled()
    local rowsTable = type(rows) == "table" and rows or {}
    local rowCount = #rowsTable
    local parentName = tostring(parentControl)
    if isControl(parentControl) and type(parentControl.GetName) == "function" then
        local ok, resolvedName = pcall(parentControl.GetName, parentControl)
        if ok and type(resolvedName) == "string" and resolvedName ~= "" then
            parentName = resolvedName
        end
    end

    if debugEnabled then
        diagnosticsDebug("[Golden.Layout] apply parent=%s rows=%d", parentName, rowCount)
    end

    if not isControl(parentControl) or type(rows) ~= "table" then
        if debugEnabled then
            diagnosticsDebug("[Golden.Layout] final height=0 fallback=false")
        end
        return 0
    end

    clearChildren(parentControl)

    local totalHeight = 0
    local previousControl = nil

    for index = 1, rowCount do
        local row = rowsTable[index]
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
            if debugEnabled then
                diagnosticsDebug("[Golden.Layout] y+=%d → total=%d", tonumber(height) or 0, totalHeight)
            end
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

    local fallbackApplied = (rowCount == 0 and totalHeight == MIN_HEIGHT)
    if debugEnabled then
        diagnosticsDebug("[Golden.Layout] final height=%d fallback=%s", totalHeight, tostring(fallbackApplied))
    end

    safeDebug("ApplyLayout rows=%d height=%d", rowCount, totalHeight)

    return totalHeight
end

Nvk3UT.GoldenTrackerLayout = Layout

return Layout
