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

local function ensureString(value, fallback)
    if value == nil then
        if fallback ~= nil then
            return tostring(fallback)
        end
        return ""
    end
    return tostring(value)
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

local goldenApi

do
    -- Local Golden API facade that centralizes promotional event queries for Golden pursuits.
    local function fetchGlobal(name)
        if type(_G) == "table" then
            local fn = rawget(_G, name)
            if type(fn) == "function" then
                return fn
            end
        end
        return nil
    end

    local RequestPromotionalEventCampaignData = fetchGlobal("RequestPromotionalEventCampaignData")
    local GetNumActivePromotionalEventCampaigns = fetchGlobal("GetNumActivePromotionalEventCampaigns")
    local GetActivePromotionalEventCampaignKey = fetchGlobal("GetActivePromotionalEventCampaignKey")
    local GetActivePromotionalEventCampaignId = fetchGlobal("GetActivePromotionalEventCampaignId")
    local GetPromotionalEventCampaignId = fetchGlobal("GetPromotionalEventCampaignId")
    local GetPromotionalEventCampaignInfo = fetchGlobal("GetPromotionalEventCampaignInfo")
    local GetPromotionalEventCampaignDisplayName = fetchGlobal("GetPromotionalEventCampaignDisplayName")
    local GetPromotionalEventCampaignDescription = fetchGlobal("GetPromotionalEventCampaignDescription")
    local GetSecondsRemainingInPromotionalEventCampaign = fetchGlobal("GetSecondsRemainingInPromotionalEventCampaign")
    local GetNumPromotionalEventCampaignActivities = fetchGlobal("GetNumPromotionalEventCampaignActivities")
    local GetNumPromotionalEventActivities = fetchGlobal("GetNumPromotionalEventActivities")
    local GetPromotionalEventCampaignActivityInfo = fetchGlobal("GetPromotionalEventCampaignActivityInfo")
    local GetPromotionalEventCampaignActivityProgress = fetchGlobal("GetPromotionalEventCampaignActivityProgress")
    local GetPromotionalEventCampaignActivityTimeRemainingSeconds = fetchGlobal("GetPromotionalEventCampaignActivityTimeRemainingSeconds")
    local GetPromotionalEventActivityInfo = fetchGlobal("GetPromotionalEventActivityInfo")
    local GetPromotionalEventActivityTimeRemainingSeconds = fetchGlobal("GetPromotionalEventActivityTimeRemainingSeconds")
    local IsPromotionalEventSystemLocked = fetchGlobal("IsPromotionalEventSystemLocked")

    local PROMO_ACTIVITY_FREQ_DAILY = rawget(_G, "PROMOTIONAL_EVENT_ACTIVITY_FREQUENCY_DAILY")
    local PROMO_ACTIVITY_FREQ_WEEKLY = rawget(_G, "PROMOTIONAL_EVENT_ACTIVITY_FREQUENCY_WEEKLY")
    local PROMO_RESET_FREQ_DAILY = rawget(_G, "PROMOTIONAL_EVENT_RESET_FREQUENCY_DAILY")
    local PROMO_RESET_FREQ_WEEKLY = rawget(_G, "PROMOTIONAL_EVENT_RESET_FREQUENCY_WEEKLY")

    goldenApi = {}

    local function collectHandles(campaignHandle, campaignIndex, campaignMeta)
        local handles = {}

        local function push(value)
            if value ~= nil then
                handles[#handles + 1] = value
            end
        end

        push(campaignHandle)
        if campaignMeta then
            push(campaignMeta.id)
            push(campaignMeta.handle)
            push(campaignMeta.key)
        end
        push(campaignIndex)

        return handles
    end

    local function invokeCampaignFunction(fn, campaignHandle, campaignIndex, campaignMeta)
        if type(fn) ~= "function" then
            return nil
        end

        local handles = collectHandles(campaignHandle, campaignIndex, campaignMeta)
        for index = 1, #handles do
            local handle = handles[index]
            local results = { safeCall(fn, handle) }
            if #results > 0 and results[1] ~= nil then
                if unpack then
                    return unpack(results)
                end
                return results[1]
            end
        end

        return nil
    end

    local function invokeCampaignActivityFunction(fn, campaignHandle, campaignIndex, campaignMeta, activityIndex)
        if type(fn) ~= "function" then
            return nil
        end

        local handles = collectHandles(campaignHandle, campaignIndex, campaignMeta)
        for index = 1, #handles do
            local handle = handles[index]
            local results = { safeCall(fn, handle, activityIndex) }
            if #results > 0 and results[1] ~= nil then
                if unpack then
                    return unpack(results)
                end
                return results[1]
            end
        end

        return nil
    end

    local function normalizeFrequency(frequency, campaignFrequency, campaignIndex)
        local function translate(value)
            if type(value) == "string" then
                local lowered = string.lower(value)
                if lowered == "daily" then
                    return "daily"
                elseif lowered == "weekly" then
                    return "weekly"
                end
            end

            local numeric = tonumber(value)
            if numeric ~= nil then
                if PROMO_ACTIVITY_FREQ_DAILY ~= nil and numeric == PROMO_ACTIVITY_FREQ_DAILY then
                    return "daily"
                end
                if PROMO_ACTIVITY_FREQ_WEEKLY ~= nil and numeric == PROMO_ACTIVITY_FREQ_WEEKLY then
                    return "weekly"
                end
                if PROMO_ACTIVITY_FREQ_DAILY == nil and numeric == 1 then
                    return "daily"
                end
                if PROMO_ACTIVITY_FREQ_WEEKLY == nil and numeric == 2 then
                    return "weekly"
                end
                if PROMO_RESET_FREQ_DAILY ~= nil and numeric == PROMO_RESET_FREQ_DAILY then
                    return "daily"
                end
                if PROMO_RESET_FREQ_WEEKLY ~= nil and numeric == PROMO_RESET_FREQ_WEEKLY then
                    return "weekly"
                end
            end

            return nil
        end

        local bucket = translate(frequency)
        if bucket ~= nil then
            return bucket
        end

        bucket = translate(campaignFrequency)
        if bucket ~= nil then
            return bucket
        end

        if campaignIndex == 1 then
            return "daily"
        elseif campaignIndex == 2 then
            return "weekly"
        end

        return nil
    end

    local function resolveCampaignHandle(index, explicitHandle)
        if explicitHandle ~= nil then
            return explicitHandle
        end
        if type(GetActivePromotionalEventCampaignKey) == "function" then
            local key = safeCall(GetActivePromotionalEventCampaignKey, index)
            if key ~= nil then
                return key
            end
        end
        if type(GetActivePromotionalEventCampaignId) == "function" then
            local value = safeCall(GetActivePromotionalEventCampaignId, index)
            if value ~= nil then
                return value
            end
        end
        if type(GetPromotionalEventCampaignId) == "function" then
            local value = safeCall(GetPromotionalEventCampaignId, index)
            if value ~= nil then
                return value
            end
        end
        return index
    end

    function goldenApi:InvokeProvider(providerFn)
        if type(providerFn) ~= "function" then
            return nil
        end

        local payload = safeCall(providerFn)
        if payload ~= nil then
            return payload
        end

        local ok, fallback = pcall(providerFn)
        if ok then
            return fallback
        end

        return nil
    end

    function goldenApi:IsSystemLocked()
        if type(IsPromotionalEventSystemLocked) ~= "function" then
            return false
        end

        local locked = safeCall(IsPromotionalEventSystemLocked)
        return locked == true
    end

    function goldenApi:GetActiveCampaignCount()
        if type(GetNumActivePromotionalEventCampaigns) ~= "function" then
            return 0
        end

        local count = safeCall(GetNumActivePromotionalEventCampaigns)
        count = ensureNumber(count, 0)
        if count < 0 then
            count = 0
        end

        return count
    end

    function goldenApi:WarmupCampaignData()
        if type(RequestPromotionalEventCampaignData) ~= "function" then
            return
        end

        safeCall(RequestPromotionalEventCampaignData)
    end

    function goldenApi:CollectVeqAugment(campaignHandle, activityIndex)
        -- Placeholder for Phase B2 VEQ augmentation hook.
        -- Future tokens will enrich Golden pursuit activities with VEQ data here.
        return nil
    end

    function goldenApi:BuildActivityPayload(campaignHandle, campaignIndex, activityIndex, campaignMeta)
        local payload = {
            campaignIndex = campaignIndex,
            campaignHandle = campaignHandle,
            activityIndex = activityIndex,
        }

        local activityId
        local name
        local description
        local completionThreshold
        local rewardId
        local rewardQuantity
        local activityFrequency

        if type(GetPromotionalEventCampaignActivityInfo) == "function" then
            activityId, name, description, completionThreshold, rewardId, rewardQuantity, activityFrequency = invokeCampaignActivityFunction(
                GetPromotionalEventCampaignActivityInfo,
                campaignHandle,
                campaignIndex,
                campaignMeta,
                activityIndex
            )
        end

        if type(GetPromotionalEventActivityInfo) == "function" then
            local fallbackName, fallbackDescription, progress, maxProgress, completed, fallbackFrequency = invokeCampaignActivityFunction(
                GetPromotionalEventActivityInfo,
                campaignHandle,
                campaignIndex,
                campaignMeta,
                activityIndex
            )
            if name == nil and fallbackName ~= nil then
                name = fallbackName
            end
            if description == nil and fallbackDescription ~= nil then
                description = fallbackDescription
            end
            if payload.progress == nil and progress ~= nil then
                payload.progress = progress
            end
            if completionThreshold == nil and maxProgress ~= nil then
                completionThreshold = maxProgress
            end
            if payload.isCompleted == nil and completed ~= nil then
                payload.isCompleted = completed == true
            end
            if activityFrequency == nil and fallbackFrequency ~= nil then
                activityFrequency = fallbackFrequency
            end
        end

        payload.id = activityId or string.format("%s:%d", tostring(campaignHandle), activityIndex)
        payload.name = ensureString(name)
        payload.description = ensureString(description)
        payload.rewardId = rewardId
        payload.rewardQuantity = rewardQuantity

        if completionThreshold ~= nil then
            payload.maxProgress = ensureNumber(completionThreshold, 1)
        end

        if type(GetPromotionalEventCampaignActivityProgress) == "function" then
            local progress, isRewardClaimed = invokeCampaignActivityFunction(
                GetPromotionalEventCampaignActivityProgress,
                campaignHandle,
                campaignIndex,
                campaignMeta,
                activityIndex
            )
            if progress ~= nil then
                payload.progress = ensureNumber(progress, payload.progress or 0)
            end
            if isRewardClaimed ~= nil and payload.isCompleted == nil then
                payload.isCompleted = isRewardClaimed == true
            end
            payload.isRewardClaimed = isRewardClaimed == true
        end

        if payload.progress == nil then
            payload.progress = 0
        end

        if payload.maxProgress == nil then
            payload.maxProgress = 1
        end

        if payload.isCompleted == nil then
            payload.isCompleted = payload.progress >= payload.maxProgress and payload.maxProgress > 0
        end

        local remaining
        if type(GetPromotionalEventCampaignActivityTimeRemainingSeconds) == "function" then
            remaining = invokeCampaignActivityFunction(
                GetPromotionalEventCampaignActivityTimeRemainingSeconds,
                campaignHandle,
                campaignIndex,
                campaignMeta,
                activityIndex
            )
        elseif type(GetPromotionalEventActivityTimeRemainingSeconds) == "function" then
            remaining = invokeCampaignActivityFunction(
                GetPromotionalEventActivityTimeRemainingSeconds,
                campaignHandle,
                campaignIndex,
                campaignMeta,
                activityIndex
            )
        end

        if remaining ~= nil then
            payload.timeRemainingSec = ensureNumber(remaining, 0)
        elseif campaignMeta and campaignMeta.timeRemainingSec ~= nil then
            payload.timeRemainingSec = ensureNumber(campaignMeta.timeRemainingSec, 0)
        end

        payload.frequency = activityFrequency
        payload.type = normalizeFrequency(activityFrequency, campaignMeta and campaignMeta.resetFrequency, campaignIndex)

        if payload.timeRemainingSec ~= nil then
            payload.remainingSeconds = payload.timeRemainingSec
        end

        local veqAugment = self:CollectVeqAugment(campaignHandle, activityIndex)
        if veqAugment ~= nil then
            payload.veq = veqAugment
        end

        return payload
    end

    function goldenApi:CollectActivitiesForCampaign(campaignHandle, campaignIndex, campaignMeta)
        local activities = {}

        local count
        if type(GetNumPromotionalEventCampaignActivities) == "function" then
            count = invokeCampaignFunction(
                GetNumPromotionalEventCampaignActivities,
                campaignHandle,
                campaignIndex,
                campaignMeta
            )
        end
        if count == nil and type(GetNumPromotionalEventActivities) == "function" then
            count = invokeCampaignFunction(
                GetNumPromotionalEventActivities,
                campaignHandle,
                campaignIndex,
                campaignMeta
            )
        end

        count = ensureNumber(count, 0)

        if count <= 0 then
            return activities
        end

        for activityIndex = 1, count do
            local entry = self:BuildActivityPayload(campaignHandle, campaignIndex, activityIndex, campaignMeta)
            if type(entry) == "table" then
                activities[#activities + 1] = entry
            end
        end

        return activities
    end

    function goldenApi:CollectCampaignActivities()
        local campaigns = {}

        if self:IsSystemLocked() then
            return campaigns
        end

        local total = self:GetActiveCampaignCount()
        if total <= 0 then
            return campaigns
        end

        for index = 1, total do
            local campaignKey
            if type(GetActivePromotionalEventCampaignKey) == "function" then
                campaignKey = safeCall(GetActivePromotionalEventCampaignKey, index)
            end

            local handle = resolveCampaignHandle(index, campaignKey)

            local baseMeta = {
                key = campaignKey,
                handle = handle,
            }

            local campaignId
            local numActivities
            local campaignFrequency
            if type(GetPromotionalEventCampaignInfo) == "function" then
                campaignId, numActivities, _, _, _, _, campaignFrequency = invokeCampaignFunction(
                    GetPromotionalEventCampaignInfo,
                    handle,
                    index,
                    baseMeta
                )
            end

            if campaignId == nil and type(GetPromotionalEventCampaignId) == "function" then
                campaignId = invokeCampaignFunction(
                    GetPromotionalEventCampaignId,
                    handle,
                    index,
                    baseMeta
                )
            end

            baseMeta.id = campaignId or campaignKey or baseMeta.id

            local campaignName
            local campaignDescription
            if type(GetPromotionalEventCampaignDisplayName) == "function" then
                campaignName = invokeCampaignFunction(
                    GetPromotionalEventCampaignDisplayName,
                    campaignId,
                    index,
                    baseMeta
                )
            end
            if type(GetPromotionalEventCampaignDescription) == "function" then
                campaignDescription = invokeCampaignFunction(
                    GetPromotionalEventCampaignDescription,
                    campaignId,
                    index,
                    baseMeta
                )
            end

            local secondsRemaining
            if type(GetSecondsRemainingInPromotionalEventCampaign) == "function" then
                secondsRemaining = invokeCampaignFunction(
                    GetSecondsRemainingInPromotionalEventCampaign,
                    handle,
                    index,
                    baseMeta
                )
            end
            secondsRemaining = ensureNumber(secondsRemaining, 0)

            local campaignMeta = {
                id = campaignId or campaignKey or handle or index,
                handle = handle,
                key = campaignKey,
                index = index,
                resetFrequency = campaignFrequency,
                numActivities = ensureNumber(numActivities, 0),
                displayName = campaignName,
                description = campaignDescription,
                timeRemainingSec = secondsRemaining,
            }

            local activities = self:CollectActivitiesForCampaign(handle, index, campaignMeta)

            if type(activities) == "table" and #activities > 0 then
                campaigns[#campaigns + 1] = {
                    id = campaignMeta.id,
                    index = index,
                    handle = handle,
                    timeRemainingSec = secondsRemaining,
                    resetFrequency = campaignFrequency,
                    displayName = campaignName,
                    description = campaignDescription,
                    activities = activities,
                }
            end
        end

        return campaigns
    end

    function goldenApi:CollectDefaultPayload()
        self:WarmupCampaignData()

        local campaigns = self:CollectCampaignActivities()

        local buckets = {}
        local ordered = {}
        for index = 1, #CATEGORY_ORDER do
            local descriptor = CATEGORY_ORDER[index]
            buckets[descriptor.key] = {
                key = descriptor.key,
                name = descriptor.name,
                entries = {},
                countCompleted = 0,
                countTotal = 0,
                hasCountCompleted = true,
                hasCountTotal = true,
                timeRemainingSec = 0,
            }
            ordered[index] = buckets[descriptor.key]
        end

        for _, campaign in ipairs(campaigns) do
            local campaignRemaining = ensureNumber(campaign.timeRemainingSec, 0)
            for _, activity in ipairs(campaign.activities or {}) do
                local bucketKey = activity.type
                if bucketKey == nil then
                    bucketKey = normalizeFrequency(activity.frequency, campaign.resetFrequency, campaign.index)
                end

                local bucket = bucketKey and buckets[bucketKey]
                if bucket then
                    local entryRemaining = ensureNumber(activity.timeRemainingSec, campaignRemaining)
                    local entryId = activity.id
                    if entryId == nil then
                        local campaignId = campaign.id or campaign.handle or campaign.index
                        entryId = string.format("%s:%d", ensureString(campaignId), ensureNumber(activity.activityIndex, 0))
                    end

                    local entry = {
                        id = ensureString(entryId),
                        name = ensureString(activity.name),
                        description = ensureString(activity.description),
                        progress = ensureNumber(activity.progress, 0),
                        maxProgress = ensureNumber(activity.maxProgress, 1),
                        isCompleted = ensureBoolean(activity.isCompleted, false),
                        timeRemainingSec = entryRemaining,
                        remainingSeconds = entryRemaining,
                        type = bucketKey,
                    }

                    bucket.entries[#bucket.entries + 1] = entry

                    if entryRemaining > 0 then
                        if bucket.timeRemainingSec <= 0 then
                            bucket.timeRemainingSec = entryRemaining
                        else
                            bucket.timeRemainingSec = math.min(bucket.timeRemainingSec, entryRemaining)
                        end
                    end
                end
            end
        end

        for _, bucket in pairs(buckets) do
            local entries = bucket.entries
            local completed = 0
            for index = 1, #entries do
                if entries[index].isCompleted then
                    completed = completed + 1
                end
            end
            bucket.countTotal = #entries
            bucket.countCompleted = completed
        end

        return {
            categories = ordered,
        }
    end

    function goldenApi:BuildPayload(providerFn)
        local payload = self:InvokeProvider(providerFn)
        if type(payload) == "table" then
            return payload
        end

        payload = self:CollectDefaultPayload()
        if type(payload) == "table" then
            return payload
        end

        return nil
    end

    function goldenApi:CreateProvider(providerFn)
        return function()
            return goldenApi:BuildPayload(providerFn)
        end
    end
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

    local dataProvider = goldenApi:CreateProvider(providerFn)
    safeCall(runListRefresh, self._list, dataProvider)

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
