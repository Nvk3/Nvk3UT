
local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local MODULE_TAG = addonName .. ".EndeavorTrackerRows"

local OBJECTIVE_ROW_HEIGHT = 20
local OBJECTIVE_TEXT_INDENT_X = 18
local OBJECTIVE_PROGRESS_WIDTH = 60
local QUEST_OBJECTIVE_FONT = "$(BOLD_FONT)|14|soft-shadow-thick"
local QUEST_PROGRESS_FONT = "$(BOLD_FONT)|14|soft-shadow-thick"
local QUEST_OBJECTIVE_COLOR_ROLE = "objectiveText"

Rows._cache = Rows._cache or setmetatable({}, { __mode = "k" })

local lastHeight = 0

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

local function coerceNumber(value)
    if type(value) == "number" then
        if value ~= value then
            return 0
        end
        return value
    end

    return 0
end

local function getAddon()
    return rawget(_G, addonName)
end

local function getQuestTrackerColor(role)
    local addon = getAddon()
    if type(addon) ~= "table" then
        return 1, 1, 1, 1
    end

    local host = rawget(addon, "TrackerHost")
    if type(host) ~= "table" then
        return 1, 1, 1, 1
    end

    if type(host.EnsureAppearanceDefaults) == "function" then
        pcall(host.EnsureAppearanceDefaults, host)
    end

    local getColor = host.GetTrackerColor
    if type(getColor) ~= "function" then
        return 1, 1, 1, 1
    end

    local ok, r, g, b, a = pcall(getColor, host, "questTracker", role)
    if ok and type(r) == "number" then
        return r, g or 1, b or 1, a or 1
    end

    return 1, 1, 1, 1
end

local function applyFont(label, font)
    if label and label.SetFont and font and font ~= "" then
        label:SetFont(font)
    end
end

local function applyObjectiveColors(label, progress, completed)
    local r, g, b, a = getQuestTrackerColor(QUEST_OBJECTIVE_COLOR_ROLE)
    if label and label.SetColor then
        label:SetColor(r, g, b, a)
    end
    if progress and progress.SetColor then
        progress:SetColor(r, g, b, a)
    end

    local alpha = completed and 0.6 or 1
    if label and label.SetAlpha then
        label:SetAlpha(alpha)
    end
    if progress and progress.SetAlpha then
        progress:SetAlpha(alpha)
    end

    return alpha
end

local function getContainerCache(container)
    if container == nil then
        return nil
    end

    local cache = Rows._cache[container]
    if type(cache) ~= "table" then
        cache = { rows = {}, lastHeight = 0 }
        Rows._cache[container] = cache
    elseif type(cache.rows) ~= "table" then
        cache.rows = {}
    end

    return cache
end

local function ensureObjectiveRow(container, baseName, index, previous)
    local wm = WINDOW_MANAGER
    if wm == nil then
        return nil
    end

    local cache = getContainerCache(container)
    if cache == nil then
        return nil
    end

    local rows = cache.rows
    local row = rows[index]
    if row and (type(row.GetName) ~= "function" or GetControl(row:GetName()) ~= row) then
        row = nil
    end

    local controlName = baseName .. index
    if not row then
        row = GetControl(controlName)
        if not row then
            row = wm:CreateControl(controlName, container, CT_CONTROL)
        end
        rows[index] = row
    end

    row:SetParent(container)
    row:SetResizeToFitDescendents(false)
    row:SetMouseEnabled(false)
    row:SetHidden(false)
    row:SetHeight(OBJECTIVE_ROW_HEIGHT)
    row:ClearAnchors()
    if previous then
        row:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, 0)
        row:SetAnchor(TOPRIGHT, previous, BOTTOMRIGHT, 0, 0)
    else
        row:SetAnchor(TOPLEFT, container, TOPLEFT, 0, 0)
        row:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, 0)
    end

    return row
end

