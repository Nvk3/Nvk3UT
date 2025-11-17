-- Tracker/Golden/Nvk3UT_GoldenTrackerController.lua
-- Normalizes Golden tracker data into an Endeavor-style category/entry view model.

local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Controller = Nvk3UT.GoldenTrackerController or {}
Nvk3UT.GoldenTrackerController = Controller

local MODULE_TAG = addonName .. ".GoldenTrackerController"

local DEFAULT_STATUS = {
    isAvailable = false,
    isLocked = false,
    hasEntries = false,
}

local state = {
    dirty = true,
    viewModel = nil,
}

local attachments = {
    model = nil,
    tracker = nil,
    debugLogger = nil,
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

local function getGoldenModel()
    if type(attachments.model) == "table" then
        return attachments.model
    end

    local root = getAddonRoot()
    if type(root) ~= "table" then
        return nil
    end

    local goldenModel = rawget(root, "GoldenModel")
    if type(goldenModel) == "table" then
        return goldenModel
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

    local debugFn = attachments.debugLogger
    if type(debugFn) ~= "function" then
        local root = getAddonRoot()
        debugFn = root and root.Debug
    end
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

local function callModelMethod(model, methodName, ...)
    if type(model) ~= "table" or type(methodName) ~= "string" then
        return nil
    end

    local method = model[methodName]
    if type(method) ~= "function" then
        safeDebug("GoldenModel:%s missing; skipping call", tostring(methodName))
        return nil
    end

    local ok, result = pcall(method, model, ...)
    if ok then
        return result
    end

    safeDebug("Call to GoldenModel:%s failed: %s", methodName, tostring(result))
    return nil
end

local function ensureString(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local function coerceNumber(value, fallback)
    local numeric = tonumber(value)
    if numeric == nil then
        numeric = fallback or 0
    end

    if numeric ~= numeric then
        numeric = fallback or 0
    end

    return numeric
end

local function clampNonNegative(value, fallback)
    local numeric = coerceNumber(value, fallback or 0)
    if numeric < 0 then
        numeric = 0
    end

    return numeric
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

    if goldenState then
        local header = callStateMethod(goldenState, "IsHeaderExpanded")
        if header ~= nil then
            headerExpanded = header ~= false
        end
    end

    return {
        header = headerExpanded,
    }
end

local function newEmptyViewModel(status, expansionFlags)
    local viewStatus = copyStatus(status)

    local headerExpanded = true
    if type(expansionFlags) == "table" and expansionFlags.header ~= nil then
        headerExpanded = expansionFlags.header ~= false
    end

    local viewModel = {
        status = viewStatus,
        header = { isExpanded = headerExpanded },
        categories = {},
        summary = {
            totalEntries = 0,
            totalCompleted = 0,
            totalRemaining = 0,
            campaignCount = 0,
        },
    }

    return viewModel
end

local function ensureViewModel()
    if type(state.viewModel) == "table" then
        return state.viewModel
    end

    local goldenState = getGoldenState()
    local expansionFlags = resolveExpansionFlags(goldenState)
    local viewStatus = resolveStateStatus(goldenState)

    state.viewModel = newEmptyViewModel(viewStatus, expansionFlags)
    safeDebug("ensureViewModel fallback: created empty view model")
    return state.viewModel
end

local function normalizeEntry(rawCategory, rawEntry, index)
    if type(rawEntry) ~= "table" then
        return nil
    end

    local categoryKey = ""
    if type(rawCategory) == "table" then
        categoryKey = ensureString(rawCategory.key or rawCategory.id or "")
    end

    local entryId = rawEntry.id
    if entryId == nil or entryId == "" then
        entryId = string.format("%s:%d", categoryKey, index)
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
        categoryKey = categoryKey,
        categoryId = ensureString(rawCategory and (rawCategory.id or categoryKey) or categoryKey),
        type = rawEntry.type or categoryKey,
        entryType = rawEntry.type or categoryKey,
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
        campaignId = rawEntry.campaignId or (rawCategory and rawCategory.campaignId),
        campaignKey = rawEntry.campaignKey or (rawCategory and rawCategory.campaignKey),
        campaignIndex = rawEntry.campaignIndex or (rawCategory and rawCategory.campaignIndex),
        rewardId = rawEntry.rewardId,
        rewardQuantity = rawEntry.rewardQuantity,
        isRewardClaimed = rawEntry.isRewardClaimed == true,
        veq = rawEntry.veq,
    }

    entryVm.objectives[1] = buildObjectiveFromEntry(entryVm)
    entryVm.hasObjectives = #entryVm.objectives > 0

    return entryVm
end

local function buildCategory(rawCategory)
    if type(rawCategory) ~= "table" then
        return nil
    end

    local key = ensureString(rawCategory.key or rawCategory.id or "")
    local displayName = ensureString(rawCategory.displayName or rawCategory.name or key)
    local expanded = rawCategory.expanded ~= false

    local categoryVm = {
        id = ensureString(rawCategory.id or key),
        categoryKey = key,
        key = key,
        categoryId = ensureString(rawCategory.id or key),
        type = key,
        displayName = displayName,
        title = displayName,
        name = displayName,
        description = ensureString(rawCategory.description),
        isExpanded = expanded,
        isCollapsed = not expanded,
        expanded = expanded,
        isVisible = true,
        entryCount = 0,
        completedCount = 0,
        totalCount = 0,
        hasEntries = false,
        timeRemainingSec = clampNonNegative(rawCategory.timeRemainingSec),
        remainingSeconds = clampNonNegative(rawCategory.remainingSeconds or rawCategory.timeRemainingSec),
        capLimit = 0,
        progressText = "0/0",
        entries = {},
        campaignId = rawCategory.campaignId,
        campaignKey = rawCategory.campaignKey,
        campaignIndex = rawCategory.campaignIndex,
    }

    local entries = {}
    local rawEntries = type(rawCategory.entries) == "table" and rawCategory.entries or {}
    for index = 1, #rawEntries do
        local entryVm = normalizeEntry(rawCategory, rawEntries[index], index)
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
    categoryVm.countCompleted = categoryVm.completedCount
    categoryVm.countTotal = categoryVm.totalCount
    categoryVm.hasEntries = categoryVm.entryCount > 0

    local progressMax = math.max(1, categoryVm.totalCount)
    categoryVm.progressText = string.format("%d/%d", math.floor(categoryVm.completedCount + 0.5), progressMax)

    if categoryVm.remainingSeconds <= 0 then
        local minRemaining
        for index = 1, #entries do
            local remaining = clampNonNegative(entries[index].timeRemainingSec)
            if remaining > 0 then
                if minRemaining == nil then
                    minRemaining = remaining
                else
                    minRemaining = math.min(minRemaining, remaining)
                end
            end
        end
        if minRemaining ~= nil then
            categoryVm.timeRemainingSec = minRemaining
            categoryVm.remainingSeconds = minRemaining
        end
    end

    return categoryVm
end

function Controller:New(model, tracker, debugLogger)
    if type(model) == "table" then
        attachments.model = model
    end

    if type(tracker) == "table" then
        attachments.tracker = tracker
    end

    if debugLogger ~= nil then
        attachments.debugLogger = debugLogger
    end

    return self
end

function Controller:Init()
    state.dirty = true
    state.viewModel = nil
    safeDebug("Init")
end

function Controller:MarkDirty(reason)
    state.dirty = true
    if reason ~= nil then
        safeDebug("MarkDirty(%s)", tostring(reason))
    end
end

function Controller:IsDirty()
    return state.dirty == true
end

function Controller:ClearDirty()
    state.dirty = false
end

function Controller:BuildViewModel(options)
    local goldenState = getGoldenState()
    local expansionFlags = resolveExpansionFlags(goldenState)
    local stateStatus = resolveStateStatus(goldenState)
    local viewModel = newEmptyViewModel(stateStatus, expansionFlags)

    local isAvailable = stateStatus.isAvailable == true
    local isLocked = stateStatus.isLocked == true
    local hasEntries = stateStatus.hasEntries == true

    if not isAvailable then
        state.viewModel = viewModel
        state.dirty = false
        safeDebug(
            "BuildViewModel gated (state unavailable): locked=%s hasEntries=%s",
            tostring(isLocked),
            tostring(hasEntries)
        )
        return viewModel
    end

    if isLocked then
        state.viewModel = viewModel
        state.dirty = false
        safeDebug("BuildViewModel gated (state locked)")
        return viewModel
    end

    if not hasEntries then
        state.viewModel = viewModel
        state.dirty = false
        safeDebug("BuildViewModel gated (state empty)")
        return viewModel
    end

    local model = getGoldenModel()
    if model == nil then
        state.viewModel = viewModel
        state.dirty = false
        safeDebug("BuildViewModel fallback: GoldenModel missing")
        return viewModel
    end

    local modelStatus = callModelMethod(model, "GetSystemStatus")
    if type(modelStatus) == "table" then
        viewModel.status = copyStatus(modelStatus)
        isAvailable = viewModel.status.isAvailable == true
        isLocked = viewModel.status.isLocked == true
        hasEntries = viewModel.status.hasEntries == true
    else
        viewModel.status = copyStatus(stateStatus)
        viewModel.status.hasEntries = true
    end

    if not isAvailable then
        state.viewModel = viewModel
        state.dirty = false
        safeDebug(
            "BuildViewModel gated (model unavailable): locked=%s hasEntries=%s",
            tostring(isLocked),
            tostring(hasEntries)
        )
        return viewModel
    end

    if isLocked then
        state.viewModel = viewModel
        state.dirty = false
        safeDebug("BuildViewModel gated (model locked)")
        return viewModel
    end

    if not hasEntries then
        state.viewModel = viewModel
        state.dirty = false
        safeDebug("BuildViewModel gated (model empty)")
        return viewModel
    end

    local rawData = callModelMethod(model, "GetViewData") or {}
    local counters = callModelMethod(model, "GetCounters") or {}

    local headerExpanded = expansionFlags.header ~= false
    if type(rawData) == "table" and rawData.headerExpanded ~= nil then
        headerExpanded = rawData.headerExpanded ~= false
    end
    viewModel.header = { isExpanded = headerExpanded }

    local rawCategories = type(rawData.categories) == "table" and rawData.categories or {}
    local categories = {}
    local totalEntries = 0
    local totalCompleted = 0

    for index = 1, #rawCategories do
        local categoryVm = buildCategory(rawCategories[index])
        if categoryVm then
            categories[#categories + 1] = categoryVm
            totalEntries = totalEntries + clampNonNegative(categoryVm.entryCount)
            totalCompleted = totalCompleted + clampNonNegative(categoryVm.completedCount)
        end
    end

    viewModel.categories = categories

    local summary = {
        totalEntries = clampNonNegative(counters.totalActivities or totalEntries),
        totalCompleted = clampNonNegative(counters.completedActivities or totalCompleted),
        campaignCount = clampNonNegative(counters.campaignCount or #categories),
    }
    summary.totalRemaining = math.max(0, summary.totalEntries - summary.totalCompleted)

    viewModel.summary = summary

    if summary.totalEntries > 0 then
        viewModel.status.isAvailable = true
        viewModel.status.hasEntries = true
    else
        viewModel.status.hasEntries = false
    end

    state.viewModel = viewModel
    state.dirty = false

    safeDebug(
        "BuildViewModel populated: avail=%s locked=%s hasEntries=%s campaigns=%d activities=%d/%d",
        tostring(viewModel.status.isAvailable),
        tostring(viewModel.status.isLocked),
        tostring(viewModel.status.hasEntries),
        summary.campaignCount,
        summary.totalCompleted,
        summary.totalEntries
    )

    return viewModel
end

function Controller:GetViewModel()
    return ensureViewModel()
end

return Controller
