-- Model/Golden/Nvk3UT_GoldenList.lua
-- Golden tracker data extraction wrapper. Normalizes provider output without touching UI or runtime.

Nvk3UT = Nvk3UT or {}

local GoldenList = Nvk3UT.GoldenList or {}
Nvk3UT.GoldenList = GoldenList

GoldenList._svRoot = type(GoldenList._svRoot) == "table" and GoldenList._svRoot or nil
GoldenList._data = type(GoldenList._data) == "table" and GoldenList._data or nil

local unpack = _G.unpack or (table and table.unpack)

local CATEGORY_ORDER = {
    { key = "daily", name = "DAILY" },
    { key = "weekly", name = "WEEKLY" },
}

local function resolveRoot()
    local root = rawget(_G, "Nvk3UT")
    if type(root) == "table" then
        return root
    end
    return Nvk3UT
end

local function resolveDiagnostics()
    local root = resolveRoot()
    local diagnostics = root and root.Diagnostics
    if type(diagnostics) == "table" then
        return diagnostics
    end
    if type(Nvk3UT_Diagnostics) == "table" then
        return Nvk3UT_Diagnostics
    end
    return nil
end

local function resolveUtils()
    local root = resolveRoot()
    local utils = root and root.Utils
    if type(utils) == "table" then
        return utils
    end
    if type(Nvk3UT_Utils) == "table" then
        return Nvk3UT_Utils
    end
    return nil
end

local function resolveSafeCall()
    local root = resolveRoot()
    if type(root.SafeCall) == "function" then
        return root.SafeCall
    end
    return nil
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end

    local safe = resolveSafeCall()
    if type(safe) == "function" then
        local ok, results = pcall(function(...)
            return { safe(fn, ...) }
        end, ...)
        if ok and type(results) == "table" then
            if unpack then
                return unpack(results)
            end
            return results[1]
        end
    end

    local ok, results = pcall(function(...)
        return { fn(...) }
    end, ...)
    if ok and type(results) == "table" then
        if unpack then
            return unpack(results)
        end
        return results[1]
    end

    return nil
end

local function isDebugEnabled()
    local utils = resolveUtils()
    if utils and type(utils.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(utils.IsDebugEnabled)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local diagnostics = resolveDiagnostics()
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return diagnostics:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local root = resolveRoot()
    if type(root.IsDebugEnabled) == "function" then
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

local function formatMessage(fmt, ...)
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, tostring(fmt), ...)
        if ok then
            return formatted
        end
    end

    if fmt == nil then
        return "<nil>"
    end

    return tostring(fmt)
end

local function debugLog(fmt, ...)
    if not isDebugEnabled() then
        return
    end

    local message = formatMessage(fmt, ...)
    local diagnostics = resolveDiagnostics()
    if diagnostics and type(diagnostics.Debug) == "function" then
        diagnostics.Debug("[GoldenList] %s", message)
        return
    end

    if type(d) == "function" then
        d(string.format("[Nvk3UT][GoldenList] %s", message))
        return
    end

    if type(print) == "function" then
        print("[Nvk3UT][GoldenList]", message)
    end
end

local function clampNumber(value, minimum, fallback)
    local numeric = tonumber(value)
    if numeric == nil then
        return fallback or minimum or 0
    end

    if minimum and numeric < minimum then
        numeric = minimum
    end

    return numeric
end

local function ensureNonNegative(value)
    local numeric = tonumber(value)
    if numeric == nil or numeric < 0 then
        return 0
    end
    return numeric
end

local function ensureMaxProgress(value)
    local numeric = tonumber(value)
    if numeric == nil or numeric < 1 then
        return 1
    end
    return numeric
end

local function ensureString(value)
    if value == nil then
        return ""
    end
    return tostring(value)
end

local function ensureBoolean(value)
    if value == nil then
        return false
    end
    return value == true
end

local function newEmptyCategory(key, name)
    return {
        key = key,
        name = name,
        entries = {},
        countCompleted = 0,
        countTotal = 0,
        timeRemainingSec = 0,
    }
end

local function wipeCategory(category)
    category.countCompleted = 0
    category.countTotal = 0
    category.timeRemainingSec = 0

    local entries = category.entries
    if type(entries) ~= "table" then
        category.entries = {}
        return
    end

    for index = #entries, 1, -1 do
        entries[index] = nil
    end
end

