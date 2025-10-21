Nvk3UT = Nvk3UT or {}

local function _nvk3ut_is_enabled(key)
    return (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features[key]) and true or false
end

local Todo = Nvk3UT.TodoData
local U = Nvk3UT and Nvk3UT.Utils

local NVK3_TODO = 84002
local ICON_UP   = "esoui/art/market/keyboard/giftmessageicon_up.dds"
local ICON_DOWN = "esoui/art/market/keyboard/giftmessageicon_down.dds"
local ICON_OVER = "esoui/art/market/keyboard/giftmessageicon_over.dds"

local todoProvide_lastTs, todoProvide_lastCount = 0, -1

local function _isDebug()
    local sv = Nvk3UT and Nvk3UT.sv
    return sv and sv.debug
end

local function _debugLog(...)
    if not _isDebug() then
        return
    end
    if U and U.d then
        U.d(...)
    end
end

local function _todoOpenPointsForTop(topId)
    if not tonumber(topId) then
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

local function _collectOrderedChildren(node)
    local ordered = {}
    if not node then
        return ordered
    end

    if node.GetNumChildren and node.GetChildByIndex then
        local count = node:GetNumChildren()
        for idx = 1, (count or 0) do
            local child = node:GetChildByIndex(idx)
            if child ~= nil then
                ordered[#ordered + 1] = child
            end
        end
    end

    if (#ordered == 0) and node.GetChildren then
        local raw = node:GetChildren()
        if type(raw) == "table" then
            for idx = 1, #raw do
                local child = raw[idx]
                if child ~= nil then
                    ordered[#ordered + 1] = child
                end
            end
        end
    end

    return ordered
end

-- Collect tooltip payloads for the To-Do category whenever its tree is rebuilt so the
-- summary tooltip lists the UI-ordered top categories with their remaining points.
local function _updateTodoTooltip(ach)
    if not ach then
        return
    end

    local parentNode = ach._nvkTodoNode
    if not (parentNode and parentNode.GetData) then
        return
    end

    local parentData = parentNode:GetData()
    if not parentData then
        return
    end

    local orderedChildren = _collectOrderedChildren(parentNode)
    if #orderedChildren == 0 and type(ach._nvkTodoChildren) == "table" then
        for idx = 1, #ach._nvkTodoChildren do
            orderedChildren[#orderedChildren + 1] = ach._nvkTodoChildren[idx]
        end
    elseif #orderedChildren > 0 then
        ach._nvkTodoChildren = orderedChildren
    end

    local lines = {}
    parentData.isNvkTodo = true
    parentData.nvkSummaryTooltipText = nil

    for idx = 1, #orderedChildren do
        local node = orderedChildren[idx]
        local data = node and node.GetData and node:GetData()
        if data then
            data.isNvkTodo = true
            local topId = data.nvkTodoTopId or data.subcategoryIndex
            if topId then
                local points = _todoOpenPointsForTop(topId)
                local line = _formatTodoTooltipLine(data, points)
                data.nvkSummaryTooltipText = line
                lines[#lines + 1] = line
            else
                data.nvkSummaryTooltipText = nil
            end
        end
    end

    if #lines > 0 then
        parentData.nvkSummaryTooltipText = table.concat(lines, "\n")
    end

    if _isDebug() then
        local payload = (#lines == 0) and "lines={}" or string.format("lines={%s}", table.concat(lines, " || "))
        _debugLog("[Nvk3UT][Todo][TooltipData]", payload)
    end
end

local function AddTodoCategory(AchClass)
    local orgAddTopLevelCategory = AchClass.AddTopLevelCategory

    function AchClass:AddTopLevelCategory(...)
        local result = orgAddTopLevelCategory(self, ...)
        if not _nvk3ut_is_enabled("todo") then
            return result
        end

        local name = select(1, ...)
        if name ~= nil then
            return result
        end

        if not Todo then
            return result
        end

        local lookup, tree = self.nodeLookupData, self.categoryTree
        local nodeTemplate = "ZO_IconHeader"
        local subTemplate  = "ZO_TreeLabelSubCategory"

        local parentNode = self:AddCategory(lookup, tree, nodeTemplate, nil, NVK3_TODO, "To-Do-Liste", false, ICON_UP, ICON_DOWN, ICON_OVER, true, true)
        self._nvkTodoNode = parentNode
        self._nvkTodoChildren = {}

        local parentData = parentNode and parentNode.GetData and parentNode:GetData()
        if parentData then
            parentData.isNvkTodo = true
            parentData.nvkSummaryTooltipText = nil
        end

        local numTop = (type(GetNumAchievementCategories) == "function") and GetNumAchievementCategories() or 0
        for top = 1, numTop do
            local topName, numSub, numAch = GetAchievementCategoryInfo(top)
            if (numSub and numSub > 0) or (numAch and numAch > 0) then
                local node = self:AddCategory(lookup, tree, subTemplate, parentNode, top, topName, true)
                if node then
                    self._nvkTodoChildren[#self._nvkTodoChildren + 1] = node
                    local data = node.GetData and node:GetData()
                    if data then
                        data.isNvkTodo = true
                        data.nvkSummaryTooltipText = nil
                        data.nvkTodoTopId = top
                    end
                end
            end
        end

        _updateTodoTooltip(self)

        if self.refreshGroups then
            self.refreshGroups:RefreshAll("FullUpdate")
        end

        return result
    end
end

local function OverrideOnCategorySelected(AchClass)
    local org = AchClass.OnCategorySelected

    function AchClass:OnCategorySelected(data, saveExpanded)
        if _nvk3ut_is_enabled("todo") and data and data.categoryIndex == NVK3_TODO then
            self:HideSummary()
            self:UpdateCategoryLabels(data, true, false)
            _updateTodoTooltip(self)
            return
        end

        return org(self, data, saveExpanded)
    end
end

local function OverrideGetCategoryInfoFromData(AchClass)
    local org = AchClass.GetCategoryInfoFromData

    function AchClass:GetCategoryInfoFromData(data, parentData)
        if _nvk3ut_is_enabled("todo") and data and data.categoryIndex == NVK3_TODO then
            local ids
            if data.subcategoryIndex then
                ids = Todo.ListOpenForTop(data.subcategoryIndex, true) or {}
            else
                ids = Todo.ListAllOpen(0, true) or {}
            end
            local num = #ids
            local points = 0
            for idx = 1, num do
                local _, _, _, pts = GetAchievementInfo(ids[idx])
                points = points + (pts or 0)
            end
            return num, points, 0, 0, 0, 0
        end
        return org(self, data, parentData)
    end
end

local function Override_ZO_GetAchievementIds()
    local base = ZO_GetAchievementIds

    function ZO_GetAchievementIds(categoryIndex, subcategoryIndex, numAchievements, considerSearchResults)
        if categoryIndex == NVK3_TODO then
            local list
            if subcategoryIndex then
                list = Todo.ListOpenForTop(subcategoryIndex, considerSearchResults)
            else
                list = Todo.ListAllOpen(0, considerSearchResults)
            end
            list = list or {}
            if _isDebug() then
                local now = U and U.now and U.now() or GetTimeStamp()
                if (now - todoProvide_lastTs) > 0.5 or #list ~= todoProvide_lastCount then
                    todoProvide_lastTs = now
                    todoProvide_lastCount = #list
                    _debugLog("[Nvk3UT][ToDo][Provide] list", string.format("data={count:%d, searchFiltered:%s}", #list, tostring(considerSearchResults and true or false)))
                end
            end
            return list
        end
        return base(categoryIndex, subcategoryIndex, numAchievements, considerSearchResults)
    end
end

local function OverrideOnAchievementUpdated(AchClass)
    local org = AchClass.OnAchievementUpdated

    function AchClass:OnAchievementUpdated(id)
        local data = self.categoryTree and self.categoryTree:GetSelectedData()
        if _nvk3ut_is_enabled("todo") and data and data.categoryIndex == NVK3_TODO then
            self:UpdateCategoryLabels(data, true, false)
            _updateTodoTooltip(self)
            return
        end
        return org(self, id)
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
