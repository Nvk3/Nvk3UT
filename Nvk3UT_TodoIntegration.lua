Nvk3UT = Nvk3UT or {}

local function _nvk3ut_is_enabled(key)
  return (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.features and Nvk3UT.sv.features[key]) and true or false
end

local Todo = Nvk3UT.TodoData
local U = Nvk3UT and Nvk3UT.Utils

local NVK3_TODO = 84002
local todoProvide_lastTs = 0
local todoProvide_lastCount = 0

local function sanitizePlainName(name)
  if U and U.StripLeadingIconTag then
    name = U.StripLeadingIconTag(name)
  end
  return name
end

-- Add one 'To-Do-Liste' header with subcategories for each basegame top category

local function _todoCollectOpenSummary(topId)
  if not topId or not Todo or type(Todo.ListOpenForTop) ~= "function" then
    return 0, 0
  end

  local ok, ids = pcall(Todo.ListOpenForTop, topId, false)
  if not ok or type(ids) ~= "table" then
    return 0, 0
  end

  local num = #ids
  local points = 0
  for index = 1, num do
    local id = ids[index]
    local infoOk, _name, _desc, score = pcall(GetAchievementInfo, id)
    if infoOk then
      points = points + (score or 0)
    end
  end

  return num, points
end

local function _formatTodoTooltipLine(data, points, iconTag)
  local name = data and (data.name or data.text)
  if not name and data and data.categoryData then
    name = data.categoryData.name or data.categoryData.text
  end
  local label = zo_strformat("<<1>>", name or "")
  local prefix = iconTag or ""
  if prefix ~= "" then
    return string.format("%s%s - %s", prefix, label, ZO_CommaDelimitNumber(points or 0))
  end
  return string.format("%s - %s", label, ZO_CommaDelimitNumber(points or 0))
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
  ach._nvkTodoChildren = orderedChildren

  for idx = 1, #orderedChildren do
    local node = orderedChildren[idx]
    local data = node and node.GetData and node:GetData()
    if data and (data.nvkTodoTopId or data.subcategoryIndex or data.categoryIndex) then
      local topId = data.nvkTodoTopId or data.subcategoryIndex or data.categoryIndex
      data.nvkTodoTopId = topId
      local count, points = _todoCollectOpenSummary(topId)
      if count > 0 then
        local iconTag = (U and U.GetAchievementCategoryIconTag and U.GetAchievementCategoryIconTag(topId)) or ""
        local line = _formatTodoTooltipLine(data, points, iconTag)
        data.isNvkTodo = true
        data.nvkTodoOpenCount = count
        data.nvkTodoOpenPoints = points
        data.nvkSummaryTooltipText = line
        lines[#lines + 1] = line
      else
        data.nvkSummaryTooltipText = nil
      end
    elseif data then
      data.nvkSummaryTooltipText = nil
    end
  end

  parentData.isNvkTodo = true
  if #lines > 0 then
    parentData.nvkSummaryTooltipText = table.concat(lines, "\n")
  end
end

local function AddTodoCategory(AchClass)
  local orgAddTopLevelCategory = AchClass.AddTopLevelCategory
  function AchClass.AddTopLevelCategory(...)
    if not _nvk3ut_is_enabled("todo") then
      return orgAddTopLevelCategory(...)
    end
    if not _nvk3ut_is_enabled("todo") then
      return (select(1, ...)).AddTopLevelCategory and select(1, ...).AddTopLevelCategory(...)
    end
    local self, name = ...
    if name then
      -- On the first real category, append "Abgeschlossen" as the last entry
      if not self._nvk_completed_added then
        self._nvk_completed_added = true
        local lookup, tree = self.nodeLookupData, self.categoryTree
        local nodeTemplate = "ZO_IconHeader"
        local subTemplate = "ZO_TreeLabelSubCategory"
        local labelDone = "Abgeschlossen"
        local parentNodeDone = self:AddCategory(
          lookup,
          tree,
          nodeTemplate,
          nil,
          84003,
          labelDone,
          false,
          nil,
          nil,
          nil,
          true,
          true
        )
        local parentRowDone = parentNodeDone and parentNodeDone.GetData and parentNodeDone:GetData()
        if parentRowDone then
          parentRowDone.nvkPlainName = parentRowDone.nvkPlainName or sanitizePlainName(labelDone)
          parentRowDone.isNvkCompleted = true
        end
        local names, ids = Nvk3UT.CompletedData.GetSubcategoryList()
        for i, n in ipairs(names) do
          local childNode = self:AddCategory(lookup, tree, subTemplate, parentNodeDone, ids[i], n, true)
          local childData = childNode and childNode.GetData and childNode:GetData()
          if childData then
            childData.nvkPlainName = childData.nvkPlainName or sanitizePlainName(n)
            childData.nvkCompletedKey = childData.nvkCompletedKey or ids[i]
            childData.isNvkCompleted = true
          end
        end
      end
      return orgAddTopLevelCategory(...)
    end

    -- Default build path: after base creates roots, add our To-Do header with subcats
    local result = orgAddTopLevelCategory(...)

    local lookup, tree = self.nodeLookupData, self.categoryTree
    local nodeTemplate = "ZO_IconHeader"
    local subTemplate = "ZO_TreeLabelSubCategory"
    local label = "To-Do-Liste"

    local parentNode = self:AddCategory(
      lookup,
      tree,
      nodeTemplate,
      nil,
      NVK3_TODO,
      label,
      false,
      nil,
      nil,
      nil,
      true,
      true
    )
    self._nvkTodoNode = parentNode
    self._nvkTodoChildren = {}
    local _row = parentNode and parentNode.GetData and parentNode:GetData()
    if _row then
      _row.isNvkTodo = true
      _row.nvkSummaryTooltipText = nil
      _row.nvkPlainName = _row.nvkPlainName or sanitizePlainName(label)
    end

    local numTop = GetNumAchievementCategories and GetNumAchievementCategories() or 0
    for top = 1, numTop do
      local ok, topName, nSub, nAch = pcall(GetAchievementCategoryInfo, top)
      if ok and ((nSub and nSub > 0) or (nAch and nAch > 0)) then
        local openCount, openPoints = _todoCollectOpenSummary(top)
        if openCount > 0 then
          local node = self:AddCategory(lookup, tree, subTemplate, parentNode, top, topName, true)
          if self._nvkTodoChildren then
            self._nvkTodoChildren[#self._nvkTodoChildren + 1] = node
          end
          local data = node and node.GetData and node:GetData()
          if data then
            data.isNvkTodo = true
            data.nvkTodoOpenCount = openCount
            data.nvkTodoOpenPoints = openPoints
            data.nvkTodoTopId = top
            data.nvkSummaryTooltipText = nil
            data.nvkPlainName = data.nvkPlainName or sanitizePlainName(topName)
          end
        end
      end
    end

    -- Update tooltip cache so hover text matches immediately.
    _updateTodoTooltip(self)

    if self.refreshGroups then
      self.refreshGroups:RefreshAll("FullUpdate")
    end
    return result
  end
end

local function OverrideOnCategorySelected(AchClass)
  local org = AchClass.OnCategorySelected
  function AchClass.OnCategorySelected(...)
    if not _nvk3ut_is_enabled("todo") then
      return org(...)
    end
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
    if not _nvk3ut_is_enabled("todo") then
      return org(...)
    end
    local self, data, parentData = ...
    if _nvk3ut_is_enabled("todo") and data and data.categoryIndex == NVK3_TODO then
      local ids
      if data.subcategoryIndex then
        ids = Todo.ListOpenForTop(data.subcategoryIndex, true)
      else
        ids = Todo.ListAllOpen(0, true)
      end
      local num, pts = #ids, 0
      for i = 1, num do
        local _, _, _, p = GetAchievementInfo(ids[i])
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
        local __res = Todo.ListOpenForTop(subcategoryIndex, considerSearchResults)
        local U = Nvk3UT and Nvk3UT.Utils
        local __now = (U and U.now and U.now() or 0)
        if
          U
          and U.d
          and Nvk3UT
          and Nvk3UT.sv
          and Nvk3UT.sv.debug
          and ((__now - todoProvide_lastTs) > 0.5 or #__res ~= todoProvide_lastCount)
        then
          todoProvide_lastTs = __now
          todoProvide_lastCount = #__res
          U.d(
            "[Nvk3UT][ToDo][Provide] list",
            "data={count:",
            #__res,
            ", searchFiltered:",
            tostring(considerSearchResults and true or false),
            "}"
          )
        end
        return __res
      else
        local __res = Todo.ListAllOpen(0, considerSearchResults)
        local U = Nvk3UT and Nvk3UT.Utils
        local __now = (U and U.now and U.now() or 0)
        if
          U
          and U.d
          and Nvk3UT
          and Nvk3UT.sv
          and Nvk3UT.sv.debug
          and ((__now - todoProvide_lastTs) > 0.5 or #__res ~= todoProvide_lastCount)
        then
          todoProvide_lastTs = __now
          todoProvide_lastCount = #__res
          U.d(
            "[Nvk3UT][ToDo][Provide] list",
            "data={count:",
            #__res,
            ", searchFiltered:",
            tostring(considerSearchResults and true or false),
            "}"
          )
        end
        return __res
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
