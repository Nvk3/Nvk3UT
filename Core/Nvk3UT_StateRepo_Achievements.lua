Nvk3UT = Nvk3UT or {}

local Repo = {}
Nvk3UT.StateRepo_Achievements = Repo
Nvk3UT_StateRepo_Achievements = Repo

local DEFAULT_RECENT_LIMIT = 100
local VALID_RECENT_LIMIT = {
    [50] = true,
    [100] = true,
    [250] = true,
}

local state = {
    addon = nil,
    account = nil,
    ac = nil,
}

local function getAddon()
    if state.addon then
        return state.addon
    end

    if Nvk3UT then
        return Nvk3UT
    end

    return nil
end

local function isDebugEnabled()
    local addon = getAddon()
    if not addon then
        return false
    end

    if addon.IsDebugEnabled then
        return addon:IsDebugEnabled() == true
    end

    return addon.debugEnabled == true
end

local function debugLog(fmt, ...)
    if not isDebugEnabled() then
        return
    end

    local addon = getAddon()
    if addon and addon.Debug then
        addon.Debug("[StateRepo.AC] " .. tostring(fmt), ...)
        return
    end

    if d then
        local ok, message = pcall(string.format, tostring(fmt), ...)
        if not ok then
            message = tostring(fmt)
        end
        d(string.format("[Nvk3UT][StateRepo.Achievements] %s", message))
    end
end

local function normalizeId(id)
    if id == nil then
        return nil
    end

    local numeric = tonumber(id)
    if not numeric then
        return nil
    end

    numeric = math.floor(numeric + 0.5)
    if numeric <= 0 then
        return nil
    end

    return numeric
end

local function ensureAccount()
    if state.account then
        return state.account
    end

    local addon = getAddon()
    if addon and type(addon.SV) == "table" then
        state.account = addon.SV
        return state.account
    end

    return nil
end

local function ensureAc(create)
    if state.ac then
        return state.ac
    end

    local account = ensureAccount()
    if type(account) ~= "table" then
        return nil
    end

    local ac = account.ac
    if type(ac) ~= "table" then
        if not create then
            return nil
        end
        ac = {}
        account.ac = ac
    end

    state.ac = ac
    return ac
end

local function pruneIfEmpty(parent, key)
    local value = parent and parent[key]
    if type(value) ~= "table" then
        return
    end

    if next(value) == nil then
        parent[key] = nil
    end
end

local function ensureFavorites(create)
    local ac = ensureAc(create)
    if not ac then
        return nil
    end

    local favorites = ac.favorites
    if type(favorites) ~= "table" then
        if not create then
            return nil
        end
        favorites = {}
        ac.favorites = favorites
    end

    return favorites
end

local function ensureCollapse(create)
    local ac = ensureAc(create)
    if not ac then
        return nil
    end

    local collapse = ac.collapse
    if type(collapse) ~= "table" then
        if not create then
            return nil
        end
        collapse = {}
        ac.collapse = collapse
    end

    if create then
        local achievements = collapse.achievements
        if type(achievements) ~= "table" then
            achievements = {}
            collapse.achievements = achievements
        end
    end

    return collapse
end

local function ensureRecent(create)
    local ac = ensureAc(create)
    if not ac then
        return nil
    end

    local recent = ac.recent
    if type(recent) ~= "table" then
        if not create then
            return nil
        end
        recent = {}
        ac.recent = recent
    end

    if create then
        if type(recent.list) ~= "table" then
            recent.list = {}
        end
        if type(recent.progress) ~= "table" then
            recent.progress = {}
        end
    end

    return recent
end

local function sanitizeFavorites()
    local favorites = ensureFavorites(false)
    if not favorites then
        return
    end

    local sanitized = {}
    local changed = false

    for key, value in pairs(favorites) do
        local normalized = normalizeId(key)
        if normalized and value == true then
            sanitized[normalized] = true
        else
            changed = true
        end
    end

    if not changed then
        return
    end

    for key in pairs(favorites) do
        favorites[key] = nil
    end

    for id in pairs(sanitized) do
        favorites[id] = true
    end

    if next(favorites) == nil then
        local ac = ensureAc(false)
        if ac then
            ac.favorites = nil
        end
    end
end

