local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local MODULE_TAG = addonName .. ".QuestTrackerRows"

local function getAddon()
    return rawget(_G, addonName)
end

local function safeDebug(message, ...)
    local addon = getAddon()
    local debugFn = addon and addon.Debug

    if type(debugFn) ~= "function" then
        return
    end

    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, message, ...)
        if ok then
            debugFn(formatted)
        else
            debugFn(message)
        end
    else
        debugFn(message)
    end
end

function Rows:Init(parentContainer, trackerState, callbacks)
    self.parent = parentContainer
    self.state = trackerState
    self.callbacks = callbacks or {}
    self.rows = (trackerState and trackerState.orderedControls) or {}
    self.activeRowsByCategory = {}
    self.categoryPool = {
        freeCategories = {},
        activeCategories = {},
    }
    self.questPool = {
        freeRows = {},
        activeRows = {},
    }

    safeDebug("%s: Init with parent %s", MODULE_TAG, tostring(parentContainer))
end

function Rows:AcquireCategoryRow()
    local control, container = self:AcquireCategory()
    if control then
        control._categoryContainer = container
    end
    return control
end

function Rows:ReleaseCategoryRow(control)
    if not control then
        return
    end
    local container = control._categoryContainer
    control._categoryContainer = nil
    self:ReleaseCategory(control, container)
end

function Rows:AcquireObjectiveRow()
    local acquire = self.callbacks and self.callbacks.AcquireConditionControl
    if type(acquire) == "function" then
        return acquire()
    end
    local pool = self.state and self.state.conditionPool
    if not pool then
        return nil
    end
    local control, key = pool:AcquireObject()
    if control then
        control.poolKey = key
    end
    return control
end

function Rows:ReleaseObjectiveRow(control)
    if not control then
        return
    end
    local pool = self.state and self.state.conditionPool
    if pool and control.poolKey then
        pool:ReleaseObject(control.poolKey)
    end
end

function Rows:ApplyObjectiveRow(control, condition)
    if not (control and control.label) then
        return
    end

    control.data = { condition = condition }
    local formatFn = self.callbacks and self.callbacks.FormatConditionText
    if formatFn then
        control.label:SetText(formatFn(condition))
    else
        local text = condition and (condition.displayText or condition.text) or ""
        control.label:SetText(text or "")
    end

    local getColor = self.callbacks and self.callbacks.GetQuestTrackerColor
    if getColor then
        local r, g, b, a = getColor("objectiveText")
        control.label:SetColor(r, g, b, a)
    end
end

function Rows:Reset()
    if not self.state then
        self.rows = {}
        self.activeRowsByCategory = {}
        return self.rows
    end

    local releaseAll = self.callbacks.ReleaseAll
    if type(releaseAll) == "function" then
        releaseAll(self.state.categoryPool)
        releaseAll(self.state.questPool)
        releaseAll(self.state.conditionPool)
    end

    if type(self.callbacks.ResetLayoutState) == "function" then
        self.callbacks.ResetLayoutState()
    end

    self.rows = self.state.orderedControls or {}
    self.viewModel = nil
    self.activeRowsByCategory = {}

    self:ReleaseAllRows()
    self:ReleaseAllCategories()

    safeDebug("%s: Reset rows", MODULE_TAG)

    return self.rows
end

function Rows:BuildOrRebuildRows(viewModel)
    self.viewModel = viewModel

    if type(self.callbacks.ResetLayoutState) == "function" then
        self.callbacks.ResetLayoutState()
    end

    self:ReleaseAllRows()
    self.activeRowsByCategory = {}

    -- Reuse existing pooled categories across rebuilds. If we do not have a view model
    -- or it is empty, release anything active and exit early.
    if not (viewModel and type(viewModel.categories) == "table") then
        self:ReleaseAllCategories()
        return self:GetRowControls()
    end

    if type(self.callbacks.EnsurePools) == "function" then
        self.callbacks.EnsurePools()
    end

    if type(self.callbacks.PrimeInitialSavedState) == "function" then
        self.callbacks.PrimeInitialSavedState()
    end

    -- Start from a clean active set each rebuild so we reuse pooled controls without leaving
    -- stale headers/containers anchored.
    self:ReleaseAllCategories()

    local usedCategoryCount = 0
    for index = 1, #viewModel.categories do
        local category = viewModel.categories[index]
        if category and category.quests and #category.quests > 0 then
            usedCategoryCount = usedCategoryCount + 1
            local header, container = self:AcquireCategory()
            if type(self.callbacks.LayoutCategory) == "function" then
                self.callbacks.LayoutCategory(category, header, container)
            end
        end
    end

    -- Return any unused active categories to the pool so repeated rebuilds do not leak controls.
    if usedCategoryCount < #self.categoryPool.activeCategories then
        for index = #self.categoryPool.activeCategories, usedCategoryCount + 1, -1 do
            local category = table.remove(self.categoryPool.activeCategories, index)
            self:ReleaseCategory(category.header, category.container)
        end
    end

    local controls = self:GetRowControls()

    safeDebug(
        "%s: BuildOrRebuildRows completed with %d row(s); questPool active=%d free=%d",
        MODULE_TAG,
        #controls,
        self.questPool and #self.questPool.activeRows or 0,
        self.questPool and #self.questPool.freeRows or 0
    )

    return controls
