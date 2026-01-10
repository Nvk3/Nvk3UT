local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Layout = {}
Layout.__index = Layout

local MODULE_TAG = addonName .. ".QuestTrackerLayout"

local function getAddon()
    return rawget(_G, addonName)
end

local function isDebugEnabled()
    local utils = (Nvk3UT and Nvk3UT.Utils) or Nvk3UT_Utils
    if utils and type(utils.IsDebugEnabled) == "function" then
        return utils:IsDebugEnabled()
    end

    local diagnostics = (Nvk3UT and Nvk3UT.Diagnostics) or Nvk3UT_Diagnostics
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        return diagnostics:IsDebugEnabled()
    end

    local addon = Nvk3UT
    if addon and type(addon.IsDebugEnabled) == "function" then
        return addon:IsDebugEnabled()
    end

    return false
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

local function getHostViewportInfo()
    local host = Nvk3UT and Nvk3UT.TrackerHost
    local align = "left"
    local scrollbarSide = "right"
    local leftInset = 0
    local rightInset = 0
    local viewportWidth

    if host and type(host.GetContentAlignment) == "function" then
        local ok, value = pcall(host.GetContentAlignment, host)
        if ok and type(value) == "string" and value ~= "" then
            align = string.lower(value)
        end
    end

    if host and type(host.GetScrollbarSide) == "function" then
        local ok, value = pcall(host.GetScrollbarSide, host)
        if ok and type(value) == "string" and value ~= "" then
            scrollbarSide = string.lower(value)
        end
    end

    if host and type(host.GetViewportInsets) == "function" then
        local ok, leftValue, rightValue = pcall(host.GetViewportInsets, host)
        if ok then
            leftInset = tonumber(leftValue) or leftInset
            rightInset = tonumber(rightValue) or rightInset
        end
    end

    if host and type(host.GetViewportWidth) == "function" then
        local ok, width = pcall(host.GetViewportWidth, host)
        if ok and type(width) == "number" then
            viewportWidth = width
        end
    end

    return {
        align = align,
        scrollbarSide = scrollbarSide,
        leftInset = leftInset,
        rightInset = rightInset,
        viewportWidth = viewportWidth,
    }
end

function Layout:Init(trackerState, deps)
    self.state = trackerState
    self.deps = deps or {}

    self.verticalPadding = deps.VERTICAL_PADDING or 0
    self.categoryBottomPadExpanded = deps.CATEGORY_BOTTOM_PAD_EXPANDED or 0
    self.categoryBottomPadCollapsed = deps.CATEGORY_BOTTOM_PAD_COLLAPSED or 0
    self.bottomPixelNudge = deps.BOTTOM_PIXEL_NUDGE or 0
    self.categorySpacingAbove = deps.CATEGORY_SPACING_ABOVE
    if self.categorySpacingAbove == nil then
        self.categorySpacingAbove = self.verticalPadding
    end
    self.categorySpacingBelow = deps.CATEGORY_SPACING_BELOW
    if self.categorySpacingBelow == nil then
        self.categorySpacingBelow = self.categoryBottomPadExpanded or 0
    end
    self.entrySpacingAbove = deps.ENTRY_SPACING_ABOVE
    if self.entrySpacingAbove == nil then
        self.entrySpacingAbove = self.verticalPadding
    end
    self.entrySpacingBelow = deps.ENTRY_SPACING_BELOW
    if self.entrySpacingBelow == nil then
        self.entrySpacingBelow = self.verticalPadding
    end
    self.objectiveSpacingAbove = deps.OBJECTIVE_SPACING_ABOVE
    if self.objectiveSpacingAbove == nil then
        self.objectiveSpacingAbove = self.verticalPadding
    end
    self.objectiveSpacingBelow = deps.OBJECTIVE_SPACING_BELOW
    if self.objectiveSpacingBelow == nil then
        self.objectiveSpacingBelow = self.verticalPadding
    end
    self.objectiveSpacingBetween = deps.OBJECTIVE_SPACING_BETWEEN
    if self.objectiveSpacingBetween == nil then
        self.objectiveSpacingBetween = self.verticalPadding
    end

    safeDebug("%s: Init layout helper", MODULE_TAG)
end

function Layout:ResetLayoutState()
    local state = self.state or {}
    state.orderedControls = {}
    state.lastAnchoredControl = nil
    state.pendingCategoryGap = nil
    state.pendingEntryGap = nil
    state.visibleRowCount = 0
    state.categoryControls = {}
    state.questControls = {}
    state.contentWidth = 0
    state.contentHeight = 0
    state.debugRowLogCount = 0
    state.categoryAlignLogged = false
    state.entryAlignLogged = false
    state.objectiveAlignLogged = false
    state.anchorHygieneLogged = false
    state.lastAnchorY = 0
    state.rightExpandedCategoryCount = 0
    state.rightExpandedChevronTexture = nil
    state.rightExpandedChevronRotation = nil
    state.rightExpandedLogEmitted = false
    self.rowsByCategory = nil
end

function Layout:GetContainerWidth()
    local container = self.state and self.state.container
    if not container or not container.GetWidth then
        return 0
    end

    local width = container:GetWidth()
    if not width or width <= 0 then
        return 0
    end

    return width
end

function Layout:GetViewportWidth()
    local info = getHostViewportInfo()
    if info.viewportWidth ~= nil then
        return info.viewportWidth
    end

    return self:GetContainerWidth()
end

function Layout:GetCategoryBottomPadding(expanded)
    if expanded then
        return self.categoryBottomPadExpanded
    end

    return self.categoryBottomPadCollapsed
