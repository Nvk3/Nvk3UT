
Nvk3UT = Nvk3UT or {}
local U = Nvk3UT.Utils
local M = {}
Nvk3UT.RecentData = M

-- account-wide SV root
local defaults = { progress = {} }

local function ensureSV()
    if not Nvk3UT._recentSV then
        Nvk3UT._recentSV = ZO_SavedVars:NewAccountWide("Nvk3UT_Data_Recent", 1, nil, defaults)
    end
    if not Nvk3UT._recentSV.progress then
        Nvk3UT._recentSV.progress = {}
    end
    return Nvk3UT._recentSV
end

-- Migration: merge all character buckets into the account-wide bucket
function M.MigrateToAccountWide()
    local raw = _G["Nvk3UT_Data_Recent"]
    local accountName = (GetDisplayName and GetDisplayName()) or nil
    if not (raw and raw["Default"] and accountName and raw["Default"][accountName]) then return 0 end
    local root = raw["Default"][accountName]
    local accNode = root["$AccountWide"] or {}
    accNode["progress"] = accNode["progress"] or {}
    local accProg = accNode["progress"]
    local moved = 0
    for key, node in pairs(root) do
        if key ~= "$AccountWide" and type(key)=="string" and key:match("^%d+$") then
            local prog = node and node["progress"]
            if type(prog)=="table" then
                for id, ts in pairs(prog) do
                    if ts then
                        if not accProg[id] or (type(ts)=="number" and ts > accProg[id]) then
                            accProg[id] = ts
                        end
                        prog[id] = nil
                        moved = moved + 1
                    end
                end
            end
        end
    end
    root["$AccountWide"] = accNode
    return moved
end

function M.InitSavedVars()
    local sv = ensureSV()
    -- run migration once (safe/no-op if nichts zu tun)
    if M.MigrateToAccountWide then M.MigrateToAccountWide() end
end

local function now() return (U and U.now and U.now()) or GetTimeStamp() end

local function IsOpen(id)
    if not id then return false end
    if U and U.IsAchievementFullyComplete then
        return not U.IsAchievementFullyComplete(id)
    end
    local _,_,_,_,completed = GetAchievementInfo(id)
    return completed == false
end

function M.Touch(id, ts)
    ensureSV()
    if not id then return end
    if U and U.NormalizeAchievementId then
        id = U.NormalizeAchievementId(id)
    end
    Nvk3UT._recentSV.progress[id] = ts or now()
end

function M.Clear(id)
    ensureSV()
    if not id then return end
    if U and U.NormalizeAchievementId then
        id = U.NormalizeAchievementId(id)
    end
    Nvk3UT._recentSV.progress[id] = nil
end

-- Build a sorted list of IDs by timestamp (desc); optional sinceTs and maxCount
function M.List(maxCount, sinceTs)
    ensureSV()
    local t = {}
    for id, ts in pairs(Nvk3UT._recentSV.progress) do
        if (not sinceTs) or (type(ts)=="number" and ts >= sinceTs) then
            t[#t+1] = {id=id, ts=ts or 0}
        end
    end
    table.sort(t, function(a,b) return a.ts > b.ts end)
    local res = {}
    local limit = tonumber(maxCount) or 0
    local removed = 0
    for i=1,#t do
        local id = t[i].id
        local open = IsOpen(id)
        if open then
            if limit == 0 or #res < limit then
                res[#res+1] = id
            end
        elseif id then
            M.Clear(id)
            removed = removed + 1
        end
    end
    if U and U.d then
        if removed > 0 then
            U.d("[Nvk3UT][Recent][List] filtered", "removed:", removed)
        end
    end
    return res
end

-- Event wiring: keep list fresh passively
function M.RegisterEvents()
    local em = EVENT_MANAGER
    if not em then return end
    em:UnregisterForEvent("Nvk3UT_RecentData", EVENT_ACHIEVEMENT_UPDATED)
    em:UnregisterForEvent("Nvk3UT_RecentData", EVENT_ACHIEVEMENT_AWARDED)
    em:RegisterForEvent("Nvk3UT_RecentData", EVENT_ACHIEVEMENT_UPDATED, function(_, id)
        local open = IsOpen(id)
        if open then M.Touch(id) else M.Clear(id) end
    end)
    em:RegisterForEvent("Nvk3UT_RecentData", EVENT_ACHIEVEMENT_AWARDED, function(_, _, _, id)
        local open = IsOpen(id)
        if open then M.Touch(id) else M.Clear(id) end
    end)
end

-- Config helpers shared with UI/Provider
local function _getConfig()
    local sv = Nvk3UT and Nvk3UT.sv or {ui={}}
    local win = (sv.ui and sv.ui.recentWindow) or 0  -- 0=alle, 7, 30
    local maxc = (sv.ui and sv.ui.recentMax) or 100  -- hardcap
    local sinceTs = nil
    if win == 7 then sinceTs = (GetTimeStamp() - 7*24*60*60)
    elseif win == 30 then sinceTs = (GetTimeStamp() - 30*24*60*60) end
    return maxc, sinceTs
end

function M.ListConfigured()
    M.InitSavedVars()
    local maxc, sinceTs = _getConfig()
    return M.List(maxc, sinceTs)
end

function M.CountConfigured()
    M.InitSavedVars()
    local maxc, sinceTs = _getConfig()
    local list = M.List(maxc, sinceTs)
    return (list and #list) or 0
end

-- Seed the account-wide recent list with up to 50 entries (only if empty)
function M.BuildInitial()
    local sv = ensureSV()
    if next(sv.progress) ~= nil then return 0 end
    local added = 0
    local INIT_CAP = 50
    local stamp = (U and U.now and U.now()) or GetTimeStamp()

    local function add(id)
        if not id or added >= INIT_CAP then return end
        if IsOpen(id) then
            local storeId = id
            if U and U.NormalizeAchievementId then
                storeId = U.NormalizeAchievementId(id)
            end
            if storeId then
                if sv.progress[storeId] == nil then
                    added = added + 1
                end
                sv.progress[storeId] = stamp
            end
        end
    end

    local numCats = GetNumAchievementCategories and GetNumAchievementCategories() or 0
    for top = 1, numCats do
        local _, numSub, numAch = GetAchievementCategoryInfo(top)
        -- top-level achievements
        for a=1,(numAch or 0) do
            if added >= INIT_CAP then break end
            local id = GetAchievementId(top, nil, a)
            add(id)
        end
        -- subcategories
        for sub=1,(numSub or 0) do
            if added >= INIT_CAP then break end
            local _, numAch2 = GetAchievementSubCategoryInfo(top, sub)
            for a=1,(numAch2 or 0) do
                if added >= INIT_CAP then break end
                local id = GetAchievementId(top, sub, a)
                add(id)
            end
        end
        if added >= INIT_CAP then break end
    end

    return added
end

