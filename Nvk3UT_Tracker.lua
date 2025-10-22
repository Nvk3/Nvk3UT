Nvk3UT = Nvk3UT or {}
local M = Nvk3UT

M.Tracker = M.Tracker or {}
local Module = M.Tracker

local function debugLog(message)
    if d then
        d(string.format("[Nvk3UT] Tracker: %s", message))
    end
end

function Module.Init()
    debugLog("Init() stub invoked")
    -- TODO: Orchestrate tracker lifecycle and module coordination.
end

function Module.ForceRefresh()
    -- TODO: Coordinate a full tracker refresh when implemented.
end

return
