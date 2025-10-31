Nvk3UT = Nvk3UT or {}

local function logShim(action)
    local diagnostics = Nvk3UT and Nvk3UT.Diagnostics
    if diagnostics and diagnostics.Debug then
        diagnostics.Debug("Journal SHIM -> %s", tostring(action))
    end
end

local function resolveJournal()
    return Nvk3UT and Nvk3UT.AchievementsJournal
end

local function safeCall(func, ...)
    if type(func) ~= "function" then
        return nil
    end

    local SafeCall = Nvk3UT and Nvk3UT.SafeCall
    if type(SafeCall) == "function" then
        return SafeCall(func, ...)
    end

    local ok, result = pcall(func, ...)
    if ok then
        return result
    end
end

local Shim = {}
Nvk3UT.Achievements = Shim

function Shim.Init(...)
    logShim("Init")
    local journal = resolveJournal()
    if not journal or type(journal.Init) ~= "function" then
        return nil
    end
    return safeCall(journal.Init, journal, ...)
end

function Shim.Refresh(...)
    logShim("Refresh")
    local journal = resolveJournal()
    if not journal or type(journal.Refresh) ~= "function" then
        return nil
    end
    return safeCall(journal.Refresh, journal, ...)
end

function Shim.IsComplete(...)
    local journal = resolveJournal()
    if not journal or type(journal.IsComplete) ~= "function" then
        return false
    end
    return safeCall(journal.IsComplete, ...)
end

return Shim
