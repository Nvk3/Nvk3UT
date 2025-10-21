Nvk3UT = Nvk3UT or {}
local function _nvk3ut_is_enabled(key)
  return (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features[key]) and true or false
end
local Comp = Nvk3UT.CompletedData

local compProvide_lastTs, compProvide_lastCount = 0, -1
local NVK3_DONE = 84003
local ICON_UP   = "esoui/art/market/keyboard/giftmessageicon_up.dds"
local ICON_DOWN = "esoui/art/market/keyboard/giftmessageicon_down.dds"
local ICON_OVER = "esoui/art/market/keyboard/giftmessageicon_over.dds"

local function _formatCompletedTooltipLine(data, points)
    local name = data and (data.name or data.text)
    if not name and data and data.categoryData then
        name = data.categoryData.name or data.categoryData.text
    end
    local label = zo_strformat("<<1>>", name or "")
    local value = ZO_CommaDelimitNumber(points or 0)
    return string.format("%s – %s", label, value)
end

local function _completedPointsForKey(key)
    if not (Comp and Comp.SummaryCountAndPointsForKey) then
        return 0
    end
    local ok, count, points = pcall(Comp.SummaryCountAndPointsForKey, key)
    if ok then
        if type(points) == "number" then
            return points
        end
        if type(count) == "number" then
            return count
        end
    end
    return 0
end

