Nvk3UT = Nvk3UT or {}

-- Nvk3UT.Recent
-- Provides maintenance helpers for the recent list.
local M = {}
Nvk3UT.Recent = M

local Utils = Nvk3UT and Nvk3UT.Utils
local Ach = Nvk3UT and Nvk3UT.Achievements
local Data = Nvk3UT and Nvk3UT.RecentData

local function isDebugEnabled()
    return Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug and Utils and Utils.d
end

local function ensureData()
    if Data and Data.InitSavedVars then
        Data.InitSavedVars()
    end
end

local function iterateProgress()
    ensureData()
    local sv = Nvk3UT and Nvk3UT._recentSV
    if not sv or type(sv.progress) ~= "table" then
        return {}
    end
    local entries = {}
    for rawId, _ in pairs(sv.progress) do
        entries[#entries + 1] = tonumber(rawId) or rawId
    end
    return entries
end

---Remove all completed achievements from the recent list.
function M.CleanupCompleted()
    if not (Ach and Ach.IsComplete and Data and Data.Clear) then
        return false
    end

    local entries = iterateProgress()
    if #entries == 0 then
        return false
    end

    local removedIds = {}
    for _, id in ipairs(entries) do
        if type(id) == "number" and Ach.IsComplete(id) then
            Data.Clear(id)
            removedIds[#removedIds + 1] = id
            if isDebugEnabled() then
                Utils.d(string.format("[Recent] Cleaned completed achievement %d", id))
            end
        end
    end

    if #removedIds > 0 then
        if Nvk3UT.UI and Nvk3UT.UI.RefreshAchievements then
            Nvk3UT.UI.RefreshAchievements()
        end
        if Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then
            Nvk3UT.UI.UpdateStatus()
        end
        return true
    end

    return false
end

return M
