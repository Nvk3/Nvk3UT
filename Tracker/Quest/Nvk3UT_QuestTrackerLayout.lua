local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Layout = {}
Layout.__index = Layout

local MODULE_TAG = addonName .. ".QuestTrackerLayout"

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

function Layout:Init(trackerState, deps)
    self.state = trackerState
    self.deps = deps or {}

    self.verticalPadding = deps.VERTICAL_PADDING or 0

    safeDebug("%s: Init layout helper", MODULE_TAG)
end

function Layout:ResetLayoutState()
    local state = self.state or {}
    state.orderedControls = {}
    state.lastAnchoredControl = nil
    state.categoryControls = {}
    state.questControls = {}
    state.contentWidth = 0
    state.contentHeight = 0
end

function Layout:AnchorControl(control, indentX)
    local state = self.state or {}
    indentX = indentX or 0

    control:ClearAnchors()

    if state.lastAnchoredControl then
        local previousIndent = state.lastAnchoredControl.currentIndent or 0
        local offsetX = indentX - previousIndent
        control:SetAnchor(TOPLEFT, state.lastAnchoredControl, BOTTOMLEFT, offsetX, self.verticalPadding)
        control:SetAnchor(TOPRIGHT, state.lastAnchoredControl, BOTTOMRIGHT, 0, self.verticalPadding)
    else
        control:SetAnchor(TOPLEFT, state.container, TOPLEFT, indentX, 0)
        control:SetAnchor(TOPRIGHT, state.container, TOPRIGHT, 0, 0)
    end

    state.lastAnchoredControl = control
    state.orderedControls[#state.orderedControls + 1] = control
    control.currentIndent = indentX
end

function Layout:UpdateContentSize()
    local state = self.state or {}
    local RefreshControlMetrics = self.deps.RefreshControlMetrics

    local maxWidth = 0
    local totalHeight = 0
    local visibleCount = 0

    for index = 1, #state.orderedControls do
        local control = state.orderedControls[index]
        if RefreshControlMetrics then
            RefreshControlMetrics(control)
        end
        if control and not control:IsHidden() then
            visibleCount = visibleCount + 1
            local width = (control:GetWidth() or 0) + (control.currentIndent or 0)
            if width > maxWidth then
                maxWidth = width
            end
            totalHeight = totalHeight + (control:GetHeight() or 0)
            if visibleCount > 1 then
                totalHeight = totalHeight + self.verticalPadding
            end
        end
    end

    state.contentWidth = maxWidth
    state.contentHeight = totalHeight

    safeDebug(
        "%s: UpdateContentSize controls=%d width=%s height=%s",
        MODULE_TAG,
        #state.orderedControls,
        tostring(state.contentWidth),
        tostring(state.contentHeight)
    )
end

function Layout:LayoutCondition(condition)
    if not (self.deps.ShouldDisplayCondition and self.deps.ShouldDisplayCondition(condition)) then
        return
    end

    local AcquireConditionControl = self.deps.AcquireConditionControl
    local FormatConditionText = self.deps.FormatConditionText
    local GetQuestTrackerColor = self.deps.GetQuestTrackerColor
    local ApplyRowMetrics = self.deps.ApplyRowMetrics

    local control = AcquireConditionControl and AcquireConditionControl()
    if not control then
        return
    end

    control.data = { condition = condition }
    if control.label and FormatConditionText then
        control.label:SetText(FormatConditionText(condition))
    end
    if control.label and GetQuestTrackerColor then
        local r, g, b, a = GetQuestTrackerColor("objectiveText")
        control.label:SetColor(r, g, b, a)
    end
    if ApplyRowMetrics then
        ApplyRowMetrics(control, self.deps.CONDITION_INDENT_X, 0, 0, 0, self.deps.CONDITION_MIN_HEIGHT)
    end
    control:SetHidden(false)
    self:AnchorControl(control, self.deps.CONDITION_INDENT_X)
end

function Layout:LayoutQuest(quest)
    local AcquireQuestControl = self.deps.AcquireQuestControl
    local AcquireQuestRow = self.deps.AcquireQuestRow
    local DetermineQuestColorRole = self.deps.DetermineQuestColorRole
    local GetQuestTrackerColor = self.deps.GetQuestTrackerColor
    local ApplyBaseColor = self.deps.ApplyBaseColor
    local UpdateQuestIconSlot = self.deps.UpdateQuestIconSlot
    local ApplyRowMetrics = self.deps.ApplyRowMetrics
    local IsQuestExpanded = self.deps.IsQuestExpanded
    local LayoutCondition = function(condition)
        self:LayoutCondition(condition)
    end

    local providedControl = AcquireQuestRow and AcquireQuestRow()
    local control = AcquireQuestControl and AcquireQuestControl(providedControl)
    if not control then
        return
    end

    control.data = { quest = quest }
    control.questJournalIndex = quest and quest.journalIndex
    control.questKey = self.deps.NormalizeQuestKey and self.deps.NormalizeQuestKey(quest and quest.journalIndex)
    control.categoryKey = quest and quest.categoryKey
    if control.label then
        control.label:SetText(quest and quest.name or "")
    end

    if DetermineQuestColorRole and GetQuestTrackerColor and ApplyBaseColor then
        local colorRole = DetermineQuestColorRole(quest)
        local r, g, b, a = GetQuestTrackerColor(colorRole)
        ApplyBaseColor(control, r, g, b, a)
    end

    local questKey = control.questKey
    local expanded = IsQuestExpanded and IsQuestExpanded(quest and quest.journalIndex)
    safeDebug(
        "%s: Layout quest=%s expanded=%s",
        MODULE_TAG,
        tostring(questKey or (quest and quest.journalIndex)),
        tostring(expanded)
    )

    if UpdateQuestIconSlot then
        UpdateQuestIconSlot(control)
    end
    if ApplyRowMetrics then
        ApplyRowMetrics(
            control,
            self.deps.QUEST_INDENT_X,
            self.deps.QUEST_ICON_SLOT_WIDTH,
            self.deps.QUEST_ICON_SLOT_PADDING_X,
            0,
            self.deps.QUEST_MIN_HEIGHT
        )
    end
    control:SetHidden(false)
    self:AnchorControl(control, self.deps.QUEST_INDENT_X)

    local state = self.state or {}
    if quest and quest.journalIndex then
        state.questControls[quest.journalIndex] = control
    end

    if expanded and quest and quest.steps then
        for stepIndex = 1, #quest.steps do
            local step = quest.steps[stepIndex]
            if step.isVisible ~= false and step.conditions then
                for conditionIndex = 1, #step.conditions do
                    LayoutCondition(step.conditions[conditionIndex])
                end
            end
        end
    end
end

function Layout:LayoutCategory(category, providedControl)
    local AcquireCategoryControl = self.deps.AcquireCategoryControl
    local FormatCategoryHeaderText = self.deps.FormatCategoryHeaderText
    local ShouldShowQuestCategoryCounts = self.deps.ShouldShowQuestCategoryCounts
    local IsCategoryExpanded = self.deps.IsCategoryExpanded
    local GetQuestTrackerColor = self.deps.GetQuestTrackerColor
    local ApplyBaseColor = self.deps.ApplyBaseColor
    local UpdateCategoryToggle = self.deps.UpdateCategoryToggle
    local ApplyRowMetrics = self.deps.ApplyRowMetrics

    local control = AcquireCategoryControl and AcquireCategoryControl(providedControl)
    if not control then
        return
    end

    control.data = {
        categoryKey = category.key,
        parentKey = category.parent and category.parent.key or nil,
        parentName = category.parent and category.parent.name or nil,
        groupKey = category.groupKey,
        groupName = category.groupName,
        categoryType = category.type,
        groupOrder = category.groupOrder,
    }
    control.categoryKey = category.key

    local state = self.state or {}
    local normalizedKey = self.deps.NormalizeCategoryKey and self.deps.NormalizeCategoryKey(category.key)
    if normalizedKey then
        state.categoryControls[normalizedKey] = control
    end

    local count = #category.quests
    if control.label and FormatCategoryHeaderText then
        control.label:SetText(FormatCategoryHeaderText(category.name or "", count, ShouldShowQuestCategoryCounts and ShouldShowQuestCategoryCounts()))
    end

    local expanded = IsCategoryExpanded and IsCategoryExpanded(category.key)
    safeDebug("%s: Layout cat=%s expanded=%s", MODULE_TAG, tostring(category.key), tostring(expanded))

    if GetQuestTrackerColor and ApplyBaseColor then
        local colorRole = expanded and "activeTitle" or "categoryTitle"
        local r, g, b, a = GetQuestTrackerColor(colorRole)
        ApplyBaseColor(control, r, g, b, a)
    end
    if UpdateCategoryToggle then
        UpdateCategoryToggle(control, expanded)
    end
    if ApplyRowMetrics then
        ApplyRowMetrics(
            control,
            self.deps.CATEGORY_INDENT_X,
            self.deps.GetToggleWidth and self.deps.GetToggleWidth(control.toggle, self.deps.CATEGORY_TOGGLE_WIDTH)
                or (self.deps.CATEGORY_TOGGLE_WIDTH or 0),
            self.deps.TOGGLE_LABEL_PADDING_X,
            0,
            self.deps.CATEGORY_MIN_HEIGHT
        )
    end
    control:SetHidden(false)
    self:AnchorControl(control, self.deps.CATEGORY_INDENT_X)

    if expanded and category.quests then
        for index = 1, count do
            self:LayoutQuest(category.quests[index])
        end
    end
end

function Layout:ReleaseRowControl(control)
    local state = self.state or {}
    if not control then
        return
    end

    local rowType = control.rowType
    if rowType == "category" then
        local normalized = control.data and self.deps.NormalizeCategoryKey and self.deps.NormalizeCategoryKey(control.data.categoryKey)
        if normalized and state.categoryControls then
            state.categoryControls[normalized] = nil
        end
        if state.categoryPool and control.poolKey then
            state.categoryPool:ReleaseObject(control.poolKey)
        end
    elseif rowType == "quest" then
        local questData = control.data and control.data.quest
        if questData and questData.journalIndex and state.questControls then
            state.questControls[questData.journalIndex] = nil
        end
        if state.questPool and control.poolKey then
            state.questPool:ReleaseObject(control.poolKey)
        end
    else
        if state.conditionPool and control.poolKey then
            state.conditionPool:ReleaseObject(control.poolKey)
        end
    end
end

function Layout:TrimOrderedControlsToCategory(keepCategoryCount)
    local state = self.state or {}
    local ReleaseAll = self.deps.ReleaseAll

    if keepCategoryCount <= 0 then
        if ReleaseAll then
            ReleaseAll(state.categoryPool)
            ReleaseAll(state.questPool)
            ReleaseAll(state.conditionPool)
        end
        self:ResetLayoutState()
        return
    end

    local categoryCounter = 0
    local releaseStartIndex = nil

    for index = 1, #state.orderedControls do
        local control = state.orderedControls[index]
        if control and control.rowType == "category" then
            categoryCounter = categoryCounter + 1
            if categoryCounter > keepCategoryCount then
                releaseStartIndex = index
                break
            end
        end
    end

    if releaseStartIndex then
        for index = #state.orderedControls, releaseStartIndex, -1 do
            self:ReleaseRowControl(state.orderedControls[index])
            table.remove(state.orderedControls, index)
        end
    end

    state.lastAnchoredControl = state.orderedControls[#state.orderedControls]
end

function Layout:RelayoutFromCategoryIndex(startCategoryIndex)
    local state = self.state or {}
    local ApplyActiveQuestFromSaved = self.deps.ApplyActiveQuestFromSaved
    local EnsurePools = self.deps.EnsurePools
    local ReleaseAll = self.deps.ReleaseAll
    local PrimeInitialSavedState = self.deps.PrimeInitialSavedState
    local NotifyHostContentChanged = self.deps.NotifyHostContentChanged
    local ProcessPendingExternalReveal = self.deps.ProcessPendingExternalReveal

    if ApplyActiveQuestFromSaved then
        ApplyActiveQuestFromSaved()
    end
    if EnsurePools then
        EnsurePools()
    end

    if
        not state.snapshot
        or not state.snapshot.categories
        or not state.snapshot.categories.ordered
        or #state.snapshot.categories.ordered == 0
    then
        if ReleaseAll then
            ReleaseAll(state.categoryPool)
            ReleaseAll(state.questPool)
            ReleaseAll(state.conditionPool)
        end
        self:ResetLayoutState()
        self:UpdateContentSize()
        if NotifyHostContentChanged then
            NotifyHostContentChanged()
        end
        if ProcessPendingExternalReveal then
            ProcessPendingExternalReveal()
        end
        return
    end

    if startCategoryIndex <= 1 then
        if ReleaseAll then
            ReleaseAll(state.categoryPool)
            ReleaseAll(state.questPool)
            ReleaseAll(state.conditionPool)
        end
        self:ResetLayoutState()
        startCategoryIndex = 1
    else
        self:TrimOrderedControlsToCategory(startCategoryIndex - 1)
    end

    if PrimeInitialSavedState then
        PrimeInitialSavedState()
    end

    for index = startCategoryIndex, #state.snapshot.categories.ordered do
        local category = state.snapshot.categories.ordered[index]
        if category and category.quests and #category.quests > 0 then
            self:LayoutCategory(category)
        end
    end

    self:UpdateContentSize()
    if NotifyHostContentChanged then
        NotifyHostContentChanged()
    end
    if ProcessPendingExternalReveal then
        ProcessPendingExternalReveal()
    end
end

function Layout:ApplyLayout(parentContainer, categoryControls, rowControls)
    if parentContainer and self.state then
        self.state.container = parentContainer
    end

    if categoryControls and type(categoryControls) == "table" then
        safeDebug("%s: ApplyLayout using provided controls (%d categories)", MODULE_TAG, #categoryControls)
    else
        safeDebug("%s: ApplyLayout using current snapshot", MODULE_TAG)
    end

    if self.state and (rowControls or (self.state.orderedControls and #self.state.orderedControls > 0)) then
        self:UpdateContentSize()
        if self.deps.NotifyHostContentChanged then
            self.deps.NotifyHostContentChanged()
        end
        if self.deps.ProcessPendingExternalReveal then
            self.deps.ProcessPendingExternalReveal()
        end
        return rowControls or self.state.orderedControls
    end

    self:RelayoutFromCategoryIndex(1)
    return self.state and self.state.orderedControls or {}
end

function Layout:GetCategoryControls()
    local state = self.state or {}
    return state.categoryControls
end

Nvk3UT.QuestTrackerLayout = Layout

return Layout
