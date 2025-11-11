local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local MODULE_TAG = addonName .. ".EndeavorTrackerRows"

local lastHeight = 0

local ROW_MIN_HEIGHT = 28

local function safeDebug(fmt, ...)
    local root = rawget(_G, addonName)
    if type(root) ~= "table" then
        return
    end

    local diagnostics = root.Diagnostics
    if diagnostics and type(diagnostics.DebugIfEnabled) == "function" then
        diagnostics:DebugIfEnabled("EndeavorTrackerRows", fmt, ...)
        return
    end

    local debugMethod = root.Debug
    if type(debugMethod) == "function" then
        if fmt == nil then
            debugMethod(root, ...)
        else
            debugMethod(root, fmt, ...)
        end
        return
    end

    if fmt == nil then
        return
    end

    local message = string.format(tostring(fmt), ...)
    local prefix = string.format("[%s]", MODULE_TAG)
    if d then
        d(prefix, message)
    elseif print then
        print(prefix, message)
    end
end

local function coerceNumber(value)
    if type(value) == "number" then
        if value ~= value then -- NaN guard
            return 0
        end
        return value
    end

    return 0
end

local function clearChildren(container)
    if not container or type(container.GetNumChildren) ~= "function" then
        return
    end

    local count = container:GetNumChildren() or 0
    for index = count, 1, -1 do
        local child = container:GetChild(index)
        if child then
            child:ClearAnchors()
            if child.SetHidden then
                child:SetHidden(true)
            end
            if child.DestroyWindow then
                child:DestroyWindow()
            else
                child:SetParent(nil)
            end
        end
    end
end

local function getLabelText(item, index)
    if type(item) ~= "table" then
        return string.format("Activity %d", index)
    end

    local text = item.name or item.label or item.title or item.text
    if text == nil or text == "" then
        text = string.format("Activity %d", index)
    end

    return tostring(text)
end

function Rows.Init()
    lastHeight = 0
end

function Rows.Clear(container)
    clearChildren(container)

    lastHeight = 0

    if container and type(container.SetHeight) == "function" then
        container:SetHeight(0)
    end

    safeDebug("EndeavorRows.Clear: height reset to 0")

    return 0
end

function Rows.Build(container, items)
    if not container then
        lastHeight = 0
        return 0
    end

    clearChildren(container)

    local sequence = {}
    if type(items) == "table" then
        for index, entry in ipairs(items) do
            sequence[#sequence + 1] = entry
        end
    end

    local count = #sequence
    if count == 0 then
        if type(container.SetHeight) == "function" then
            container:SetHeight(0)
        end
        lastHeight = 0
        safeDebug("EndeavorRows.Build: count=0 total=0")
        return 0
    end

    local wm = WINDOW_MANAGER
    if wm == nil then
        lastHeight = 0
        return 0
    end

    local totalHeight = 0
    local previous
    local containerName
    if type(container.GetName) == "function" then
        local ok, name = pcall(container.GetName, container)
        if ok then
            containerName = name
        end
    end

    for index, entry in ipairs(sequence) do
        local rowName = string.format("%sRow%d", containerName or "Nvk3UT_Endeavor", index)
        local row = wm:CreateControl(rowName, container, CT_CONTROL)

        row:ClearAnchors()
        if previous then
            row:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, 0)
            row:SetAnchor(TOPRIGHT, previous, BOTTOMRIGHT, 0, 0)
        else
            row:SetAnchor(TOPLEFT, container, TOPLEFT, 0, 0)
            row:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, 0)
        end

        local rowHeight = ROW_MIN_HEIGHT
        row:SetHeight(rowHeight)

        local labelName = rowName .. "Label"
        local label = wm:CreateControl(labelName, row, CT_LABEL)
        label:ClearAnchors()
        label:SetAnchor(TOPLEFT, row, TOPLEFT, 0, 0)
        label:SetAnchor(BOTTOMRIGHT, row, BOTTOMRIGHT, 0, 0)
        label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
        label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
        if label.SetFont then
            label:SetFont("ZoFontGame")
        end
        label:SetText(getLabelText(entry, index))

        totalHeight = totalHeight + coerceNumber(rowHeight)
        previous = row
    end

    if type(container.SetHeight) == "function" then
        container:SetHeight(totalHeight)
    end

    lastHeight = totalHeight

    safeDebug("EndeavorRows.Build: count=%d total=%d", count, totalHeight)

    return totalHeight
end

function Rows.GetLastHeight()
    return coerceNumber(lastHeight)
end

Nvk3UT.EndeavorTrackerRows = Rows

return Rows
