Nvk3UT = Nvk3UT or {}

local EVENT_NAMESPACE = "Nvk3UT_RecentSummary"

local function logShim(action)
    local diagnostics = Nvk3UT and Nvk3UT.Diagnostics
    if diagnostics and diagnostics.Debug then
        diagnostics.Debug("RecentSummary SHIM -> %s", tostring(action))
    end
end

local function resolveSummary()
    return Nvk3UT and Nvk3UT.RecentSummary
end

local tableUnpack = table.unpack or unpack

local function safeCall(method, ...)
    local SafeCall = Nvk3UT and Nvk3UT.SafeCall
    if type(SafeCall) == "function" then
        return SafeCall(method, ...)
    end

    if type(method) ~= "function" then
        return nil
    end

    local results = { pcall(method, ...) }
    if not results[1] then
        return nil
    end

    table.remove(results, 1)
    return tableUnpack(results)
end

local eventsRegistered = false

local function safeRefresh(summary)
    if not summary or type(summary.Refresh) ~= "function" then
        return
    end
    safeCall(summary.Refresh, summary)
end

local function registerAchievementEvents(summary)
    if eventsRegistered then
        return
    end

    local em = GetEventManager()
    if not em then
        return
    end

    local function onAchievementsUpdated(eventCode)
        if not (SCENE_MANAGER and type(SCENE_MANAGER.IsShowing) == "function") then
            return
        end
        if not SCENE_MANAGER:IsShowing("achievements") then
            return
        end
        safeRefresh(summary)
    end

    local function onAchievementUpdated(eventCode, achievementId)
        local data = Nvk3UT and Nvk3UT.RecentData
        if data and type(data.Touch) == "function" then
            safeCall(data.Touch, data, achievementId)
        end
    end

    local function onAchievementAwarded(eventCode, _, _, achievementId)
        local data = Nvk3UT and Nvk3UT.RecentData
        if data and type(data.Clear) == "function" then
            safeCall(data.Clear, data, achievementId)
        end
    end

    em:RegisterForEvent(EVENT_NAMESPACE, EVENT_ACHIEVEMENTS_UPDATED, onAchievementsUpdated)
    em:RegisterForEvent(EVENT_NAMESPACE, EVENT_ACHIEVEMENT_UPDATED, onAchievementUpdated)
    em:RegisterForEvent(EVENT_NAMESPACE, EVENT_ACHIEVEMENT_AWARDED, onAchievementAwarded)

    eventsRegistered = true
end

function Nvk3UT_EnableRecentSummary(...)
    logShim("Init")
    local summary = resolveSummary()
    if not summary or type(summary.Init) ~= "function" then
        return nil
    end

    local result = safeCall(summary.Init, summary, ...)
    registerAchievementEvents(summary)
    return result
end
