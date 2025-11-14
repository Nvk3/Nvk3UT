local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local MODULE_TAG = addonName .. ".GoldenTrackerRows"

local DEFAULTS = {
    CATEGORY_HEIGHT = 24,
    ENTRY_HEIGHT = 22,
    OBJECTIVE_HEIGHT = 20,
    CATEGORY_FONT = "ZoFontGameBold",
    ENTRY_FONT = "ZoFontGameMedium",
    OBJECTIVE_FONT = "ZoFontGameSmall",
    CATEGORY_COLOR = {1, 1, 1, 1},
    ENTRY_COLOR = {1, 1, 1, 1},
    OBJECTIVE_COLOR = {1, 1, 1, 1},
    OBJECTIVE_INDENT_X = 14,
}

local controlCounters = {
    category = 0,
    entry = 0,
    objective = 0,
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

local function applyLabelDefaults(label, font, color)
    if not label then
        return
    end

    if label.SetFont and font then
        label:SetFont(font)
    end

    if label.SetColor and type(color) == "table" then
        label:SetColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
    end

    if label.SetWrapMode and rawget(_G, "TEXT_WRAP_MODE_ELLIPSIS") then
        label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    end
end

local function createControl(parent, kind)
    local wm = getWindowManager()
    if wm == nil then
        return nil
    end

    if parent == nil then
        safeDebug("createControl skipped; parent missing for kind '%s'", tostring(kind))
        return nil
    end

    local controlName = nextControlName(parent, kind)
    local control = wm:CreateControl(controlName, parent, CT_CONTROL)
    if control and control.SetResizeToFitDescendents then
        control:SetResizeToFitDescendents(true)
    end
    if control and control.SetHidden then
        control:SetHidden(false)
    end

    return control
end

local function createLabel(parent, suffix)
    local wm = getWindowManager()
    if wm == nil or parent == nil then
        return nil
    end

    local baseName = resolveParentName(parent)
    local labelName = string.format("%s_%sLabel", baseName, suffix)
    local label = wm:CreateControl(labelName, parent, CT_LABEL)
    if label and label.SetHidden then
        label:SetHidden(false)
    end

    return label
end

function Rows.CreateCategoryHeader(parent, categoryData)
    if parent == nil then
        return nil
    end

    local control = createControl(parent, "category")
    if not control then
        return nil
    end

    control.__height = DEFAULTS.CATEGORY_HEIGHT
    if control.SetHeight then
        control:SetHeight(DEFAULTS.CATEGORY_HEIGHT)
    end

    local label = createLabel(control, "Category")
    if label then
        if label.SetAnchor then
            label:SetAnchor(LEFT, control, LEFT, 0, 0)
        end
        applyLabelDefaults(label, DEFAULTS.CATEGORY_FONT, DEFAULTS.CATEGORY_COLOR)

        local text = ""
        if type(categoryData) == "table" then
            local display = categoryData.displayName or categoryData.title or categoryData.name
            if display == nil then
                display = ""
            end
            text = tostring(display)
        end
        if label.SetText then
            label:SetText(text)
        end
    end

    return control
end

function Rows.CreateEntryRow(parent, entryData)
    if parent == nil then
        return nil
    end

    local control = createControl(parent, "entry")
    if not control then
        return nil
    end

    control.__height = DEFAULTS.ENTRY_HEIGHT
    if control.SetHeight then
        control:SetHeight(DEFAULTS.ENTRY_HEIGHT)
    end

    local label = createLabel(control, "EntryTitle")
    if label then
        if label.SetAnchor then
            label:SetAnchor(LEFT, control, LEFT, 0, 0)
        end
        applyLabelDefaults(label, DEFAULTS.ENTRY_FONT, DEFAULTS.ENTRY_COLOR)

        local text = ""
        if type(entryData) == "table" then
            local display = entryData.displayName or entryData.title or entryData.name
            if display == nil then
                display = ""
            end
            text = tostring(display)
        end
        if label.SetText then
            label:SetText(text)
        end
    end

        if type(entryData) == "table" then
            local counterText = entryData.counterText
            local count = tonumber(entryData.count or entryData.progressDisplay)
            local maxValue = tonumber(entryData.max or entryData.maxDisplay)
            if not counterText and count and maxValue then
                counterText = string.format("%d/%d", count, maxValue)
            end

            if counterText then
                local counterLabel = createLabel(control, "EntryCounter")
                if counterLabel then
                    if counterLabel.SetAnchor then
                        counterLabel:SetAnchor(RIGHT, control, RIGHT, 0, 0)
                    end
                    applyLabelDefaults(counterLabel, DEFAULTS.ENTRY_FONT, DEFAULTS.ENTRY_COLOR)
                    if counterLabel.SetHorizontalAlignment and rawget(_G, "TEXT_ALIGN_RIGHT") then
                        counterLabel:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
                    end
                    if counterLabel.SetText then
                        counterLabel:SetText(tostring(counterText))
                    end
                end
            end
        end

    return control
end

function Rows.CreateObjectiveRow(parent, objectiveData)
    if parent == nil then
        return nil
    end

    local control = createControl(parent, "objective")
    if not control then
        return nil
    end

    control.__height = DEFAULTS.OBJECTIVE_HEIGHT
    if control.SetHeight then
        control:SetHeight(DEFAULTS.OBJECTIVE_HEIGHT)
    end

    local label = createLabel(control, "Objective")
    if label then
        if label.SetAnchor then
            label:SetAnchor(LEFT, control, LEFT, DEFAULTS.OBJECTIVE_INDENT_X, 0)
        end
        applyLabelDefaults(label, DEFAULTS.OBJECTIVE_FONT, DEFAULTS.OBJECTIVE_COLOR)

        local text = ""
        if type(objectiveData) == "table" then
            local display = objectiveData.displayName or objectiveData.title or objectiveData.name or objectiveData.text
            if display == nil then
                display = ""
            end
            text = tostring(display)

            local counterText = objectiveData.counterText
            local progress = tonumber(objectiveData.progressDisplay or objectiveData.progress or objectiveData.current)
            local maxValue = tonumber(objectiveData.maxDisplay or objectiveData.max)
            if not counterText and progress and maxValue then
                counterText = string.format("%d/%d", progress, maxValue)
            end
            if counterText and counterText ~= "" then
                text = string.format("%s (%s)", text, counterText)
            end
        end

        if label.SetText then
            label:SetText(text)
        end
    end

    return control
end

Nvk3UT.GoldenTrackerRows = Rows

return Rows
