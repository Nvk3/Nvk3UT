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

-- local debug logger
local function DBG(fmt, ...)
    if not (Nvk3UT and Nvk3UT.debug) then
        return
    end

    local ok, message = pcall(string.format, fmt or "", ...)
    if not ok then
        message = tostring(fmt)
    end

    if type(d) == "function" then
        d("[EndeavorController] " .. message)
    elseif type(print) == "function" then
        print("[EndeavorController] " .. message)
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

    local args = { ... }

    local results = { safeCall(function()
        if target ~= nil then
            return method(target, unpack(args))
        end

        return method(unpack(args))
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

local function clampNonNegative(value, fallback)
    local numeric = coerceNumber(value, fallback or 0)
    if numeric < 0 then
        numeric = 0
    end

    return numeric
end

local function clampProgress(value, maxValue)
    local numeric = clampNonNegative(value, 0)
    if type(maxValue) == "number" and maxValue >= 0 and numeric > maxValue then
        numeric = maxValue
    end

    return numeric
end

local function clampMax(value)
    local numeric = coerceNumber(value, 1)
    if numeric < 1 then
        numeric = 1
    end

    return numeric
end

local function coerceBoolean(value)
    return value == true
end

local function getStateModule()
    local root = getRoot()
    if type(root) ~= "table" then
        return nil
    end

    local stateModule = rawget(root, "EndeavorState")
    if type(stateModule) ~= "table" then
        return nil
    end

    return stateModule
end

local function isStateExpanded(stateModule)
    if type(stateModule) ~= "table" then
        return false
    end

    local method = stateModule.IsExpanded
    if type(method) ~= "function" then
        return false
    end

    local ok, expanded = pcall(method, stateModule)
    return ok and expanded == true
end

local function isCategoryExpanded(stateModule, key)
    if type(stateModule) ~= "table" then
        return false
    end

    local method = stateModule.IsCategoryExpanded
    if type(method) ~= "function" then
        return false
    end

    local ok, expanded = pcall(method, stateModule, key)
    return ok and expanded == true
end

function Controller:BuildViewModel()
    local aggregatedItems = {}
    local dailyObjectives = {}
    local weeklyObjectives = {}
    local dailyCompleted = 0
    local dailyTotal = 0
    local weeklyCompleted = 0
    local weeklyTotal = 0

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

    local summary
    if type(model) == "table" then
        local getSummary = model.GetSummary
        if type(getSummary) == "function" then
            local ok, result = pcall(getSummary, model)
            if ok and type(result) == "table" then
                summary = result
            end
        end
    end

    local dailyBucket = type(viewData.daily) == "table" and viewData.daily or {}
    local weeklyBucket = type(viewData.weekly) == "table" and viewData.weekly or {}

    dailyCompleted = clampNonNegative(summary and summary.dailyCompleted or dailyBucket.completed, 0)
    dailyTotal = clampNonNegative(summary and summary.dailyTotal or dailyBucket.total, 0)
    weeklyCompleted = clampNonNegative(summary and summary.weeklyCompleted or weeklyBucket.completed, 0)
    weeklyTotal = clampNonNegative(summary and summary.weeklyTotal or weeklyBucket.total, 0)

    local function buildObjectives(bucket, target, kind)
        if type(bucket) ~= "table" or type(target) ~= "table" then
            return
        end

        local list = bucket.items
        if type(list) ~= "table" then
            return
        end

        for _, item in ipairs(list) do
            if type(item) == "table" then
                local maxValue = clampMax(item.maxProgress)
                local progressValue = clampProgress(item.progress, maxValue)
                local completed = item.completed == true or progressValue >= maxValue

                local objective = {
                    text = tostring(item.name or ""),
                    progress = progressValue,
                    max = maxValue,
                    completed = completed,
                    remainingSeconds = clampNonNegative(item.remainingSeconds, 0),
                }

                target[#target + 1] = objective

                aggregatedItems[#aggregatedItems + 1] = {
                    name = tostring(item.name or ""),
                    description = tostring(item.description or ""),
                    progress = progressValue,
                    maxProgress = maxValue,
                    type = kind,
                    remainingSeconds = objective.remainingSeconds,
                    completed = completed,
                }
            end
        end
    end

    buildObjectives(dailyBucket, dailyObjectives, "daily")
    buildObjectives(weeklyBucket, weeklyObjectives, "weekly")

    local stateModule = getStateModule()
    local vm = {
        category = {
            title = "Bestrebungen",
            expanded = isStateExpanded(stateModule),
        },
        daily = {
            title = "Tägliche Bestrebungen",
            completed = dailyCompleted,
            total = dailyTotal,
            expanded = isCategoryExpanded(stateModule, "daily"),
            objectives = dailyObjectives,
        },
        weekly = {
            title = "Wöchentliche Bestrebungen",
            completed = weeklyCompleted,
            total = weeklyTotal,
            expanded = isCategoryExpanded(stateModule, "weekly"),
            objectives = weeklyObjectives,
        },
        items = aggregatedItems,
        count = #aggregatedItems,
    }

    DBG(
        "[EndeavorVM] daily=%d/%d weekly=%d/%d objsD=%d objsW=%d",
        dailyCompleted,
        dailyTotal,
        weeklyCompleted,
        weeklyTotal,
        #dailyObjectives,
        #weeklyObjectives
    )

    return vm
end

return Controller
