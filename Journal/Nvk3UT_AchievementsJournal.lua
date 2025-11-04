Nvk3UT = Nvk3UT or {}

Nvk3UT.Journal = Nvk3UT.Journal or {}
local JournalApi = Nvk3UT.Journal

local Journal = {}
Nvk3UT.AchievementsJournal = Journal

local Diagnostics = Nvk3UT and Nvk3UT.Diagnostics

local Utils = Nvk3UT and Nvk3UT.Utils

local FavoritesCategory = Nvk3UT and Nvk3UT.FavoritesCategory
local CompletedSummary = Nvk3UT and Nvk3UT.CompletedSummary
local CompletedCategory = Nvk3UT and Nvk3UT.CompletedCategory
local RecentSummary = Nvk3UT and Nvk3UT.RecentSummary
local RecentCategory = Nvk3UT and Nvk3UT.RecentCategory
local TodoSummary = Nvk3UT and Nvk3UT.TodoSummary
local TodoCategory = Nvk3UT and Nvk3UT.TodoCategory

local state = {
    parent = nil,
    favorites = nil,
    completedSummary = nil,
    completed = nil,
    recentSummary = nil,
    recent = nil,
    todoSummary = nil,
    todo = nil,
}

local function logShim(action)
    if Diagnostics and Diagnostics.Debug then
        Diagnostics.Debug("Journal SHIM -> %s", tostring(action))
    end
end

local function safeCall(func, ...)
    local SafeCall = Nvk3UT and Nvk3UT.SafeCall
    if type(SafeCall) == "function" then
        return SafeCall(func, ...)
    end

    if type(func) ~= "function" then
        return nil
    end

    local ok, result = pcall(func, ...)
    if ok then
        return result
    end
end

local function isDebugEnabled()
    return Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug and Utils and Utils.d
end

local FAVORITES_CATEGORY_ID = "Nvk3UT_Favorites"
local REFRESH_DEBOUNCE_MS = 80

local favoritesRefreshState = {
    pending = false,
    callId = nil,
    lastContext = nil,
}

local function cloneTable(source)
    if type(source) ~= "table" then
        return nil
    end

    local target = {}
    for key, value in pairs(source) do
        target[key] = value
    end
    return target
end

local function normalizeFavoritesContext(context)
    if context == nil then
        return nil
    end

    if type(context) == "table" then
        local payload = cloneTable(context) or {}
        if type(payload.changedIds) == "table" then
            local copy = {}
            for index = 1, #payload.changedIds do
                copy[index] = payload.changedIds[index]
            end
            payload.changedIds = copy
        end
        return payload
    end

    return { reason = context }
end

