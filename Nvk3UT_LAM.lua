Nvk3UT = Nvk3UT or {}
local M = Nvk3UT

M.LAM = M.LAM or {}
local Module = M.LAM

local function debugLog(message)
    if d then
        d(string.format("[Nvk3UT] LAM: %s", message))
    end
end

function Module.Init()
    debugLog("Init() stub invoked")
    -- TODO: Implement LibAddonMenu integration wiring.
end

function Module.ForceRefresh()
    -- TODO: Trigger settings-driven refresh logic when implemented.
end

return
