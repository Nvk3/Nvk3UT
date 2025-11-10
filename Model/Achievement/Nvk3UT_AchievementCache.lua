Nvk3UT = Nvk3UT or {}

local AchievementCache = {}
Nvk3UT.AchievementCache = AchievementCache

local RULES_VERSION = 1
local PREBUILD_DELAY_MS = 1500
local DEFAULT_CHUNK_DELAY_MS = 25
local CATEGORY_SEQUENCE = { "Favorites", "Recent", "Completed", "ToDo" }

local sessionState = {
    sessionBuilt = false,
    isBuilding = false,
    dirty = {
        Favorites = false,
        Recent = false,
        Completed = false,
        ToDo = false,
    },
    prebuildScheduled = false,
    prebuildHandle = nil,
    pendingTasks = 0,
    partialScheduled = false,
}

local function logDebug(fmt, ...)
    if Nvk3UT and Nvk3UT.Debug then
        Nvk3UT.Debug("AchievementCache: " .. tostring(fmt), ...)
    end
end

local function getSavedRoot()
    local addon = Nvk3UT
    local sv = addon and addon.sv
    return sv and sv.AchievementCache
end

local function getCategoriesNode()
    local root = getSavedRoot()
    return root and root.categories
end

local function now()
    if GetTimeStamp then
        return GetTimeStamp()
    end
    return os.time()
end

local function scheduleCallback(delayMs, callback)
    if type(callback) ~= "function" then
        return nil
    end

    local delay = tonumber(delayMs) or 0
    if delay < 0 then
        delay = 0
    end

    if type(zo_callLater) == "function" then
        return zo_callLater(callback, delay)
    end

    local name = "Nvk3UT_AchievementCache_" .. tostring(math.random(1, 1e6))
    EVENT_MANAGER:RegisterForUpdate(name, delay, function()
        EVENT_MANAGER:UnregisterForUpdate(name)
        callback()
    end)
    return name
end

local function safeCall(func, ...)
    if type(func) ~= "function" then
        return nil
    end
    local ok, result = pcall(func, ...)
    if ok then
        return result
    end
    return nil
end

local function safeCallMulti(func, ...)
    if type(func) ~= "function" then
        return nil
    end
    local results = { pcall(func, ...) }
    if not results[1] then
        return nil
    end
    table.remove(results, 1)
    return table.unpack(results)
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local result = {}
    for key, val in pairs(value) do
        result[key] = deepCopy(val)
    end
    return result
end

local function normalizeCategoryKey(category)
    if type(category) ~= "string" then
        return nil
    end

    local lowered = category:lower()
    if lowered == "favorites" then
        return "Favorites"
    elseif lowered == "recent" then
        return "Recent"
    elseif lowered == "completed" then
        return "Completed"
    elseif lowered == "todo" or lowered == "to-do" or lowered == "to do" or lowered == "todo" then
        return "ToDo"
    end

    return nil
end

local function resetDirtyFlags(categories)
    local dirty = sessionState.dirty
    if type(categories) == "table" then
        for index = 1, #categories do
            local normalized = normalizeCategoryKey(categories[index])
            if normalized and dirty[normalized] ~= nil then
                dirty[normalized] = false
            end
        end
        return
    end

    for key in pairs(dirty) do
        dirty[key] = false
    end
end

