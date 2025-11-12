
local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Layout = {}
Layout.__index = Layout

local MODULE_TAG = addonName .. ".EndeavorTrackerLayout"

local CATEGORY_ROW_HEIGHT = 28
local SECTION_ROW_HEIGHT = 24

local lastHeight = 0

local function safeDebug(fmt, ...)
    local root = rawget(_G, addonName)
    if type(root) ~= "table" then
        return
    end

    local diagnostics = root.Diagnostics
    if diagnostics and type(diagnostics.DebugIfEnabled) == "function" then
        diagnostics:DebugIfEnabled("EndeavorTrackerLayout", fmt, ...)
        return
    end

    if fmt == nil then
        return
    end

    local message = string.format(tostring(fmt), ...)
    local prefix = string.format("[%s]", MODULE_TAG)
    if type(root.Debug) == "function" then
        root:Debug("%s %s", prefix, message)
    elseif type(d) == "function" then
        d(prefix, message)
    elseif type(print) == "function" then
        print(prefix, message)
    end
end

local function coerceHeight(value)
    if type(value) == "number" then
        if value ~= value then
            return 0
        end
        return value
    end

    return 0
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

    return fallback or 0
end

local function shouldExpand(entry)
    return type(entry) == "table" and entry.expanded == true
end

function Layout.Init()
    lastHeight = 0
end

function Layout.Apply(container, context)
    local measured = 0
    if container == nil then
        lastHeight = 0
        return 0
    end

    local previous
    local function anchor(control)
        if not control then
            return
        end

        if control.ClearAnchors then
            control:ClearAnchors()
        end

        if previous then
            control:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, 0)
            control:SetAnchor(TOPRIGHT, previous, BOTTOMRIGHT, 0, 0)
        else
            control:SetAnchor(TOPLEFT, container, TOPLEFT, 0, 0)
            control:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, 0)
        end

        previous = control
    end

    local data = type(context) == "table" and context or {}

    local categoryEntry = type(data.category) == "table" and data.category or {}
    local categoryControl = categoryEntry.control
    if categoryControl then
        if categoryControl.SetHidden then
            categoryControl:SetHidden(false)
        end
        anchor(categoryControl)
        measured = measured + getControlHeight(categoryControl, CATEGORY_ROW_HEIGHT)
    end

    local categoryExpanded = data.categoryExpanded == true

    local dailyEntry = type(data.daily) == "table" and data.daily or {}
    local dailyControl = dailyEntry.control
    local dailyObjectivesEntry = type(data.dailyObjectives) == "table" and data.dailyObjectives or {}
    local dailyObjectivesControl = dailyObjectivesEntry.control

    local weeklyEntry = type(data.weekly) == "table" and data.weekly or {}
    local weeklyControl = weeklyEntry.control
    local weeklyObjectivesEntry = type(data.weeklyObjectives) == "table" and data.weeklyObjectives or {}
    local weeklyObjectivesControl = weeklyObjectivesEntry.control

    if categoryExpanded then
        if dailyControl then
            if dailyControl.SetHidden then
                dailyControl:SetHidden(false)
            end
            anchor(dailyControl)
            measured = measured + getControlHeight(dailyControl, SECTION_ROW_HEIGHT)
        end

        if dailyObjectivesControl then
            if shouldExpand(dailyObjectivesEntry) then
                if dailyObjectivesControl.SetHidden then
                    dailyObjectivesControl:SetHidden(false)
                end
                anchor(dailyObjectivesControl)
                measured = measured + getControlHeight(dailyObjectivesControl, 0)
            elseif dailyObjectivesControl.SetHidden then
                dailyObjectivesControl:SetHidden(true)
            end
        end

        if weeklyControl then
            if weeklyControl.SetHidden then
                weeklyControl:SetHidden(false)
            end
            anchor(weeklyControl)
            measured = measured + getControlHeight(weeklyControl, SECTION_ROW_HEIGHT)
        end

        if weeklyObjectivesControl then
            if shouldExpand(weeklyObjectivesEntry) then
                if weeklyObjectivesControl.SetHidden then
                    weeklyObjectivesControl:SetHidden(false)
                end
                anchor(weeklyObjectivesControl)
                measured = measured + getControlHeight(weeklyObjectivesControl, 0)
            elseif weeklyObjectivesControl.SetHidden then
                weeklyObjectivesControl:SetHidden(true)
            end
        end
    else
        if dailyControl and dailyControl.SetHidden then
            dailyControl:SetHidden(true)
        end
        if dailyObjectivesControl and dailyObjectivesControl.SetHidden then
            dailyObjectivesControl:SetHidden(true)
        end
        if weeklyControl and weeklyControl.SetHidden then
            weeklyControl:SetHidden(true)
        end
        if weeklyObjectivesControl and weeklyObjectivesControl.SetHidden then
            weeklyObjectivesControl:SetHidden(true)
        end
    end

    if container and container.SetHeight then
        container:SetHeight(measured)
    end

    lastHeight = measured

    safeDebug("EndeavorTrackerLayout.Apply: height=%d", measured)

    return measured
end

function Layout.GetLastHeight()
    return coerceHeight(lastHeight)
end

Nvk3UT.EndeavorTrackerLayout = Layout

return Layout
