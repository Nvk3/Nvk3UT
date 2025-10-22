Nvk3UT = Nvk3UT or {}
local M = Nvk3UT

M.TrackerView = M.TrackerView or {}
local Module = M.TrackerView

local function debugLog(message)
    if d then
        d(string.format("[Nvk3UT] TrackerView: %s", message))
    end
end

function Module.Init()
    debugLog("Init() stub invoked")
    -- TODO: Create tracker scroll list and row templates.
end

function Module.ForceRefresh()
    -- TODO: Rebuild tracker rows when rendering is implemented.
end

return