local function mergeChangedIds(target, source)
    if type(source) ~= "table" then
        return
    end

    target.changedIds = target.changedIds or {}
    local lookup = {}

    for index = 1, #target.changedIds do
        lookup[target.changedIds[index]] = true
    end

    for index = 1, #source do
        local entry = source[index]
        if (type(entry) == "number" or type(entry) == "string") and not lookup[entry] then
            target.changedIds[#target.changedIds + 1] = entry
            lookup[entry] = true
        end
    end
end

local function mergeFavoritesContext(existing, incoming)
    if not incoming then
        return existing
    end

    if not existing then
        return normalizeFavoritesContext(incoming)
    end

    local normalizedIncoming = normalizeFavoritesContext(incoming)
    if not normalizedIncoming then
        return existing
    end

    if normalizedIncoming.reason ~= nil then
        existing.reason = normalizedIncoming.reason
    end

    if normalizedIncoming.changedIds then
        mergeChangedIds(existing, normalizedIncoming.changedIds)
    end

    if normalizedIncoming.reason == nil and existing.reason == nil then
        existing.reason = "aggregated"
    end

    return existing
end

local function debugFavoritesRefresh(fmt, ...)
    if not isDebugEnabled() then
        return
    end

    local ok, message = pcall(string.format, fmt, ...)
    message = ok and message or tostring(fmt)

    if Diagnostics and Diagnostics.Debug then
        Diagnostics.Debug("Journal Favorites -> %s", message)
    elseif Utils and Utils.d then
        Utils.d(string.format("[Ach][Journal] %s", message))
    end
end

local function isJournalSceneVisible()
    if not (SCENE_MANAGER and type(SCENE_MANAGER.IsShowing) == "function") then
        return false
    end

    if not SCENE_MANAGER:IsShowing("achievements") then
        return false
    end

    local achievements = ACHIEVEMENTS
    if not achievements then
        return false
    end

    if type(achievements.IsHidden) == "function" and achievements:IsHidden() then
        return false
    end

    local control = achievements.control
    if control and type(control.IsHidden) == "function" and control:IsHidden() then
        return false
    end

    return true
end

local function getSelectedCategoryData()
    local achievements = ACHIEVEMENTS
    if not achievements then
        return nil
    end

    local tree = achievements.categoryTree
    if not (tree and type(tree.GetSelectedData) == "function") then
        return nil
    end

    local ok, data = pcall(tree.GetSelectedData, tree)
    if ok then
        return data
    end

    return nil
end

local function isFavoritesCategory(data)
    if not data then
        return false
    end

    if data.categoryIndex == FAVORITES_CATEGORY_ID or data.isNvkFavorites then
        return true
    end

    local nested = data.categoryData or data.data
    if nested then
        if nested.categoryIndex == FAVORITES_CATEGORY_ID or nested.isNvkFavorites then
            return true
        end
    end

    return false
end

local function isFavoritesViewVisible()
    if not isJournalSceneVisible() then
        return false
    end

    return isFavoritesCategory(getSelectedCategoryData())
end

local function scheduleFavoritesDebounce()
    if type(zo_callLater) ~= "function" then
        JournalApi:FlushPendingFavoritesRefresh("immediate")
        return
    end

    if favoritesRefreshState.callId then
        return
    end

    favoritesRefreshState.callId = zo_callLater(function()
        favoritesRefreshState.callId = nil
        JournalApi:FlushPendingFavoritesRefresh("debounce")
    end, REFRESH_DEBOUNCE_MS)
end

function JournalApi:ForceBasegameAchievementsFullUpdate()
    local achievements = ACHIEVEMENTS
    if not achievements then
        return false
    end

    local refreshGroups = achievements.refreshGroups
    if refreshGroups and type(refreshGroups.RefreshAll) == "function" then
        local ok = pcall(refreshGroups.RefreshAll, refreshGroups, "FullUpdate")
        if ok then
            return true
        end
    end

    if type(achievements.RefreshVisibleCategories) == "function" then
        local ok = pcall(achievements.RefreshVisibleCategories, achievements)
        if ok then
            return true
        end
    end

    local categoryTree = achievements.categoryTree
    if categoryTree and type(categoryTree.GetSelectedNode) == "function" and type(achievements.OnCategorySelected) == "function" then
        local okNode, selectedNode = pcall(categoryTree.GetSelectedNode, categoryTree)
        if okNode and selectedNode then
            local ok = pcall(achievements.OnCategorySelected, achievements, categoryTree, selectedNode)
            if ok then
                return true
            end
        end
    end

    return false
end

function JournalApi:RefreshFavoritesIfVisible(context)
    if not isFavoritesViewVisible() then
        return false
    end

    if favoritesRefreshState.pending then
        favoritesRefreshState.lastContext = mergeFavoritesContext(favoritesRefreshState.lastContext, context)
        return true
    end

    favoritesRefreshState.pending = true
    favoritesRefreshState.lastContext = normalizeFavoritesContext(context)

    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if runtime and type(runtime.QueueDirty) == "function" then
        pcall(runtime.QueueDirty, runtime, "achievement")
    end

    scheduleFavoritesDebounce()
    return true
end

function JournalApi:FlushPendingFavoritesRefresh(context)
    favoritesRefreshState.callId = nil

    if not favoritesRefreshState.pending then
        favoritesRefreshState.lastContext = nil
        return false
    end

    if not isFavoritesViewVisible() then
        favoritesRefreshState.pending = false
        favoritesRefreshState.lastContext = nil
        return false
    end

    favoritesRefreshState.pending = false
    local reasonContext = mergeFavoritesContext(normalizeFavoritesContext(context), favoritesRefreshState.lastContext)
    favoritesRefreshState.lastContext = nil

    local ok = self:ForceBasegameAchievementsFullUpdate()

    local reasonLabel = nil
    if type(reasonContext) == "table" and reasonContext.reason ~= nil then
        reasonLabel = tostring(reasonContext.reason)
    else
        reasonLabel = tostring(reasonContext or "runtime")
    end

    local changedCount = 0
    if type(reasonContext) == "table" and type(reasonContext.changedIds) == "table" then
        changedCount = #reasonContext.changedIds
    end

    debugFavoritesRefresh("Favorites refresh executed (context=%s, changed=%d, basegame=%s)", reasonLabel, changedCount, ok and "ok" or "fail")
    return ok
end

local function buildCriteriaSnapshot(achievementId)
    if type(GetAchievementNumCriteria) ~= "function" or type(GetAchievementCriterion) ~= "function" then
        return nil
    end

    local okCount, total = pcall(GetAchievementNumCriteria, achievementId)
    if not okCount or type(total) ~= "number" or total < 0 then
        return nil
    end

    if total == 0 then
        return { total = 0, completed = 0, allComplete = false }
    end

    local completed = 0
    for index = 1, total do
        local okCrit, _, numCompleted, numRequired = pcall(GetAchievementCriterion, achievementId, index)
        if okCrit then
            local completedValue = tonumber(numCompleted) or 0
            local requiredValue = tonumber(numRequired) or 0
            local achieved
            if requiredValue > 0 then
                achieved = completedValue >= requiredValue
            else
                achieved = completedValue > 0
            end
            if achieved then
                completed = completed + 1
            end
        else
            return { total = total, completed = completed, allComplete = false }
        end
    end

    return {
        total = total,
        completed = completed,
        allComplete = (completed >= total and total > 0),
    }
end

local function ensureCompletionFromInfo(achievementId)
    if type(GetAchievementInfo) ~= "function" then
        return false
    end
    local okInfo, _, _, _, completed = pcall(GetAchievementInfo, achievementId)
    if not okInfo then
        return false
    end
    return completed == true
end

---Initialize the journal view host reference.
---@param parentOrSceneFragment any
function Journal:Init(parentOrSceneFragment)
    state.parent = parentOrSceneFragment
    if FavoritesCategory and type(FavoritesCategory.Init) == "function" then
        local ok, result = pcall(FavoritesCategory.Init, FavoritesCategory, parentOrSceneFragment)
        if ok then
            state.favorites = result or parentOrSceneFragment
        else
            state.favorites = parentOrSceneFragment
        end
    end
    if CompletedSummary and type(CompletedSummary.Init) == "function" then
        local ok, result = pcall(CompletedSummary.Init, CompletedSummary, parentOrSceneFragment)
        if ok then
            state.completedSummary = result or parentOrSceneFragment
        else
            state.completedSummary = parentOrSceneFragment
        end
    end
    if CompletedCategory and type(CompletedCategory.Init) == "function" then
        local ok, result = pcall(CompletedCategory.Init, CompletedCategory, parentOrSceneFragment)
        if ok then
            state.completed = result or parentOrSceneFragment
        else
            state.completed = parentOrSceneFragment
        end
    end
    if RecentSummary and type(RecentSummary.Init) == "function" then
        local ok, result = pcall(RecentSummary.Init, RecentSummary, parentOrSceneFragment)
        if ok then
            state.recentSummary = result or parentOrSceneFragment
        else
            state.recentSummary = parentOrSceneFragment
        end
    end
    if RecentCategory and type(RecentCategory.Init) == "function" then
        local ok, result = pcall(RecentCategory.Init, RecentCategory, parentOrSceneFragment)
        if ok then
            state.recent = result or parentOrSceneFragment
        else
            state.recent = parentOrSceneFragment
        end
    end
    if TodoSummary and type(TodoSummary.Init) == "function" then
        local ok, result = pcall(TodoSummary.Init, TodoSummary, parentOrSceneFragment)
        if ok then
            state.todoSummary = result or parentOrSceneFragment
        else
            state.todoSummary = parentOrSceneFragment
        end
    end
    if TodoCategory and type(TodoCategory.Init) == "function" then
        local ok, result = pcall(TodoCategory.Init, TodoCategory, parentOrSceneFragment)
        if ok then
            state.todo = result or parentOrSceneFragment
        else
            state.todo = parentOrSceneFragment
        end
    end
    return state.favorites
        or state.completedSummary
        or state.completed
        or state.recentSummary
        or state.recent
        or state.todoSummary
        or state.todo
        or parentOrSceneFragment
end

---Refresh the journal view.
---@return any
function Journal:Refresh()
    if FavoritesCategory and type(FavoritesCategory.Refresh) == "function" then
        local ok = pcall(FavoritesCategory.Refresh, FavoritesCategory)
        if not ok and Utils and Utils.d and isDebugEnabled() then
            Utils.d("[Ach][Journal] FavoritesCategory.Refresh failed")
        end
    end
    if CompletedSummary and type(CompletedSummary.Refresh) == "function" then
        local ok = pcall(CompletedSummary.Refresh, CompletedSummary)
        if not ok and Utils and Utils.d and isDebugEnabled() then
            Utils.d("[Ach][Journal] CompletedSummary.Refresh failed")
        end
    end
    if CompletedCategory and type(CompletedCategory.Refresh) == "function" then
        local ok = pcall(CompletedCategory.Refresh, CompletedCategory)
        if not ok and Utils and Utils.d and isDebugEnabled() then
            Utils.d("[Ach][Journal] CompletedCategory.Refresh failed")
        end
    end
    if RecentSummary and type(RecentSummary.Refresh) == "function" then
        local ok = pcall(RecentSummary.Refresh, RecentSummary)
        if not ok and Utils and Utils.d and isDebugEnabled() then
            Utils.d("[Ach][Journal] RecentSummary.Refresh failed")
        end
    end
    if RecentCategory and type(RecentCategory.Refresh) == "function" then
        local ok = pcall(RecentCategory.Refresh, RecentCategory)
        if not ok and Utils and Utils.d and isDebugEnabled() then
            Utils.d("[Ach][Journal] RecentCategory.Refresh failed")
        end
    end
    if TodoSummary and type(TodoSummary.Refresh) == "function" then
        local ok = pcall(TodoSummary.Refresh, TodoSummary)
        if not ok and Utils and Utils.d and isDebugEnabled() then
            Utils.d("[Ach][Journal] TodoSummary.Refresh failed")
        end
    end
    if TodoCategory and type(TodoCategory.Refresh) == "function" then
        local ok = pcall(TodoCategory.Refresh, TodoCategory)
        if not ok and Utils and Utils.d and isDebugEnabled() then
            Utils.d("[Ach][Journal] TodoCategory.Refresh failed")
        end
    end
    return state.parent
end

---Determine whether an achievement is fully complete, including multi-stage chains.
---@param achievementId number
---@return boolean
function Journal.IsComplete(achievementId)
    if type(achievementId) ~= "number" then
        return false
    end

    local helper = _G.Nvk3UT_MultiStage
    local helperResult
    if helper and type(helper.IsMultiStageComplete) == "function" then
        local okHelper, result = pcall(helper.IsMultiStageComplete, achievementId, false)
        if okHelper then
            helperResult = result
        end
    end

    local snapshot = buildCriteriaSnapshot(achievementId)
    local resolved

    if type(helperResult) == "boolean" then
        resolved = helperResult
    elseif helper and type(helper.GetMultiStageProgress) == "function" then
        local okProgress, progress = pcall(helper.GetMultiStageProgress, achievementId)
        if okProgress and type(progress) == "table" then
            local total = tonumber(progress.total) or tonumber(progress.totalStages)
            local done = tonumber(progress.completed) or tonumber(progress.completedStages)
            if total and done and total > 0 then
                snapshot = snapshot or { total = total, completed = done }
                snapshot.total = total
                snapshot.completed = done
                snapshot.allComplete = done >= total
                resolved = snapshot.allComplete
            end
        end
    end

    if resolved == nil then
        if snapshot and snapshot.total > 0 then
            resolved = snapshot.allComplete == true
        else
            resolved = ensureCompletionFromInfo(achievementId)
        end
    end

    if snapshot and snapshot.total == 0 then
        snapshot.completed = resolved and 1 or 0
    end

    if isDebugEnabled() then
        local total = snapshot and snapshot.total or 0
        local completed = snapshot and snapshot.completed or (resolved and total) or 0
        Utils.d(string.format("[Ach] %d complete=%s (stages %d/%d)", achievementId, tostring(resolved == true), completed, total))
    end

    return resolved == true
end

local Shim = {}
Nvk3UT.Achievements = Shim

function Shim.Init(...)
    logShim("Init")
    if type(Journal.Init) ~= "function" then
        return nil
    end
    return safeCall(Journal.Init, Journal, ...)
end

function Shim.Refresh(...)
    logShim("Refresh")
    if type(Journal.Refresh) ~= "function" then
        return nil
    end
    return safeCall(Journal.Refresh, Journal, ...)
end

function Shim.IsComplete(...)
    if type(Journal.IsComplete) ~= "function" then
        return false
    end
    return safeCall(Journal.IsComplete, ...)
end

return Journal
