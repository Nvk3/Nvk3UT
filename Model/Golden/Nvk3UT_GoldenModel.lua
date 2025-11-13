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
GoldenModel.api = type(GoldenModel.api) == "table" and GoldenModel.api or nil
GoldenModel.apiReady = GoldenModel.apiReady == true
GoldenModel.apiGuardedEmpty = GoldenModel.apiGuardedEmpty == true

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

    self:ResetPromoApiBindings()

    self._rawData = nil
    self._vm = newEmptyCampaignViewModel()
    self._viewData = newEmptyCampaignViewModel()
    self._counters = newEmptyCounters()
    self._isEmpty = true

    debugLog("init")

    return self
end

local function callWithArgs(fn, args)
    if type(fn) ~= "function" then
        return false, "missing function"
    end

    if type(args) ~= "table" or #args == 0 then
        local ok, err = pcall(fn)
        if not ok then
            return false, err
        end
        return true
    end

    if unpack then
        local ok, err = pcall(function()
            return fn(unpack(args))
        end)
        if not ok then
            return false, err
        end
        return true
    end

    local count = #args
    if count == 1 then
        local ok, err = pcall(fn, args[1])
        if not ok then
            return false, err
        end
        return true
    elseif count == 2 then
        local ok, err = pcall(fn, args[1], args[2])
        if not ok then
            return false, err
        end
        return true
    elseif count == 3 then
        local ok, err = pcall(fn, args[1], args[2], args[3])
        if not ok then
            return false, err
        end
        return true
    end

    local ok, err = pcall(function()
        return fn()
    end)
    if not ok then
        return false, err
    end
    return true
end

local function BindFuncAny(role, names, probeArgs)
    if type(names) ~= "table" then
        return nil, nil
    end

    for index = 1, #names do
        local candidate = names[index]
        local fn = rawget(_G, candidate)
        if type(fn) == "function" then
            local ok = true
            local err
            if probeArgs ~= false then
                local args = nil
                if type(probeArgs) == "function" then
                    local success, produced = pcall(probeArgs, candidate)
                    if success then
                        args = produced
                    else
                        args = {}
                    end
                elseif type(probeArgs) == "table" then
                    args = probeArgs
                else
                    args = {}
                end

                ok, err = callWithArgs(fn, args)
            end

            if ok then
                Dbg("bind %s=%s", tostring(role), tostring(candidate))
                return fn, candidate
            end

            if err ~= nil then
                Dbg("bind %s probe failed (%s): %s", tostring(role), tostring(candidate), tostring(err))
            end
        end
    end

    Dbg("bind %s failed (no candidates)", tostring(role))
    return nil, nil
end

local PROMO_API_CANDIDATES = {
    GetCampaignCount = {
        names = {
            "GetNumActivePromotionalEventCampaigns",
        },
        probe = {},
    },
    GetCampaignKey = {
        names = {
            "GetActivePromotionalEventCampaignKey",
        },
        probe = { 1 },
    },
    GetCampaignInfo = {
        names = {
            "GetPromotionalEventCampaignInfo",
        },
        probe = false,
    },
    GetCampaignName = {
        names = {
            "GetPromotionalEventCampaignDisplayName",
        },
        probe = false,
    },
    GetCampaignDesc = {
        names = {
            "GetPromotionalEventCampaignDescription",
        },
        probe = false,
    },
    GetSecondsLeft = {
        names = {
            "GetSecondsRemainingInPromotionalEventCampaign",
        },
        probe = false,
    },
    GetCampaignProg = {
        names = {
            "GetPromotionalEventCampaignProgress",
        },
        probe = false,
    },
    GetActivityInfo = {
        names = {
            "GetPromotionalEventCampaignActivityInfo",
        },
        probe = false,
    },
    GetActivityProg = {
        names = {
            "GetPromotionalEventCampaignActivityProgress",
        },
        probe = false,
    },
    GetActivityCount = {
        names = {
            "GetNumPromotionalEventCampaignActivities",
        },
        probe = false,
    },
    GetTracked = {
        names = {
            "GetTrackedPromotionalEventActivityInfo",
        },
        probe = {},
    },
}