local function newEmptyData()
    local categories = {}
    for index = 1, #CATEGORY_ORDER do
        local descriptor = CATEGORY_ORDER[index]
        categories[index] = newEmptyCategory(descriptor.key, descriptor.name)
    end
    return {
        categories = categories,
    }
end

local function deepCopyTable(source)
    if type(source) ~= "table" then
        return nil
    end

    local function copier(tbl, seen)
        if seen[tbl] then
            return seen[tbl]
        end

        local clone = {}
        seen[tbl] = clone

        for key, value in pairs(tbl) do
            if type(value) == "table" then
                clone[key] = copier(value, seen)
            else
                clone[key] = value
            end
        end

        return clone
    end

    local function copyWrapper()
        return copier(source, {})
    end

    local copy = safeCall(copyWrapper)
    if type(copy) == "table" then
        return copy
    end

    local ok, fallback = pcall(copyWrapper)
    if ok and type(fallback) == "table" then
        return fallback
    end

    return nil
end

local function getCategoryMap(data)
    local map = {}
    local categories = type(data) == "table" and data.categories
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

local function normalizeEntry(rawEntry, typeKey, fallbackRemaining)
    local normalized = {}
    if type(rawEntry) ~= "table" then
        normalized.id = ""
        normalized.name = ""
        normalized.description = ""
        normalized.progress = 0
        normalized.maxProgress = 1
        normalized.isCompleted = false
        normalized.type = typeKey
        normalized.timeRemainingSec = ensureNonNegative(fallbackRemaining)
        return normalized
    end

    normalized.id = rawEntry.id ~= nil and rawEntry.id or ""
    normalized.name = ensureString(rawEntry.name)
    normalized.description = ensureString(rawEntry.description)

    local progress = ensureNonNegative(rawEntry.progress)
    local maxProgress = ensureMaxProgress(rawEntry.maxProgress)

    normalized.progress = progress
    normalized.maxProgress = maxProgress
    normalized.type = typeKey

    local entryRemaining = rawEntry.timeRemainingSec
    if entryRemaining == nil and rawEntry.remainingSeconds ~= nil then
        entryRemaining = rawEntry.remainingSeconds
    end
    normalized.timeRemainingSec = ensureNonNegative(entryRemaining or fallbackRemaining)

    if rawEntry.isCompleted ~= nil then
        normalized.isCompleted = ensureBoolean(rawEntry.isCompleted)
    else
        normalized.isCompleted = progress >= maxProgress and maxProgress > 0
    end

    return normalized
end

local function toCategoryKey(identifier)
    if identifier == "daily" or identifier == "Daily" or identifier == "DAILY" then
        return "daily"
    end
    if identifier == "weekly" or identifier == "Weekly" or identifier == "WEEKLY" then
        return "weekly"
    end
    return nil
end

