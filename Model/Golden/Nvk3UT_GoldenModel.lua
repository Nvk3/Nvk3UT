-- Model/Golden/Nvk3UT_GoldenModel.lua
-- Golden tracker facade that composes GoldenState and GoldenList.
-- Builds read-only raw/view data snapshots without touching UI or runtime pieces.

Nvk3UT = Nvk3UT or {}

local GoldenModel = Nvk3UT.GoldenModel or {}
Nvk3UT.GoldenModel = GoldenModel

GoldenModel._svRoot = type(GoldenModel._svRoot) == "table" and GoldenModel._svRoot or nil
GoldenModel._state = type(GoldenModel._state) == "table" and GoldenModel._state or nil
GoldenModel._list = type(GoldenModel._list) == "table" and GoldenModel._list or nil
GoldenModel._rawData = type(GoldenModel._rawData) == "table" and GoldenModel._rawData or nil
GoldenModel._viewData = type(GoldenModel._viewData) == "table" and GoldenModel._viewData or nil
GoldenModel._counters = type(GoldenModel._counters) == "table" and GoldenModel._counters or nil

local unpack = _G.unpack or (table and table.unpack)

local CATEGORY_ORDER = {
    { key = "daily", name = "DAILY", stateGetter = "IsDailyExpanded" },
    { key = "weekly", name = "WEEKLY", stateGetter = "IsWeeklyExpanded" },
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
        diagnostics.Debug("[GoldenModel] %s", message)
        return
    end

    if type(d) == "function" then
        d(string.format("[Nvk3UT][GoldenModel] %s", message))
        return
    end

    if type(print) == "function" then
        print("[Nvk3UT][GoldenModel]", message)
    end
end

local function ensureBoolean(value, fallback)
    if value == nil then
        return fallback == true
    end
    return value == true
end

local function ensureNumber(value, fallback)
    local numeric = tonumber(value)
    if numeric == nil then
        return fallback or 0
    end
    if numeric < 0 and (fallback or 0) >= 0 then
        numeric = fallback or 0
    end
    return numeric
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

local function newEmptyCategory(descriptor)
    return {
        key = descriptor.key,
        name = descriptor.name,
        entries = {},
        countCompleted = 0,
        countTotal = 0,
        timeRemainingSec = 0,
        expanded = true,
    }
end

local function newEmptyRawData()
    local categories = {}
    for index = 1, #CATEGORY_ORDER do
        categories[index] = newEmptyCategory(CATEGORY_ORDER[index])
    end
    return {
        categories = categories,
    }
end

local function newEmptyCounters()
    return {
        dailyCompleted = 0,
        dailyTotal = 0,
        weeklyCompleted = 0,
        weeklyTotal = 0,
    }
end

local function copyOrEmpty(value, fallbackFactory)
    if type(value) == "table" then
        local copy = deepCopyTable(value)
        if type(copy) == "table" then
            return copy
        end
    end

    if type(fallbackFactory) == "function" then
        return fallbackFactory()
    end

    return {}
end

local function findCategoryByKey(data, key)
    if type(data) ~= "table" or type(data.categories) ~= "table" then
        return nil
    end

    for index = 1, #data.categories do
        local category = data.categories[index]
        if type(category) == "table" and category.key == key then
            return category
        end
    end

    return nil
end

local function coerceEntries(category)
    if type(category) ~= "table" then
        return {}
    end
    local entries = category.entries
    if type(entries) ~= "table" then
        return {}
    end
    local copy = deepCopyTable(entries)
    if type(copy) == "table" then
        return copy
    end
    local fallback = {}
    for index = 1, #entries do
        fallback[index] = entries[index]
    end
    return fallback
end

local function coerceCount(value, entries)
    local numeric = tonumber(value)
    if numeric ~= nil and numeric >= 0 then
        return numeric
    end
    if type(entries) == "table" then
        return #entries
    end
    return 0
end

local function getStateBoolean(state, methodName, fallback)
    if type(state) ~= "table" or type(methodName) ~= "string" then
        return ensureBoolean(fallback, true)
    end
    local method = state[methodName]
    if type(method) ~= "function" then
        return ensureBoolean(fallback, true)
    end

    local ok, value = pcall(method, state)
    if ok then
        return ensureBoolean(value, fallback)
    end

    return ensureBoolean(fallback, true)
end

local function refreshStateInit(state, svRoot)
    if type(state) ~= "table" or type(state.Init) ~= "function" then
        return
    end
    safeCall(function()
        state:Init(svRoot)
    end)
end

local function refreshListInit(list, svRoot)
    if type(list) ~= "table" or type(list.Init) ~= "function" then
        return
    end
    safeCall(function()
        list:Init(svRoot)
    end)
end

local function buildCounters(data)
    local counters = newEmptyCounters()
    if type(data) ~= "table" then
        return counters
    end

    local categories = data.categories
    if type(categories) ~= "table" then
        return counters
    end

    for index = 1, #categories do
        local category = categories[index]
        if type(category) == "table" then
            local key = category.key
            local entries = category.entries
            local completed = coerceCount(category.countCompleted, entries)
            local total = coerceCount(category.countTotal, entries)
            if key == "daily" then
                counters.dailyCompleted = completed
                counters.dailyTotal = total
            elseif key == "weekly" then
                counters.weeklyCompleted = completed
                counters.weeklyTotal = total
            end
        end
    end

    return counters
end

local function computeIsEmpty(counters)
    if type(counters) ~= "table" then
        return true
    end

    local dailyTotal = tonumber(counters.dailyTotal) or 0
    local weeklyTotal = tonumber(counters.weeklyTotal) or 0

    return dailyTotal <= 0 and weeklyTotal <= 0
end

local function buildCategoryView(descriptor, rawCategory, state)
    local entries = coerceEntries(rawCategory)
    local countCompleted = coerceCount(rawCategory and rawCategory.countCompleted, entries)
    local countTotal = coerceCount(rawCategory and rawCategory.countTotal, entries)
    local remaining = ensureNumber(rawCategory and rawCategory.timeRemainingSec, 0)
    local expanded = getStateBoolean(state, descriptor.stateGetter, true)

    return {
        key = descriptor.key,
        name = descriptor.name,
        entries = entries,
        countCompleted = countCompleted,
        countTotal = countTotal,
        timeRemainingSec = remaining,
        expanded = expanded,
    }
end

local function buildViewDataSnapshot(rawData, state)
    local data = type(rawData) == "table" and rawData or newEmptyRawData()
    local headerExpanded = getStateBoolean(state, "IsHeaderExpanded", true)

    local categories = {}
    for index = 1, #CATEGORY_ORDER do
        local descriptor = CATEGORY_ORDER[index]
        local source = findCategoryByKey(data, descriptor.key)
        categories[index] = buildCategoryView(descriptor, source, state)
    end

    return {
        headerExpanded = headerExpanded,
        categories = categories,
    }
end

function GoldenModel:Init(svRoot, goldenState, goldenList)
    if type(svRoot) == "table" then
        self._svRoot = svRoot
    else
        self._svRoot = nil
    end

    if type(goldenState) == "table" then
        self._state = goldenState
    else
        self._state = type(Nvk3UT.GoldenState) == "table" and Nvk3UT.GoldenState or nil
    end

    if type(goldenList) == "table" then
        self._list = goldenList
    else
        self._list = type(Nvk3UT.GoldenList) == "table" and Nvk3UT.GoldenList or nil
    end

    if self._state then
        refreshStateInit(self._state, self._svRoot)
    end

    if self._list then
        refreshListInit(self._list, self._svRoot)
    end

    self._rawData = newEmptyRawData()
    self._viewData = buildViewDataSnapshot(self._rawData, self._state)
    self._counters = buildCounters(self._rawData)
    self._isEmpty = computeIsEmpty(self._counters)

    debugLog("init")

    return self
end

local function runListRefresh(list, providerFn)
    if type(list) ~= "table" or type(list.RefreshFromGame) ~= "function" then
        return
    end
    list:RefreshFromGame(providerFn)
end

function GoldenModel:RefreshFromGame(providerFn)
    if type(self._list) ~= "table" then
        self._rawData = newEmptyRawData()
        self._viewData = buildViewDataSnapshot(self._rawData, self._state)
        self._counters = buildCounters(self._rawData)
        self._isEmpty = computeIsEmpty(self._counters)
        return false
    end

    safeCall(runListRefresh, self._list, providerFn)

    local rawData = copyOrEmpty(self._list.GetRawData and self._list:GetRawData(), newEmptyRawData)
    if type(rawData.categories) ~= "table" then
        rawData = newEmptyRawData()
    end

    self._rawData = rawData
    self._viewData = buildViewDataSnapshot(self._rawData, self._state)
    self._counters = buildCounters(self._rawData)
    self._isEmpty = computeIsEmpty(self._counters)

    debugLog(
        "refresh: daily=%d/%d weekly=%d/%d",
        self._counters.dailyCompleted or 0,
        self._counters.dailyTotal or 0,
        self._counters.weeklyCompleted or 0,
        self._counters.weeklyTotal or 0
    )

    return true
end

function GoldenModel:GetRawData()
    local copy = deepCopyTable(self._rawData)
    if type(copy) == "table" then
        return copy
    end
    return newEmptyRawData()
end

function GoldenModel:GetViewData()
    local copy = deepCopyTable(self._viewData)
    if type(copy) == "table" then
        return copy
    end
    return buildViewDataSnapshot(self._rawData, self._state)
end

function GoldenModel:GetCounters()
    local counters = self._counters
    if type(counters) ~= "table" then
        counters = newEmptyCounters()
    end

    return {
        dailyCompleted = counters.dailyCompleted or 0,
        dailyTotal = counters.dailyTotal or 0,
        weeklyCompleted = counters.weeklyCompleted or 0,
        weeklyTotal = counters.weeklyTotal or 0,
    }
end

function GoldenModel:IsEmpty()
    if self._isEmpty ~= nil then
        return self._isEmpty == true
    end
    self._isEmpty = computeIsEmpty(self._counters)
    return self._isEmpty == true
end

return GoldenModel