local function sanitizeRecentList()
    local recent = ensureRecent(false)
    if not recent then
        return {}
    end

    local list = recent.list
    local sanitized = {}
    local seen = {}
    local changed = type(list) ~= "table"

    if type(list) == "table" then
        for index = 1, #list do
            local normalized = normalizeId(list[index])
            if normalized and not seen[normalized] then
                sanitized[#sanitized + 1] = normalized
                seen[normalized] = true
            else
                changed = true
            end
        end
    end

    if changed then
        if #sanitized == 0 then
            recent.list = nil
        else
            recent.list = sanitized
        end
    end

    return sanitized
end

local function sanitizeProgress()
    local recent = ensureRecent(false)
    if not recent then
        return
    end

    local progress = recent.progress
    if type(progress) ~= "table" then
        return
    end

    local sanitized = {}
    local changed = false

    for key, value in pairs(progress) do
        local normalized = normalizeId(key)
        if normalized then
            sanitized[normalized] = value
        else
            changed = true
        end
    end

    if not changed then
        return
    end

    for key in pairs(progress) do
        progress[key] = nil
    end

    for id, value in pairs(sanitized) do
        progress[id] = value
    end
end

local function sanitizeRecentLimit()
    local recent = ensureRecent(false)
    if not recent then
        return DEFAULT_RECENT_LIMIT
    end

    local limit = tonumber(recent.limit)
    if not VALID_RECENT_LIMIT[limit] then
        limit = DEFAULT_RECENT_LIMIT
    end

    if limit == DEFAULT_RECENT_LIMIT then
        recent.limit = nil
    else
        recent.limit = limit
    end

    return limit
end

local function sanitizeCollapse()
    local collapse = ensureCollapse(false)
    if not collapse then
        return
    end

    if collapse.block_favorites_collapsed ~= true then
        collapse.block_favorites_collapsed = nil
    end

    local achievements = collapse.achievements
    if type(achievements) ~= "table" then
        achievements = nil
    else
        local sanitized = {}
        local changed = false
        for key, value in pairs(achievements) do
            local normalized = normalizeId(key)
            if normalized and value == true then
                sanitized[normalized] = true
            else
                changed = true
            end
        end

        if changed then
            achievements = next(sanitized) ~= nil and sanitized or nil
        end
    end

    collapse.achievements = achievements

    pruneIfEmpty(collapse, "achievements")

    if collapse.block_favorites_collapsed == nil and collapse.achievements == nil then
        local ac = ensureAc(false)
        if ac then
            ac.collapse = nil
        end
    end
end

local function getStoredLimit()
    local recent = ensureRecent(false)
    if not recent then
        return DEFAULT_RECENT_LIMIT
    end

    local limit = tonumber(recent.limit)
    if not VALID_RECENT_LIMIT[limit] then
        return DEFAULT_RECENT_LIMIT
    end

    return limit
end

local function storeLimit(limit)
    local recent = ensureRecent(true)
    if not recent then
        return DEFAULT_RECENT_LIMIT
    end

    if not VALID_RECENT_LIMIT[limit] then
        limit = DEFAULT_RECENT_LIMIT
    end

    if limit == DEFAULT_RECENT_LIMIT then
        recent.limit = nil
    else
        recent.limit = limit
    end

    return limit
end

local function writeRecentList(values)
    local recent = ensureRecent(true)
    if not recent then
        return
    end

    if type(values) ~= "table" or #values == 0 then
        recent.list = nil
        return
    end

    local list = {}
    local seen = {}
    for index = 1, #values do
        local normalized = normalizeId(values[index])
        if normalized and not seen[normalized] then
            list[#list + 1] = normalized
            seen[normalized] = true
        end
    end

    if #list == 0 then
        recent.list = nil
    else
        recent.list = list
    end
end

local function pruneRecentList()
    local limit = getStoredLimit()
    local list = sanitizeRecentList()
    if #list <= limit then
        return list
    end

    local trimmed = {}
    for index = 1, limit do
        trimmed[index] = list[index]
    end

    writeRecentList(trimmed)
    return trimmed
end

local function sanitizeAll()
    sanitizeFavorites()
    sanitizeRecentList()
    sanitizeProgress()
    sanitizeRecentLimit()
    pruneRecentList()
    sanitizeCollapse()
end

function Repo.AC_Fav_Add(id)
    local normalized = normalizeId(id)
    if not normalized then
        return false
    end

    local favorites = ensureFavorites(true)
    if not favorites then
        return false
    end

    if favorites[normalized] == true then
        return false
    end

    favorites[normalized] = true
    debugLog("Favorite added: %d", normalized)
    return true
end

function Repo.AC_Fav_Remove(id)
    local normalized = normalizeId(id)
    if not normalized then
        return false
    end

    local favorites = ensureFavorites(false)
    if not favorites or favorites[normalized] ~= true then
        return false
    end

    favorites[normalized] = nil
    if next(favorites) == nil then
        local ac = ensureAc(false)
        if ac then
            ac.favorites = nil
        end
    end

    debugLog("Favorite removed: %d", normalized)
    return true
end

function Repo.AC_Fav_Has(id)
    local normalized = normalizeId(id)
    if not normalized then
        return false
    end

    local favorites = ensureFavorites(false)
    return favorites and favorites[normalized] == true or false
end

function Repo.AC_Fav_List()
    local favorites = ensureFavorites(false)
    if not favorites then
        return {}
    end

    local list = {}
    for id, value in pairs(favorites) do
        if value == true then
            list[#list + 1] = id
        end
    end

    table.sort(list)
    return list
end

function Repo.AC_Recent_GetLimit()
    return getStoredLimit()
end

function Repo.AC_Recent_SetLimit(limit)
    local numeric = tonumber(limit)
    if not VALID_RECENT_LIMIT[numeric] then
        numeric = DEFAULT_RECENT_LIMIT
    end

    local stored = storeLimit(numeric)
    pruneRecentList()
    debugLog("Recent limit set to %d", stored)
    return stored
end

function Repo.AC_Recent_List(optionalLimit)
    local list = sanitizeRecentList()
    local limit = getStoredLimit()

    if optionalLimit ~= nil then
        local requested = tonumber(optionalLimit)
        if requested and requested > 0 then
            limit = math.min(limit, math.floor(requested))
        end
    end

    local result = {}
    for index = 1, math.min(#list, limit) do
        result[index] = list[index]
    end

    return result
end

function Repo.AC_Recent_SetList(values)
    writeRecentList(values)
    return pruneRecentList()
end

function Repo.AC_Recent_PruneOverLimit()
    return pruneRecentList()
end

function Repo.AC_Recent_Touch(id)
    local normalized = normalizeId(id)
    if not normalized then
        return false
    end

    local existing = sanitizeRecentList()
    local filtered = {}
    local index = 1
    for i = 1, #existing do
        local value = existing[i]
        if value ~= normalized then
            filtered[index] = value
            index = index + 1
        end
    end

    table.insert(filtered, 1, normalized)
    Repo.AC_Recent_SetList(filtered)
    debugLog("Recent touch: %d", normalized)
    return true
end

function Repo.AC_Recent_GetStorage(create)
    return ensureRecent(create)
end

function Repo.AC_Recent_GetProgressTable(create)
    local recent = ensureRecent(create)
    if not recent then
        return nil
    end

    local progress = recent.progress
    if type(progress) ~= "table" then
        if not create then
            return nil
        end
        progress = {}
        recent.progress = progress
    end

    return progress
end

function Repo.AC_Block_IsCollapsed()
    local collapse = ensureCollapse(false)
    if not collapse then
        return false
    end
    return collapse.block_favorites_collapsed == true
end

function Repo.AC_Block_SetCollapsed(value)
    local collapse = ensureCollapse(value == true)
    if not collapse then
        return false
    end

    local desired = value == true and true or nil
    if collapse.block_favorites_collapsed == desired then
        return false
    end

    collapse.block_favorites_collapsed = desired
    pruneIfEmpty(collapse, "achievements")
    if desired == nil and collapse.achievements == nil then
        local ac = ensureAc(false)
        if ac then
            ac.collapse = nil
        end
    end

    debugLog("Favorites block collapsed=%s", tostring(value))
    return true
end

function Repo.AC_IsCollapsed(id)
    local normalized = normalizeId(id)
    if not normalized then
        return false
    end

    local collapse = ensureCollapse(false)
    local achievements = collapse and collapse.achievements
    return achievements and achievements[normalized] == true or false
end

function Repo.AC_SetCollapsed(id, value)
    local normalized = normalizeId(id)
    if not normalized then
        return false
    end

    local collapse = ensureCollapse(value == true)
    if not collapse then
        return false
    end

    local achievements = collapse.achievements
    if type(achievements) ~= "table" then
        if value ~= true then
            return false
        end
        achievements = {}
        collapse.achievements = achievements
    end

    local desired = value == true and true or nil
    if achievements[normalized] == desired then
        return false
    end

    if desired then
        achievements[normalized] = true
    else
        achievements[normalized] = nil
        if next(achievements) == nil then
            collapse.achievements = nil
        end
    end

    if collapse.block_favorites_collapsed ~= true and collapse.achievements == nil then
        local ac = ensureAc(false)
        if ac then
            ac.collapse = nil
        end
    end

    debugLog("Achievement %d collapsed=%s", normalized, tostring(value))
    return true
end

function Repo.Init(accountSaved)
    if type(accountSaved) == "table" then
        state.account = accountSaved
        state.ac = accountSaved.ac
    else
        state.account = ensureAccount()
        state.ac = state.account and state.account.ac or nil
    end

    sanitizeAll()
    debugLog("Achievement state repository initialised")
end

function Repo.AttachToRoot(addon)
    if type(addon) ~= "table" then
        return
    end

    state.addon = addon
    addon.AchievementRepo = Repo
end

return Repo