local function _updateCompletedTooltip(ach)
    if not ach or not Comp then
        return
    end

    local parentNode = ach._nvkCompletedNode
    local children = ach._nvkCompletedChildren
    if not parentNode or not parentNode.GetData then
        return
    end

    local parentData = parentNode:GetData()
    if not parentData then
        return
    end
    parentData.nvkSummaryTooltipText = nil

    local lines = {}
    local orderedChildren = {}
    if parentNode.GetChildren then
        local actualChildren = parentNode:GetChildren()
        if type(actualChildren) == "table" then
            for idx = 1, #actualChildren do
                orderedChildren[#orderedChildren + 1] = actualChildren[idx]
            end
        end
    end
    if #orderedChildren == 0 and type(children) == "table" then
        for idx = 1, #children do
            orderedChildren[#orderedChildren + 1] = children[idx]
        end
    end
    ach._nvkCompletedChildren = orderedChildren

    for idx = 1, #orderedChildren do
        local node = orderedChildren[idx]
        local data = node and node.GetData and node:GetData()
        if data and data.subcategoryIndex then
            local pts = _completedPointsForKey(data.subcategoryIndex)
            local line = _formatCompletedTooltipLine(data, pts)
            data.isNvkCompleted = true
            data.nvkSummaryTooltipText = line
            lines[#lines + 1] = line
        elseif data then
            data.nvkSummaryTooltipText = nil
        end
    end

    parentData.isNvkCompleted = true
    if #lines > 0 then
        parentData.nvkSummaryTooltipText = table.concat(lines, "\n")
    end
end

local function AddCompletedCategory(AchClass)
    local orgAddTopLevelCategory = AchClass.AddTopLevelCategory
    function AchClass.AddTopLevelCategory(...)
                if not _nvk3ut_is_enabled("completed") then return orgAddTopLevelCategory(...) end
        if not _nvk3ut_is_enabled("completed") then return (
            select(1, ...)).AddTopLevelCategory and select(1, ...).AddTopLevelCategory(...) end
        local self, name = ...
        local result = orgAddTopLevelCategory(...)
        if name then local U = Nvk3UT and Nvk3UT.Utils; local __now = (U and U.now and U.now() or 0); if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug and ((__now - compProvide_lastTs) > 0.5 or #result ~= compProvide_lastCount) then compProvide_lastTs = __now; compProvide_lastCount = #result; U.d("[Nvk3UT][Completed][Provide] list", "data={count:", #result, ", searchFiltered:", tostring(considerSearchResults and true or false), "}") end; return result end

        local lookup, tree = self.nodeLookupData, self.categoryTree
        local nodeTemplate = "ZO_IconHeader"
        local subTemplate  = "ZO_TreeLabelSubCategory"
        local label        = "Abgeschlossen"

        local parentNode = self:AddCategory(lookup, tree, nodeTemplate, nil, NVK3_DONE, label, false, ICON_UP, ICON_DOWN, ICON_OVER, true, true)

        self._nvkCompletedNode = parentNode
        self._nvkCompletedChildren = {}

        local _row = parentNode and parentNode.GetData and parentNode:GetData()
        if _row then
            _row.isNvkCompleted = true
            _row.nvkSummaryTooltipText = nil
        end

        local names, ids = Comp.GetSubcategoryList()
        for i, n in ipairs(names) do
            local node = self:AddCategory(lookup, tree, subTemplate, parentNode, ids[i], n, true)
            if self._nvkCompletedChildren then
                self._nvkCompletedChildren[#self._nvkCompletedChildren + 1] = node
            end
            local data = node and node.GetData and node:GetData()
            if data then
                data.isNvkCompleted = true
                data.nvkSummaryTooltipText = nil
            end
        end

        -- Collect tooltip data immediately so hover state matches the freshly built tree.
        _updateCompletedTooltip(self)

        if self.refreshGroups then self.refreshGroups:RefreshAll("FullUpdate") end
        return result
    end
end

local function OverrideOnCategorySelected(AchClass)
    local org = AchClass.OnCategorySelected
    function AchClass.OnCategorySelected(...)
                if not _nvk3ut_is_enabled("completed") then return org(...) end
        local self, data, saveExpanded = ...
        if _nvk3ut_is_enabled("completed") and data and data.categoryIndex == NVK3_DONE then
            self:HideSummary()
            self:UpdateCategoryLabels(data, true, false)
            _updateCompletedTooltip(self)
            if Nvk3UT and Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then Nvk3UT.UI.UpdateStatus() end
        else
            local __r = org(...)
            if Nvk3UT and Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then Nvk3UT.UI.UpdateStatus() end
            return __r
        end
    end
end

local function OverrideGetCategoryInfoFromData(AchClass)
    local org = AchClass.GetCategoryInfoFromData
    function AchClass.GetCategoryInfoFromData(...)
                if not _nvk3ut_is_enabled("completed") then return org(...) end
        local self, data, parentData = ...
        if _nvk3ut_is_enabled("completed") and data and data.categoryIndex == NVK3_DONE then
            local idx = data.subcategoryIndex or Comp.Constants().LAST50_KEY
            local num, pts = Comp.SummaryCountAndPointsForKey(idx)
            return num, pts, 0, 0, 0, 0
        end
        return org(...)
    end
end

local function Override_ZO_GetAchievementIds()
    local base = ZO_GetAchievementIds
    function ZO_GetAchievementIds(categoryIndex, subcategoryIndex, numAchievements, considerSearchResults)
        if categoryIndex == NVK3_DONE then
            local idx = subcategoryIndex or Comp.Constants().LAST50_KEY
            return Comp.ListForKey(idx)
        end
        return base(categoryIndex, subcategoryIndex, numAchievements, considerSearchResults)
    end
end

local function OverrideOnAchievementUpdated(AchClass)
    local org = AchClass.OnAchievementUpdated
    function AchClass.OnAchievementUpdated(...)
        local self, id = ...
        local data = self.categoryTree:GetSelectedData()
        if _nvk3ut_is_enabled("completed") and data and data.categoryIndex == NVK3_DONE then
            Comp.Rebuild()
            self:UpdateCategoryLabels(data, true, false)
            _updateCompletedTooltip(self)
            if Nvk3UT and Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then Nvk3UT.UI.UpdateStatus() end
        else
            local __r = org(...)
            if Nvk3UT and Nvk3UT.UI and Nvk3UT.UI.UpdateStatus then Nvk3UT.UI.UpdateStatus() end
            return __r
        end
    end
end

function Nvk3UT_EnableCompletedCategory()
    local AchClass = getmetatable(ACHIEVEMENTS).__index
    AddCompletedCategory(AchClass)
    OverrideOnCategorySelected(AchClass)
    OverrideGetCategoryInfoFromData(AchClass)
    Override_ZO_GetAchievementIds()
    OverrideOnAchievementUpdated(AchClass)
end