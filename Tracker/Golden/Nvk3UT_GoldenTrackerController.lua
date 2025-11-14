-- Tracker/Golden/Nvk3UT_GoldenTrackerController.lua
-- Normalizes Golden tracker data into an Endeavor-style category/entry view model.

local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Controller = Nvk3UT.GoldenTrackerController or {}
Nvk3UT.GoldenTrackerController = Controller

local MODULE_TAG = addonName .. ".GoldenTrackerController"

local CATEGORY_DEFINITIONS = {
    {
        key = "daily",
        categoryId = "golden_daily",
        displayName = "Golden — Daily",
        summaryKey = "daily",
    },
    {
        key = "weekly",
        categoryId = "golden_weekly",
        displayName = "Golden — Weekly",
        summaryKey = "weekly",
    },
}

local DEFAULT_STATUS = {
    isAvailable = false,
    isLocked = false,
    hasEntries = false,
}

local state = {
    dirty = true,
    viewModel = nil,
}

local function getAddonRoot()
    local root = rawget(_G, addonName)
    if type(root) == "table" then
        return root
    end
    return Nvk3UT
end

local function getGoldenState()
    local root = getAddonRoot()
    if type(root) ~= "table" then
        return nil
    end

    local goldenState = rawget(root, "GoldenState")
    if type(goldenState) == "table" then
        return goldenState
    end

    return nil
end