local PROMO_API_ORDER = {
    "GetCampaignCount",
    "GetCampaignKey",
    "GetCampaignInfo",
    "GetCampaignName",
    "GetCampaignDesc",
    "GetSecondsLeft",
    "GetCampaignProg",
    "GetActivityInfo",
    "GetActivityProg",
    "GetActivityCount",
    "GetTracked",
}

local REQUIRED_PROMO_API_ROLES = {
    "GetCampaignCount",
    "GetCampaignKey",
    "GetCampaignInfo",
    "GetCampaignName",
    "GetActivityInfo",
    "GetActivityProg",
}

local function resetPromoApiBindings(model)
    if type(model) ~= "table" then
        return
    end

    model.apiReady = false
    model.api = nil
end

function GoldenModel:ResetPromoApiBindings()
    resetPromoApiBindings(self)
end

function GoldenModel:BindAPIsIfNeeded()
    if self.apiReady then
        return true
    end

    local api = type(self.api) == "table" and self.api or {}
    api.names = type(api.names) == "table" and api.names or {}

    self.api = api

    for index = 1, #PROMO_API_ORDER do
        local role = PROMO_API_ORDER[index]
        local descriptor = PROMO_API_CANDIDATES[role]
        local fn, actual = BindFuncAny(role, descriptor and descriptor.names or nil, descriptor and descriptor.probe)
        api[role] = fn
        api.names[role] = actual
    end

    for index = 1, #REQUIRED_PROMO_API_ROLES do
        local role = REQUIRED_PROMO_API_ROLES[index]
        if type(api[role]) ~= "function" then
            self.apiReady = false
            Dbg("promo API missing; delivering empty VM (binder missing %s)", tostring(role))
            return false
        end
    end

    self.apiReady = true

    local summary = {}
    for index = 1, #PROMO_API_ORDER do
        local role = PROMO_API_ORDER[index]
        if type(api[role]) == "function" then
            summary[#summary + 1] = string.format("%s=%s", tostring(role), tostring(api.names[role] or "?"))
        end
    end

    if #summary > 0 then
        Dbg("promo API ready: %s", table.concat(summary, ", "))
    end

    return true
end

function GoldenModel:IsPromoApiReady()
    return self.apiReady == true
end

function GoldenModel:WasPromoApiGuardedEmpty()
    return self.apiGuardedEmpty == true
end

local function resolveBoundName(api, role)
    if type(api) == "table" and type(api.names) == "table" then
        local name = api.names[role]
        if name ~= nil then
            return tostring(name)
        end
    end
    return "?"
end

local function callPromoApi(model, api, role, fn, ...)
    if type(fn) ~= "function" then
        resetPromoApiBindings(model)
        Dbg("missing binder: %s", tostring(role))
        return false
    end

    local ok, a, b, c, d, e, f = pcall(fn, ...)
    if not ok then
        resetPromoApiBindings(model)
        Dbg(
            "call failed: %s/%s → %s",
            tostring(role),
            resolveBoundName(api, role),
            tostring(a)
        )
        return false
    end

    return true, a, b, c, d, e, f
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

local function fetchTrackedActivity(model, api)
    if type(model) ~= "table" or type(api) ~= "table" then
        return nil, nil, true
    end

    local fn = api.GetTracked
    if type(fn) ~= "function" then
        resetPromoApiBindings(model)
        Dbg("missing binder: GetTracked")
        return nil, nil, true
    end

    local ok, campaignKey, activityIndex = callPromoApi(model, api, "GetTracked", fn)
    if not ok then
        return nil, nil, true
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

local function buildCampaignActivities(model, api, progressKey, infoId, trackedCampaignKey, trackedActivityIndex)
    local activities = {}
    local totalActivities = 0
    local completedActivities = 0

    if type(api) ~= "table" then
        return activities, totalActivities, completedActivities, true
    end

    local progressHandle = progressKey
    local infoHandle = infoId or progressHandle
    if infoHandle == nil and progressHandle == nil then
        return activities, totalActivities, completedActivities, true
    end

    local normalizedProgressKey = nil
    if progressHandle ~= nil then
        normalizedProgressKey = normalizeCampaignKey(progressHandle)
    end

    local infoFn = api.GetActivityInfo
    if type(infoFn) ~= "function" then
        resetPromoApiBindings(model)
        Dbg("missing binder: GetActivityInfo")
        return activities, totalActivities, completedActivities, true
    end

    local progressFn = api.GetActivityProg
    if type(progressFn) ~= "function" then
        resetPromoApiBindings(model)
        Dbg("missing binder: GetActivityProg")
        return activities, totalActivities, completedActivities, true
    end

    local countFn = api.GetActivityCount

    local activityCountOverride = nil
    if type(countFn) == "function" and progressHandle ~= nil then
        local okCount, countValue = callPromoApi(model, api, "GetActivityCount", countFn, progressHandle)
        if not okCount then
            return activities, totalActivities, completedActivities, true
        end

        activityCountOverride = toNonNegativeInteger(countValue)
    end

    local loopUpperBound = activityCountOverride
    if loopUpperBound == nil then
        loopUpperBound = MAX_CAMPAIGN_ACTIVITIES
    end

    for index = 1, loopUpperBound do
        local okInfo, name, description = callPromoApi(model, api, "GetActivityInfo", infoFn, infoHandle, index)
        if not okInfo then
            return activities, totalActivities, completedActivities, true
        end

        local hasName = type(name) == "string" and name ~= ""
        local hasDescription = type(description) == "string" and description ~= ""
        if name == nil and description == nil then
            break
        end
        if not hasName and not hasDescription and name == "" and description == "" then
            break
        end

        local activityName = ensureString(name)
        local activityDescription = sanitizeDescription(description)

        local current, maximum = 0, 0
        if progressHandle ~= nil then
            local okProgress, progressCurrent, progressMax = callPromoApi(model, api, "GetActivityProg", progressFn, progressHandle, index)
            if not okProgress then
                return activities, totalActivities, completedActivities, true
            end

            current = ensureNumber(progressCurrent, 0)
            maximum = ensureNumber(progressMax, 0)
        else
            current = 0
            maximum = 0
        end

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
        if trackedCampaignKey ~= nil and trackedCampaignKey == normalizedProgressKey then
            if toNonNegativeInteger(trackedActivityIndex) == index then
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

local function extractHasRewards(model, api, infoHandle)
    if type(api) ~= "table" then
        return nil
    end

    if infoHandle == nil then
        return nil
    end

    local infoFn = api.GetCampaignInfo
    if type(infoFn) ~= "function" then
        return nil
    end

    local okInfo, a, b, c, d, e, f = callPromoApi(model, api, "GetCampaignInfo", infoFn, infoHandle)
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

local function buildCampaign(model, api, campaignKey, campaignId, trackedCampaignKey, trackedActivityIndex)
    if campaignKey == nil and campaignId == nil then
        return nil, 0, 0, false
    end

    local normalizedKey = nil
    if campaignKey ~= nil then
        normalizedKey = normalizeCampaignKey(campaignKey)
    end

    if type(api) ~= "table" then
        return nil, 0, 0, true
    end

    local nameFn = api.GetCampaignName
    if type(nameFn) ~= "function" then
        resetPromoApiBindings(model)
        Dbg("missing binder: GetCampaignName")
        return nil, 0, 0, true
    end

    local infoHandle = campaignId or normalizedKey
    if infoHandle == nil then
        return nil, 0, 0, true
    end
    local okName, displayName = callPromoApi(model, api, "GetCampaignName", nameFn, infoHandle)
    if not okName then
        return nil, 0, 0, true
    end
    local campaignName = ensureString(displayName)

    local description = nil
    local descFn = api.GetCampaignDesc
    if type(descFn) == "function" then
        local okDesc, descValue = callPromoApi(model, api, "GetCampaignDesc", descFn, infoHandle)
        if okDesc then
            description = sanitizeDescription(descValue)
        end
    end

    local activities, activityCount, completedActivities, missingActivities = buildCampaignActivities(
        model,
        api,
        campaignKey,
        campaignKey,
        trackedCampaignKey,
        trackedActivityIndex
    )
    if missingActivities then
        return nil, 0, 0, true
    end

    local progressCurrent, progressMax = 0, 0
    local progressFn = api.GetCampaignProg
    if type(progressFn) == "function" and campaignKey ~= nil then
        local okProgress, currentValue, maxValue = callPromoApi(model, api, "GetCampaignProg", progressFn, campaignKey)
        if okProgress then
            progressCurrent = ensureNumber(currentValue, 0)
            progressMax = ensureNumber(maxValue, 0)
        end
    end

    if progressCurrent < 0 then
        progressCurrent = 0
    end
    if progressMax < 0 then
        progressMax = 0
    end

    local hasRewards = extractHasRewards(model, api, campaignKey)

    local isCompleted = false
    if activityCount > 0 then
        isCompleted = completedActivities >= activityCount
    elseif progressMax > 0 then
        isCompleted = progressCurrent >= progressMax
    end

    local storedKey = normalizedKey or normalizeCampaignKey(infoHandle)

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

local function buildCampaignViewModel(model, api)
    local campaigns = {}
    if type(api) ~= "table" then
        return newEmptyCampaignViewModel(), newEmptyCampaignStats(), true
    end

    local countFn = api.GetCampaignCount
    local keyFn = api.GetCampaignKey
    local infoFn = api.GetCampaignInfo
    local nameFn = api.GetCampaignName
    if type(countFn) ~= "function" or type(keyFn) ~= "function" or type(infoFn) ~= "function" or type(nameFn) ~= "function" then
        resetPromoApiBindings(model)
        Dbg("promo API missing; delivering empty VM")
        return newEmptyCampaignViewModel(), newEmptyCampaignStats(), true
    end

    local okCount, countValue = callPromoApi(model, api, "GetCampaignCount", countFn)
    if not okCount then
        return newEmptyCampaignViewModel(), newEmptyCampaignStats(), true
    end

    local campaignCount = toNonNegativeInteger(countValue)

    local trackedCampaignKey, trackedActivityIndex, missingTracked = fetchTrackedActivity(model, api)
    if missingTracked then
        Dbg("promo API missing; delivering empty VM (tracked)")
        return newEmptyCampaignViewModel(), newEmptyCampaignStats(), true
    end

    local totalActivities = 0
    local completedActivities = 0

    for index = 1, campaignCount do
        local okKey, campaignKey = callPromoApi(model, api, "GetCampaignKey", keyFn, index)
        if not okKey then
            return newEmptyCampaignViewModel(), newEmptyCampaignStats(), true
        end

        local campaignId = nil
        local okInfo, infoId = callPromoApi(model, api, "GetCampaignInfo", infoFn, campaignKey)
        if not okInfo then
            return newEmptyCampaignViewModel(), newEmptyCampaignStats(), true
        end

        campaignId = infoId

        if campaignKey ~= nil or campaignId ~= nil then
            local campaign, activityCount, completedCount, missingApi = buildCampaign(
                model,
                api,
                campaignKey,
                campaignId,
                trackedCampaignKey,
                trackedActivityIndex
            )
            if missingApi then
                return newEmptyCampaignViewModel(), newEmptyCampaignStats(), true
            end

            if type(campaign) == "table" then
                campaigns[#campaigns + 1] = campaign
                totalActivities = totalActivities + (activityCount or 0)
                completedActivities = completedActivities + (completedCount or 0)
            end
        end
    end

    return {
        campaigns = campaigns,
    }, {
        totalCampaigns = #campaigns,
        totalActivities = totalActivities,
        completedActivities = completedActivities,
    }, false
end

function GoldenModel:RefreshFromGame(providerFn)
    local apiReady = self:BindAPIsIfNeeded()

    local viewModel
    local stats
    local guardedEmpty = false

    if not apiReady then
        guardedEmpty = true
        viewModel = newEmptyCampaignViewModel()
        stats = newEmptyCampaignStats()
    else
        viewModel, stats, guardedEmpty = buildCampaignViewModel(self, self.api)
        if type(viewModel) ~= "table" then
            viewModel = newEmptyCampaignViewModel()
        end

        if guardedEmpty then
            viewModel = newEmptyCampaignViewModel()
            stats = newEmptyCampaignStats()
        end
    end

    self.apiGuardedEmpty = guardedEmpty == true

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
