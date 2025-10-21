Nvk3UT = Nvk3UT or {}
local M = {}
Nvk3UT.Diagnostics = M
function M.SelfTest()
    d("[Nvk3UT] SelfTest: ZO_Achievements: "..tostring(ZO_Achievements ~= nil))
    d("[Nvk3UT] SelfTest: categoryTree: "..tostring(ZO_Achievements and ZO_Achievements.categoryTree ~= nil))
    d("[Nvk3UT] SelfTest: LibAddonMenu2: "..tostring(LibAddonMenu2 ~= nil))
end
function M.SystemTest()
    local ach = SYSTEMS and SYSTEMS:GetObject("achievements")
    d("[Nvk3UT] SYSTEMS achievements: "..tostring(ach ~= nil))
    if ach then
        d("[Nvk3UT] ach.categoryTree: "..tostring(ach.categoryTree ~= nil))
        d("[Nvk3UT] ach.control: "..tostring(ach.control ~= nil))
    end
end
