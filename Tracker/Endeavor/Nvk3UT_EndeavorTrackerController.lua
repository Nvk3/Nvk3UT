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

local function isGlobalDebugEnabled()
    local diagnostics = Nvk3UT_Diagnostics
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(diagnostics.IsDebugEnabled, diagnostics)
        if ok then
            return enabled == true
        end
    end

    local root = getRoot()
    if type(root) == "table" and type(root.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(root.IsDebugEnabled, root)
        if ok then
            return enabled == true
        end
    end

    return false
end

-- local debug logger
local function DBG(fmt, ...)
    if not isGlobalDebugEnabled() then
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


local function getTrackerOptions()
    local root = getRoot()
    if type(root) ~= "table" then
        return {}
    end

    local tracker = rawget(root, "EndeavorTracker")
    if type(tracker) == "table" then
        local getter = tracker.GetOptions or tracker.GetSettings
        if type(getter) == "function" then
            local ok, options = pcall(getter, tracker)
            if ok and type(options) == "table" then
                return options
            end
        end
    end

    local sv = rawget(root, "sv")
    if type(sv) == "table" then
        local options = sv.Endeavor
        if type(options) == "table" then
            return options
        end
    end

    return {}
end

local function normalizeCompletedHandling(value)
    if value == "recolor" then
        return "recolor"
    end
    return "hide"
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
    local dailyDisplayCompleted = 0
    local dailyDisplayLimit = 0
    local weeklyDisplayCompleted = 0
    local weeklyDisplayLimit = 0

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

    local trackerOptions = getTrackerOptions()
    local completedHandling = normalizeCompletedHandling(
        trackerOptions.completedHandling or trackerOptions.CompletedHandling
    )
    local hideCompleted = completedHandling ~= "recolor"

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

    local DAILY_LIMIT = 3
    local WEEKLY_LIMIT = 1

    dailyDisplayLimit = DAILY_LIMIT
    weeklyDisplayLimit = WEEKLY_LIMIT

    local dailyCompletedValue = clampNonNegative(dailyCompleted, 0)
    local weeklyCompletedValue = clampNonNegative(weeklyCompleted, 0)

    local dailyDoneCapped = math.min(dailyCompletedValue, DAILY_LIMIT)
    local weeklyDoneCapped = math.min(weeklyCompletedValue, WEEKLY_LIMIT)

    dailyDisplayCompleted = dailyDoneCapped
    weeklyDisplayCompleted = weeklyDoneCapped

    local function mapObjective(item)
        if type(item) ~= "table" then
            return nil, nil
        end

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

        local aggregated = {
            name = tostring(item.name or ""),
            description = tostring(item.description or ""),
            progress = progressValue,
            maxProgress = maxValue,
            type = nil,
            remainingSeconds = objective.remainingSeconds,
            completed = completed,
        }

        return objective, aggregated
    end

    local function buildObjectives(bucket, target, kind)
        if type(bucket) ~= "table" or type(target) ~= "table" then
            return
        end

        local list = bucket.items
        if type(list) ~= "table" then
            return
        end

        for _, item in ipairs(list) do
            local objective, aggregated = mapObjective(item)
            if objective then
                if aggregated then
                    aggregated.type = kind
                    aggregatedItems[#aggregatedItems + 1] = aggregated
                end

                if objective.completed ~= true or not hideCompleted then
                    target[#target + 1] = objective
                end
            end
        end
    end

    buildObjectives(dailyBucket, dailyObjectives, "daily")
    buildObjectives(weeklyBucket, weeklyObjectives, "weekly")

    local remainingDaily = math.max(0, DAILY_LIMIT - dailyDoneCapped)
    local remainingWeekly = math.max(0, WEEKLY_LIMIT - weeklyDoneCapped)
    local remainingTotal = remainingDaily + remainingWeekly

    local stateModule = getStateModule()
    local vm = {
        category = {
            title = "Bestrebungen",
            expanded = isStateExpanded(stateModule),
            remaining = remainingTotal,
        },
        daily = {
            title = "Tägliche Bestrebungen",
            completed = dailyCompleted,
            total = dailyTotal,
            displayCompleted = dailyDisplayCompleted,
            displayLimit = dailyDisplayLimit,
            expanded = isCategoryExpanded(stateModule, "daily"),
            objectives = dailyObjectives,
        },
        weekly = {
            title = "Wöchentliche Bestrebungen",
            completed = weeklyCompleted,
            total = weeklyTotal,
            displayCompleted = weeklyDisplayCompleted,
            displayLimit = weeklyDisplayLimit,
            expanded = isCategoryExpanded(stateModule, "weekly"),
            objectives = weeklyObjectives,
        },
        items = aggregatedItems,
        count = #aggregatedItems,
        completedHandling = completedHandling,
    }

    DBG(
        "[EndeavorVM] remaining=%d daily=%d/%d weekly=%d/%d objsD=%d objsW=%d",
        remainingTotal,
        dailyDisplayCompleted,
        dailyDisplayLimit,
        weeklyDisplayCompleted,
        weeklyDisplayLimit,
        #dailyObjectives,
        #weeklyObjectives
    )

    return vm
end

Controller._dirtyReasons = Controller._dirtyReasons or {}

function Controller.MarkDirty(_, reason)
    Controller._dirtyReasons[reason or "general"] = true
    return true
end

return Controller
