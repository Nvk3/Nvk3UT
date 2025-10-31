Nvk3UT = Nvk3UT or {}

local function logShim(action)
    local diagnostics = Nvk3UT and Nvk3UT.Diagnostics
    if diagnostics and diagnostics.Debug then
        diagnostics.Debug("CompletedSummary SHIM -> %s", tostring(action))
    end
end

local function resolveSummary()
    return Nvk3UT and Nvk3UT.CompletedSummary
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

function Nvk3UT_EnableCompletedSummary(...)
    logShim("Init")
    local summary = resolveSummary()
    if not summary or type(summary.Init) ~= "function" then
        return nil
    end
    return safeCall(summary.Init, summary, ...)
end

function Nvk3UT_RefreshCompletedSummary(...)
    logShim("Refresh")
    local summary = resolveSummary()
    if not summary or type(summary.Refresh) ~= "function" then
        return nil
    end
    return safeCall(summary.Refresh, summary, ...)
end

function Nvk3UT_SetCompletedSummaryVisible(...)
    logShim("SetVisible")
    local summary = resolveSummary()
    if not summary or type(summary.SetVisible) ~= "function" then
        return nil
    end
    return safeCall(summary.SetVisible, summary, ...)
end

function Nvk3UT_GetCompletedSummaryHeight(...)
    local summary = resolveSummary()
    if not summary or type(summary.GetHeight) ~= "function" then
        return 0
    end
    local height = safeCall(summary.GetHeight, summary, ...)
    return tonumber(height) or 0
end

return true