end

function Layout:ConsumePendingCategoryGap()
    local state = self.state or {}
    local gap = state.pendingCategoryGap
    state.pendingCategoryGap = nil
    return gap
end

function Layout:ConsumePendingEntryGap()
    local state = self.state or {}
    local gap = state.pendingEntryGap
    state.pendingEntryGap = nil
    return gap
end

function Layout:SetPendingCategoryGap(expanded)
    local state = self.state or {}
    local gap = self.categorySpacingBelow
    if type(gap) ~= "number" then
        gap = self:GetCategoryBottomPadding(expanded)
    end
    state.pendingCategoryGap = gap
end

function Layout:SetPendingEntryGap()
    local state = self.state or {}
    local gap = self.entrySpacingBelow
    if type(gap) ~= "number" then
        gap = self.verticalPadding
    end
    state.pendingEntryGap = gap
end

function Layout:ComputeRowHeight(control, indent, toggleWidth, leftPadding, rightPadding, minHeight, widthOverride)
    if not control or not control.label then
        return 0
    end

    indent = indent or 0
    toggleWidth = toggleWidth or 0
    leftPadding = leftPadding or 0
    rightPadding = rightPadding or 0

    local targetWidth = widthOverride
    if type(targetWidth) ~= "number" or targetWidth <= 0 then
        targetWidth = self:GetContainerWidth()
    end

    local availableWidth = targetWidth - indent - toggleWidth - leftPadding - rightPadding
    if availableWidth < 0 then
        availableWidth = 0
    end

    control.label:SetWidth(availableWidth)

    local textHeight = control.label:GetTextHeight() or 0
    local targetHeight = textHeight + (self.deps.ROW_TEXT_PADDING_Y or 0)
    if minHeight then
        targetHeight = math.max(minHeight, targetHeight)
    end

    control:SetHeight(targetHeight)

    return targetHeight
end

function Layout:GetObjectiveSpacing(prevRowType, rowType)
    if not prevRowType or not rowType then
        return 0
    end

    local prevIsObjective = prevRowType == "condition"
    local currentIsObjective = rowType == "condition"

    if currentIsObjective then
        if prevIsObjective then
            return tonumber(self.objectiveSpacingBetween) or 0
        end
        return tonumber(self.objectiveSpacingAbove) or 0
    end

    if prevIsObjective then
        return tonumber(self.objectiveSpacingBelow) or 0
    end

    return 0
end

