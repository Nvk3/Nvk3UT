
Nvk3UT = Nvk3UT or {}
local function _nvk3ut_is_enabled(key)
  return (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features[key]) and true or false
end
local Todo = Nvk3UT.TodoData
local todoProvide_lastTs, todoProvide_lastCount = 0, -1

local NVK3_TODO = 84002
local ICON_UP   = "esoui/art/market/keyboard/giftmessageicon_up.dds"
local ICON_DOWN = "esoui/art/market/keyboard/giftmessageicon_down.dds"
local ICON_OVER = "esoui/art/market/keyboard/giftmessageicon_over.dds"

-- Add one 'To-Do-Liste' header with subcategories for each basegame top category

local function _todoOpenPointsForTop(topId)
    if not topId then
        return 0
    end
    local ok, _name, _numSub, _numAch, earned, total = pcall(GetAchievementCategoryInfo, topId)
    if not ok then
        return 0
    end
    local open = (total or 0) - (earned or 0)
    if open < 0 then
        open = 0
    end
    return open
end

local function _formatTodoTooltipLine(data, points)
    local name = data and (data.name or data.text)
    if not name and data and data.categoryData then
        name = data.categoryData.name or data.categoryData.text
    end
    local label = zo_strformat("<<1>>", name or "")
    return string.format("%s – %s", label, ZO_CommaDelimitNumber(points or 0))
end

local function _debugTodoTooltip(lines)
    local utils = Nvk3UT and Nvk3UT.Utils
    if not (utils and utils.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug) then
        return
    end

    local payload
    if #lines == 0 then
        payload = "lines={}"
    else
        payload = string.format("lines={%s}", table.concat(lines, " || "))
    end

    utils.d("[Nvk3UT][Todo][TooltipData]", payload)
end

