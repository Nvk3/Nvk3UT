
Nvk3UT = Nvk3UT or {}
local M = {}
Nvk3UT.Utils = M

-- Debug logger: prints only when sv.debug is true.
function M.d(...)
    local sv = Nvk3UT and Nvk3UT.sv
    if not (sv and sv.debug) then return end
    local parts = {}
    for i=1, select("#", ...) do
        parts[#parts+1] = tostring(select(i, ...))
    end
    local msg = table.concat(parts, " ")
    msg = msg:gsub("^%s*", "")
    if msg:find("^%[Nvk3UT%]") then
        msg = msg:gsub("^%[Nvk3UT%]", "", 1)
    end
    msg = "[Nvk3UT]" .. msg
    if d then d(msg) end
end

-- timestamp helper
function M.now()
    return GetTimeStamp()
end