end

function Rows:GetRowControls()
    return self.state and self.state.orderedControls or self.rows or {}
end

function Rows:GetCategoryControls()
    local categoryControls = {}
    if self.categoryPool and self.categoryPool.activeCategories then
        for index = 1, #self.categoryPool.activeCategories do
            categoryControls[#categoryControls + 1] = self.categoryPool.activeCategories[index].header
        end
    end
    return categoryControls
end

function Rows:RegisterQuestRow(row, categoryKey)
    if not row then
        return
    end

    categoryKey = categoryKey or row.categoryKey
    if not categoryKey then
        return
    end

    self.activeRowsByCategory = self.activeRowsByCategory or {}

    if row.categoryKey and row.categoryKey ~= categoryKey then
        local previous = self.activeRowsByCategory[row.categoryKey]
        if previous then
            for index = #previous, 1, -1 do
                if previous[index] == row then
                    table.remove(previous, index)
                end
            end
            if #previous == 0 then
                self.activeRowsByCategory[row.categoryKey] = nil
            end
        end
    end

    row.categoryKey = categoryKey
    local bucket = self.activeRowsByCategory[categoryKey]
    if not bucket then
        bucket = {}
        self.activeRowsByCategory[categoryKey] = bucket
    end

    for index = 1, #bucket do
        if bucket[index] == row then
            return
        end
    end

    bucket[#bucket + 1] = row
end

function Rows:GetActiveRowsByCategory()
    return self.activeRowsByCategory or {}
end

function Rows:AcquireCategory()
    if not self.categoryPool then
        self.categoryPool = {
            freeCategories = {},
            activeCategories = {},
        }
    end

    local category = table.remove(self.categoryPool.freeCategories)
    local header = category and category.header or nil
    local container = category and category.container or nil

    if not header then
        local headerNameBase = self.parent and self.parent.GetName and self.parent:GetName() or MODULE_TAG
        local index = (#self.categoryPool.activeCategories) + (#self.categoryPool.freeCategories) + 1
        local headerName = string.format("%s_CategoryHeader_%d", headerNameBase, index)
        header = CreateControlFromVirtual(headerName, self.parent, "CategoryHeader_Template")
        header.rowType = "category"
        container = CreateControl(headerName .. "_Container", self.parent, CT_CONTROL)
    end

    if header.ClearAnchors then
        header:ClearAnchors()
    end
    if container and container.ClearAnchors then
        container:ClearAnchors()
    end

    if header.SetHidden then
        header:SetHidden(true)
    end
    if container and container.SetHidden then
        container:SetHidden(true)
    end

    table.insert(self.categoryPool.activeCategories, { header = header, container = container })

    return header, container
end

function Rows:ReleaseCategory(header, container)
    if not self.categoryPool then
        return
    end

    for index, category in ipairs(self.categoryPool.activeCategories) do
        if category.header == header and category.container == container then
            table.remove(self.categoryPool.activeCategories, index)
            break
        end
    end

    if header then
        if header.ClearAnchors then
            header:ClearAnchors()
        end
        if header.SetHidden then
            header:SetHidden(true)
        end
        header.data = nil
        header.categoryKey = nil
        header.currentIndent = nil
        header.baseColor = nil
        header.isExpanded = false
        if header.toggle and header.toggle.SetTexture then
            header.toggle:SetTexture("EsoUI/Art/Buttons/tree_closed_up.dds")
        end
    end

    if container then
        if container.GetNumChildren then
            for childIndex = container:GetNumChildren(), 1, -1 do
                local child = container:GetChild(childIndex)
                if child then
                    if child.rowType == "quest" then
                        self:ReleaseQuestRow(child)
                    end
                    if child.ClearAnchors then
                        child:ClearAnchors()
                    end
                    if child.SetParent then
                        child:SetParent(self.parent)
                    end
                    if child.SetHidden then
                        child:SetHidden(true)
                    end
                end
            end
        end
        if container.ClearAnchors then
            container:ClearAnchors()
        end
        if container.SetHidden then
            container:SetHidden(true)
        end
        container.data = nil
    end

    table.insert(self.categoryPool.freeCategories, { header = header, container = container })
end

function Rows:ReleaseAllCategories()
    if not self.categoryPool then
        return
    end

    while #self.categoryPool.activeCategories > 0 do
        local category = table.remove(self.categoryPool.activeCategories)
        self:ReleaseCategory(category.header, category.container)
    end
end

function Rows:AcquireQuestRow()
    if not self.questPool then
        self.questPool = {
            freeRows = {},
            activeRows = {},
        }
    end

    local row = table.remove(self.questPool.freeRows)
    local created = false
    local name

    if not row then
        local nameBase = self.parent and self.parent.GetName and self.parent:GetName() or MODULE_TAG
        local index = (#self.questPool.activeRows) + (#self.questPool.freeRows) + 1
        name = string.format("%s_QuestRow_%d", nameBase, index)
        row = CreateControlFromVirtual(name, self.parent, "QuestHeader_Template")
        created = true
    else
        name = row.GetName and row:GetName() or "<questRow>"
    end

    if row.ClearAnchors then
        row:ClearAnchors()
    end
    if row.SetHidden then
        row:SetHidden(false)
    end

    row.rowType = "quest"
    table.insert(self.questPool.activeRows, row)

    safeDebug(
        "%s: AcquireQuestRow %s (%s)",
        MODULE_TAG,
        tostring(name),
        created and "new" or "reused"
    )

    return row
end

function Rows:ReleaseQuestRow(row)
    if not (self.questPool and row) then
        return
    end

    if self.activeRowsByCategory then
        local categoryKey = row.categoryKey
        local bucket = categoryKey and self.activeRowsByCategory[categoryKey]
        if bucket then
            for index = #bucket, 1, -1 do
                if bucket[index] == row then
                    table.remove(bucket, index)
                end
            end
            if #bucket == 0 then
                self.activeRowsByCategory[categoryKey] = nil
            end
        end
    end

    for index, active in ipairs(self.questPool.activeRows) do
        if active == row then
            table.remove(self.questPool.activeRows, index)
            break
        end
    end

    if row.ClearAnchors then
        row:ClearAnchors()
    end
    if row.SetParent then
        row:SetParent(self.parent)
    end
    if row.SetHidden then
        row:SetHidden(true)
    end

    row.data = nil
    row.questJournalIndex = nil
    row.questKey = nil
    row.categoryKey = nil
    row.questId = nil
    row.objectiveCount = nil
    row.poolKey = nil
    row.rowType = "quest"

    if row.iconSlot then
        if row.iconSlot.SetTexture then
            row.iconSlot:SetTexture(nil)
        end
        if row.iconSlot.SetAlpha then
            row.iconSlot:SetAlpha(0)
        end
        if row.iconSlot.SetHidden then
            row.iconSlot:SetHidden(false)
        end
    end
    if row.label and row.label.SetText then
        row.label:SetText("")
    end

    safeDebug("%s: ReleaseQuestRow %s", MODULE_TAG, row.GetName and row:GetName() or "<questRow>")

    table.insert(self.questPool.freeRows, row)
end

function Rows:ReleaseAllRows()
    if not self.questPool then
        return
    end

    while #self.questPool.activeRows > 0 do
        local row = table.remove(self.questPool.activeRows)
        self:ReleaseQuestRow(row)
    end
end

function Rows:SetCategoryRowsVisible(categoryKey, visible)
    if not categoryKey then
        return
    end

    local rowsByCategory = self.activeRowsByCategory or {}
    local rows = rowsByCategory[categoryKey]
    if not rows or #rows == 0 then
        return
    end

    for index = 1, #rows do
        local row = rows[index]
        if row then
            if row.SetHidden then
                row:SetHidden(not visible)
            end
            if not visible and row.ClearAnchors then
                row:ClearAnchors()
            end
        end
    end
end

Nvk3UT.QuestTrackerRows = Rows

return Rows
