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

    safeDebug("%s: Reset rows", MODULE_TAG)

    return self.rows
end

function Rows:BuildOrRebuildRows(viewModel)
    self.viewModel = viewModel

    if type(self.callbacks.EnsurePools) == "function" then
        self.callbacks.EnsurePools()
    end

    if not (viewModel and viewModel.categories and viewModel.categories.ordered) then
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

    if type(self.callbacks.PrimeInitialSavedState) == "function" then
        self.callbacks.PrimeInitialSavedState()
    end

    for index = 1, #viewModel.categories.ordered do
        local category = viewModel.categories.ordered[index]
        if category and category.quests and #category.quests > 0 then
            if type(self.callbacks.LayoutCategory) == "function" then
                self.callbacks.LayoutCategory(category)
            end
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

Nvk3UT.QuestTrackerRows = Rows

return Rows