function Rows.ApplyObjectiveRow(row, objective)
    if row == nil then
        return
    end

    local wm = WINDOW_MANAGER
    if wm == nil then
        return
    end

    local data = type(objective) == "table" and objective or {}
    local text = tostring(data.text or "")
    if text == "" then
        text = "Objective"
    end

    local maxValue = tonumber(data.max) or 0
    if maxValue < 1 then
        maxValue = 1
    end
    local progressValue = tonumber(data.progress) or 0
    if progressValue < 0 then
        progressValue = 0
    end
    if progressValue > maxValue then
        progressValue = maxValue
    end

    local completed = data.completed == true or progressValue >= maxValue
    local progressText
    if completed then
        progressText = "✓"
    else
        progressText = string.format("%d/%d", math.floor(progressValue + 0.5), math.floor(maxValue + 0.5))
    end

    local rowName = type(row.GetName) == "function" and row:GetName() or ""
    local titleName = rowName .. "Title"
    local progressName = rowName .. "Progress"

    if row.GetNamedChild then
        local bullet = row:GetNamedChild("Bullet")
        if bullet and bullet.SetHidden then
            bullet:SetHidden(true)
        end
        local icon = row:GetNamedChild("Icon")
        if icon and icon.SetHidden then
            icon:SetHidden(true)
        end
        local dot = row:GetNamedChild("Dot")
        if dot and dot.SetHidden then
            dot:SetHidden(true)
        end
    end

    local title = GetControl(titleName)
    if not title then
        title = wm:CreateControl(titleName, row, CT_LABEL)
    end
    title:SetParent(row)
    applyFont(title, QUEST_OBJECTIVE_FONT)
    title:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    title:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    title:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    title:ClearAnchors()
    title:SetAnchor(TOPLEFT, row, TOPLEFT, OBJECTIVE_TEXT_INDENT_X, 0)
    title:SetAnchor(BOTTOMRIGHT, row, BOTTOMRIGHT, -(OBJECTIVE_PROGRESS_WIDTH + 8), 0)
    title:SetText(text)

    local progress = GetControl(progressName)
    if not progress then
        progress = wm:CreateControl(progressName, row, CT_LABEL)
    end
    progress:SetParent(row)
    applyFont(progress, QUEST_PROGRESS_FONT)
    progress:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    progress:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    progress:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    progress:ClearAnchors()
    progress:SetAnchor(TOPRIGHT, row, TOPRIGHT, -4, 0)
    progress:SetAnchor(BOTTOMRIGHT, row, BOTTOMRIGHT, -4, 0)
    if progress.SetWidth then
        progress:SetWidth(OBJECTIVE_PROGRESS_WIDTH)
    elseif progress.SetDimensions then
        progress:SetDimensions(OBJECTIVE_PROGRESS_WIDTH, OBJECTIVE_ROW_HEIGHT)
    end
    progress:SetText(progressText)

    local alpha = applyObjectiveColors(title, progress, completed)

    if row.SetAlpha then
        row:SetAlpha(alpha)
    end
end

function Rows.Init()
    Rows._cache = setmetatable({}, { __mode = "k" })
    lastHeight = 0
end

function Rows.ClearObjectives(container)
    local cache = getContainerCache(container)
    if cache then
        local rows = cache.rows or {}
        for index = 1, #rows do
            local row = rows[index]
            if row and row.SetHidden then
                row:SetHidden(true)
            end
        end
        cache.lastHeight = 0
    end

    if container and container.SetHeight then
        container:SetHeight(0)
    end

    lastHeight = 0

    safeDebug("[EndeavorRows.ClearObjectives] container=%s", container and (container.GetName and select(2, pcall(container.GetName, container))) or "<nil>")

    return 0
end

function Rows.BuildObjectives(container, list)
    if container == nil then
        lastHeight = 0
        return 0
    end

    local cache = getContainerCache(container)
    if cache == nil then
        lastHeight = 0
        return 0
    end

    local sequence = {}
    if type(list) == "table" then
        for index = 1, #list do
            sequence[#sequence + 1] = list[index]
        end
    end

    local count = #sequence
    if count == 0 then
        Rows.ClearObjectives(container)
        safeDebug("[EndeavorRows.BuildObjectives] count=0")
        return 0
    end

    local containerName = nil
    if type(container.GetName) == "function" then
        local ok, name = pcall(container.GetName, container)
        if ok and type(name) == "string" then
            containerName = name
        end
    end
    local baseName = (containerName or "Nvk3UT_Endeavor") .. "Obj"

    local totalHeight = 0
    local previous

    for index = 1, count do
        local row = ensureObjectiveRow(container, baseName, index, previous)
        if row then
            Rows.ApplyObjectiveRow(row, sequence[index])
            previous = row
            totalHeight = totalHeight + OBJECTIVE_ROW_HEIGHT
        end
    end

    local rows = cache.rows
    for index = count + 1, #rows do
        local extra = rows[index]
        if extra and extra.SetHidden then
            extra:SetHidden(true)
        end
    end

    if container.SetHeight then
        container:SetHeight(totalHeight)
    end

    cache.lastHeight = totalHeight
    lastHeight = totalHeight

    safeDebug("[EndeavorRows.BuildObjectives] count=%d height=%d", count, totalHeight)

    return totalHeight
end

function Rows.GetMeasuredHeight(container)
    local cache = getContainerCache(container)
    if cache then
        return coerceNumber(cache.lastHeight)
    end
    return 0
end

function Rows.GetLastHeight()
    return coerceNumber(lastHeight)
end

Nvk3UT.EndeavorTrackerRows = Rows

return Rows
