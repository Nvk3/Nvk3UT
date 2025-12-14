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

    self:ReleaseAllCategories()

    safeDebug("%s: Reset rows", MODULE_TAG)

    return self.rows
end

function Rows:BuildOrRebuildRows(viewModel)
    self.viewModel = viewModel

    -- Reuse existing pooled categories across rebuilds. If we do not have a view model
    -- or it is empty, release anything active and exit early.
    if not (viewModel and viewModel.categories and viewModel.categories.ordered) then
        self:ReleaseAllCategories()

        if type(self.callbacks.UpdateContentSize) == "function" then
            self.callbacks.UpdateContentSize()
        end
        if type(self.callbacks.NotifyHostContentChanged) == "function" then
            self.callbacks.NotifyHostContentChanged()
        end
        if type(self.callbacks.ProcessPendingExternalReveal) == "function" then
            self.callbacks.ProcessPendingExternalReveal()
        end
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

    if type(self.callbacks.UpdateContentSize) == "function" then
        self.callbacks.UpdateContentSize()
    end

    if type(self.callbacks.NotifyHostContentChanged) == "function" then
        self.callbacks.NotifyHostContentChanged()
    end

    if type(self.callbacks.ProcessPendingExternalReveal) == "function" then
        self.callbacks.ProcessPendingExternalReveal()
    end

    local controls = self:GetRowControls()

    safeDebug("%s: BuildOrRebuildRows completed with %d row(s)", MODULE_TAG, #controls)

    return controls
end

function Rows:GetRowControls()
    return self.state and self.state.orderedControls or self.rows or {}
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
        header.currentIndent = nil
        header.baseColor = nil
        header.isExpanded = nil
    end

    if container then
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

Nvk3UT.QuestTrackerRows = Rows

return Rows
