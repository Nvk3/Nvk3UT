Nvk3UT = Nvk3UT or {}

local FavoritesData = {}
Nvk3UT.FavoritesData = FavoritesData

local ACCOUNT_SCOPE = "account"
local CHARACTER_SCOPE = "character"

local ACCOUNT_VERSION = 1
local CHARACTER_VERSION = 1

local EMPTY_SET = {}

local function isDebugEnabled()
    local utils = (Nvk3UT and Nvk3UT.Utils) or Nvk3UT_Utils
    if utils and type(utils.IsDebugEnabled) == "function" then
        return utils:IsDebugEnabled()
    end
    local diagnostics = (Nvk3UT and Nvk3UT.Diagnostics) or Nvk3UT_Diagnostics
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        return diagnostics:IsDebugEnabled()
    end
    local root = Nvk3UT
    if root and type(root.IsDebugEnabled) == "function" then
        return root:IsDebugEnabled()
    end
    return false
end

local function emitDebugMessage(fmt, ...)
    if not isDebugEnabled() then
        return
    end

    local Utils = Nvk3UT and Nvk3UT.Utils
    local ok, message = pcall(string.format, fmt, ...)
    if not ok then
        message = tostring(fmt)
    end

    if Utils and Utils.d then
        Utils.d("[Nvk3UT][FavoritesData] %s", message)
    elseif d then
        d(string.format("[Nvk3UT][FavoritesData] %s", message))
    end
end

local function normalizeScope(scope)
    if type(scope) ~= "string" then
        return nil
    end

    local normalized = scope:lower()
    if normalized == ACCOUNT_SCOPE then
        return ACCOUNT_SCOPE
    end
    if normalized == CHARACTER_SCOPE then
        return CHARACTER_SCOPE
    end

    return nil
end

local function resolveScope(scopeOverride)
    local normalizedOverride = normalizeScope(scopeOverride)
    if normalizedOverride then
        return normalizedOverride
    end

    local general = Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.General
    local configured = general and general.favScope
    local normalizedConfigured = normalizeScope(configured)

    return normalizedConfigured or ACCOUNT_SCOPE
end

local function ensureSavedVars()
    if not Nvk3UT_Data_Favorites_Account or not Nvk3UT_Data_Favorites_Characters then
        FavoritesData.InitSavedVars()
    end
end

local function ensureSet(scope, create)
    if scope ~= ACCOUNT_SCOPE and scope ~= CHARACTER_SCOPE then
        return nil
    end

    ensureSavedVars()

    if scope == ACCOUNT_SCOPE then
        local saved = Nvk3UT_Data_Favorites_Account
        if not saved then
            if create then
                FavoritesData.InitSavedVars()
                saved = Nvk3UT_Data_Favorites_Account
            else
                return nil
            end
        end

        if type(saved.list) ~= "table" and create then
            saved.list = {}
        end

        return saved and saved.list or nil
    end

    local saved = Nvk3UT_Data_Favorites_Characters
    if not saved then
        if create then
            FavoritesData.InitSavedVars()
            saved = Nvk3UT_Data_Favorites_Characters
        else
            return nil
        end
    end

    if type(saved.list) ~= "table" and create then
        saved.list = {}
    end

    return saved and saved.list or nil
end

local function getSet(scope)
    local saved = ensureSet(scope, false)
    return saved or EMPTY_SET
end

local function isFavoritedInScope(id, scope)
    local set = ensureSet(scope, false)
    if not set then
        return false
    end

    return set[id] and true or false
end