local function _updateTodoTooltip(ach)
    if not ach then
        return
    end
    local parentNode = ach._nvkTodoNode
    local children = ach._nvkTodoChildren
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
    local hasFreshOrder = false

    if parentNode.GetChildren then
        local actualChildren = parentNode:GetChildren()
        if type(actualChildren) == "table" then
            for idx = 1, #actualChildren do
                local node = actualChildren[idx]
                if node ~= nil then
                    orderedChildren[#orderedChildren + 1] = node
                end
            end
            if #orderedChildren == 0 and parentNode.GetNumChildren and parentNode.GetChildByIndex then
                local count = parentNode:GetNumChildren()
                for idx = 1, (count or 0) do
                    local node = parentNode:GetChildByIndex(idx)
                    if node ~= nil then
                        orderedChildren[#orderedChildren + 1] = node
                    end
                end
            end
            hasFreshOrder = (#orderedChildren > 0)
        end
    end

    if (not hasFreshOrder) and type(children) == "table" then
        for idx = 1, #children do
            orderedChildren[#orderedChildren + 1] = children[idx]
        end
    end

    if hasFreshOrder then
        ach._nvkTodoChildren = orderedChildren
    end

    for idx = 1, #orderedChildren do
        local node = orderedChildren[idx]
        local data = node and node.GetData and node:GetData()
        if data then
            local key = data.nvkTodoTopId or data.subcategoryIndex
            if key then
                local points = _todoOpenPointsForTop(key)
                local line = _formatTodoTooltipLine(data, points)
                data.isNvkTodo = true
                data.nvkSummaryTooltipText = line
                lines[#lines + 1] = line
            else
                data.nvkSummaryTooltipText = nil
            end
        end
    end

    parentData.isNvkTodo = true
    if #lines > 0 then
        parentData.nvkSummaryTooltipText = table.concat(lines, "\n")
    end

    _debugTodoTooltip(lines)
end

local function AddTodoCategory(AchClass)
    local orgAddTopLevelCategory = AchClass.AddTopLevelCategory
    function AchClass.AddTopLevelCategory(...)
                if not _nvk3ut_is_enabled("todo") then return orgAddTopLevelCategory(...) end
        if not _nvk3ut_is_enabled("todo") then return (
            select(1, ...)).AddTopLevelCategory and select(1, ...).AddTopLevelCategory(...) end
        local self, name = ...
        if name then
            -- On the first real category, append "Abgeschlossen" as the last entry
            if not self._nvk_completed_added then
                self._nvk_completed_added = true
                local lookup, tree = self.nodeLookupData, self.categoryTree
                local nodeTemplate = "ZO_IconHeader"
                local subTemplate  = "ZO_TreeLabelSubCategory"
                local labelDone    = "Abgeschlossen"
                local parentNodeDone = self:AddCategory(lookup, tree, nodeTemplate, nil, 84003, labelDone, false, ICON_UP, ICON_DOWN, ICON_OVER, true, true)
                local names, ids = Nvk3UT.CompletedData.GetSubcategoryList()
                for i, n in ipairs(names) do
                    self:AddCategory(lookup, tree, subTemplate, parentNodeDone, ids[i], n, true)
                end
            end
            return orgAddTopLevelCategory(...)
        end

        -- Default build path: after base creates roots, add our To-Do header with subcats
        local result = orgAddTopLevelCategory(...)

        local lookup, tree = self.nodeLookupData, self.categoryTree
        local nodeTemplate = "ZO_IconHeader"
        local subTemplate  = "ZO_TreeLabelSubCategory"
        local label        = "To-Do-Liste"

        local parentNode = self:AddCategory(lookup, tree, nodeTemplate, nil, NVK3_TODO, label, false, ICON_UP, ICON_DOWN, ICON_OVER, true, true)
        self._nvkTodoNode = parentNode
        self._nvkTodoChildren = {}
        local _row = parentNode and parentNode.GetData and parentNode:GetData()
        if _row then
            _row.isNvkTodo = true
            _row.nvkSummaryTooltipText = nil
        end

        local numTop = GetNumAchievementCategories and GetNumAchievementCategories() or 0
        for top=1,numTop do
            local topName, nSub, nAch = GetAchievementCategoryInfo(top)
            if (nSub and nSub>0) or (nAch and nAch>0) then
                local node = self:AddCategory(lookup, tree, subTemplate, parentNode, top, topName, true)
                if self._nvkTodoChildren then
                    self._nvkTodoChildren[#self._nvkTodoChildren + 1] = node
                end
                local data = node and node.GetData and node:GetData()
                if data then
                    data.isNvkTodo = true
                    data.nvkSummaryTooltipText = nil
                    data.nvkTodoTopId = top
                end
            end
        end

        -- Update tooltip cache so hover text matches immediately.
        _updateTodoTooltip(self)

        if self.refreshGroups then self.refreshGroups:RefreshAll("FullUpdate") end
        return result
    end
end


local function OverrideOnCategorySelected(AchClass)
    local org = AchClass.OnCategorySelected
    function AchClass.OnCategorySelected(...)
                if not _nvk3ut_is_enabled("todo") then return org(...) end
        local self, data, saveExpanded = ...
        if _nvk3ut_is_enabled("todo") and data and data.categoryIndex == NVK3_TODO then
            self:HideSummary()
            self:UpdateCategoryLabels(data, true, false)
            _updateTodoTooltip(self)
        else
            return org(...)
        end
    end
end

local function OverrideGetCategoryInfoFromData(AchClass)
    local org = AchClass.GetCategoryInfoFromData
    function AchClass.GetCategoryInfoFromData(...)
                if not _nvk3ut_is_enabled("todo") then return org(...) end
        local self, data, parentData = ...
        if _nvk3ut_is_enabled("todo") and data and data.categoryIndex == NVK3_TODO then
            local ids
            if data.subcategoryIndex then
                ids = Todo.ListOpenForTop(data.subcategoryIndex, true)
            else
                ids = Todo.ListAllOpen(0, true)
            end
            local num, pts = #ids, 0
            for i=1,num do
                local _,_,_,p = GetAchievementInfo(ids[i])
                pts = pts + (p or 0)
            end
            return num, pts, 0, 0, 0, 0
        end
        return org(...)
    end
end

local function Override_ZO_GetAchievementIds()
    local base = ZO_GetAchievementIds
    function ZO_GetAchievementIds(categoryIndex, subcategoryIndex, numAchievements, considerSearchResults)
        if categoryIndex == NVK3_TODO then
            if subcategoryIndex then
                local __res = Todo.ListOpenForTop(subcategoryIndex, considerSearchResults); local U = Nvk3UT and Nvk3UT.Utils; local __now = (U and U.now and U.now() or 0); if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug and ((__now - todoProvide_lastTs) > 0.5 or #__res ~= todoProvide_lastCount) then todoProvide_lastTs = __now; todoProvide_lastCount = #__res; U.d("[Nvk3UT][ToDo][Provide] list", "data={count:", #__res, ", searchFiltered:", tostring(considerSearchResults and true or false), "}") end; return __res
            else
                local __res = Todo.ListAllOpen(0, considerSearchResults); local U = Nvk3UT and Nvk3UT.Utils; local __now = (U and U.now and U.now() or 0); if U and U.d and Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug and ((__now - todoProvide_lastTs) > 0.5 or #__res ~= todoProvide_lastCount) then todoProvide_lastTs = __now; todoProvide_lastCount = #__res; U.d("[Nvk3UT][ToDo][Provide] list", "data={count:", #__res, ", searchFiltered:", tostring(considerSearchResults and true or false), "}") end; return __res
            end
        end
        return base(categoryIndex, subcategoryIndex, numAchievements, considerSearchResults)
    end
end

local function OverrideOnAchievementUpdated(AchClass)
    local org = AchClass.OnAchievementUpdated
    function AchClass.OnAchievementUpdated(...)
        local self, id = ...
        local data = self.categoryTree:GetSelectedData()
        if _nvk3ut_is_enabled("todo") and data and data.categoryIndex == NVK3_TODO then
            self:UpdateCategoryLabels(data, true, false)
            _updateTodoTooltip(self)
        else
            return org(...)
        end
    end
end

function Nvk3UT_EnableTodoCategory()
    local AchClass = getmetatable(ACHIEVEMENTS).__index
    AddTodoCategory(AchClass)
    OverrideOnCategorySelected(AchClass)
    OverrideGetCategoryInfoFromData(AchClass)
    Override_ZO_GetAchievementIds()
    OverrideOnAchievementUpdated(AchClass)
end