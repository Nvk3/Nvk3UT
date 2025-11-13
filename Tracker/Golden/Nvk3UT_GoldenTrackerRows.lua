local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local MODULE_TAG = addonName .. ".GoldenTrackerRows"

local DEFAULTS = {
    CATEGORY_HEIGHT = 44,
    CATEGORY_FONT = "ZoFontHeader2",
    CATEGORY_COLOR = {1, 1, 1, 1},
    CATEGORY_LABEL_OFFSET_X = 16,
}

local controlCounters = {
    category = 0,
}

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

local function getWindowManager()
    local wm = rawget(_G, "WINDOW_MANAGER")
    if wm == nil then
        safeDebug("WINDOW_MANAGER unavailable; skipping row creation")
    end
    return wm
end

local function resolveParentName(parent)
    if parent and type(parent.GetName) == "function" then
        local ok, name = pcall(parent.GetName, parent)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end

    return "Nvk3UT_Golden"
end

local function nextControlName(parent, kind)
    controlCounters[kind] = (controlCounters[kind] or 0) + 1
    local parentName = resolveParentName(parent)
    return string.format("%s_%sRow%u", parentName, kind, controlCounters[kind])
end

local function applyLabelDefaults(label)
    if not label then
        return
    end

    if label.SetFont and DEFAULTS.CATEGORY_FONT then
        label:SetFont(DEFAULTS.CATEGORY_FONT)
    end

    if label.SetColor and type(DEFAULTS.CATEGORY_COLOR) == "table" then
        local color = DEFAULTS.CATEGORY_COLOR
        label:SetColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end

    if label.SetWrapMode and rawget(_G, "TEXT_WRAP_MODE_ELLIPSIS") then
        label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    end

    if label.SetHorizontalAlignment and rawget(_G, "TEXT_ALIGN_LEFT") then
        label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    end

    if label.SetVerticalAlignment and rawget(_G, "TEXT_ALIGN_CENTER") then
        label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    end
end

local function createCategoryControl(parent)
    local wm = getWindowManager()
    if wm == nil then
        return nil
    end

    local controlName = nextControlName(parent, "category")
    local control = wm:CreateControl(controlName, parent, CT_CONTROL)
    if not control then
        return nil
    end

    if control.SetResizeToFitDescendents then
        control:SetResizeToFitDescendents(false)
    end
    if control.SetMouseEnabled then
        control:SetMouseEnabled(false)
    end
    if control.SetHidden then
        control:SetHidden(false)
    end
    if control.SetHeight then
        control:SetHeight(DEFAULTS.CATEGORY_HEIGHT)
    end

    control.__height = DEFAULTS.CATEGORY_HEIGHT

    return control
end

local function ensureCategoryLabel(control)
    if not isControl(control) then
        return nil
    end

    if type(control.__categoryLabel) == "userdata" then
        return control.__categoryLabel
    end

    local wm = getWindowManager()
    if wm == nil then
        return nil
    end

    local parentName = resolveParentName(control)
    local labelName = string.format("%s_CategoryLabel", parentName)
    local label = wm:CreateControl(labelName, control, CT_LABEL)
    if not label then
        return nil
    end

    if label.SetHidden then
        label:SetHidden(false)
    end

    if label.ClearAnchors then
        label:ClearAnchors()
    end

    local offsetX = DEFAULTS.CATEGORY_LABEL_OFFSET_X or 0
    if label.SetAnchor then
        label:SetAnchor(LEFT, control, LEFT, offsetX, 0)
        label:SetAnchor(RIGHT, control, RIGHT, -offsetX, 0)
    end

    applyLabelDefaults(label)

    control.__categoryLabel = label

    return label
end

local function formatCategoryName(categoryData)
    local name = ""
    if type(categoryData) == "table" then
        name = categoryData.name or categoryData.title or ""
    end

    if type(name) ~= "string" then
        name = tostring(name or "")
    end

    if name ~= "" then
        local ok, upper = pcall(string.upper, name)
        if ok and type(upper) == "string" then
            name = upper
        end
    end

    return name
end

function Rows.CreateCategoryHeader(parent, categoryData)
    if parent == nil then
        safeDebug("CreateCategoryHeader skipped: parent missing")
        return nil
    end

    local control = createCategoryControl(parent)
    if not control then
        safeDebug("CreateCategoryHeader failed: control missing")
        return nil
    end

    local row = {
        control = control,
        height = DEFAULTS.CATEGORY_HEIGHT,
    }

    Rows.UpdateCategoryHeader(row, categoryData)

    return row
end

function Rows.UpdateCategoryHeader(row, categoryData)
    if type(row) ~= "table" then
        return
    end

    local control = row.control
    if not isControl(control) then
        return
    end

    control.__height = DEFAULTS.CATEGORY_HEIGHT
    if control.SetHeight then
        control:SetHeight(DEFAULTS.CATEGORY_HEIGHT)
    end
    if control.SetHidden then
        control:SetHidden(false)
    end

    local label = row.label or ensureCategoryLabel(control)
    row.label = label
    if label then
        if label.SetHidden then
            label:SetHidden(false)
        end
        if label.SetText then
            label:SetText(formatCategoryName(categoryData))
        end
    else
        safeDebug("UpdateCategoryHeader warning: label unavailable; fallback header should cover display")
    end

    row.height = DEFAULTS.CATEGORY_HEIGHT
end

function Rows.AcquireCategoryHeader(parent, recycledRow, categoryData)
    local debugEnabled = isDiagnosticsDebugEnabled()
    local wm = rawget(_G, "WINDOW_MANAGER")
    if debugEnabled and (not isControl(parent) or wm == nil) then
        diagnosticsDebug("[Golden.Rows] WARN cannot create header: parent=%s WM=%s", tostring(parent), tostring(wm))
    end

    local row = recycledRow
    if type(row) ~= "table" or not isControl(row.control) then
        row = Rows.CreateCategoryHeader(parent, categoryData)
        if debugEnabled and row == nil then
            diagnosticsDebug("[Golden.Rows] WARN header creation returned nil (factory path)")
        end
    else
        if row.control.SetParent then
            row.control:SetParent(parent)
        end
        Rows.UpdateCategoryHeader(row, categoryData)
    end

    if debugEnabled and type(row) == "table" and isControl(row.control) then
        local control = row.control
        local controlName = nil
        if type(control.GetName) == "function" then
            local ok, name = pcall(control.GetName, control)
            if ok then
                controlName = name
            end
        end

        local height = tonumber(row.height) or 0
        if height == 0 and type(control.GetHeight) == "function" then
            local okHeight, measured = pcall(control.GetHeight, control)
            if okHeight and tonumber(measured) then
                height = tonumber(measured)
            end
        end
        if height == 0 and tonumber(control.__height) then
            height = tonumber(control.__height)
        end

        diagnosticsDebug("[Golden.Rows] header '%s' h=%d", tostring(controlName or control), height)
    end

    return row
end

function Rows.ReleaseRow(row)
    if type(row) ~= "table" then
        return
    end

    local control = row.control
    if not isControl(control) then
        return
    end

    if control.ClearAnchors then
        control:ClearAnchors()
    end
    if control.SetHidden then
        control:SetHidden(true)
    end
    if control.SetParent then
        control:SetParent(nil)
    end
end

Nvk3UT.GoldenTrackerRows = Rows

return Rows