local function buildScopeOrder(scopeOverride)
    local order = {}
    local seen = {}

    local function push(scope)
        if scope and not seen[scope] then
            seen[scope] = true
            order[#order + 1] = scope
        end
    end

    local normalizedOverride = normalizeScope(scopeOverride)
    if normalizedOverride then
        push(normalizedOverride)
        return order
    end

    push(resolveScope(nil))
    push(ACCOUNT_SCOPE)
    push(CHARACTER_SCOPE)

    return order
end

local function queueAchievementDirty()
    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if runtime and type(runtime.QueueDirty) == "function" then
        pcall(runtime.QueueDirty, runtime, "achievement")
    end
end

local function touchFavoriteTimestamp(achievementId)
    local State = Nvk3UT and Nvk3UT.AchievementState
    local touch = State and State.TouchTimestamp
    if type(touch) ~= "function" then
        return
    end

    local ok, key = pcall(string.format, "favorite:%d", achievementId)
    if not ok then
        key = "favorite:" .. tostring(achievementId)
    end

    pcall(touch, key)
end

local function removeFavoritedIdInternal(normalized, scopeOverride)
    local removedCount = 0
    local scopes = buildScopeOrder(scopeOverride)
    local stringKey = tostring(normalized)

    for index = 1, #scopes do
        local scope = scopes[index]
        local set = ensureSet(scope, false)
        if type(set) == "table" then
            if set[normalized] ~= nil then
                set[normalized] = nil
                removedCount = removedCount + 1
            end
            if stringKey and set[stringKey] ~= nil then
                set[stringKey] = nil
                removedCount = removedCount + 1
            end
        end
    end

    return removedCount
end

local function removeFavoritedIdWithTimestamp(normalized, scopeOverride)
    local removedCount = removeFavoritedIdInternal(normalized, scopeOverride)
    if removedCount > 0 then
        touchFavoriteTimestamp(normalized)
    end
    return removedCount
end

local function NotifyFavoritesChanged()
    local Model = Nvk3UT and Nvk3UT.AchievementModel
    if Model and Model.OnFavoritesChanged then
        pcall(Model.OnFavoritesChanged)
    end

    local tracker = Nvk3UT and Nvk3UT.AchievementTracker
    if tracker and tracker.RequestRefresh then
        pcall(tracker.RequestRefresh)
    end

    queueAchievementDirty()

    local cache = Nvk3UT and Nvk3UT.AchievementCache
    if cache and cache.OnFavoritesChanged then
        pcall(cache.OnFavoritesChanged)
    end
end

function FavoritesData.InitSavedVars()
    if not Nvk3UT_Data_Favorites_Account then
        Nvk3UT_Data_Favorites_Account =
            ZO_SavedVars:NewAccountWide("Nvk3UT_Data_Favorites", ACCOUNT_VERSION, "account", { list = {} })
    elseif type(Nvk3UT_Data_Favorites_Account.list) ~= "table" then
        Nvk3UT_Data_Favorites_Account.list = {}
    end

    if not Nvk3UT_Data_Favorites_Characters then
        Nvk3UT_Data_Favorites_Characters =
            ZO_SavedVars:NewCharacterIdSettings("Nvk3UT_Data_Favorites", CHARACTER_VERSION, "characters", { list = {} })
    elseif type(Nvk3UT_Data_Favorites_Characters.list) ~= "table" then
        Nvk3UT_Data_Favorites_Characters.list = {}
    end
end

function FavoritesData.NormalizeId(id)
    if id == nil then
        return nil
    end

    if type(id) == "number" then
        if id > 0 then
            return math.floor(id)
        end
        return nil
    end

    local numeric = tonumber(id)
    if numeric and numeric > 0 then
        return math.floor(numeric)
    end

    return nil
end

function FavoritesData.IsFavorited(id, scopeOverride)
    local normalized = FavoritesData.NormalizeId(id)
    if not normalized then
        return false
    end

    local scopes = buildScopeOrder(scopeOverride)
    for index = 1, #scopes do
        local scope = scopes[index]
        if isFavoritedInScope(normalized, scope) then
            return true
        end
    end

    return false
end

function FavoritesData.SetFavorited(id, shouldFavorite, source, scopeOverride)
    local normalized = FavoritesData.NormalizeId(id)
    if not normalized then
        return false
    end

    local scope = resolveScope(scopeOverride)
    local set = ensureSet(scope, true)
    if not set then
        return false
    end

    local desired = shouldFavorite and true or false
    local current = set[normalized] and true or false
    if current == desired then
        return false
    end

    if desired then
        set[normalized] = true
    else
        set[normalized] = nil
    end

    emitDebugMessage(
        "set id=%d favorited=%s scope=%s source=%s",
        normalized,
        tostring(desired),
        tostring(scope),
        tostring(source or "auto")
    )

    NotifyFavoritesChanged()

    return true
end

function FavoritesData.RemoveFavorite(id, scopeOverride)
    local normalized = FavoritesData.NormalizeId(id)
    if not normalized then
        return false
    end

    local removedCount = removeFavoritedIdWithTimestamp(normalized, scopeOverride)
    if removedCount <= 0 then
        return false
    end

    emitDebugMessage(
        "remove id=%d scope=%s removed=%d",
        normalized,
        tostring(scopeOverride or "all"),
        removedCount
    )

    NotifyFavoritesChanged()

    return true
end

function FavoritesData.ToggleFavorited(id, source, scopeOverride)
    local normalized = FavoritesData.NormalizeId(id)
    if not normalized then
        return false, false
    end

    local scope = resolveScope(scopeOverride)
    local before = isFavoritedInScope(normalized, scope)
    local changed = FavoritesData.SetFavorited(normalized, not before, source, scope)
    local after = before
    if changed then
        after = not before
    end

    return after, changed
end

function FavoritesData.GetAllFavorites(scopeOverride)
    local scope = resolveScope(scopeOverride)
    local set = getSet(scope)

    if type(set) ~= "table" then
        return next, EMPTY_SET, nil
    end

    return next, set, nil
end

function FavoritesData.Iterate(scopeOverride)
    return FavoritesData.GetAllFavorites(scopeOverride)
end

function FavoritesData.IsCompleted(achievementId)
    local normalized = FavoritesData.NormalizeId(achievementId)
    if not normalized then
        return false
    end

    local Completed = Nvk3UT and Nvk3UT.CompletedData
    if Completed and type(Completed.IsCompleted) == "function" then
        local ok, result = pcall(Completed.IsCompleted, normalized)
        if ok then
            return result == true
        end
    end

    if type(IsAchievementComplete) == "function" then
        local ok, result = pcall(IsAchievementComplete, normalized)
        if ok and result ~= nil then
            return result == true
        end
    end

    if type(GetAchievementInfo) == "function" then
        local ok, _, _, _, _, completed = pcall(GetAchievementInfo, normalized)
        if ok and completed ~= nil then
            return completed == true
        end
    end

    return false
end

function FavoritesData.RemoveIfCompleted(achievementId)
    local normalized = FavoritesData.NormalizeId(achievementId)
    if not normalized then
        return false
    end

    if not FavoritesData.IsFavorited(normalized) then
        return false
    end

    if not FavoritesData.IsCompleted(normalized) then
        return false
    end

    return FavoritesData.RemoveFavorite(normalized)
end

function FavoritesData.PruneCompletedFavorites()
    local candidates = {}
    local scopes = { ACCOUNT_SCOPE, CHARACTER_SCOPE }

    for index = 1, #scopes do
        local scope = scopes[index]
        local set = ensureSet(scope, false)
        if type(set) == "table" then
            for rawId, flagged in pairs(set) do
                if flagged then
                    local normalized = FavoritesData.NormalizeId(rawId)
                    if normalized and FavoritesData.IsCompleted(normalized) then
                        candidates[normalized] = true
                    end
                end
            end
        end
    end

    local removedEntries = 0
    local uniqueRemoved = 0

    for normalized in pairs(candidates) do
        local removedCount = removeFavoritedIdWithTimestamp(normalized, nil)
        if removedCount > 0 then
            removedEntries = removedEntries + removedCount
            uniqueRemoved = uniqueRemoved + 1
        end
    end

    if removedEntries > 0 then
        emitDebugMessage("prune removed=%d unique=%d", removedEntries, uniqueRemoved)
        NotifyFavoritesChanged()
    end

    return removedEntries
end

function FavoritesData.MigrateScope(fromScope, toScope)
    FavoritesData.InitSavedVars()

    local normalizedFrom = resolveScope(fromScope)
    local normalizedTo = resolveScope(toScope)

    if normalizedFrom == normalizedTo then
        return
    end

    local moved = 0

    if normalizedFrom == CHARACTER_SCOPE and normalizedTo == ACCOUNT_SCOPE then
        local raw = _G["Nvk3UT_Data_Favorites"]
        local accountName = (GetDisplayName and GetDisplayName()) or (Nvk3UT and Nvk3UT.accountName) or nil
        local accountNode = raw and raw["Default"] and accountName and raw["Default"][accountName]
        local accList = ensureSet(ACCOUNT_SCOPE, true)

        if accountNode and accountNode["$AccountWide"] then
            for key, node in pairs(accountNode) do
                if key ~= "$AccountWide" and type(key) == "string" and key:match("^%d+$") then
                    local characters = node and node["characters"]
                    local lst = characters and characters["list"]
                    if type(lst) == "table" then
                        for entryId, flagged in pairs(lst) do
                            if flagged then
                                accList[entryId] = true
                                lst[entryId] = nil
                                moved = moved + 1
                            end
                        end
                    end
                end
            end
        else
            local charList = ensureSet(CHARACTER_SCOPE, true)
            for entryId, flagged in pairs(charList) do
                if flagged then
                    accList[entryId] = true
                    charList[entryId] = nil
                    moved = moved + 1
                end
            end
        end
    else
        local fromSet = ensureSet(normalizedFrom, true)
        local toSet = ensureSet(normalizedTo, true)

        for entryId, flagged in pairs(fromSet) do
            if flagged then
                toSet[entryId] = true
                fromSet[entryId] = nil
                moved = moved + 1
            end
        end
    end

    emitDebugMessage(
        "migrate from=%s to=%s moved=%d",
        tostring(normalizedFrom),
        tostring(normalizedTo),
        tonumber(moved) or 0
    )

    local movedNum = tonumber(moved) or 0
    local fromLabel = (normalizedFrom == CHARACTER_SCOPE and "Charakter-weit") or "Account-weit"
    local toLabel = (normalizedTo == CHARACTER_SCOPE and "Charakter-weit") or "Account-weit"
    if d then
        d(string.format("[Nvk3UT] Favoriten migriert: %d (von %s nach %s).", movedNum, fromLabel, toLabel))
    end

    if movedNum > 0 then
        NotifyFavoritesChanged()
    end
end

return FavoritesData
