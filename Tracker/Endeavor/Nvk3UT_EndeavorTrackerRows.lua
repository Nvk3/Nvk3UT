local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local MODULE_TAG = addonName .. ".EndeavorTrackerRows"

local lastHeight = 0

local ROW_MIN_HEIGHT = 28

Rows._cache = Rows._cache or setmetatable({}, { __mode = "k" })

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

local function getContainerCache(container)
    if not container then
        return nil
    end

    local cache = Rows._cache[container]
    if not cache then
        cache = { rows = {} }
        Rows._cache[container] = cache
    end

    return cache
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

local function applyRowData(row, item, index)
    if not row or type(row.GetName) ~= "function" then
        return
    end

    local wm = WINDOW_MANAGER
    if not wm then
        return
    end

    local rowName = row:GetName()
    local labelName = rowName .. "Label"
    local label = GetControl(labelName)
    if not label then
        label = wm:CreateControl(labelName, row, CT_LABEL)
    end

    label:SetParent(row)
    if label.ClearAnchors then
        label:ClearAnchors()
    end
    label:SetAnchor(TOPLEFT, row, TOPLEFT, 0, 0)
    label:SetAnchor(BOTTOMRIGHT, row, BOTTOMRIGHT, 0, 0)
    label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    if label.SetFont then
        label:SetFont("ZoFontGame")
    end

    if label.SetHidden then
        label:SetHidden(false)
    end

    if label.SetText then
        label:SetText(getLabelText(item, index))
    end
end

function Rows.Init()
    lastHeight = 0
end

function Rows.Clear(container)
    local cache = getContainerCache(container)
    if cache then
        local rows = cache.rows
        if type(rows) == "table" then
            for index = 1, #rows do
                local row = rows[index]
                if row and row.SetHidden then
                    row:SetHidden(true)
                end
            end
        end
    end

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

    local sequence = {}
    if type(items) == "table" then
        for index, entry in ipairs(items) do
            sequence[#sequence + 1] = entry
        end
    end

    local count = #sequence
    if count == 0 then
        Rows.Clear(container)
        safeDebug("[EndeavorRows.Build] count=0 reused=0 new=0 hidden=0")
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

    local baseName = string.format("%sRow", containerName or "Nvk3UT_Endeavor")
    local cache = getContainerCache(container)
    local rows = cache and cache.rows or {}
    local reused = 0
    local created = 0

    for index, entry in ipairs(sequence) do
        local row = rows[index]
        if row and (type(row.GetName) ~= "function" or GetControl(row:GetName()) ~= row) then
            row = nil
        end

        if not row then
            local controlName = baseName .. index
            row = GetControl(controlName)
            if not row then
                row = wm:CreateControl(controlName, container, CT_CONTROL)
                created = created + 1
            else
                reused = reused + 1
            end
            rows[index] = row
        else
            reused = reused + 1
        end

        row:SetParent(container)
        if row.SetHidden then
            row:SetHidden(false)
        end

        row:ClearAnchors()
        if previous then
            row:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, 0)
            row:SetAnchor(TOPRIGHT, previous, BOTTOMRIGHT, 0, 0)
        else
            row:SetAnchor(TOPLEFT, container, TOPLEFT, 0, 0)
            row:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, 0)
        end

        row:SetHeight(ROW_MIN_HEIGHT)
        applyRowData(row, entry, index)

        totalHeight = totalHeight + ROW_MIN_HEIGHT
        previous = row
    end

    cache.rows = rows

    local hidden = 0
    for index = count + 1, #rows do
        local extra = rows[index]
        if extra and extra.SetHidden then
            extra:SetHidden(true)
            hidden = hidden + 1
        end
    end

    if type(container.SetHeight) == "function" then
        container:SetHeight(totalHeight)
    end

    lastHeight = totalHeight

    safeDebug("[EndeavorRows.Build] count=%d reused=%d new=%d hidden=%d", count, reused, created, hidden)

    return totalHeight
end

function Rows.GetLastHeight()
    return coerceNumber(lastHeight)
end

Nvk3UT.EndeavorTrackerRows = Rows

return Rows