local function isDebugEnabled()
    local root = getAddonRoot()

    local utils = root and root.Utils or Nvk3UT_Utils
    if type(utils) == "table" and type(utils.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(utils.IsDebugEnabled)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local diagnostics = root and root.Diagnostics or Nvk3UT_Diagnostics
    if type(diagnostics) == "table" and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return diagnostics:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    if type(root) == "table" and type(root.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return root:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local sv = root and (root.sv or root.SV)
    if type(sv) == "table" and sv.debug ~= nil then
        return sv.debug == true
    end

    return false
end

local function safeDebug(message, ...)
    if not isDebugEnabled() then
        return
    end

    local root = getAddonRoot()
    local debugFn = root and root.Debug
    if type(debugFn) ~= "function" then
        return
    end

    local payload = tostring(message)
    if select("#", ...) > 0 then
        local formatString = type(message) == "string" and message or payload
        local ok, formatted = pcall(string.format, formatString, ...)
        if ok and formatted ~= nil then
            payload = formatted
        end
    end

    pcall(debugFn, string.format("%s: %s", MODULE_TAG, tostring(payload)))
end

local function callStateMethod(goldenState, methodName)
    if type(goldenState) ~= "table" or type(methodName) ~= "string" then
        return nil
    end

    local method = goldenState[methodName]
    if type(method) ~= "function" then
        return nil
    end

    local ok, result = pcall(method, goldenState)
    if ok then
        return result
    end

    safeDebug("Call to GoldenState:%s failed: %s", methodName, tostring(result))
    return nil
end

local function copyStatus(status)
    local snapshot = {
        isAvailable = false,
        isLocked = false,
        hasEntries = false,
    }

    if type(status) == "table" then
        snapshot.isAvailable = status.isAvailable == true
        snapshot.isLocked = status.isLocked == true
        snapshot.hasEntries = status.hasEntries == true
    end

    return snapshot
end

local function resolveStateStatus(goldenState)
    local status = callStateMethod(goldenState, "GetSystemStatus")
    if type(status) == "table" then
        return copyStatus(status)
    end

    return copyStatus(DEFAULT_STATUS)
end

local function resolveExpansionFlags(goldenState)
    local headerExpanded = true
    local dailyExpanded = true
    local weeklyExpanded = true

    if goldenState then
        local header = callStateMethod(goldenState, "IsHeaderExpanded")
        if header ~= nil then
            headerExpanded = header ~= false
        end

        local daily = callStateMethod(goldenState, "IsDailyExpanded")
        if daily ~= nil then
            dailyExpanded = daily ~= false
        end

        local weekly = callStateMethod(goldenState, "IsWeeklyExpanded")
        if weekly ~= nil then
            weeklyExpanded = weekly ~= false
        end
    end

    return {
        header = headerExpanded,
        daily = dailyExpanded,
        weekly = weeklyExpanded,
    }
end

local function newEmptyCategory(definition, expanded)
    local displayName = definition.displayName or definition.key
    local isExpanded = expanded ~= false

    return {
        id = definition.categoryId,
        categoryKey = definition.key,
        key = definition.key,
        categoryId = definition.categoryId,
        type = definition.key,
        displayName = displayName,
        title = displayName,
        name = displayName,
        isExpanded = isExpanded,
        isCollapsed = not isExpanded,
        expanded = isExpanded,
        isVisible = true,
        entryCount = 0,
        completedCount = 0,
        totalCount = 0,
        hasEntries = false,
        timeRemainingSec = 0,
        remainingSeconds = 0,
        capLimit = 0,
        progressText = "0/0",
        entries = {},
    }
end

local function newEmptyViewModel(status, expansionFlags)
    local categories = {}
    local categoryExpansion = type(expansionFlags) == "table" and expansionFlags or nil

    for index = 1, #CATEGORY_DEFINITIONS do
        local definition = CATEGORY_DEFINITIONS[index]
        local expanded = nil
        if categoryExpansion then
            local value = categoryExpansion[definition.key]
            if value ~= nil then
                expanded = value ~= false
            end
        end
        categories[index] = newEmptyCategory(definition, expanded)
    end

    local summary = {
        totalEntries = 0,
        totalCompleted = 0,
        totalRemaining = 0,
        categories = {
            daily = { completed = 0, total = 0, limit = 0, remaining = 0, counterText = "0/0", hasEntries = false, timeRemainingSec = 0 },
            weekly = { completed = 0, total = 0, limit = 0, remaining = 0, counterText = "0/0", hasEntries = false, timeRemainingSec = 0 },
        },
    }

    local headerExpanded = true
    if categoryExpansion and categoryExpansion.header ~= nil then
        headerExpanded = categoryExpansion.header ~= false
    end

    return {
        header = {
            isExpanded = headerExpanded,
        },
        status = copyStatus(status or DEFAULT_STATUS),
        categories = categories,
        summary = summary,
    }
end

local function ensureViewModel()
    if type(state.viewModel) ~= "table" then
        state.viewModel = newEmptyViewModel()
        return state.viewModel
    end

    local vm = state.viewModel
    if type(vm.categories) ~= "table" then
        vm.categories = {}
    end
    if type(vm.header) ~= "table" then
        vm.header = { isExpanded = true }
    end
    if type(vm.status) ~= "table" then
        vm.status = copyStatus(DEFAULT_STATUS)
    end
    if type(vm.summary) ~= "table" then
        vm.summary = {
            totalEntries = 0,
            totalCompleted = 0,
            totalRemaining = 0,
            categories = {
                daily = { completed = 0, total = 0, limit = 0, remaining = 0, counterText = "0/0", hasEntries = false, timeRemainingSec = 0 },
                weekly = { completed = 0, total = 0, limit = 0, remaining = 0, counterText = "0/0", hasEntries = false, timeRemainingSec = 0 },
            },
        }
    else
        local categoriesSummary = vm.summary.categories
        if type(categoriesSummary) ~= "table" then
            vm.summary.categories = {
                daily = { completed = 0, total = 0, limit = 0, remaining = 0, counterText = "0/0", hasEntries = false, timeRemainingSec = 0 },
                weekly = { completed = 0, total = 0, limit = 0, remaining = 0, counterText = "0/0", hasEntries = false, timeRemainingSec = 0 },
            }
        else
            categoriesSummary.daily = categoriesSummary.daily or { completed = 0, total = 0, limit = 0, remaining = 0, counterText = "0/0", hasEntries = false, timeRemainingSec = 0 }
            categoriesSummary.weekly = categoriesSummary.weekly or { completed = 0, total = 0, limit = 0, remaining = 0, counterText = "0/0", hasEntries = false, timeRemainingSec = 0 }
        end
    end

    return vm
end

local function getGoldenModel()
    local root = getAddonRoot()
    if type(root) ~= "table" then
        return nil
    end

    local model = rawget(root, "GoldenModel")
    if type(model) == "table" then
        return model
    end

    return nil
end

local function callModelMethod(model, methodName)
    if type(model) ~= "table" or type(methodName) ~= "string" then
        return nil
    end

    local method = model[methodName]
    if type(method) ~= "function" then
        return nil
    end

    local ok, result = pcall(method, model)
    if ok then
        return result
    end

    safeDebug("Call to GoldenModel:%s failed: %s", methodName, tostring(result))
    return nil
end

local function clampNonNegative(value)
    local numeric = tonumber(value)
    if numeric == nil or numeric < 0 then
        return 0
    end
    return numeric
end

local function normalizeProgressPair(progress, maxProgress)
    local current = tonumber(progress) or 0
    if current < 0 then
        current = 0
    end

    local maxValue = tonumber(maxProgress) or 0
    if maxValue < 1 then
        maxValue = 1
    end

    return current, maxValue
end

local function buildObjectiveFromEntry(entryVm)
    local label = entryVm.description
    if label == nil or label == "" then
        label = entryVm.title
    end

    if label == nil then
        label = ""
    end

    local counterText = nil
    if (entryVm.progressDisplay or entryVm.count) and (entryVm.maxDisplay or entryVm.max) then
        local currentValue = tonumber(entryVm.progressDisplay or entryVm.count)
        local maxValue = tonumber(entryVm.maxDisplay or entryVm.max)
        if currentValue and maxValue then
            counterText = string.format("%d/%d", currentValue, maxValue)
        end
    end

    local objective = {
        objectiveId = tostring(entryVm.entryId) .. ":objective",
        id = tostring(entryVm.entryId) .. ":objective",
        categoryKey = entryVm.categoryKey,
        title = label,
        name = label,
        text = label,
        progress = entryVm.progressDisplay or entryVm.count,
        current = entryVm.progressDisplay or entryVm.count,
        max = entryVm.maxDisplay or entryVm.max,
        progressDisplay = entryVm.progressDisplay or entryVm.count,
        maxDisplay = entryVm.maxDisplay or entryVm.max,
        isComplete = entryVm.isComplete,
        isCompleted = entryVm.isComplete,
        remainingSeconds = entryVm.remainingSeconds,
        counterText = counterText,
    }

    return objective
end

local function normalizeEntry(definition, rawEntry, index)
    if type(rawEntry) ~= "table" then
        return nil
    end

    local entryId = rawEntry.id
    if entryId == nil or entryId == "" then
        entryId = string.format("%s:%d", tostring(definition.key), index)
    end

    local title = rawEntry.name
    if title == nil then
        title = ""
    else
        title = tostring(title)
    end

    local description = rawEntry.description
    if description == nil then
        description = ""
    else
        description = tostring(description)
    end

    local currentValue, maxValue = normalizeProgressPair(rawEntry.progress, rawEntry.maxProgress)
    local currentInt = math.floor(currentValue + 0.5)
    local maxInt = math.max(1, math.floor(maxValue + 0.5))
    local isComplete = rawEntry.isCompleted == true or (maxValue > 0 and currentValue >= maxValue)

    local remainingSeconds = rawEntry.timeRemainingSec
    if remainingSeconds == nil and rawEntry.remainingSeconds ~= nil then
        remainingSeconds = rawEntry.remainingSeconds
    end
    remainingSeconds = clampNonNegative(remainingSeconds)

    local progressText = string.format("%d/%d", currentInt, maxInt)

    local entryVm = {
        entryId = tostring(entryId),
        id = tostring(entryId),
        categoryKey = definition.key,
        categoryId = definition.categoryId,
        type = rawEntry.type or definition.key,
        entryType = rawEntry.type or definition.key,
        title = title,
        displayName = title,
        name = title,
        description = description,
        tooltip = description,
        current = currentValue,
        progressCurrent = currentValue,
        count = currentInt,
        max = maxInt,
        progressMax = maxValue,
        maxProgress = maxValue,
        maxDisplay = maxInt,
        progressDisplay = currentInt,
        isComplete = isComplete,
        isCompleted = isComplete,
        isVisible = true,
        isHidden = false,
        progressPercent = maxValue > 0 and currentValue / maxValue or 0,
        progressText = progressText,
        counterText = progressText,
        remainingSeconds = remainingSeconds,
        timeRemainingSec = remainingSeconds,
        objectives = {},
        index = index,
    }

    entryVm.objectives[1] = buildObjectiveFromEntry(entryVm)
    entryVm.hasObjectives = #entryVm.objectives > 0

    return entryVm
end

local function buildCategory(definition, rawCategory, counters, expanded)
    local categoryVm = newEmptyCategory(definition, expanded)

    if type(rawCategory) ~= "table" then
        return categoryVm
    end

    if type(rawCategory.name) == "string" and rawCategory.name ~= "" then
        local label = tostring(rawCategory.name)
        categoryVm.displayName = label
        categoryVm.title = label
        categoryVm.name = label
    end

    local entries = {}
    local rawEntries = type(rawCategory.entries) == "table" and rawCategory.entries or {}

    for index = 1, #rawEntries do
        local entryVm = normalizeEntry(definition, rawEntries[index], index)
        if entryVm then
            entries[#entries + 1] = entryVm
        end
    end

    categoryVm.entries = entries
    categoryVm.entryCount = #entries

    local countCompleted = tonumber(rawCategory.countCompleted)
    if countCompleted == nil then
        local completed = 0
        for index = 1, #entries do
            if entries[index].isComplete then
                completed = completed + 1
            end
        end
        countCompleted = completed
    end

    local countTotal = tonumber(rawCategory.countTotal)
    if countTotal == nil then
        countTotal = categoryVm.entryCount
    end

    categoryVm.completedCount = clampNonNegative(countCompleted)
    categoryVm.totalCount = clampNonNegative(countTotal)
    categoryVm.capLimit = categoryVm.totalCount
    categoryVm.limit = categoryVm.capLimit
    categoryVm.countCompleted = categoryVm.completedCount
    categoryVm.countTotal = categoryVm.totalCount
    categoryVm.counterText = categoryVm.progressText
    categoryVm.hasEntries = categoryVm.entryCount > 0

    local remaining = clampNonNegative(rawCategory.timeRemainingSec)
    categoryVm.timeRemainingSec = remaining
    categoryVm.remainingSeconds = remaining

    categoryVm.progressText = string.format(
        "%d/%d",
        math.floor(categoryVm.completedCount + 0.5),
        math.max(0, math.floor(categoryVm.totalCount + 0.5))
    )

    if type(rawCategory.expanded) == "boolean" then
        categoryVm.isExpanded = rawCategory.expanded
        categoryVm.isCollapsed = not rawCategory.expanded
    elseif expanded ~= nil then
        categoryVm.isExpanded = expanded ~= false
        categoryVm.isCollapsed = not categoryVm.isExpanded
    end

    if type(counters) == "table" and definition.summaryKey then
        local key = definition.summaryKey
        local completedKey = key .. "Completed"
        local totalKey = key .. "Total"
        if counters[completedKey] ~= nil then
            categoryVm.completedCount = clampNonNegative(counters[completedKey])
        end
        if counters[totalKey] ~= nil then
            categoryVm.totalCount = clampNonNegative(counters[totalKey])
            categoryVm.capLimit = categoryVm.totalCount
        end
    end

    return categoryVm
end

local function indexCategoriesByKey(rawData)
    local map = {}
    if type(rawData) ~= "table" then
        return map
    end

    local categories = rawData.categories
    if type(categories) ~= "table" then
        return map
    end

    for index = 1, #categories do
        local category = categories[index]
        if type(category) == "table" and type(category.key) == "string" then
            map[category.key] = category
        end
    end

    return map
end

function Controller:Init()
    state.dirty = true
    state.viewModel = nil
    safeDebug("Init")
end

function Controller:MarkDirty()
    state.dirty = true
end

function Controller:IsDirty()
    return state.dirty == true
end

function Controller:ClearDirty()
    state.dirty = false
end

function Controller:BuildViewModel()
    local goldenState = getGoldenState()
    local expansionFlags = resolveExpansionFlags(goldenState)
    local viewStatus = resolveStateStatus(goldenState)
    local viewModel = newEmptyViewModel(viewStatus, expansionFlags)

    local model = getGoldenModel()
    if model == nil then
        state.viewModel = viewModel
        state.dirty = false
        safeDebug("BuildViewModel fallback: GoldenModel missing")
        return state.viewModel
    end

    local modelStatus = callModelMethod(model, "GetSystemStatus")
    if type(modelStatus) == "table" then
        viewModel.status = copyStatus(modelStatus)
    else
        viewModel.status = copyStatus(viewStatus)
    end

    local isAvailable = viewModel.status.isAvailable == true
    local isLocked = viewModel.status.isLocked == true
    local hasEntries = viewModel.status.hasEntries == true

    if isLocked then
        state.viewModel = viewModel
        state.dirty = false
        safeDebug(
            "BuildViewModel gated: locked (available=%s hasEntries=%s)",
            tostring(isAvailable),
            tostring(hasEntries)
        )
        return state.viewModel
    end

    if not isAvailable then
        state.viewModel = viewModel
        state.dirty = false
        safeDebug(
            "BuildViewModel gated: unavailable (locked=%s hasEntries=%s)",
            tostring(isLocked),
            tostring(hasEntries)
        )
        return state.viewModel
    end

    if not hasEntries then
        state.viewModel = viewModel
        state.dirty = false
        safeDebug("BuildViewModel gated: empty (available=true)")
        return state.viewModel
    end

    local rawData = callModelMethod(model, "GetViewData") or {}
    local counters = callModelMethod(model, "GetCounters") or {}

    local headerExpanded = expansionFlags.header ~= false
    if type(rawData) == "table" and rawData.headerExpanded ~= nil then
        headerExpanded = rawData.headerExpanded ~= false
    end
    viewModel.header = { isExpanded = headerExpanded }

    local categoryMap = indexCategoriesByKey(rawData)

    local summary = {
        totalEntries = 0,
        totalCompleted = 0,
        totalRemaining = 0,
        categories = {
            daily = { completed = 0, total = 0, limit = 0, remaining = 0, counterText = "0/0", hasEntries = false, timeRemainingSec = 0 },
            weekly = { completed = 0, total = 0, limit = 0, remaining = 0, counterText = "0/0", hasEntries = false, timeRemainingSec = 0 },
        },
    }

    local categories = {}
    for index = 1, #CATEGORY_DEFINITIONS do
        local definition = CATEGORY_DEFINITIONS[index]
        local rawCategory = categoryMap[definition.key]
        local expanded = rawCategory and rawCategory.expanded
        if expanded == nil then
            local stateExpanded = expansionFlags[definition.key]
            if stateExpanded ~= nil then
                expanded = stateExpanded ~= false
            end
        end
        local categoryVm = buildCategory(definition, rawCategory, counters, expanded)

        categories[index] = categoryVm

        summary.totalEntries = summary.totalEntries + categoryVm.entryCount
        summary.totalCompleted = summary.totalCompleted + categoryVm.completedCount

        if definition.summaryKey then
            summary.categories[definition.summaryKey] = {
                completed = categoryVm.completedCount,
                total = categoryVm.totalCount,
                limit = categoryVm.capLimit,
                counterText = categoryVm.progressText,
                hasEntries = categoryVm.hasEntries,
                timeRemainingSec = categoryVm.timeRemainingSec,
                remaining = math.max(0, categoryVm.totalCount - categoryVm.completedCount),
            }
        end
    end

    viewModel.categories = categories
    viewModel.summary = summary
    summary.totalRemaining = math.max(0, summary.totalEntries - summary.totalCompleted)

    if summary.totalEntries > 0 then
        viewModel.status.isAvailable = true
        viewModel.status.hasEntries = true
    else
        viewModel.status.hasEntries = false
    end

    state.viewModel = viewModel
    state.dirty = false

    local statusSummary = string.format(
        "avail=%s locked=%s hasEntries=%s",
        tostring(viewModel.status.isAvailable),
        tostring(viewModel.status.isLocked),
        tostring(viewModel.status.hasEntries)
    )

    safeDebug(
        "BuildViewModel populated: %s daily=%d/%d weekly=%d/%d totalEntries=%d",
        statusSummary,
        summary.categories.daily.completed or 0,
        summary.categories.daily.total or 0,
        summary.categories.weekly.completed or 0,
        summary.categories.weekly.total or 0,
        summary.totalEntries
    )

    return viewModel
end

function Controller:GetViewModel()
    return ensureViewModel()
end

return Controller
