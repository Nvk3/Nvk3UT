
Nvk3UT = Nvk3UT or {}
local M = {}
Nvk3UT.FavoritesData = M

local ACC_VER = 1
local CHAR_VER = 1

-- SavedVariables:
-- Account-wide: Nvk3UT_Data_Favorites (section 'account').list[id] = true
-- CharacterId:  Nvk3UT_Data_Favorites (section 'characters').list[id] = true

function M.InitSavedVars()
    if not Nvk3UT_Data_Favorites_Account then
        Nvk3UT_Data_Favorites_Account =
            ZO_SavedVars:NewAccountWide("Nvk3UT_Data_Favorites", ACC_VER, "account", { list = {} })
    end
    if not Nvk3UT_Data_Favorites_Characters then
        Nvk3UT_Data_Favorites_Characters =
            ZO_SavedVars:NewCharacterIdSettings("Nvk3UT_Data_Favorites", CHAR_VER, "characters", { list = {} })
    end
end

local function getSet(scope)
    if scope == "character" then
        return (Nvk3UT_Data_Favorites_Characters and Nvk3UT_Data_Favorites_Characters.list) or {}
    end
    return (Nvk3UT_Data_Favorites_Account and Nvk3UT_Data_Favorites_Account.list) or {}
end

local function normalizeKey(id)
    if id == nil then
        return nil
    end

    local numeric = tonumber(id)
    return numeric or id
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
end

function M.IsFavorite(id, scope)
    if not id then return false end
    local key = normalizeKey(id)
    if not key then
        return false
    end
    local set = getSet(scope)
    return set[key] and true or false
end

function M.Toggle(id, scope)
    local key = normalizeKey(id)
    if not key then
        return false
    end

    local set = getSet(scope)
    local wasFavorite = set[key] and true or false
    if wasFavorite then
        set[key] = nil
    else
        set[key] = true
    end

    NotifyFavoritesChanged()

    return not wasFavorite
end

function M.Add(id, scope)
    local key = normalizeKey(id)
    if not key then
        return
    end

    local set = getSet(scope)
    if set[key] then
        return
    end

    set[key] = true
    NotifyFavoritesChanged()
end

function M.Remove(id, scope)
    local key = normalizeKey(id)
    if not key then
        return
    end

    local set = getSet(scope)
    if not set[key] then
        return
    end

    set[key] = nil
    NotifyFavoritesChanged()
end

function M.Iterate(scope)
    local set = getSet(scope)
    return next, set, nil
end

-- Migrate favorites between scopes. "fromScope"/"toScope" = "account"|"character".


function M.MigrateScope(fromScope, toScope)
    M.InitSavedVars()
    if fromScope == toScope then return end
    local U = Nvk3UT and Nvk3UT.Utils
    local moved = 0

    if fromScope == "character" and toScope == "account" then
        -- Bulk migrate ALL characters' favorites to account-wide
        local raw = _G["Nvk3UT_Data_Favorites"]
        local accountName = (GetDisplayName and GetDisplayName()) or (Nvk3UT and Nvk3UT.accountName) or nil
        local accountNode = raw and raw["Default"] and accountName and raw["Default"][accountName]
        local accList = (Nvk3UT_Data_Favorites_Account and Nvk3UT_Data_Favorites_Account.list) or {}

        if accountNode and accountNode["$AccountWide"] then
            -- iterate all keys under this account, pick numeric character ids
            for key, node in pairs(accountNode) do
                if key ~= "$AccountWide" and type(key) == "string" and key:match("^%d+$") then
                    local lst = node and node["characters"] and node["characters"]["list"]
                    if type(lst) == "table" then
                        for id, v in pairs(lst) do
                            if v then
                                accList[id] = true
                                lst[id] = nil
                                moved = moved + 1
                            end
                        end
                    end
                end
            end
        else
            -- Fallback: migrate current character only
            local cur = (Nvk3UT_Data_Favorites_Characters and Nvk3UT_Data_Favorites_Characters.list) or {}
            for id, v in pairs(cur) do
                if v then
                    accList[id] = true
                    cur[id] = nil
                    moved = moved + 1
                end
            end
        end
    else
        -- account -> current character (or other): migrate only current bucket
        local fromSet = (fromScope == "character") and ((Nvk3UT_Data_Favorites_Characters and Nvk3UT_Data_Favorites_Characters.list) or {}) or ((Nvk3UT_Data_Favorites_Account and Nvk3UT_Data_Favorites_Account.list) or {})
        local toSet   = (toScope   == "character") and ((Nvk3UT_Data_Favorites_Characters and Nvk3UT_Data_Favorites_Characters.list) or {}) or ((Nvk3UT_Data_Favorites_Account and Nvk3UT_Data_Favorites_Account.list) or {})
        for id, v in pairs(fromSet) do
            if v then
                toSet[id] = true
                fromSet[id] = nil
                moved = moved + 1
            end
        end
    end

    if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug then
        U.d("[Nvk3UT][Favorites][MigrateScope]", "data={from:'"..tostring(fromScope).."', to:'"..tostring(toScope).."', moved:"..tostring(moved).."}")
    end
    -- Always inform in chat
    local movedNum = tonumber(moved) or 0
    local fromLabel = (fromScope=="character" and "Charakter-weit") or "Account-weit"
    local toLabel   = (toScope=="character" and "Charakter-weit") or "Account-weit"
    if d then d(string.format("[Nvk3UT] Favoriten migriert: %d (von %s nach %s).", movedNum, fromLabel, toLabel)) end

    if movedNum > 0 then
        NotifyFavoritesChanged()
    end
end