local function normalizeCategoryPayload(payload)
    if type(payload) ~= "table" then
        return {
            entries = {},
            countCompleted = 0,
            countTotal = 0,
            hasCountCompleted = false,
            hasCountTotal = false,
            timeRemainingSec = 0,
        }
    end

    local hasCountCompleted = payload.hasCountCompleted
    if hasCountCompleted == nil then
        hasCountCompleted = payload.countCompleted ~= nil
    else
        hasCountCompleted = hasCountCompleted == true
    end

    local hasCountTotal = payload.hasCountTotal
    if hasCountTotal == nil then
        hasCountTotal = payload.countTotal ~= nil
    else
        hasCountTotal = hasCountTotal == true
    end

    local result = {
        entries = {},
        countCompleted = clampNumber(payload.countCompleted, 0, 0),
        countTotal = clampNumber(payload.countTotal, 0, 0),
        hasCountCompleted = hasCountCompleted,
        hasCountTotal = hasCountTotal,
        timeRemainingSec = ensureNonNegative(payload.timeRemainingSec),
    }

    if result.timeRemainingSec == 0 and payload.remainingSeconds ~= nil then
        result.timeRemainingSec = ensureNonNegative(payload.remainingSeconds)
    end

    local rawEntries = payload.entries
    if type(rawEntries) == "table" then
        if #rawEntries > 0 then
            for index = 1, #rawEntries do
                result.entries[#result.entries + 1] = rawEntries[index]
            end
        else
            for _, value in pairs(rawEntries) do
                result.entries[#result.entries + 1] = value
            end
        end
    end

    return result
end

function GoldenList:_ensureData()
    if type(self._data) ~= "table" then
        self._data = newEmptyData()
    end
    return self._data
end

function GoldenList:Init(svRoot)
    if type(svRoot) == "table" then
        self._svRoot = svRoot
    else
        self._svRoot = nil
    end

    self._data = newEmptyData()

    debugLog("initialized GoldenList module")
end

local function applyProviderPayload(categoryMap, payload)
    local totals = { daily = 0, weekly = 0 }
    local completed = { daily = 0, weekly = 0 }

    if type(categoryMap) ~= "table" then
        return totals, completed
    end

    if type(payload) ~= "table" then
        debugLog("refresh: provider returned no data; using empty list")
        return totals, completed
    end

    local keyedPayload = {}
    if payload.categories and type(payload.categories) == "table" then
        for _, item in pairs(payload.categories) do
            if type(item) == "table" then
                local key = toCategoryKey(item.key or item.type or item.id or item.name)
                if key ~= nil then
                    keyedPayload[key] = normalizeCategoryPayload(item)
                end
            end
        end
    end

    if type(payload.daily) == "table" then
        keyedPayload.daily = normalizeCategoryPayload(payload.daily)
    end
    if type(payload.weekly) == "table" then
        keyedPayload.weekly = normalizeCategoryPayload(payload.weekly)
    end

    for key, payloadCategory in pairs(keyedPayload) do
        local bucketKey = toCategoryKey(key)
        local category = categoryMap[bucketKey]
        if category then
            local fallbackRemaining = ensureNonNegative(payloadCategory.timeRemainingSec)

            local normalizedEntries = {}
            local rawEntries = payloadCategory.entries
            if type(rawEntries) ~= "table" then
                rawEntries = {}
            end

            for index = 1, #rawEntries do
                local normalized = normalizeEntry(rawEntries[index], bucketKey, fallbackRemaining)
                normalizedEntries[index] = normalized
                if normalized.isCompleted then
                    completed[bucketKey] = completed[bucketKey] + 1
                end
            end

            category.entries = normalizedEntries
            if payloadCategory.hasCountTotal then
                category.countTotal = clampNumber(payloadCategory.countTotal, 0, #normalizedEntries)
            else
                category.countTotal = #normalizedEntries
            end
            if payloadCategory.hasCountCompleted then
                category.countCompleted = clampNumber(payloadCategory.countCompleted, 0, category.countTotal)
            else
                category.countCompleted = completed[bucketKey]
            end
            category.timeRemainingSec = fallbackRemaining

            totals[bucketKey] = #normalizedEntries
            if category.countCompleted < completed[bucketKey] then
                category.countCompleted = completed[bucketKey]
            end
        end
    end

    return totals, completed
end

function GoldenList:RefreshFromGame(providerFn)
    local data = self:_ensureData()
    local categories = data.categories
    local categoryMap = {}
    for index = 1, #categories do
        local category = categories[index]
        if type(category) == "table" then
            wipeCategory(category)
            categoryMap[category.key] = category
        end
    end

    local payload
    if type(providerFn) == "function" then
        payload = safeCall(providerFn)
        if payload == nil then
            local ok, fallback = pcall(providerFn)
            if ok then
                payload = fallback
            end
        end
    end

    local totals, completed = applyProviderPayload(categoryMap, payload)

    for key, category in pairs(categoryMap) do
        if category.countTotal <= 0 then
            category.countTotal = totals[key] or 0
        end
        if category.countCompleted <= 0 and (totals[key] or 0) > 0 then
            category.countCompleted = completed[key] or 0
        end
    end

    debugLog(
        "refresh: daily=%d weekly=%d",
        totals.daily or 0,
        totals.weekly or 0
    )
end

function GoldenList:GetRawData()
    local data = self:_ensureData()
    local copy = deepCopyTable({
        categories = data.categories,
    })
    if type(copy) ~= "table" then
        return {
            categories = {},
        }
    end
    return copy
end

function GoldenList:IsEmpty()
    local data = self:_ensureData()
    local categories = data.categories
    if type(categories) ~= "table" then
        return true
    end

    for index = 1, #categories do
        local category = categories[index]
        if type(category) == "table" and type(category.entries) == "table" then
            if #category.entries > 0 then
                return false
            end
        end
    end

    return true
end

return GoldenList
