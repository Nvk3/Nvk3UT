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
GoldenModel._vm = type(GoldenModel._vm) == "table" and GoldenModel._vm or nil
GoldenModel._counters = type(GoldenModel._counters) == "table" and GoldenModel._counters or nil
GoldenModel._promoApiReady = GoldenModel._promoApiReady == true
GoldenModel._promoGuardedEmpty = GoldenModel._promoGuardedEmpty == true
GoldenModel._promoLastFailureMessage = type(GoldenModel._promoLastFailureMessage) == "string" and GoldenModel._promoLastFailureMessage or nil

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

local function Dbg(fmt, ...)
    debugLog(fmt, ...)
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

local function newEmptyCampaignViewModel()
    return {
        campaigns = {},
    }
end

local function newEmptyCounters()
    return {
        campaigns = 0,
        activitiesCompleted = 0,
        activitiesTotal = 0,
    }
end

local function newEmptyCampaignStats()
    return {
        totalCampaigns = 0,
        totalActivities = 0,
        completedActivities = 0,
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

    local campaignCount = tonumber(counters.campaigns) or 0
    local activityTotal = tonumber(counters.activitiesTotal) or 0

    return campaignCount <= 0 and activityTotal <= 0
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

    self._rawData = nil
    self._vm = newEmptyCampaignViewModel()
    self._viewData = newEmptyCampaignViewModel()
    self._counters = newEmptyCounters()
    self._isEmpty = true

    debugLog("init")

    return self
end

local REQUIRED_PROMO_API_NAMES = {
    GetCampaignCount = "GetNumActivePromotionalEventCampaigns",
    GetCampaignKey = "GetActivePromotionalEventCampaignKey",
    GetCampaignInfo = "GetPromotionalEventCampaignInfo",
    GetCampaignName = "GetPromotionalEventCampaignDisplayName",
    GetActivityInfo = "GetPromotionalEventCampaignActivityInfo",
    GetActivityProg = "GetPromotionalEventCampaignActivityProgress",
}

local OPTIONAL_PROMO_API_NAMES = {
    GetCampaignDesc = "GetPromotionalEventCampaignDescription",
    GetCampaignProg = "GetPromotionalEventCampaignProgress",
    GetSecondsLeft = "GetSecondsRemainingInPromotionalEventCampaign",
    GetActivityCount = "GetNumPromotionalEventCampaignActivities",
    GetTracked = "GetTrackedPromotionalEventActivityInfo",
}

local function collectPromoApiFunctions()
    local api = { names = {} }

    for role, globalName in pairs(REQUIRED_PROMO_API_NAMES) do
        local fn = rawget(_G, globalName)
        if type(fn) ~= "function" then
            return nil, string.format("missing promo API: %s", tostring(globalName))
        end
        api[role] = fn
        api.names[role] = globalName
    end

    for role, globalName in pairs(OPTIONAL_PROMO_API_NAMES) do
        local fn = rawget(_G, globalName)
        if type(fn) == "function" then
            api[role] = fn
            api.names[role] = globalName
        end
    end

    return api, nil
end

local function setPromoFailure(context, message)
    if type(context) ~= "table" then
        return
    end

    if context.failure ~= nil then
        return
    end

    context.failure = message
end

local function callDirectPromoApi(context, api, role, ...)
    if type(api) ~= "table" then
        setPromoFailure(context, "promo API table missing")
        return false
    end

    local fn = api[role]
    if type(fn) ~= "function" then
        local label = (api.names and api.names[role]) or role
        setPromoFailure(context, string.format("missing promo API: %s", tostring(label)))
        return false
    end

    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if not ok then
        local label = (api.names and api.names[role]) or role
        setPromoFailure(context, string.format("promo API failed: %s → %s", tostring(label), tostring(a)))
        return false
    end

    return true, a, b, c, d, e, f
end

local function callOptionalPromoApi(context, api, role, ...)
    if type(api) ~= "table" then
        return false
    end

    local fn = api[role]
    if type(fn) ~= "function" then
        return false
    end

    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if not ok then
        local label = (api.names and api.names[role]) or role
        setPromoFailure(context, string.format("promo API failed: %s → %s", tostring(label), tostring(a)))
        return false
    end

    return true, a, b, c, d, e, f
end

local function recordPromoFailure(model, message)
    if type(model) ~= "table" then
        return
    end

    if message == nil or message == "" then
        if model._promoLastFailureMessage ~= nil then
            model._promoLastFailureMessage = nil
        end
        return
    end

    if model._promoLastFailureMessage == message then
        return
    end

    model._promoLastFailureMessage = message
    Dbg("%s", message)
end

local function normalizeCampaignKey(value)
    if value == nil then
        return nil
    end

    local valueType = type(value)
    if valueType == "string" then
        return value
    end

    if valueType == "number" or valueType == "boolean" then
        return tostring(value)
    end

    if valueType == "userdata" then
        local ok, text = pcall(tostring, value)
        if ok then
            return text
        end
    end

    return tostring(value)
end

local function toNonNegativeInteger(value)
    local numeric = tonumber(value) or 0
    if numeric < 0 then
        numeric = 0
    end
    if type(numeric) == "number" and math and type(math.floor) == "function" then
        numeric = math.floor(numeric)
    end
    return numeric
end

local MAX_CAMPAIGN_ACTIVITIES = 50

local function fetchTrackedActivity(context, api)
    local ok, campaignKey, activityIndex = callOptionalPromoApi(context, api, "GetTracked")
    if not ok then
        if type(context) == "table" and context.failure ~= nil then
            return nil, nil, true
        end
        return nil, nil, false
    end

    if campaignKey == nil or activityIndex == nil then
        return nil, nil, false
    end

    local normalizedKey = normalizeCampaignKey(campaignKey)

    return normalizedKey, toNonNegativeInteger(activityIndex), false
end

local function sanitizeDescription(value)
    if type(value) == "string" then
        if value == "" then
            return nil
        end
        return value
    end

    if value ~= nil then
        local text = tostring(value)
        if text ~= "" then
            return text
        end
    end

    return nil
end

local function buildCampaignActivities(context, api, campaignKey, trackedCampaignKey, trackedActivityIndex)
    local activities = {}
    local totalActivities = 0
    local completedActivities = 0

    if campaignKey == nil then
        return activities, totalActivities, completedActivities, false
    end

    local normalizedCampaignKey = normalizeCampaignKey(campaignKey)
    local normalizedTrackedKey = normalizeCampaignKey(trackedCampaignKey)
    local trackedIndexValue = toNonNegativeInteger(trackedActivityIndex)

    local loopUpperBound = nil
    local okCount, countValue = callOptionalPromoApi(context, api, "GetActivityCount", campaignKey)
    if okCount then
        loopUpperBound = toNonNegativeInteger(countValue)
    elseif type(context) == "table" and context.failure ~= nil then
        return activities, totalActivities, completedActivities, true
    end

    if loopUpperBound == nil or loopUpperBound <= 0 then
        loopUpperBound = MAX_CAMPAIGN_ACTIVITIES
    end

    for index = 1, loopUpperBound do
        local okInfo, activityId, rawName, rawDesc = callDirectPromoApi(context, api, "GetActivityInfo", campaignKey, index)
        if not okInfo then
            return activities, totalActivities, completedActivities, true
        end

        local hasName = type(rawName) == "string" and rawName ~= ""
        local hasDescription = type(rawDesc) == "string" and rawDesc ~= ""
        if activityId == nil and rawName == nil and rawDesc == nil then
            break
        end
        if not hasName and not hasDescription and rawName == "" and rawDesc == "" then
            break
        end

        local displayName = rawName
        if not hasName then
            displayName = activityId
        end

        local activityName = ensureString(displayName)
        local activityDescription = sanitizeDescription(rawDesc)

        local okProgress, progressCurrent, progressMax = callDirectPromoApi(context, api, "GetActivityProg", campaignKey, index)
        if not okProgress then
            return activities, totalActivities, completedActivities, true
        end

        local current = ensureNumber(progressCurrent, 0)
        local maximum = ensureNumber(progressMax, 0)
        if current < 0 then
            current = 0
        end
        if maximum < 0 then
            maximum = 0
        end

        local completed = maximum > 0 and current >= maximum
        if completed then
            completedActivities = completedActivities + 1
        end

        local isTracked = false
        if normalizedCampaignKey ~= nil and normalizedTrackedKey ~= nil then
            if normalizedCampaignKey == normalizedTrackedKey and trackedIndexValue == index then
                isTracked = true
            end
        end

        if activityName ~= "" or activityDescription ~= nil or maximum > 0 then
            activities[#activities + 1] = {
                name = activityName,
                desc = activityDescription,
                current = current,
                max = maximum,
                tracked = isTracked,
                completed = completed,
            }
            totalActivities = totalActivities + 1
        end
    end

    return activities, totalActivities, completedActivities, false
end

local function extractHasRewards(context, api, infoHandle)
    if infoHandle == nil then
        return nil
    end

    local okInfo, a, b, c, d, e, f = callOptionalPromoApi(context, api, "GetCampaignInfo", infoHandle)
    if not okInfo then
        return nil
    end

    local values = { a, b, c, d, e, f }
    for index = 1, #values do
        if type(values[index]) == "boolean" then
            return values[index]
        end
    end

    return nil
end

local function buildCampaign(context, api, campaignKey, campaignId, trackedCampaignKey, trackedActivityIndex)
    if campaignKey == nil and campaignId == nil then
        return nil, 0, 0, false
    end

    local infoHandle = campaignId or campaignKey
    if infoHandle == nil then
        return nil, 0, 0, true
    end

    local okName, displayName = callDirectPromoApi(context, api, "GetCampaignName", infoHandle)
    if not okName then
        return nil, 0, 0, true
    end
    local campaignName = ensureString(displayName)

    local description = nil
    local okDesc, descValue = callOptionalPromoApi(context, api, "GetCampaignDesc", infoHandle)
    if okDesc then
        description = sanitizeDescription(descValue)
    elseif type(context) == "table" and context.failure ~= nil then
        return nil, 0, 0, true
    end

    local activities, activityCount, completedActivities, missingActivities = buildCampaignActivities(
        context,
        api,
        campaignKey,
        trackedCampaignKey,
        trackedActivityIndex
    )
    if missingActivities then
        return nil, 0, 0, true
    end

    local progressCurrent, progressMax = 0, 0
    if campaignKey ~= nil then
        local okProgress, currentValue, maxValue = callOptionalPromoApi(context, api, "GetCampaignProg", campaignKey)
        if okProgress then
            progressCurrent = ensureNumber(currentValue, 0)
            progressMax = ensureNumber(maxValue, 0)
            if progressCurrent < 0 then
                progressCurrent = 0
            end
            if progressMax < 0 then
                progressMax = 0
            end
        elseif type(context) == "table" and context.failure ~= nil then
            return nil, 0, 0, true
        end
    end

    local hasRewards = extractHasRewards(context, api, campaignKey or infoHandle)

    local isCompleted = false
    if activityCount > 0 then
        isCompleted = completedActivities >= activityCount
    elseif progressMax > 0 then
        isCompleted = progressCurrent >= progressMax
    end

    local storedKey = normalizeCampaignKey(campaignKey or infoHandle)

    local campaign = {
        key = storedKey,
        id = campaignId,
        name = campaignName,
        desc = description,
        progress = {
            current = progressCurrent,
            max = progressMax,
        },
        activities = activities,
        hasRewards = hasRewards,
        isCompleted = isCompleted == true,
    }

    return campaign, activityCount, completedActivities, false
end

local function buildCampaignViewModel(api)
    local context = { failure = nil }

    if type(api) ~= "table" then
        context.failure = "promo API table missing"
        return newEmptyCampaignViewModel(), newEmptyCampaignStats(), true, context.failure
    end

    local okCount, countValue = callDirectPromoApi(context, api, "GetCampaignCount")
    if not okCount then
        return newEmptyCampaignViewModel(), newEmptyCampaignStats(), true, context.failure
    end

    local campaignCount = toNonNegativeInteger(countValue)
    if campaignCount <= 0 then
        return { campaigns = {} }, { totalCampaigns = 0, totalActivities = 0, completedActivities = 0 }, false, nil
    end

    local trackedCampaignKey, trackedActivityIndex, trackedFailure = fetchTrackedActivity(context, api)
    if trackedFailure then
        return newEmptyCampaignViewModel(), newEmptyCampaignStats(), true, context.failure
    end

    local campaigns = {}
    local totalActivities = 0
    local completedActivities = 0

    for index = 1, campaignCount do
        local okKey, campaignKey = callDirectPromoApi(context, api, "GetCampaignKey", index)
        if not okKey then
            return newEmptyCampaignViewModel(), newEmptyCampaignStats(), true, context.failure
        end

        local okInfo, campaignId = callDirectPromoApi(context, api, "GetCampaignInfo", campaignKey)
        if not okInfo then
            return newEmptyCampaignViewModel(), newEmptyCampaignStats(), true, context.failure
        end

        local campaign, activityCount, completedCount, missingApi = buildCampaign(
            context,
            api,
            campaignKey,
            campaignId,
            trackedCampaignKey,
            trackedActivityIndex
        )
        if missingApi then
            return newEmptyCampaignViewModel(), newEmptyCampaignStats(), true, context.failure
        end

        if type(campaign) == "table" then
            campaigns[#campaigns + 1] = campaign
            totalActivities = totalActivities + (activityCount or 0)
            completedActivities = completedActivities + (completedCount or 0)
        end
    end

    if context.failure ~= nil then
        return newEmptyCampaignViewModel(), newEmptyCampaignStats(), true, context.failure
    end

    return {
        campaigns = campaigns,
    }, {
        totalCampaigns = #campaigns,
        totalActivities = totalActivities,
        completedActivities = completedActivities,
    }, false, nil
end

function GoldenModel:RefreshFromGame(providerFn)
    local promoApiReady = true
    local guardedEmpty = false
    local failureMessage = nil

    local viewModel = newEmptyCampaignViewModel()
    local stats = newEmptyCampaignStats()

    local isLocked = false
    local lockFn = rawget(_G, "IsPromotionalEventSystemLocked")
    if type(lockFn) == "function" then
        local okLocked, lockedValue = pcall(lockFn)
        if not okLocked then
            promoApiReady = false
            guardedEmpty = true
            failureMessage = string.format("promo lock check failed: %s", tostring(lockedValue))
        elseif lockedValue then
            isLocked = true
        end
    end

    if not guardedEmpty and not isLocked then
        local api, missingMessage = collectPromoApiFunctions()
        if not api then
            promoApiReady = false
            guardedEmpty = true
            failureMessage = missingMessage
        else
            local builtViewModel, builtStats, contextGuarded, contextFailure = buildCampaignViewModel(api)
            if contextGuarded then
                promoApiReady = false
                guardedEmpty = true
                failureMessage = contextFailure or missingMessage
            else
                viewModel = type(builtViewModel) == "table" and builtViewModel or viewModel
                stats = type(builtStats) == "table" and builtStats or stats
            end
        end
    end

    if guardedEmpty then
        viewModel = newEmptyCampaignViewModel()
        stats = newEmptyCampaignStats()
    end

    self._promoApiReady = promoApiReady == true
    self._promoGuardedEmpty = guardedEmpty == true

    if guardedEmpty then
        recordPromoFailure(self, failureMessage)
    else
        recordPromoFailure(self, nil)
    end

    self._vm = viewModel
    self._viewData = deepCopyTable(viewModel) or newEmptyCampaignViewModel()
    self._rawData = nil

    stats = type(stats) == "table" and stats or newEmptyCampaignStats()
    self._counters = {
        campaigns = toNonNegativeInteger(stats.totalCampaigns),
        activitiesCompleted = toNonNegativeInteger(stats.completedActivities),
        activitiesTotal = toNonNegativeInteger(stats.totalActivities),
    }
    self._isEmpty = computeIsEmpty(self._counters)

    debugLog(
        "scan: campaigns=%d activities=%d completed=%d",
        self._counters.campaigns or 0,
        self._counters.activitiesTotal or 0,
        self._counters.activitiesCompleted or 0
    )

    if (self._counters.campaigns or 0) <= 0 then
        debugLog("no active golden campaigns (empty VM)")
    end

    return true
end

function GoldenModel:IsPromoApiReady()
    return self._promoApiReady == true
end

function GoldenModel:WasPromoApiGuardedEmpty()
    return self._promoGuardedEmpty == true
end

function GoldenModel:GetRawData()
    return self:GetViewData()
end

function GoldenModel:GetViewData()
    local source = self._viewData or self._vm
    local copy = deepCopyTable(source)
    if type(copy) ~= "table" then
        copy = newEmptyCampaignViewModel()
    end

    if type(copy.campaigns) ~= "table" then
        copy.campaigns = {}
    end

    return copy
end

function GoldenModel:GetCounters()
    local counters = self._counters
    if type(counters) ~= "table" then
        counters = newEmptyCounters()
    end

    return {
        campaigns = counters.campaigns or 0,
        activitiesCompleted = counters.activitiesCompleted or 0,
        activitiesTotal = counters.activitiesTotal or 0,
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
