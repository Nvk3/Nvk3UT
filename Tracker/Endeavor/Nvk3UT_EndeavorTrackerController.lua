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

local function getSavedVars()
    local root = getRoot()
    if type(root) ~= "table" then
        return nil
    end

    return rawget(root, "sv")
end

local function getConfig()
    local saved = getSavedVars()
    if type(saved) ~= "table" then
        return {}
    end

    local config = saved.Endeavor
    if type(config) ~= "table" then
        return {}
    end

    return config
end

local function resolveEnabled(config)
    if type(config) == "table" and config.Enabled ~= nil then
        return config.Enabled ~= false
    end

    local saved = getSavedVars()
    local achievement = saved and saved.AchievementTracker
    if type(achievement) == "table" and achievement.active ~= nil then
        return achievement.active ~= false
    end

    return true
end

local function resolveShowCounts(config)
    if type(config) == "table" and config.ShowCountsInHeaders ~= nil then
        return config.ShowCountsInHeaders ~= false
    end

    local saved = getSavedVars()
    local general = saved and saved.General
    if type(general) == "table" and general.showAchievementCategoryCounts ~= nil then
        return general.showAchievementCategoryCounts ~= false
    end

    return true
end

local function resolveCompletedHandling(config)
    if type(config) == "table" and config.CompletedHandling == "recolor" then
        return "recolor"
    end
    return "hide"
end

local DEFAULT_COLOR_CATEGORY = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 }
local DEFAULT_COLOR_ENTRY = { r = 1, g = 1, b = 0, a = 1 }
local DEFAULT_COLOR_ACTIVE = { r = 1, g = 1, b = 1, a = 1 }
local DEFAULT_COLOR_COMPLETED = { r = 0.6, g = 0.6, b = 0.6, a = 1 }
local DEFAULT_COLOR_OBJECTIVE = DEFAULT_COLOR_CATEGORY

local DEFAULT_FONT_FACE = "$(BOLD_FONT)"
local DEFAULT_FONT_OUTLINE = "soft-shadow-thick"
local DEFAULT_FONT_SIZE = 16

local function normalizeColorComponent(value, fallback)
    local numeric = tonumber(value)
    if numeric == nil then
        numeric = fallback or 1
    end

    if numeric ~= numeric then
        numeric = fallback or 1
    end

    if numeric < 0 then
        numeric = 0
    elseif numeric > 1 then
        numeric = 1
    end

    return numeric
end

local function copyColor(source, fallback)
    local default = fallback or DEFAULT_COLOR_ACTIVE
    local r = normalizeColorComponent(source and (source.r or source[1]), default.r or default[1] or 1)
    local g = normalizeColorComponent(source and (source.g or source[2]), default.g or default[2] or 1)
    local b = normalizeColorComponent(source and (source.b or source[3]), default.b or default[3] or 1)
    local a = normalizeColorComponent(source and (source.a or source[4]), default.a or default[4] or 1)

    return { r = r, g = g, b = b, a = a }
end

local function buildColors(config)
    local colorsConfig = type(config) == "table" and config.Colors or nil
    return {
        categoryTitle = copyColor(colorsConfig and colorsConfig.CategoryTitle, DEFAULT_COLOR_CATEGORY),
        entryTitle = copyColor(colorsConfig and colorsConfig.EntryName, DEFAULT_COLOR_ENTRY),
        objectiveText = copyColor(colorsConfig and colorsConfig.Objective, DEFAULT_COLOR_OBJECTIVE),
        activeTitle = copyColor(colorsConfig and colorsConfig.Active, DEFAULT_COLOR_ACTIVE),
        completed = copyColor(colorsConfig and colorsConfig.Completed, DEFAULT_COLOR_COMPLETED),
    }
end

local function clampFontSize(value)
    local numeric = tonumber(value)
    if numeric == nil then
        numeric = DEFAULT_FONT_SIZE
    end
    numeric = math.floor(numeric + 0.5)
    if numeric < 12 then
        numeric = 12
    elseif numeric > 36 then
        numeric = 36
    end
    return numeric
end

