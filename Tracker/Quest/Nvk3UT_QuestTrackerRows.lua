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

function Rows:Reset()
    if not self.state then
        self.rows = {}
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

    self:ReleaseAllRows()
    self:ReleaseAllCategories()

    safeDebug("%s: Reset rows", MODULE_TAG)

    return self.rows
end

function Rows:BuildOrRebuildRows(viewModel)
    self.viewModel = viewModel

    self:ReleaseAllRows()

    -- Reuse existing pooled categories across rebuilds. If we do not have a view model
    -- or it is empty, release anything active and exit early.
    if not (viewModel and viewModel.categories and viewModel.categories.ordered) then
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
    for index = 1, #viewModel.categories.ordered do
        local category = viewModel.categories.ordered[index]
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

    row.objectiveControls = row.objectiveControls or {}

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
    row.poolKey = nil
    row.rowType = "quest"

    if row.objectiveControls then
        for index = 1, #row.objectiveControls do
            local objectiveControl = row.objectiveControls[index]
            if objectiveControl then
                if objectiveControl.ClearAnchors then
                    objectiveControl:ClearAnchors()
                end
                if objectiveControl.SetParent then
                    objectiveControl:SetParent(self.parent)
                end
                if objectiveControl.SetHidden then
                    objectiveControl:SetHidden(true)
                end
                if objectiveControl.label and objectiveControl.label.SetText then
                    objectiveControl.label:SetText("")
                end
            end
            row.objectiveControls[index] = nil
        end
    end

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

Nvk3UT.QuestTrackerRows = Rows

return Rows
