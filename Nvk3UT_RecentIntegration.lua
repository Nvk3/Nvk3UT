Nvk3UT = Nvk3UT or {}
local function _nvk3ut_is_enabled(key)
  return (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features[key]) and true or false
end
local RD = Nvk3UT.RecentData

local recProvide_lastTs, recProvide_lastCount = 0, -1
local NVK3_RECENT = 84001

-- Use same icon set as Favoriten for visual parity
local ICON_UP   = "esoui/art/market/keyboard/giftmessageicon_up.dds"
local ICON_DOWN = "esoui/art/market/keyboard/giftmessageicon_down.dds"
local ICON_OVER = "esoui/art/market/keyboard/giftmessageicon_over.dds"

local function AddRecentCategory(AchClass)
    local orgAddTopLevelCategory = AchClass.AddTopLevelCategory
    function AchClass.AddTopLevelCategory(...)
                if not _nvk3ut_is_enabled("recent") then return orgAddTopLevelCategory(...) end
        if not _nvk3ut_is_enabled("recent") then return (
            select(1, ...)).AddTopLevelCategory and select(1, ...).AddTopLevelCategory(...) end
        local self, name = ...
        if name then
            return orgAddTopLevelCategory(...)
        end
        local result = orgAddTopLevelCategory(...)
        local lookup, tree = self.nodeLookupData, self.categoryTree
        local label = "Kürzlich"
        local parentNode = self:AddCategory(lookup, tree, "ZO_IconChildlessHeader", nil, NVK3_RECENT, label, false, ICON_UP, ICON_DOWN, ICON_OVER, true, true)
        local _row = parentNode and parentNode.GetData and parentNode:GetData()
        if _row then _row.isNvkRecent = true end
        if self.refreshGroups then self.refreshGroups:RefreshAll("FullUpdate") end
        local U = Nvk3UT and Nvk3UT.Utils; local __now = (U and U.now and U.now() or 0); if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug and ((__now - recProvide_lastTs) > 0.5 or #result ~= recProvide_lastCount) then recProvide_lastTs = __now; recProvide_lastCount = #result; U.d("[Nvk3UT][Recent][Provide] list", "data={count:", #result, ", searchFiltered:", tostring(considerSearchResults and true or false), "}") end; return result
    end
end

local function OverrideOnCategorySelected(AchClass)
    local org = AchClass.OnCategorySelected
    function AchClass.OnCategorySelected(...)
                if not _nvk3ut_is_enabled("recent") then return org(...) end
        local self, data, saveExpanded = ...
        if _nvk3ut_is_enabled("recent") and data and data.categoryIndex == NVK3_RECENT then
            self:HideSummary()
            self:UpdateCategoryLabels(data, true, false)
            if self.refreshGroups then self.refreshGroups:RefreshAll("FullUpdate") end
        else
            return org(...)
        end
    end
end

local function OverrideGetCategoryInfoFromData(AchClass)
    local org = AchClass.GetCategoryInfoFromData
    function AchClass.GetCategoryInfoFromData(...)
                if not _nvk3ut_is_enabled("recent") then return org(...) end
        local self, data, parentData = ...
        if _nvk3ut_is_enabled("recent") and data and data.categoryIndex == NVK3_RECENT then
            local list = RD.List(100)
            local num = #list
            return num, 0, 0, true -- hidesPoints
        end
        return org(...)
    end
end

local function OverrideOnAchievementUpdated(AchClass)
    local org = AchClass.OnAchievementUpdated
    function AchClass.OnAchievementUpdated(...)
        local self, id = ...
        RD.Touch(id)
        local data = self.categoryTree:GetSelectedData()
        if _nvk3ut_is_enabled("recent") and data and data.categoryIndex == NVK3_RECENT then
            self:UpdateCategoryLabels(data, true, false)
        else
            return org(...)
        end
    end
end

local function Override_ZO_GetAchievementIds()
    local base = ZO_GetAchievementIds
    function ZO_GetAchievementIds(categoryIndex, subcategoryIndex, numAchievements, considerSearchResults)
        if categoryIndex == NVK3_RECENT then
            return RD.ListConfigured()
        end
        return base(categoryIndex, subcategoryIndex, numAchievements, considerSearchResults)
    end
end

function Nvk3UT_EnableRecentCategory()
    RD.InitSavedVars()
    if RD.BuildInitial then RD.BuildInitial() end
    RD.RegisterEvents()
    local AchClass = getmetatable(ACHIEVEMENTS).__index
    AddRecentCategory(AchClass)
    OverrideOnCategorySelected(AchClass)
    OverrideGetCategoryInfoFromData(AchClass)
    OverrideOnAchievementUpdated(AchClass)
    Override_ZO_GetAchievementIds()
end