local function buildFontStrings(fontConfig)
    local config = type(fontConfig) == "table" and fontConfig or {}
    local face = config.Family
    if type(face) ~= "string" or face == "" then
        face = DEFAULT_FONT_FACE
    end

    local baseSize = clampFontSize(config.Size)
    local outline = config.Outline
    if type(outline) ~= "string" or outline == "" then
        outline = DEFAULT_FONT_OUTLINE
    end

    local objectiveSize = math.max(baseSize - 2, 12)
    local categorySize = math.min(baseSize + 4, 48)

    local function fontString(size)
        return string.format("%s|%d|%s", face, size, outline)
    end

    local fonts = {
        category = fontString(categorySize),
        section = fontString(baseSize),
        objective = fontString(objectiveSize),
        family = face,
        outline = outline,
        baseSize = baseSize,
        categorySize = categorySize,
        objectiveSize = objectiveSize,
    }

    fonts.rowHeight = math.max(objectiveSize + 6, 20)

    return fonts
end

local function buildRowsOptions(colors, fonts, completedHandling)
    return {
        font = fonts.objective,
        rowHeight = fonts.rowHeight,
        colors = colors,
        colorKind = "endeavorTracker",
        defaultRole = "objectiveText",
        completedRole = "completed",
        completedHandling = completedHandling,
    }
end

local function isDebugEnabled()
    local utils = (Nvk3UT and Nvk3UT.Utils) or Nvk3UT_Utils
    if utils and type(utils.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(utils.IsDebugEnabled)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local diagnostics = (Nvk3UT and Nvk3UT.Diagnostics) or Nvk3UT_Diagnostics
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return diagnostics:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local root = getRoot()
    if type(root) == "table" and type(root.IsDebugEnabled) == "function" then
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

-- local debug logger
local function DBG(fmt, ...)
    if not isDebugEnabled() then
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

    local config = getConfig()
    local enabled = resolveEnabled(config)
    local showCounts = resolveShowCounts(config)
    local completedHandling = resolveCompletedHandling(config)
    local DAILY_LIMIT = 3
    local WEEKLY_LIMIT = 1

    local colors = buildColors(config)
    local fonts = buildFontStrings(config and config.Font)
    local rowsOptions = buildRowsOptions(colors, fonts, completedHandling)

    if not enabled then
        local stateModule = getStateModule()
        return {
            category = {
                title = "Bestrebungen",
                expanded = isStateExpanded(stateModule),
                remaining = 0,
            },
            daily = {
                title = "Tägliche Bestrebungen",
                completed = 0,
                total = 0,
                displayCompleted = 0,
                displayLimit = DAILY_LIMIT,
                expanded = isCategoryExpanded(stateModule, "daily"),
                objectives = {},
            },
            weekly = {
                title = "Wöchentliche Bestrebungen",
                completed = 0,
                total = 0,
                displayCompleted = 0,
                displayLimit = WEEKLY_LIMIT,
                expanded = isCategoryExpanded(stateModule, "weekly"),
                objectives = {},
            },
            items = {},
            count = 0,
            settings = {
                enabled = false,
                showCounts = showCounts,
                completedHandling = completedHandling,
                colors = colors,
                fonts = fonts,
                rowsOptions = rowsOptions,
            },
        }
    end

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

    local includeCompleted = completedHandling == "recolor"

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

                if includeCompleted or objective.completed ~= true then
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
            kind = "endeavorCategoryHeader",
            title = "Bestrebungen",
            expanded = isStateExpanded(stateModule),
            remaining = remainingTotal,
        },
        daily = {
            kind = "dailyHeader",
            title = "Tägliche Bestrebungen",
            completed = dailyCompleted,
            total = dailyTotal,
            displayCompleted = dailyDisplayCompleted,
            displayLimit = dailyDisplayLimit,
            expanded = isCategoryExpanded(stateModule, "daily"),
            objectives = dailyObjectives,
        },
        weekly = {
            kind = "weeklyHeader",
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

    vm.settings = {
        enabled = true,
        showCounts = showCounts,
        completedHandling = completedHandling,
        colors = colors,
        fonts = fonts,
        rowsOptions = rowsOptions,
    }

    return vm
end

return Controller
