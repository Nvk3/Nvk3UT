Nvk3UT = Nvk3UT or {}
local M = Nvk3UT

M.QuestModel = M.QuestModel or {}
local Module = M.QuestModel

local function debugLog(message)
    if d then
        d(string.format("[Nvk3UT] QuestModel: %s", message))
    end
end

function Module.Init()
    debugLog("Init() stub invoked")
    -- TODO: Register quest-related events and data collection.
end

function Module.ForceRefresh()
    -- TODO: Force a quest data refresh when implemented.
end

return
