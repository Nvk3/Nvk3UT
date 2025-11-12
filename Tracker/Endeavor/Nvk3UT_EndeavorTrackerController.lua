-- Tracker/Endeavor/Nvk3UT_EndeavorTrackerController.lua
-- Builds Endeavor tracker view models from the Endeavor model snapshot.

local addonName = "Nvk3UT"
local unpack = unpack or table.unpack

Nvk3UT = Nvk3UT or {}

local Controller = Nvk3UT.EndeavorTrackerController or {}
Nvk3UT.EndeavorTrackerController = Controller

local function getRoot()
    local root = rawget(_G, addonName)
    if type(root) == "table" then
        return root
    end

    return Nvk3UT
end

local function resolveDiagnostics()
    local root = getRoot()
    local diagnostics = root and root.Diagnostics
    if type(diagnostics) == "table" then
        return diagnostics
    end

    return nil
end

local function isDebugEnabled()
    local diagnostics = resolveDiagnostics()
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(diagnostics.IsDebugEnabled, diagnostics)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local root = getRoot()
    if type(root) == "table" and type(root.debug) == "boolean" then
        return root.debug
    end

    return false
end

local function debugLog(fmt, ...)
    if not isDebugEnabled() then
        return
    end

    local diagnostics = resolveDiagnostics()
    if diagnostics and type(diagnostics.Debug) == "function" then
        diagnostics.Debug("[EndeavorController] " .. tostring(fmt), ...)
        return
    end

    if type(d) == "function" then
        d(string.format("[Nvk3UT][EndeavorController] " .. tostring(fmt), ...))
        return
    end

    if type(print) == "function" then
        print("[Nvk3UT][EndeavorController]", string.format(tostring(fmt), ...))
    end
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end

    local root = getRoot()
    if type(root) == "table" then
        local safe = rawget(root, "SafeCall")
        if type(safe) == "function" then
            return safe(fn, ...)
        end
    end

    local results = { pcall(fn, ...) }
    if results[1] then
        table.remove(results, 1)
        if #results == 0 then
            return nil
        end
        return unpack(results)
    end

    return nil
end

local function callWithOptionalSelf(target, method, ...)
    if type(method) ~= "function" then
        return nil
    end

    local results = { safeCall(function()
        if target ~= nil then
            return method(target, ...)
        end

        return method(...)
    end) }

    if #results == 0 then
        return nil
    end

    return unpack(results)
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

local function coerceBoolean(value)
    return value == true
end

function Controller:MarkDirty()
    local root = getRoot()
    if type(root) ~= "table" then
        return
    end

    local runtime = rawget(root, "TrackerRuntime")
    if type(runtime) ~= "table" then
        return
    end

    local queueDirty = runtime.QueueDirty or runtime.MarkDirty or runtime.RequestRefresh
    if type(queueDirty) ~= "function" then
        return
    end

    safeCall(function()
        queueDirty(runtime, "endeavor")
    end)
end

function Controller:BuildViewModel()
    local items = {}
    local dailyCount = 0
    local weeklyCount = 0

    local root = getRoot()
    local model = root and rawget(root, "EndeavorModel")

    local viewData
    if type(model) == "table" then
        local getViewData = model.GetViewData or model.GetViewModel
        if type(getViewData) == "function" then
            viewData = callWithOptionalSelf(model, getViewData)
        end
    end

    if type(viewData) ~= "table" then
        viewData = {}
    end

    local function appendItems(bucket, kind)
        if type(bucket) ~= "table" then
            return
        end

        local list = bucket.items
        if type(list) ~= "table" then
            return
        end

        for _, item in ipairs(list) do
            if type(item) == "table" then
                items[#items + 1] = {
                    name = item.name or "",
                    description = item.description or "",
                    progress = coerceNumber(item.progress, 0),
                    maxProgress = coerceNumber(item.maxProgress, 1),
                    type = kind,
                    remainingSeconds = coerceNumber(item.remainingSeconds, 0),
                    completed = coerceBoolean(item.completed),
                }

                if kind == "daily" then
                    dailyCount = dailyCount + 1
                elseif kind == "weekly" then
                    weeklyCount = weeklyCount + 1
                end
            end
        end
    end

    appendItems(viewData.daily, "daily")
    appendItems(viewData.weekly, "weekly")

    debugLog("built view model: count=%d (daily=%d weekly=%d)", #items, dailyCount, weeklyCount)

    return {
        items = items,
        count = #items,
    }
end

return Controller