function Layout:BuildFlatRowList(viewModel)
    local rows = {}
    local categories = viewModel and viewModel.categories
    if type(categories) ~= "table" then
        return rows
    end

    local IsCategoryExpanded = self.deps.IsCategoryExpanded
    local IsQuestExpanded = self.deps.IsQuestExpanded
    local ShouldDisplayCondition = self.deps.ShouldDisplayCondition

    for index = 1, #categories do
        local category = categories[index]
        if category and category.quests and #category.quests > 0 then
            local expanded = IsCategoryExpanded and IsCategoryExpanded(category.key)
            rows[#rows + 1] = {
                rowType = "category",
                category = category,
                expanded = expanded == true,
            }

            if expanded then
                for questIndex = 1, #category.quests do
                    local quest = category.quests[questIndex]
                    if quest then
                        rows[#rows + 1] = {
                            rowType = "quest",
                            quest = quest,
                            category = category,
                        }

                        local questExpanded = IsQuestExpanded and IsQuestExpanded(quest.journalIndex)
                        if questExpanded and quest.steps then
                            for stepIndex = 1, #quest.steps do
                                local step = quest.steps[stepIndex]
                                if step and step.isVisible ~= false and step.conditions then
                                    for conditionIndex = 1, #step.conditions do
                                        local condition = step.conditions[conditionIndex]
                                        if not ShouldDisplayCondition or ShouldDisplayCondition(condition) then
                                            rows[#rows + 1] = {
                                                rowType = "condition",
                                                quest = quest,
                                                category = category,
                                                condition = condition,
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return rows
end

function Layout:ApplyCategoryAlignment(control, expanded)
    if not (control and control.label and control.toggle) then
        return
    end

    local info = getHostViewportInfo()
    local align = info.align
    local indent = tonumber(self.deps.CATEGORY_INDENT_X) or 0
    local padding = tonumber(self.deps.TOGGLE_LABEL_PADDING_X) or 0

    if control.indentAnchor and control.indentAnchor.SetAnchor then
        control.indentAnchor:ClearAnchors()
        if align == "right" then
            control.indentAnchor:SetAnchor(TOPRIGHT, control, TOPRIGHT, -indent, 0)
        else
            control.indentAnchor:SetAnchor(TOPLEFT, control, TOPLEFT, indent, 0)
        end
    end

    control.toggle:ClearAnchors()
    if align == "right" then
        control.toggle:SetAnchor(TOPRIGHT, control.indentAnchor or control, TOPRIGHT, 0, 0)
    else
        control.toggle:SetAnchor(TOPLEFT, control.indentAnchor or control, TOPLEFT, 0, 0)
    end

    if control.label then
        control.label:ClearAnchors()
        if align == "right" then
            control.label:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
            control.label:SetAnchor(TOPRIGHT, control.toggle, TOPLEFT, -padding, 0)
            control.label:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
        else
            control.label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
            control.label:SetAnchor(TOPLEFT, control.toggle, TOPRIGHT, padding, 0)
            control.label:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
        end
    end

    if control.toggle.SetTextureRotation then
        local rotation = 0
        if align == "right" and not expanded then
            rotation = math.pi
        end
        control.toggle:SetTextureRotation(rotation, 0.5, 0.5)
    end
end

function Layout:ApplyQuestEntryAlignment(control)
    if not (control and control.label and control.label.ClearAnchors) then
        return
    end

    local info = getHostViewportInfo()
    local align = info.align
    local padding = tonumber(self.deps.QUEST_ICON_SLOT_PADDING_X) or 0
    local iconSlot = control.iconSlot

    if iconSlot and iconSlot.ClearAnchors then
        iconSlot:ClearAnchors()
        if align == "right" then
            iconSlot:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
        else
            iconSlot:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
        end
    end

    control.label:ClearAnchors()
    if align == "right" then
        control.label:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
        if iconSlot then
            control.label:SetAnchor(TOPRIGHT, iconSlot, TOPLEFT, -padding, 0)
        else
            control.label:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
        end
        control.label:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
    else
        control.label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
        if iconSlot then
            control.label:SetAnchor(TOPLEFT, iconSlot, TOPRIGHT, padding, 0)
        else
            control.label:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
        end
        control.label:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
    end
end

function Layout:ApplyConditionAlignment(control)
    if not (control and control.label and control.label.SetHorizontalAlignment) then
        return
    end

    local info = getHostViewportInfo()
    if control.label.ClearAnchors then
        control.label:ClearAnchors()
        control.label:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
        control.label:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
    end
    if info.align == "right" then
        control.label:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    else
        control.label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    end
end

function Layout:LogRowMetrics(control, indentX)
    if not (control and control.label) then
        return
    end

    local state = self.state or {}
    local maxLogs = self.deps.DEBUG_ROW_LOG_COUNT or 10
    if maxLogs <= 0 then
        return
    end
    if not isDebugEnabled() then
        return
    end
    if (state.debugRowLogCount or 0) >= maxLogs then
        return
    end

    local labelWidth = control.label.GetWidth and control.label:GetWidth()
    local textHeight = control.label.GetTextHeight and control.label:GetTextHeight()
    local controlHeight = control.GetHeight and control:GetHeight()

    state.debugRowLogCount = (state.debugRowLogCount or 0) + 1
    safeDebug(
        "%s: RowMetrics #%d type=%s labelWidth=%s textHeight=%s controlHeight=%s indentX=%s",
        MODULE_TAG,
        state.debugRowLogCount,
        tostring(control.rowType),
        tostring(labelWidth),
        tostring(textHeight),
        tostring(controlHeight),
        tostring(indentX)
    )
end

function Layout:ApplyRowDescriptor(rowDescriptor, providedControl)
    if not rowDescriptor then
        return nil
    end

    local rowType = rowDescriptor.rowType

    if rowType == "category" then
        local AcquireCategoryControl = self.deps.AcquireCategoryControl
        local control = AcquireCategoryControl and AcquireCategoryControl(providedControl)
        if not control then
            return nil
        end

        local category = rowDescriptor.category or {}
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

        local count = category.quests and #category.quests or 0
        local FormatCategoryHeaderText = self.deps.FormatCategoryHeaderText
        local ShouldShowQuestCategoryCounts = self.deps.ShouldShowQuestCategoryCounts
        if control.label and FormatCategoryHeaderText then
            control.label:SetText(FormatCategoryHeaderText(category.name or "", count, ShouldShowQuestCategoryCounts and ShouldShowQuestCategoryCounts()))
        end

        local expanded = rowDescriptor.expanded == true
        control.isExpanded = expanded

        local GetQuestTrackerColor = self.deps.GetQuestTrackerColor
        local ApplyBaseColor = self.deps.ApplyBaseColor
        if GetQuestTrackerColor and ApplyBaseColor then
            local colorRole = expanded and "activeTitle" or "categoryTitle"
            local r, g, b, a = GetQuestTrackerColor(colorRole)
            ApplyBaseColor(control, r, g, b, a)
        end

        local UpdateCategoryToggle = self.deps.UpdateCategoryToggle
        if UpdateCategoryToggle then
            UpdateCategoryToggle(control, expanded)
        end

        self:ApplyCategoryAlignment(control, expanded)
        self:GetCategoryHeaderHeight(control)
        control:SetHidden(false)

        local host = Nvk3UT and Nvk3UT.TrackerHost
        local alignInfo = getHostViewportInfo()
        if alignInfo.align == "right" and expanded and control.toggle then
            local texturePath
            local rotation
            if host and type(host.ApplyChevronVisualTopRightExpanded) == "function" then
                texturePath, rotation = host.ApplyChevronVisualTopRightExpanded(control.toggle)
            end

            local layoutState = self.state or {}
            layoutState.rightExpandedCategoryCount = (layoutState.rightExpandedCategoryCount or 0) + 1
            if layoutState.rightExpandedChevronTexture == nil then
                if texturePath == nil and control.toggle.GetTextureFileName then
                    local okTexture, resolved = pcall(control.toggle.GetTextureFileName, control.toggle)
                    if okTexture then
                        texturePath = resolved
                    end
                end
                layoutState.rightExpandedChevronTexture = texturePath
                layoutState.rightExpandedChevronRotation = rotation
            end
        end

        local state = self.state or {}
        if not state.categoryAlignLogged and isDebugEnabled() then
            local info = getHostViewportInfo()
            local width = self:GetViewportWidth()
            safeDebug(
                "%s: Category align=%s scrollbar=%s insets=(%s,%s) rowWidth=%s",
                MODULE_TAG,
                tostring(info.align),
                tostring(info.scrollbarSide),
                tostring(info.leftInset),
                tostring(info.rightInset),
                tostring(width)
            )
            state.categoryAlignLogged = true
        end

        return control, 0
    elseif rowType == "quest" then
        local AcquireQuestControl = self.deps.AcquireQuestControl
        local control = AcquireQuestControl and AcquireQuestControl(providedControl)
        if not control then
            return nil
        end

        if self.deps.ResetQuestRowObjectives then
            self.deps.ResetQuestRowObjectives(control)
        end

        local quest = rowDescriptor.quest or {}
        control.data = { quest = quest }
        control.questJournalIndex = quest and quest.journalIndex
        control.questKey = self.deps.NormalizeQuestKey and self.deps.NormalizeQuestKey(quest and quest.journalIndex)
        control.categoryKey = quest and quest.categoryKey
        if control.label then
            control.label:SetText(quest and quest.name or "")
        end

        if self.deps.RegisterQuestRow then
            self.deps.RegisterQuestRow(control, control.categoryKey)
        end

        local DetermineQuestColorRole = self.deps.DetermineQuestColorRole
        local GetQuestTrackerColor = self.deps.GetQuestTrackerColor
        local ApplyBaseColor = self.deps.ApplyBaseColor
        if DetermineQuestColorRole and GetQuestTrackerColor and ApplyBaseColor then
            local colorRole = DetermineQuestColorRole(quest)
            local r, g, b, a = GetQuestTrackerColor(colorRole)
            ApplyBaseColor(control, r, g, b, a)
        end

        local questKey = control.questKey
        local IsQuestExpanded = self.deps.IsQuestExpanded
        local expanded = IsQuestExpanded and IsQuestExpanded(quest and quest.journalIndex)
        safeDebug(
            "%s: Layout quest=%s expanded=%s",
            MODULE_TAG,
            tostring(questKey or (quest and quest.journalIndex)),
            tostring(expanded)
        )

        if self.deps.UpdateQuestIconSlot then
            self.deps.UpdateQuestIconSlot(control)
        end
        self:ApplyQuestEntryAlignment(control)
        self:GetQuestRowHeight(control, control.data)
        control:SetHidden(false)

        local state = self.state or {}
        if not state.entryAlignLogged and isDebugEnabled() then
            local info = getHostViewportInfo()
            local wrapperWidth
            local host = Nvk3UT and Nvk3UT.TrackerHost
            if host and type(host.GetScrollContent) == "function" then
                local okContent, scrollContent = pcall(host.GetScrollContent, host)
                if okContent and scrollContent and scrollContent.GetWidth then
                    local okWidth, measured = pcall(scrollContent.GetWidth, scrollContent)
                    if okWidth then
                        wrapperWidth = tonumber(measured)
                    end
                end
            end
            if wrapperWidth == nil and control.GetParent then
                local parent = control:GetParent()
                if parent and parent.GetWidth then
                    local okWidth, measured = pcall(parent.GetWidth, parent)
                    if okWidth then
                        wrapperWidth = tonumber(measured)
                    end
                end
            end

            local labelWidth
            if control.label and control.label.GetWidth then
                local okWidth, measured = pcall(control.label.GetWidth, control.label)
                if okWidth then
                    labelWidth = tonumber(measured)
                end
            end

            local iconUsage = "slot"
            if control.iconSlot then
                local hasTexture = false
                if control.iconSlot.GetTextureFileName then
                    local okTexture, texture = pcall(control.iconSlot.GetTextureFileName, control.iconSlot)
                    if okTexture and type(texture) == "string" and texture ~= "" then
                        hasTexture = true
                    end
                end
                if not hasTexture and control.iconSlot.GetAlpha then
                    local okAlpha, alpha = pcall(control.iconSlot.GetAlpha, control.iconSlot)
                    if okAlpha and type(alpha) == "number" and alpha > 0 then
                        hasTexture = true
                    end
                end
                iconUsage = hasTexture and "real" or "slot"
            end

            safeDebug(
                "%s: Entry align=%s wrapperWidth=%s labelWidth=%s icon=%s anchors=%s",
                MODULE_TAG,
                tostring(info.align),
                tostring(wrapperWidth),
                tostring(labelWidth),
                tostring(iconUsage),
                tostring(info.align)
            )
            state.entryAlignLogged = true
        end

        if quest and quest.journalIndex then
            state.questControls[quest.journalIndex] = control
        end

        return control, self.deps.QUEST_INDENT_X or 0
    elseif rowType == "condition" then
        local AcquireObjectiveRow = self.deps.AcquireObjectiveRow
        local control = AcquireObjectiveRow and AcquireObjectiveRow()
        if not control then
            return nil
        end

        if self.deps.ApplyObjectiveRow then
            self.deps.ApplyObjectiveRow(control, rowDescriptor.condition)
        else
            control.data = { condition = rowDescriptor.condition }
            local FormatConditionText = self.deps.FormatConditionText
            if control.label and FormatConditionText then
                control.label:SetText(FormatConditionText(rowDescriptor.condition))
            end
            local GetQuestTrackerColor = self.deps.GetQuestTrackerColor
            if control.label and GetQuestTrackerColor then
                local r, g, b, a = GetQuestTrackerColor("objectiveText")
                control.label:SetColor(r, g, b, a)
            end
        end

        control.categoryKey = rowDescriptor.category and rowDescriptor.category.key or nil
        self:ApplyConditionAlignment(control)
        self:GetConditionHeight(control)
        control:SetHidden(false)

        local state = self.state or {}
        if not state.objectiveAlignLogged and isDebugEnabled() then
            local info = getHostViewportInfo()
            local wrapperWidth
            local host = Nvk3UT and Nvk3UT.TrackerHost
            if host and type(host.GetScrollContent) == "function" then
                local okContent, scrollContent = pcall(host.GetScrollContent, host)
                if okContent and scrollContent and scrollContent.GetWidth then
                    local okWidth, measured = pcall(scrollContent.GetWidth, scrollContent)
                    if okWidth then
                        wrapperWidth = tonumber(measured)
                    end
                end
            end
            if wrapperWidth == nil and control.GetParent then
                local parent = control:GetParent()
                if parent and parent.GetWidth then
                    local okWidth, measured = pcall(parent.GetWidth, parent)
                    if okWidth then
                        wrapperWidth = tonumber(measured)
                    end
                end
            end

            local labelWidth
            if control.label and control.label.GetWidth then
                local okWidth, measured = pcall(control.label.GetWidth, control.label)
                if okWidth then
                    labelWidth = tonumber(measured)
                end
            end

            local baseOffset = self.deps and self.deps.OBJECTIVE_BASE_INDENT
            safeDebug(
                "%s: Objective align=%s wrapperWidth=%s labelWidth=%s baseOffset=%s side=%s",
                MODULE_TAG,
                tostring(info.align),
                tostring(wrapperWidth),
                tostring(labelWidth),
                tostring(baseOffset),
                tostring(info.align)
            )
            state.objectiveAlignLogged = true
        end

        return control, self.deps.CONDITION_INDENT_X or 0
    end

    return nil
end

function Layout:GetCategoryHeaderHeight(categoryControl)
    if not categoryControl then
        return 0
    end

    local toggleWidth = 0
    if categoryControl.toggle then
        local GetToggleWidth = self.deps.GetToggleWidth
        toggleWidth = GetToggleWidth and GetToggleWidth(categoryControl.toggle, self.deps.CATEGORY_TOGGLE_WIDTH)
            or (self.deps.CATEGORY_TOGGLE_WIDTH or 0)
    end

    return self:ComputeRowHeight(
        categoryControl,
        self.deps.CATEGORY_INDENT_X,
        toggleWidth,
        self.deps.TOGGLE_LABEL_PADDING_X,
        0,
        self.deps.CATEGORY_MIN_HEIGHT,
        self:GetViewportWidth()
    )
end

function Layout:GetQuestRowHeight(rowControl, rowData)
    if not rowControl then
        return 0
    end

    return self:ComputeRowHeight(
        rowControl,
        self.deps.QUEST_INDENT_X,
        self.deps.QUEST_ICON_SLOT_WIDTH,
        self.deps.QUEST_ICON_SLOT_PADDING_X,
        0,
        self.deps.QUEST_MIN_HEIGHT
    )
end

function Layout:GetObjectiveTextHeight(conditionControl, objective)
    if not conditionControl then
        return 0
    end

    local label = conditionControl.label
    if label then
        local text = label.GetText and label:GetText()
        if not text or text == "" then
            text = objective
            if type(objective) == "table" then
                text = objective.displayText or objective.text or ""
            end
        end
        label:SetText(text or "")
    end

    return self:ComputeRowHeight(
        conditionControl,
        self.deps.CONDITION_INDENT_X,
        0,
        0,
        0,
        self.deps.CONDITION_MIN_HEIGHT
    )
end

function Layout:GetQuestRowContentHeight(rowControl, rowData)
    if not rowControl then
        return 0
    end

    return self:GetQuestRowHeight(rowControl, rowData and rowData.quest)
end

function Layout:GetConditionHeight(conditionControl)
    if not conditionControl then
        return 0
    end

    return self:GetObjectiveTextHeight(conditionControl, conditionControl.data and conditionControl.data.condition)
end

function Layout:GetCategoryTotalHeight(categoryControl, rowsInCategory)
    local headerHeight = self:GetCategoryHeaderHeight(categoryControl)
    local totalHeight = headerHeight
    local questCount = 0

    if rowsInCategory then
        for index = 1, #rowsInCategory do
            local row = rowsInCategory[index]
            local rowType = row and row.rowType
            local rowHeight = 0

            if rowType == "quest" then
                rowHeight = self:GetQuestRowContentHeight(row, row and row.data)
                questCount = questCount + 1
            elseif rowType == "condition" then
                rowHeight = self:GetConditionHeight(row, row and row.data and row.data.condition)
            else
                rowHeight = row and row.GetHeight and row:GetHeight() or 0
            end

            if rowHeight > 0 then
                totalHeight = totalHeight + self.verticalPadding + rowHeight
            end
        end
    end

    if headerHeight > 0 then
        totalHeight = totalHeight + self:GetCategoryBottomPadding(categoryControl and categoryControl.isExpanded)
    end

    return totalHeight, questCount
end

function Layout:AnchorControl(control, indentX, gapOverride)
    local state = self.state or {}
    indentX = indentX or 0

    control:ClearAnchors()
    local rowType = control.rowType
    local info = getHostViewportInfo()
    local align = info.align

    local gap = gapOverride
    if type(gap) ~= "number" then
        local isFirst = (state.visibleRowCount or 0) == 0
        local pendingGap = nil
        local pendingEntryGap = nil
        local previousRowType = state.lastAnchoredControl and state.lastAnchoredControl.rowType

        if not isFirst then
            pendingGap = self:ConsumePendingCategoryGap()
            pendingEntryGap = self:ConsumePendingEntryGap()
        end

        if type(pendingGap) == "number" then
            gap = pendingGap
        elseif rowType == "category" then
            gap = 0
        else
            gap = self.verticalPadding
        end

        if type(pendingEntryGap) == "number" then
            gap = gap + pendingEntryGap
        end

        gap = gap + self:GetObjectiveSpacing(previousRowType, rowType)

        if rowType == "category" then
            local aboveGap = self.categorySpacingAbove
            if type(aboveGap) ~= "number" then
                aboveGap = self.verticalPadding
            end
            gap = gap + aboveGap
        elseif rowType == "quest" then
            local aboveGap = self.entrySpacingAbove
            if type(aboveGap) ~= "number" then
                aboveGap = self.verticalPadding
            end
            gap = gap + aboveGap
        end
    end

    local currentY
    if state.lastAnchoredControl then
        local previousHeight = state.lastAnchoredControl.GetHeight and state.lastAnchoredControl:GetHeight() or 0
        currentY = (state.lastAnchorY or 0) + previousHeight + gap
    else
        currentY = gap
    end

    if rowType == "condition" and align == "right" then
        control:SetAnchor(TOPLEFT, state.container, TOPLEFT, 0, currentY)
        control:SetAnchor(TOPRIGHT, state.container, TOPRIGHT, -indentX, currentY)
    else
        control:SetAnchor(TOPLEFT, state.container, TOPLEFT, indentX, currentY)
        control:SetAnchor(TOPRIGHT, state.container, TOPRIGHT, 0, currentY)
    end

    state.lastAnchoredControl = control
    state.orderedControls[#state.orderedControls + 1] = control
    control.currentIndent = indentX
    state.lastAnchorY = currentY
    state.visibleRowCount = (state.visibleRowCount or 0) + 1
end

function Layout:UpdateContentSize()
    local state = self.state or {}
    local rowsByCategory = self.rowsByCategory
        or (self.deps.GetActiveRowsByCategory and self.deps.GetActiveRowsByCategory())
        or {}

    local maxWidth = 0
    local totalHeight = 0
    local visibleCount = 0

    local currentCategoryControl = nil
    local currentCategoryRows = nil
    local pendingCategoryGap = nil
    local pendingEntryGap = nil
    local currentCategoryActive = false
    local prevRowType = nil

    local function resolveRowSpacingBefore(rowType, prevType, isFirst)
        local gap = 0
        local pendingGap = nil
        local pendingEntry = nil
        if not isFirst then
            pendingGap = pendingCategoryGap
            pendingEntry = pendingEntryGap
        end

        if type(pendingGap) == "number" then
            gap = pendingGap
            pendingCategoryGap = nil
        elseif rowType == "category" then
            gap = 0
        else
            gap = self.verticalPadding
        end

        if type(pendingEntry) == "number" then
            gap = gap + pendingEntry
            pendingEntryGap = nil
        end

        gap = gap + self:GetObjectiveSpacing(prevType, rowType)

        if rowType == "category" then
            local aboveGap = self.categorySpacingAbove
            if type(aboveGap) ~= "number" then
                aboveGap = self.verticalPadding
            end
            gap = gap + aboveGap
        elseif rowType == "quest" then
            local aboveGap = self.entrySpacingAbove
            if type(aboveGap) ~= "number" then
                aboveGap = self.verticalPadding
            end
            gap = gap + aboveGap
        end

        return gap
    end

    local function peekNextVisibleRow(startIndex)
        for nextIndex = startIndex + 1, #state.orderedControls do
            local nextControl = state.orderedControls[nextIndex]
            if nextControl and not nextControl:IsHidden() then
                return nextControl, nextControl.rowType
            end
        end
        return nil, nil
    end

    for index = 1, #state.orderedControls do
        local control = state.orderedControls[index]
        if control and not control:IsHidden() then
            local rowType = control.rowType
            local height = 0

            if rowType == "category" then
                local categoryKey = control.categoryKey or (control.data and control.data.categoryKey)
                if categoryKey and control.isExpanded == false and self.deps.SetCategoryRowsVisible then
                    self.deps.SetCategoryRowsVisible(categoryKey, false)
                end
                if currentCategoryControl and self.deps.IsDebugLoggingEnabled and self.deps.IsDebugLoggingEnabled() then
                    local previousHeight, previousQuestCount = self:GetCategoryTotalHeight(currentCategoryControl, currentCategoryRows)
                    safeDebug(
                        "%s: Category height cat=%s quests=%d total=%s",
                        MODULE_TAG,
                        tostring(currentCategoryControl.categoryKey or (currentCategoryControl.data and currentCategoryControl.data.categoryKey)),
                        previousQuestCount or 0,
                        tostring(previousHeight)
                    )
                end

                currentCategoryControl = control
                currentCategoryActive = true
                if categoryKey and rowsByCategory then
                    currentCategoryRows = rowsByCategory[categoryKey] or {}
                else
                    currentCategoryRows = {}
                end
                if control.isExpanded == false then
                    currentCategoryRows = {}
                end
                height = self:GetCategoryHeaderHeight(control)
            elseif rowType == "quest" then
                if currentCategoryControl and currentCategoryControl.isExpanded == false then
                    height = 0
                    if self.deps.SetCategoryRowsVisible then
                        self.deps.SetCategoryRowsVisible(
                            currentCategoryControl.categoryKey or (currentCategoryControl.data and currentCategoryControl.data.categoryKey),
                            false
                        )
                    end
                else
                    height = self:GetQuestRowContentHeight(control, control.data)
                    if currentCategoryRows then
                        local alreadyListed = false
                        for index = 1, #currentCategoryRows do
                            if currentCategoryRows[index] == control then
                                alreadyListed = true
                                break
                            end
                        end
                        if not alreadyListed then
                            table.insert(currentCategoryRows, control)
                        end
                    end
                end
            elseif rowType == "condition" then
                if currentCategoryControl and currentCategoryControl.isExpanded == false then
                    height = 0
                else
                    height = self:GetConditionHeight(control, control.data and control.data.condition)
                    if currentCategoryRows then
                        local alreadyListed = false
                        for index = 1, #currentCategoryRows do
                            if currentCategoryRows[index] == control then
                                alreadyListed = true
                                break
                            end
                        end
                        if not alreadyListed then
                            table.insert(currentCategoryRows, control)
                        end
                    end
                end
            else
                height = control.GetHeight and control:GetHeight() or 0
            end

            local gap = resolveRowSpacingBefore(rowType, prevRowType, visibleCount == 0)
            if gap > 0 then
                totalHeight = totalHeight + gap
            end

            totalHeight = totalHeight + height
            visibleCount = visibleCount + 1
            prevRowType = rowType

            local width = (control:GetWidth() or 0) + (control.currentIndent or 0)
            if width > maxWidth then
                maxWidth = width
            end

            local nextControl, nextRowType = peekNextVisibleRow(index)
            if rowType == "quest" or rowType == "condition" then
                if nextControl == nil or nextRowType ~= "condition" then
                    pendingEntryGap = self.entrySpacingBelow
                    if type(pendingEntryGap) ~= "number" then
                        pendingEntryGap = self.verticalPadding
                    end
                end
            end
            if currentCategoryActive and (nextControl == nil or nextRowType == "category") then
                pendingCategoryGap = self.categorySpacingBelow
                if type(pendingCategoryGap) ~= "number" then
                    pendingCategoryGap = self:GetCategoryBottomPadding(currentCategoryControl and currentCategoryControl.isExpanded)
                end
                currentCategoryActive = false
            end
        end
    end

    if currentCategoryControl and self.deps.IsDebugLoggingEnabled and self.deps.IsDebugLoggingEnabled() then
        local height, questCount = self:GetCategoryTotalHeight(currentCategoryControl, currentCategoryRows)
        safeDebug(
            "%s: Category height cat=%s quests=%d total=%s",
            MODULE_TAG,
            tostring(currentCategoryControl.categoryKey or (currentCategoryControl.data and currentCategoryControl.data.categoryKey)),
            questCount or 0,
            tostring(height)
        )
    end

    if type(pendingEntryGap) == "number" then
        totalHeight = totalHeight + pendingEntryGap
    end

    if type(pendingCategoryGap) == "number" then
        totalHeight = totalHeight + pendingCategoryGap
    end

    if visibleCount > 0 then
        totalHeight = totalHeight + self.bottomPixelNudge
    end

    state.contentWidth = maxWidth
    state.contentHeight = totalHeight

    if isDebugEnabled() and not state.rightExpandedLogEmitted then
        local info = getHostViewportInfo()
        if info.align == "right" then
            safeDebug(
                "%s: Right align expanded categories=%s firstChevronTexture=%s rotation=%s",
                MODULE_TAG,
                tostring(state.rightExpandedCategoryCount or 0),
                tostring(state.rightExpandedChevronTexture),
                tostring(state.rightExpandedChevronRotation)
            )
            state.rightExpandedLogEmitted = true
        end
    end

    safeDebug(
        "%s: UpdateContentSize controls=%d width=%s height=%s",
        MODULE_TAG,
        #state.orderedControls,
        tostring(state.contentWidth),
        tostring(state.contentHeight)
    )

    if not state.anchorHygieneLogged and isDebugEnabled() then
        local firstQuest
        local firstCondition
        for index = 1, #state.orderedControls do
            local control = state.orderedControls[index]
            if control and control.rowType == "quest" and not firstQuest then
                firstQuest = control
            elseif control and control.rowType == "condition" and not firstCondition then
                firstCondition = control
            end
            if firstQuest and firstCondition then
                break
            end
        end
        safeDebug(
            "%s: Anchor hygiene rows=%d questRow=%s conditionLabel=%s",
            MODULE_TAG,
            #state.orderedControls,
            tostring(firstQuest and firstQuest.GetName and firstQuest:GetName() or "none"),
            tostring(firstCondition and firstCondition.label and firstCondition.label.GetName and firstCondition.label:GetName() or "none")
        )
        state.anchorHygieneLogged = true
    end
end

function Layout:LayoutCondition(condition)
    if not (self.deps.ShouldDisplayCondition and self.deps.ShouldDisplayCondition(condition)) then
        return
    end

    local control, indentX = self:ApplyRowDescriptor({
        rowType = "condition",
        condition = condition,
    })
    if not control then
        return
    end

    self:AnchorControl(control, indentX)
    self:LogRowMetrics(control, indentX)
end

function Layout:LayoutQuest(quest)
    local providedControl = self.deps.AcquireQuestRow and self.deps.AcquireQuestRow()
    local control, indentX = self:ApplyRowDescriptor({
        rowType = "quest",
        quest = quest,
    }, providedControl)
    if not control then
        return
    end

    self:AnchorControl(control, indentX)
    self:LogRowMetrics(control, indentX)
    self:SetPendingEntryGap()
end

function Layout:LayoutCategory(category, providedControl)
    local control, indentX = self:ApplyRowDescriptor({
        rowType = "category",
        category = category,
        expanded = self.deps.IsCategoryExpanded and self.deps.IsCategoryExpanded(category.key),
    }, providedControl)
    if not control then
        return
    end

    self:AnchorControl(control, indentX or 0)
    self:LogRowMetrics(control, indentX or 0)

    if control.isExpanded and category.quests then
        for index = 1, #category.quests do
            self:LayoutQuest(category.quests[index])
        end
    elseif self.deps.SetCategoryRowsVisible then
        self.deps.SetCategoryRowsVisible(category.key, false)
    end

    self:SetPendingCategoryGap(control.isExpanded)
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
        if self.deps.ReleaseCategoryRow then
            self.deps.ReleaseCategoryRow(control)
        elseif state.categoryPool and control.poolKey then
            state.categoryPool:ReleaseObject(control.poolKey)
        end
    elseif rowType == "quest" then
        local questData = control.data and control.data.quest
        if questData and questData.journalIndex and state.questControls then
            state.questControls[questData.journalIndex] = nil
        end
        if self.deps.ReleaseQuestRow then
            self.deps.ReleaseQuestRow(control)
        elseif state.questPool and control.poolKey then
            state.questPool:ReleaseObject(control.poolKey)
        end
    else
        if self.deps.ReleaseObjectiveRow then
            self.deps.ReleaseObjectiveRow(control)
        elseif state.conditionPool and control.poolKey then
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
    state.visibleRowCount = 0
    for index = 1, #state.orderedControls do
        local control = state.orderedControls[index]
        if control and not control:IsHidden() then
            state.visibleRowCount = state.visibleRowCount + 1
        end
    end
    state.pendingCategoryGap = nil
    state.pendingEntryGap = nil
    if state.visibleRowCount > 0 then
        local lastCategoryControl = nil
        local lastVisibleControl = nil
        for index = #state.orderedControls, 1, -1 do
            local control = state.orderedControls[index]
            if control and control.rowType == "category" then
                lastCategoryControl = control
                break
            end
        end
        for index = #state.orderedControls, 1, -1 do
            local control = state.orderedControls[index]
            if control and not control:IsHidden() then
                lastVisibleControl = control
                break
            end
        end
        if lastCategoryControl then
            self:SetPendingCategoryGap(lastCategoryControl.isExpanded)
        end
        if lastVisibleControl then
            local rowType = lastVisibleControl.rowType
            if rowType == "quest" or rowType == "condition" then
                self:SetPendingEntryGap()
            end
        end
    end
end

function Layout:RelayoutFromCategoryIndex(startCategoryIndex)
    if self.deps.ApplyActiveQuestFromSaved then
        self.deps.ApplyActiveQuestFromSaved()
    end

    if self.deps.PrimeInitialSavedState then
        self.deps.PrimeInitialSavedState()
    end

    self:ApplyLayout(self.state and self.state.container)
end

function Layout:ApplyLayout(parentContainer, categoryControls, rowControls, rowsByCategory)
    if parentContainer and self.state then
        self.state.container = parentContainer
    end

    self.rowsByCategory = rowsByCategory

    if self.deps.EnsurePools then
        self.deps.EnsurePools()
    end
    if self.deps.ApplyActiveQuestFromSaved then
        self.deps.ApplyActiveQuestFromSaved()
    end
    if self.deps.PrimeInitialSavedState then
        self.deps.PrimeInitialSavedState()
    end

    if self.state and self.state.orderedControls and #self.state.orderedControls > 0 then
        for index = #self.state.orderedControls, 1, -1 do
            self:ReleaseRowControl(self.state.orderedControls[index])
        end
    end

    self:ResetLayoutState()

    local viewModel = self.state and self.state.viewModel
    local flatRows = self:BuildFlatRowList(viewModel)
    local currentCategoryExpanded = nil
    local currentCategoryActive = false

    for index = 1, #flatRows do
        local rowDescriptor = flatRows[index]
        local rowType = rowDescriptor and rowDescriptor.rowType
        local nextRow = flatRows[index + 1]
        local nextRowType = nextRow and nextRow.rowType

        local providedControl = nil
        if rowType == "category" and self.deps.AcquireCategoryRow then
            providedControl = self.deps.AcquireCategoryRow()
        elseif rowType == "quest" and self.deps.AcquireQuestRow then
            providedControl = self.deps.AcquireQuestRow()
        end

        local control, indentX = self:ApplyRowDescriptor(rowDescriptor, providedControl)
        if control then
            self:AnchorControl(control, indentX or 0)
            self:LogRowMetrics(control, indentX or 0)
        end

        if rowType == "category" then
            currentCategoryExpanded = rowDescriptor.expanded == true
            currentCategoryActive = true
        end

        if rowType == "quest" or rowType == "condition" then
            if nextRowType ~= "condition" then
                self:SetPendingEntryGap()
            end
        end

        if currentCategoryActive and (nextRowType == nil or nextRowType == "category") then
            self:SetPendingCategoryGap(currentCategoryExpanded)
            currentCategoryActive = false
        end
    end

    self:UpdateContentSize()
    if self.deps.NotifyHostContentChanged then
        self.deps.NotifyHostContentChanged()
    end
    if self.deps.ProcessPendingExternalReveal then
        self.deps.ProcessPendingExternalReveal()
    end

    return self.state and self.state.orderedControls or {}
end

function Layout:GetCategoryControls()
    local state = self.state or {}
    return state.categoryControls
end

Nvk3UT.QuestTrackerLayout = Layout

return Layout