function AchievementCache.ComputeBuildHash()
    local parts = {}
    local addon = Nvk3UT
    if addon then
        if type(addon.GetVersion) == "function" then
            parts[#parts + 1] = tostring(addon:GetVersion())
        elseif addon.addonVersion then
            parts[#parts + 1] = tostring(addon.addonVersion)
        end
    end

    if GetAPIVersion then
        parts[#parts + 1] = tostring(GetAPIVersion())
    end

    if GetCVar then
        parts[#parts + 1] = tostring(GetCVar("language.2"))
    end

    parts[#parts + 1] = tostring(RULES_VERSION)

    local sv = addon and addon.sv
    local general = sv and sv.General
    if type(general) == "table" then
        parts[#parts + 1] = tostring(general.favScope or "")
        parts[#parts + 1] = tostring(general.recentWindow or "")
        parts[#parts + 1] = tostring(general.recentMax or "")
        local features = general.features or {}
        parts[#parts + 1] = features.favorites and "1" or "0"
        parts[#parts + 1] = features.recent and "1" or "0"
        parts[#parts + 1] = features.completed and "1" or "0"
        parts[#parts + 1] = features.todo and "1" or "0"
    end

    local trackerSettings = sv and sv.AchievementTracker
    if type(trackerSettings) == "table" then
        local sections = trackerSettings.sections or {}
        parts[#parts + 1] = sections.favorites and "1" or "0"
        parts[#parts + 1] = sections.recent and "1" or "0"
        parts[#parts + 1] = sections.completed and "1" or "0"
        parts[#parts + 1] = sections.todo and "1" or "0"
    end

    return table.concat(parts, "|")
end

local function notifyUiRefresh(reason)
    local rebuild = Nvk3UT and Nvk3UT.Rebuild
    if rebuild and type(rebuild.ForceAchievementRefresh) == "function" then
        safeCall(rebuild.ForceAchievementRefresh, reason)
    end

    local ui = Nvk3UT and Nvk3UT.UI
    if ui then
        if type(ui.RefreshAchievements) == "function" then
            safeCall(ui.RefreshAchievements)
        end
        if type(ui.UpdateStatus) == "function" then
            safeCall(ui.UpdateStatus)
        end
    end
end

local function applyAchievementListCache(snapshot)
    local listModule = Nvk3UT and Nvk3UT.AchievementList
    if listModule and type(listModule.ApplyCacheSnapshot) == "function" then
        safeCall(listModule.ApplyCacheSnapshot, snapshot)
    end
end

local function applyRecentCache(snapshot)
    local recentModule = Nvk3UT and Nvk3UT.RecentData
    if recentModule and type(recentModule.ApplyCacheSnapshot) == "function" then
        safeCall(recentModule.ApplyCacheSnapshot, snapshot)
    end
end

local function applyCompletedCache(snapshot)
    local completedModule = Nvk3UT and Nvk3UT.CompletedData
    if completedModule and type(completedModule.ApplyCacheSnapshot) == "function" then
        safeCall(completedModule.ApplyCacheSnapshot, snapshot)
    end
end

local function applyTodoCache(snapshot)
    local todoModule = Nvk3UT and Nvk3UT.TodoData
    if todoModule and type(todoModule.ApplyCacheSnapshot) == "function" then
        safeCall(todoModule.ApplyCacheSnapshot, snapshot)
    end
end

function AchievementCache.ApplySavedCache()
    local categories = getCategoriesNode()
    if not categories then
        return
    end

    if type(categories.Favorites) == "table" and next(categories.Favorites) ~= nil then
        applyAchievementListCache(categories.Favorites)
    end

    if type(categories.Recent) == "table" and next(categories.Recent) ~= nil then
        applyRecentCache(categories.Recent)
    end

    local completedCache = categories.Completed
    if type(completedCache) == "table" and next(completedCache) ~= nil then
        applyCompletedCache(completedCache)
    end

    local todoCache = categories.ToDo or categories.Todo
    if type(todoCache) == "table" and next(todoCache) ~= nil then
        applyTodoCache(todoCache)
    end
end

function AchievementCache.Init(savedRoot)
    local root = savedRoot or (Nvk3UT and Nvk3UT.sv)
    if type(root) ~= "table" then
        return
    end

    local cacheNode = root.AchievementCache
    if type(cacheNode) ~= "table" then
        return
    end

    -- Reset transient session flags on init.
    sessionState.sessionBuilt = false
    sessionState.isBuilding = false
    sessionState.pendingTasks = 0
    sessionState.prebuildScheduled = false
    sessionState.prebuildHandle = nil
    sessionState.partialScheduled = false
    resetDirtyFlags()

    AchievementCache.ApplySavedCache()
end

local function captureRecentSnapshot()
    local snapshot = { ids = {}, total = 0, progress = {} }
    local categories = getCategoriesNode()
    if type(categories) == "table" then
        local favorites = categories.Favorites
        if type(favorites) == "table" then
            local ids = favorites.recentIds or favorites.recent or favorites.ids
            if type(ids) == "table" then
                snapshot.ids = deepCopy(ids)
                snapshot.total = favorites.recentTotal or #snapshot.ids
            end
        end
    end

    local recentData = Nvk3UT and Nvk3UT.RecentData
    if recentData then
        if #snapshot.ids == 0 then
            local list = safeCall(recentData.ListConfigured) or safeCall(recentData.List)
            if type(list) == "table" then
                snapshot.ids = deepCopy(list)
                snapshot.total = #snapshot.ids
            end
        end

        if type(recentData.IterateProgress) == "function" then
            local iterator, state, key = safeCallMulti(recentData.IterateProgress)
            if type(iterator) == "function" then
                local progress = {}
                for storedId, ts in iterator, state, key do
                    progress[storedId] = ts
                end
                snapshot.progress = progress
            end
        end
    end

    return snapshot
end

local function buildFavoritesCategory(categoriesNode, onDone)
    local listModule = Nvk3UT and Nvk3UT.AchievementList
    local result = {
        achievements = {},
        total = 0,
        totalComplete = 0,
        totalIncomplete = 0,
        favoriteIds = {},
        recentIds = {},
        recentTotal = 0,
        todoIds = {},
        todoNames = {},
        todoKeys = {},
        todoTopIds = {},
        todoTotal = 0,
    }

    if listModule and type(listModule.RefreshFromGame) == "function" then
        local ok, raw = pcall(listModule.RefreshFromGame, listModule, "achievementCache")
        if ok and type(raw) == "table" then
            result = deepCopy(raw)
            applyAchievementListCache(result)
        else
            logDebug("Favorites build failed: %s", tostring(raw))
        end
    else
        logDebug("Favorites build skipped (list module unavailable)")
    end

    categoriesNode.Favorites = result
    onDone()
end

local function buildRecentCategory(categoriesNode, onDone)
    local snapshot = captureRecentSnapshot()
    categoriesNode.Recent = snapshot
    applyRecentCache(snapshot)
    onDone()
end

local function buildCompletedCategory(categoriesNode, onDone)
    local completedModule = Nvk3UT and Nvk3UT.CompletedData
    local snapshot = {
        names = {},
        keys = {},
        lists = {},
        counts = {},
        points = {},
        constants = {},
    }

    if completedModule then
        safeCall(completedModule.Rebuild)

        local names, keys = safeCallMulti(completedModule.GetSubcategoryList)
        if type(names) == "table" then
            snapshot.names = deepCopy(names)
        end
        if type(keys) == "table" then
            snapshot.keys = deepCopy(keys)
        end

        if type(keys) == "table" then
            for index = 1, #keys do
                local key = keys[index]
                local list = safeCall(completedModule.ListForKey, key) or {}
                snapshot.lists[key] = deepCopy(list)

                local count, points = safeCallMulti(completedModule.SummaryCountAndPointsForKey, key)
                snapshot.counts[key] = count or (type(list) == "table" and #list or 0)
                snapshot.points[key] = points or 0
            end
        end

        local constants = safeCall(completedModule.Constants)
        if type(constants) == "table" then
            snapshot.constants = deepCopy(constants)
        end

        applyCompletedCache(snapshot)
    else
        logDebug("Completed build skipped (module unavailable)")
    end

    categoriesNode.Completed = snapshot
    onDone()
end

local function buildTodoCategory(categoriesNode, onDone)
    local todoModule = Nvk3UT and Nvk3UT.TodoData
    local snapshot = {
        names = {},
        keys = {},
        topIds = {},
        lists = {},
        counts = {},
        points = {},
    }

    if todoModule then
        local names, keys, topIds = safeCallMulti(todoModule.GetSubcategoryList, false)
        if type(names) == "table" then
            snapshot.names = deepCopy(names)
        end
        if type(keys) == "table" then
            snapshot.keys = deepCopy(keys)
        end
        if type(topIds) == "table" then
            snapshot.topIds = deepCopy(topIds)
        end

        if type(topIds) == "table" then
            for index = 1, #topIds do
                local topId = topIds[index]
                local list = safeCall(todoModule.ListOpenForTop, topId, false) or {}
                snapshot.lists[topId] = deepCopy(list)
                snapshot.counts[topId] = type(list) == "table" and #list or 0
                snapshot.points[topId] = safeCall(todoModule.PointsForSubcategory, topId, false) or 0
            end
        end

        snapshot.allOpen = safeCall(todoModule.ListAllOpen, nil, false) or {}
        snapshot.allOpen = deepCopy(snapshot.allOpen)

        applyTodoCache(snapshot)
    else
        logDebug("ToDo build skipped (module unavailable)")
    end

    categoriesNode.ToDo = snapshot
    categoriesNode.Todo = snapshot
    onDone()
end

local CATEGORY_BUILDERS = {
    Favorites = buildFavoritesCategory,
    Recent = buildRecentCategory,
    Completed = buildCompletedCategory,
    ToDo = buildTodoCategory,
}

local function runCategoryQueue(categories, onComplete, opts)
    local queue = {}
    for index = 1, #categories do
        local normalized = normalizeCategoryKey(categories[index])
        if normalized and CATEGORY_BUILDERS[normalized] then
            queue[#queue + 1] = normalized
        end
    end

    if #queue == 0 then
        if onComplete then
            onComplete()
        end
        return
    end

    local categoriesNode = getCategoriesNode()
    if not categoriesNode then
        if onComplete then
            onComplete()
        end
        return
    end

    sessionState.pendingTasks = #queue

    local chunkDelay = (opts and opts.chunkDelayMs) or DEFAULT_CHUNK_DELAY_MS

    local function step()
        if #queue == 0 then
            sessionState.pendingTasks = 0
            if onComplete then
                onComplete()
            end
            return
        end

        local category = table.remove(queue, 1)
        local builder = CATEGORY_BUILDERS[category]
        if not builder then
            scheduleCallback(chunkDelay, step)
            return
        end

        logDebug("Building %s cache", category)
        builder(categoriesNode, function()
            sessionState.pendingTasks = math.max(0, sessionState.pendingTasks - 1)
            sessionState.dirty[category] = false
            scheduleCallback(chunkDelay, step)
        end)
    end

    step()
end

local function finalizeBuild(categories, opts)
    local root = getSavedRoot()
    if type(root) ~= "table" then
        return
    end

    local shouldUpdateHash = true
    if opts and opts.updateHash == false then
        shouldUpdateHash = false
    end

    if shouldUpdateHash then
        root.buildHash = AchievementCache.ComputeBuildHash()
        root.lastBuildAt = now()
    end

    AchievementCache.ApplySavedCache()
    resetDirtyFlags(categories)
    notifyUiRefresh("AchievementCacheBuild")

    if type(categories) == "table" then
        logDebug("Build complete for %d categories", #categories)
    else
        logDebug("Build complete")
    end
end

function AchievementCache.FullBuild(categories, onComplete, opts)
    if sessionState.isBuilding then
        logDebug("FullBuild skipped (already building)")
        return
    end

    local targets
    if type(categories) == "table" and #categories > 0 then
        targets = categories
    else
        targets = CATEGORY_SEQUENCE
    end

    sessionState.isBuilding = true

    runCategoryQueue(targets, function()
        sessionState.isBuilding = false
        finalizeBuild(targets, opts)
        sessionState.sessionBuilt = true
        if onComplete then
            onComplete(true)
        end
    end, opts)
end

function AchievementCache.PartialBuild(category, onComplete)
    local normalized = normalizeCategoryKey(category)
    if not normalized then
        if onComplete then
            onComplete(false)
        end
        return
    end

    AchievementCache.FullBuild({ normalized }, function()
        if onComplete then
            onComplete(true)
        end
    end, { updateHash = false })
end

function AchievementCache.MarkDirty(category)
    if category == nil then
        return
    end

    if type(category) == "table" then
        for index = 1, #category do
            AchievementCache.MarkDirty(category[index])
        end
        return
    end

    local normalized = normalizeCategoryKey(category)
    if not normalized then
        return
    end

    local dirty = sessionState.dirty
    if dirty[normalized] == false then
        logDebug("Marked %s cache dirty", normalized)
    end
    dirty[normalized] = true

    if sessionState.sessionBuilt and not sessionState.isBuilding and not sessionState.partialScheduled then
        sessionState.partialScheduled = true
        scheduleCallback(PREBUILD_DELAY_MS / 3, function()
            sessionState.partialScheduled = false
            AchievementCache.ProcessDirty()
        end)
    end
end

function AchievementCache.ProcessDirty()
    if sessionState.isBuilding then
        return
    end

    local categories = {}
    for key, flagged in pairs(sessionState.dirty) do
        if flagged then
            categories[#categories + 1] = key
        end
    end

    if #categories == 0 then
        return
    end

    AchievementCache.FullBuild(categories, nil, { updateHash = false })
end

function AchievementCache.HasDirty()
    for _, flagged in pairs(sessionState.dirty) do
        if flagged then
            return true
        end
    end
    return false
end

function AchievementCache.IsBuilding()
    return sessionState.isBuilding == true
end

function AchievementCache.SchedulePrebuild(delayMs)
    if sessionState.sessionBuilt or sessionState.isBuilding then
        return
    end

    if sessionState.prebuildScheduled then
        return
    end

    local delay = tonumber(delayMs) or PREBUILD_DELAY_MS
    sessionState.prebuildScheduled = true
    sessionState.prebuildHandle = scheduleCallback(delay, function()
        sessionState.prebuildScheduled = false
        sessionState.prebuildHandle = nil
        AchievementCache.StartPrebuild()
    end)

    logDebug("Prebuild scheduled in %dms", delay)
end

function AchievementCache.StartPrebuild()
    if sessionState.sessionBuilt or sessionState.isBuilding then
        return
    end

    local root = getSavedRoot()
    if type(root) ~= "table" then
        return
    end

    local currentHash = AchievementCache.ComputeBuildHash()
    local cachedHash = root.buildHash

    if type(root.categories) ~= "table" then
        root.categories = {}
    end

    if cachedHash == currentHash and next(root.categories) ~= nil then
        logDebug("Prebuild skipped (hash unchanged)")
        sessionState.sessionBuilt = true
        AchievementCache.ApplySavedCache()
        resetDirtyFlags()
        return
    end

    logDebug("Prebuild starting (hash mismatch)")
    AchievementCache.FullBuild(nil, nil, { updateHash = true })
end

function AchievementCache.IsSessionBuilt()
    return sessionState.sessionBuilt == true
end

function AchievementCache.OnAchievementAwarded(achievementId)
    AchievementCache.MarkDirty({ "Recent", "Completed", "ToDo" })
end

function AchievementCache.OnFavoritesChanged()
    AchievementCache.MarkDirty("Favorites")
end

function AchievementCache.OnOptionsChanged(options)
    AchievementCache.MarkDirty({ "Favorites", "Recent", "Completed", "ToDo" })
end

AchievementCache.sessionState = sessionState
AchievementCache.RULES_VERSION = RULES_VERSION

return AchievementCache
