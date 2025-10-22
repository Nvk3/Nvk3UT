Nvk3UT = Nvk3UT or {}
local function _nvk3ut_is_enabled(key)
  return (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features[key]) and true or false
end
local RD = Nvk3UT.RecentData
local U = Nvk3UT and Nvk3UT.Utils

local NVK3_RECENT = 84001
local ICON_PATH_RECENT = "/esoui/art/journal/journal_tabicon_quest_up.dds"
local RECENT_LOOKUP_KEY = "NVK3UT_RECENT_ROOT"

local function sanitizePlainName(name)
    if U and U.StripLeadingIconTag then
        name = U.StripLeadingIconTag(name)
    end
    return name
end

-- Use same icon set as Favoriten for visual parity
local function _countRecent()
    if not RD then
        return 0
    end
    if type(RD.CountConfigured) == "function" then
        local ok, count = pcall(RD.CountConfigured)
        if ok and type(count) == "number" then
            return count
        end
    end
    if type(RD.ListConfigured) == "function" then
        local ok, list = pcall(RD.ListConfigured)
        if ok and type(list) == "table" then
            return #list
        end
    end
    return 0
end

local function _updateRecentTooltip(ach)
    if not ach then
        return
    end
    local node = ach._nvkRecentNode
    local data
    if node and node.GetData then
        data = node:GetData()
    end
    data = data or ach._nvkRecentData
    if not data then
        return
    end

    local count = _countRecent()
    local name = data.name or data.text or (data.categoryData and data.categoryData.name) or "Kürzlich"
    local label = zo_strformat("<<1>>", name)
    local iconTag = (U and U.GetIconTagForTexture and U.GetIconTagForTexture(ICON_PATH_RECENT)) or ""
    local displayLabel = (iconTag ~= "" and (iconTag .. label)) or label
    local line = string.format("%s - %s", displayLabel, ZO_CommaDelimitNumber(count or 0))
    data.isNvkRecent = true
    data.nvkSummaryTooltipText = line
    ach._nvkRecentData = data
end

local function AddRecentCategory(AchClass)
    local orgAddTopLevelCategory = AchClass.AddTopLevelCategory
    function AchClass:AddTopLevelCategory(...)
        local result = orgAddTopLevelCategory(self, ...)
        if not _nvk3ut_is_enabled("recent") then
            return result
        end

        local lookup, tree = self.nodeLookupData, self.categoryTree
        if not (lookup and tree) then
            return result
        end

        if lookup[RECENT_LOOKUP_KEY] then
            local node = lookup[RECENT_LOOKUP_KEY]
            if node and not self._nvkRecentNode then
                self._nvkRecentNode = node
            end
            return result
        end

        local label = "Kürzlich"
        local parentNode =
            self:AddCategory(lookup, tree, "ZO_IconChildlessHeader", nil, NVK3_RECENT, label, false, nil, nil, nil, true, true)
        if not parentNode then
            return result
        end

        lookup[RECENT_LOOKUP_KEY] = parentNode
        self._nvkRecentNode = parentNode
        local row = parentNode.GetData and parentNode:GetData()
        if row then
            row.isNvkRecent = true
            row.nvkSummaryTooltipText = nil
            local plain = row.name or row.text or label
            row.nvkPlainName = row.nvkPlainName or sanitizePlainName(plain)
            self._nvkRecentData = row
        end

        _updateRecentTooltip(self)
        if self.refreshGroups then
            self.refreshGroups:RefreshAll("FullUpdate")
        end

        return result
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
            _updateRecentTooltip(self)
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
            _updateRecentTooltip(self)
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