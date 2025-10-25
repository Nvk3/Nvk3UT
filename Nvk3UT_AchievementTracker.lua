local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local AchievementTracker = {}
AchievementTracker.__index = AchievementTracker

local MODULE_NAME = addonName .. "AchievementTracker"

local Utils = Nvk3UT and Nvk3UT.Utils
local FormatCategoryHeaderText =
    (Utils and Utils.FormatCategoryHeaderText)
    or function(baseText, count, showCounts)
        local text = baseText or ""
        if showCounts ~= false and type(count) == "number" and count >= 0 then
            local numericCount = math.floor(count + 0.5)
            return string.format("%s (%d)", text, numericCount)
        end
        return text
    end

local CATEGORY_TOGGLE_TEXTURES = {
    expanded = {
        up = "EsoUI/Art/Buttons/tree_open_up.dds",
        over = "EsoUI/Art/Buttons/tree_open_over.dds",
    },
    collapsed = {
        up = "EsoUI/Art/Buttons/tree_closed_up.dds",
        over = "EsoUI/Art/Buttons/tree_closed_over.dds",
    },
}

local CATEGORY_INDENT_X = 0
local ACHIEVEMENT_INDENT_X = 18
local ACHIEVEMENT_ICON_SLOT_WIDTH = 18
local ACHIEVEMENT_ICON_SLOT_HEIGHT = 18
local ACHIEVEMENT_ICON_SLOT_PADDING_X = 6
local ACHIEVEMENT_LABEL_INDENT_X = ACHIEVEMENT_INDENT_X + ACHIEVEMENT_ICON_SLOT_WIDTH + ACHIEVEMENT_ICON_SLOT_PADDING_X
-- keep objective text inset relative to achievement titles after adding the persistent icon slot
local OBJECTIVE_RELATIVE_INDENT = 18
local OBJECTIVE_INDENT_X = ACHIEVEMENT_LABEL_INDENT_X + OBJECTIVE_RELATIVE_INDENT
local VERTICAL_PADDING = 3

local CATEGORY_KEY = "achievements"

local CATEGORY_MIN_HEIGHT = 26
local ACHIEVEMENT_MIN_HEIGHT = 24
local OBJECTIVE_MIN_HEIGHT = 20
local ROW_TEXT_PADDING_Y = 8
local TOGGLE_LABEL_PADDING_X = 4
local CATEGORY_TOGGLE_WIDTH = 20

local DEFAULT_FONTS = {
    category = "$(BOLD_FONT)|20|soft-shadow-thick",
    achievement = "$(BOLD_FONT)|16|soft-shadow-thick",
    objective = "$(BOLD_FONT)|14|soft-shadow-thick",
    toggle = "$(BOLD_FONT)|20|soft-shadow-thick",
}

local unpack = table.unpack or unpack
local LEFT_MOUSE_BUTTON = MOUSE_BUTTON_INDEX_LEFT or 1

local DEFAULT_FONT_OUTLINE = "soft-shadow-thick"
local REFRESH_DEBOUNCE_MS = 80

local COLOR_ROW_HOVER = { 1, 1, 0.6, 1 }

local state = {
    isInitialized = false,
    opts = {},
    fonts = {},
    saved = nil,
    control = nil,
    container = nil,
    categoryPool = nil,
    achievementPool = nil,
    objectivePool = nil,
    orderedControls = {},
    lastAnchoredControl = nil,
    snapshot = nil,
    subscription = nil,
    pendingRefresh = false,
    contentWidth = 0,
    contentHeight = 0,
}

local function ApplyLabelDefaults(label)
    if not label or not label.SetHorizontalAlignment then
        return
    end

    label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    if label.SetVerticalAlignment then
        label:SetVerticalAlignment(TEXT_ALIGN_TOP)
    end
    if label.SetWrapMode then
        label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    end
end

local function ApplyToggleDefaults(toggle)
    if not toggle or not toggle.SetVerticalAlignment then
        return
    end

    toggle:SetVerticalAlignment(TEXT_ALIGN_TOP)
end

local function GetAchievementTrackerColor(role)
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host and host.GetTrackerColor then
        return host.GetTrackerColor("achievementTracker", role)
    end
    return 1, 1, 1, 1
end

local function ApplyBaseColor(control, r, g, b, a)
    if not control then
        return
    end

    local color = control.baseColor
    if type(color) ~= "table" then
        color = {}
        control.baseColor = color
    end

    color[1] = r or 1
    color[2] = g or 1
    color[3] = b or 1
    color[4] = a or 1

    if control.label and control.label.SetColor then
        control.label:SetColor(color[1], color[2], color[3], color[4])
    end
end

local function GetToggleWidth(toggle, fallback)
    if toggle then
        if toggle.IsHidden and toggle:IsHidden() then
            return 0
        end

        if toggle.GetWidth then
            local width = toggle:GetWidth()
            if width and width > 0 then
                return width
            end
        end
    end

    return fallback or 0
end

local function GetContainerWidth()
    if not state.container or not state.container.GetWidth then
        return 0
    end

    local width = state.container:GetWidth()
    if not width or width <= 0 then
        return 0
    end

    return width
end

local function ApplyRowMetrics(control, indent, toggleWidth, leftPadding, rightPadding, minHeight)
    if not control or not control.label then
        return
    end

    indent = indent or 0
    toggleWidth = toggleWidth or 0
    leftPadding = leftPadding or 0
    rightPadding = rightPadding or 0

    local containerWidth = GetContainerWidth()
    local availableWidth = containerWidth - indent - toggleWidth - leftPadding - rightPadding
    if availableWidth < 0 then
        availableWidth = 0
    end

    control.label:SetWidth(availableWidth)

    local textHeight = control.label:GetTextHeight() or 0
    local targetHeight = textHeight + ROW_TEXT_PADDING_Y
    if minHeight then
        targetHeight = math.max(minHeight, targetHeight)
    end

    control:SetHeight(targetHeight)
end

local function RefreshControlMetrics(control)
    if not control or not control.label then
        return
    end

    local indent = control.currentIndent or 0
    local rowType = control.rowType

    if rowType == "category" then
        ApplyRowMetrics(
            control,
            indent,
            GetToggleWidth(control.toggle, CATEGORY_TOGGLE_WIDTH),
            TOGGLE_LABEL_PADDING_X,
            0,
            CATEGORY_MIN_HEIGHT
        )
    elseif rowType == "achievement" then
        ApplyRowMetrics(
            control,
            indent,
            ACHIEVEMENT_ICON_SLOT_WIDTH,
            ACHIEVEMENT_ICON_SLOT_PADDING_X,
            0,
            ACHIEVEMENT_MIN_HEIGHT
        )
    elseif rowType == "objective" then
        ApplyRowMetrics(control, indent, 0, 0, 0, OBJECTIVE_MIN_HEIGHT)
    end
end

local function IsDebugLoggingEnabled()
    local sv = Nvk3UT and Nvk3UT.sv
    return sv and sv.debug == true
end

local function DebugLog(...)
    if not IsDebugLoggingEnabled() then
        return
    end

    if d then
        d(string.format("[%s]", MODULE_NAME), ...)
    elseif print then
        print("[" .. MODULE_NAME .. "]", ...)
    end
end

local function EscapeDebugString(value)
    return tostring(value):gsub('"', '\\"')
end

local function AppendDebugField(parts, key, value, treatAsString)
    if not key or key == "" then
        return
    end

    if value == nil then
        parts[#parts + 1] = string.format("%s=nil", key)
        return
    end

    local valueType = type(value)
    if valueType == "boolean" then
        parts[#parts + 1] = string.format("%s=%s", key, value and "true" or "false")
    elseif valueType == "number" then
        parts[#parts + 1] = string.format("%s=%s", key, tostring(value))
    elseif treatAsString or valueType == "string" then
        parts[#parts + 1] = string.format('%s="%s"', key, EscapeDebugString(value))
    else
        parts[#parts + 1] = string.format("%s=%s", key, tostring(value))
    end
end

local function EmitDebugAction(action, trigger, entityType, fieldList)
    if not IsDebugLoggingEnabled() then
        return
    end

    local parts = { "[NVK]" }
    AppendDebugField(parts, "action", action or "unknown")
    AppendDebugField(parts, "trigger", trigger or "unknown")
    AppendDebugField(parts, "type", entityType or "unknown")

    if type(fieldList) == "table" then
        for index = 1, #fieldList do
            local entry = fieldList[index]
            if entry and entry.key then
                AppendDebugField(parts, entry.key, entry.value, entry.string)
            end
        end
    end

    local message = table.concat(parts, " ")
    if d then
        d(message)
    elseif print then
        print(message)
    end
end

local function LogCategoryExpansion(action, trigger, beforeExpanded, afterExpanded, source)
    if not IsDebugLoggingEnabled() then
        return
    end

    local fields = {
        { key = "id", value = "root" },
        { key = "before.expanded", value = beforeExpanded },
        { key = "after.expanded", value = afterExpanded },
    }

    if source then
        fields[#fields + 1] = { key = "source", value = source, string = true }
    end

    EmitDebugAction(action, trigger, "category", fields)
end

local function NotifyHostContentChanged()
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if not (host and host.NotifyContentChanged) then
        return
    end

    pcall(host.NotifyContentChanged)
end

local function EnsureSavedVars()
    Nvk3UT.sv = Nvk3UT.sv or {}
    Nvk3UT.sv.AchievementTracker = Nvk3UT.sv.AchievementTracker or {}
    local saved = Nvk3UT.sv.AchievementTracker
    if saved.categoryExpanded == nil then
        saved.categoryExpanded = true
    end
    saved.entryExpanded = saved.entryExpanded or {}
    state.saved = saved
end

local function ApplyFont(label, font)
    if not label or not label.SetFont then
        return
    end
    if not font or font == "" then
        return
    end
    label:SetFont(font)
end

local function ResolveFont(fontId)
    if type(fontId) == "string" and fontId ~= "" then
        return fontId
    end
    return nil
end

local function MergeFonts(opts)
    local fonts = {}
    fonts.category = ResolveFont(opts.category) or DEFAULT_FONTS.category
    fonts.achievement = ResolveFont(opts.achievement) or DEFAULT_FONTS.achievement
    fonts.objective = ResolveFont(opts.objective) or DEFAULT_FONTS.objective
    fonts.toggle = ResolveFont(opts.toggle) or DEFAULT_FONTS.toggle
    return fonts
end

local function BuildFontString(descriptor, fallback)
    if type(descriptor) ~= "table" then
        return ResolveFont(descriptor) or fallback
    end

    local face = descriptor.face or descriptor.path
    local size = descriptor.size
    local outline = descriptor.outline or DEFAULT_FONT_OUTLINE

    if not face or face == "" or not size then
        return fallback
    end

    return string.format("%s|%d|%s", face, size, outline or DEFAULT_FONT_OUTLINE)
end

local function BuildFavoritesScope()
    local sv = Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.General
    return (sv and sv.favScope) or "account"
end

local function IsFavoriteAchievement(achievementId)
    if not achievementId then
        return false
    end

    local Fav = Nvk3UT and Nvk3UT.FavoritesData
    if not (Fav and Fav.IsFavorite) then
        return false
    end

    local scope = BuildFavoritesScope()
    if Fav.IsFavorite(achievementId, scope) then
        return true
    end

    if scope ~= "account" and Fav.IsFavorite(achievementId, "account") then
        return true
    end

    if scope ~= "character" and Fav.IsFavorite(achievementId, "character") then
        return true
    end

    return false
end

local function IsRecentAchievement(achievementId)
    if not achievementId then
        return false
    end

    local recent = Nvk3UT and Nvk3UT._recentSV and Nvk3UT._recentSV.progress
    if not recent then
        return false
    end

    if recent[achievementId] ~= nil then
        return true
    end

    local key = tostring(achievementId)
    return recent[key] ~= nil
end

local function BuildTodoLookup()
    local Todo = Nvk3UT and Nvk3UT.TodoData
    if not (Todo and Todo.ListAllOpen) then
        return nil
    end

    local list = Todo.ListAllOpen(nil, false)
    if type(list) ~= "table" then
        return nil
    end

    local lookup = {}
    for index = 1, #list do
        local id = list[index]
        if id then
            lookup[id] = true
        end
    end

    return lookup
end

local function RequestRefresh()
    if not state.isInitialized then
        return
    end

    if state.pendingRefresh then
        return
    end

    state.pendingRefresh = true

    local function execute()
        state.pendingRefresh = false
        AchievementTracker.Refresh()
    end

    if zo_callLater then
        zo_callLater(execute, REFRESH_DEBOUNCE_MS)
    else
        execute()
    end
end

local function RefreshVisibility()
    if not state.control then
        return
    end

    local hidden = state.opts and state.opts.active == false
    state.control:SetHidden(hidden)
    NotifyHostContentChanged()
end

local function ResetLayoutState()
    state.orderedControls = {}
    state.lastAnchoredControl = nil
end

local function ReleaseAll(pool)
    if pool then
        pool:ReleaseAllObjects()
    end
end

local function AnchorControl(control, indentX)
    indentX = indentX or 0
    control:ClearAnchors()

    if state.lastAnchoredControl then
        local previousIndent = state.lastAnchoredControl.currentIndent or 0
        local offsetX = indentX - previousIndent
        control:SetAnchor(TOPLEFT, state.lastAnchoredControl, BOTTOMLEFT, offsetX, VERTICAL_PADDING)
        control:SetAnchor(TOPRIGHT, state.lastAnchoredControl, BOTTOMRIGHT, 0, VERTICAL_PADDING)
    else
        control:SetAnchor(TOPLEFT, state.container, TOPLEFT, indentX, 0)
        control:SetAnchor(TOPRIGHT, state.container, TOPRIGHT, 0, 0)
    end

    state.lastAnchoredControl = control
    state.orderedControls[#state.orderedControls + 1] = control
    control.currentIndent = indentX
end

local function UpdateContentSize()
    local maxWidth = 0
    local totalHeight = 0
    local visibleCount = 0

    for index = 1, #state.orderedControls do
        local control = state.orderedControls[index]
        if control then
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
                totalHeight = totalHeight + VERTICAL_PADDING
            end
        end
    end

    state.contentWidth = maxWidth
    state.contentHeight = totalHeight
end

local function IsCategoryExpanded()
    if not state.saved then
        return true
    end
    if state.saved.categoryExpanded == nil then
        state.saved.categoryExpanded = true
    end
    return state.saved.categoryExpanded ~= false
end

local function SetCategoryExpanded(expanded, context)
    if not state.saved then
        return
    end
    local beforeExpanded = IsCategoryExpanded()
    state.saved.categoryExpanded = expanded and true or false
    local afterExpanded = IsCategoryExpanded()

    if beforeExpanded ~= afterExpanded then
        LogCategoryExpansion(
            afterExpanded and "expand" or "collapse",
            (context and context.trigger) or "unknown",
            beforeExpanded,
            afterExpanded,
            (context and context.source) or "AchievementTracker:SetCategoryExpanded"
        )
    end
end

local function SetEntryExpanded(achievementId, expanded)
    if not state.saved or not achievementId then
        return
    end
    state.saved.entryExpanded[achievementId] = expanded and true or false
end

local function IsEntryExpanded(achievementId)
    if not state.saved or not achievementId then
        return true
    end
    local expanded = state.saved.entryExpanded[achievementId]
    if expanded == nil then
        state.saved.entryExpanded[achievementId] = true
        expanded = true
    end
    return expanded ~= false
end

local function SelectCategoryToggleTexture(expanded, isMouseOver)
    local textures = expanded and CATEGORY_TOGGLE_TEXTURES.expanded or CATEGORY_TOGGLE_TEXTURES.collapsed
    if isMouseOver then
        return textures.over
    end
    return textures.up
end

local function UpdateCategoryToggle(control, expanded)
    if not control or not control.toggle then
        return
    end
    control.toggle:SetHidden(false)
    if control.toggle.SetTexture then
        local isMouseOver = false
        if control.IsMouseOver and control:IsMouseOver() then
            isMouseOver = true
        elseif control.toggle.IsMouseOver and control.toggle:IsMouseOver() then
            isMouseOver = true
        end
        local texture = SelectCategoryToggleTexture(expanded, isMouseOver)
        control.toggle:SetTexture(texture)
    end
    control.isExpanded = expanded and true or false
end

local function UpdateAchievementIconSlot(control)
    if not control or not control.iconSlot then
        return
    end

    if control.iconSlot.SetTexture then
        control.iconSlot:SetTexture(nil)
    end
    if control.iconSlot.SetAlpha then
        control.iconSlot:SetAlpha(0)
    end
    if control.iconSlot.SetHidden then
        control.iconSlot:SetHidden(false)
    end
end

local function FormatObjectiveText(objective)
    local description = objective.description or ""
    if description == "" then
        return ""
    end

    local current = objective.current
    local maxValue = objective.max

    local hasCurrent = current ~= nil and current ~= ""
    local hasMax = maxValue ~= nil and maxValue ~= ""

    local text
    if hasCurrent and hasMax then
        text = string.format("%s (%s/%s)", description, tostring(current), tostring(maxValue))
    elseif hasCurrent then
        text = string.format("%s (%s)", description, tostring(current))
    else
        text = description
    end

    if zo_strformat then
        return zo_strformat("<<1>>", text)
    end
    return text
end

local function ShouldDisplayObjective(objective)
    if not objective then
        return false
    end

    if objective.isVisible == false then
        return false
    end

    local text = objective.description
    if not text or text == "" then
        return false
    end

    return true
end

local function AcquireCategoryControl()
    local control = state.categoryPool:AcquireObject()
    if not control.initialized then
        control.label = control:GetNamedChild("Label")
        control.toggle = control:GetNamedChild("Toggle")
        if control.toggle and control.toggle.SetTexture then
            control.toggle:SetTexture(SelectCategoryToggleTexture(false, false))
        end
        control.isExpanded = false
        control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
            if not upInside or button ~= LEFT_MOUSE_BUTTON then
                return
            end
            local expanded = not IsCategoryExpanded()
            SetCategoryExpanded(expanded, {
                trigger = "click",
                source = "AchievementTracker:OnCategoryClick",
            })
            AchievementTracker.Refresh()
        end)
        control:SetHandler("OnMouseEnter", function(ctrl)
            if ctrl.label then
                ctrl.label:SetColor(unpack(COLOR_ROW_HOVER))
            end
            local expanded = ctrl.isExpanded
            if expanded == nil then
                expanded = IsCategoryExpanded()
            end
            UpdateCategoryToggle(ctrl, expanded)
        end)
        control:SetHandler("OnMouseExit", function(ctrl)
            if ctrl.label and ctrl.baseColor then
                ctrl.label:SetColor(unpack(ctrl.baseColor))
            end
            local expanded = ctrl.isExpanded
            if expanded == nil then
                expanded = IsCategoryExpanded()
            end
            UpdateCategoryToggle(ctrl, expanded)
        end)
        control.initialized = true
    end
    control.rowType = "category"
    ApplyLabelDefaults(control.label)
    ApplyToggleDefaults(control.toggle)
    ApplyFont(control.label, state.fonts.category)
    ApplyFont(control.toggle, state.fonts.toggle)
    return control
end

local function AcquireAchievementControl()
    local control = state.achievementPool:AcquireObject()
    if not control.initialized then
        control.label = control:GetNamedChild("Label")
        control.iconSlot = control:GetNamedChild("IconSlot")
        if control.iconSlot then
            control.iconSlot:SetDimensions(ACHIEVEMENT_ICON_SLOT_WIDTH, ACHIEVEMENT_ICON_SLOT_HEIGHT)
            control.iconSlot:ClearAnchors()
            control.iconSlot:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
            if control.iconSlot.SetTexture then
                control.iconSlot:SetTexture(nil)
            end
            if control.iconSlot.SetAlpha then
                control.iconSlot:SetAlpha(0)
            end
            if control.iconSlot.SetHidden then
                control.iconSlot:SetHidden(false)
            end
        end
        if control.label then
            control.label:ClearAnchors()
            if control.iconSlot then
                control.label:SetAnchor(TOPLEFT, control.iconSlot, TOPRIGHT, ACHIEVEMENT_ICON_SLOT_PADDING_X, 0)
            else
                control.label:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
            end
            control.label:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
        end
        control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
            if not upInside or button ~= LEFT_MOUSE_BUTTON then
                return
            end
            if not ctrl.data or not ctrl.data.achievementId or not ctrl.data.hasObjectives then
                return
            end
            local achievementId = ctrl.data.achievementId
            local expanded = not IsEntryExpanded(achievementId)
            SetEntryExpanded(achievementId, expanded)
            AchievementTracker.Refresh()
        end)
        control.initialized = true
    end
    control.rowType = "achievement"
    ApplyLabelDefaults(control.label)
    ApplyFont(control.label, state.fonts.achievement)
    return control
end

local function AcquireObjectiveControl()
    local control = state.objectivePool:AcquireObject()
    if not control.initialized then
        control.label = control:GetNamedChild("Label")
        control.initialized = true
    end
    control.rowType = "objective"
    ApplyLabelDefaults(control.label)
    ApplyFont(control.label, state.fonts.objective)
    return control
end

local function EnsurePools()
    if state.categoryPool then
        return
    end

    state.categoryPool = ZO_ControlPool:New("AchievementsCategoryHeader_Template", state.container)
    state.achievementPool = ZO_ControlPool:New("AchievementHeader_Template", state.container)
    state.objectivePool = ZO_ControlPool:New("AchievementObjective_Template", state.container)

    local function resetControl(control)
        control:SetHidden(true)
        control.data = nil
        control.currentIndent = nil
    end

    state.categoryPool:SetCustomResetBehavior(function(control)
        resetControl(control)
        control.baseColor = nil
        if control.toggle then
            if control.toggle.SetTexture then
                control.toggle:SetTexture(SelectCategoryToggleTexture(false, false))
            end
            if control.toggle.SetHidden then
                control.toggle:SetHidden(false)
            end
        end
        control.isExpanded = nil
    end)

    state.achievementPool:SetCustomResetBehavior(function(control)
        resetControl(control)
        if control.label and control.label.SetText then
            control.label:SetText("")
        end
        if control.iconSlot then
            if control.iconSlot.SetTexture then
                control.iconSlot:SetTexture(nil)
            end
            if control.iconSlot.SetAlpha then
                control.iconSlot:SetAlpha(0)
            end
            if control.iconSlot.SetHidden then
                control.iconSlot:SetHidden(false)
            end
        end
    end)

    state.objectivePool:SetCustomResetBehavior(function(control)
        resetControl(control)
        if control.label then
            control.label:SetText("")
        end
    end)
end

local function LayoutObjective(achievement, objective)
    if not ShouldDisplayObjective(objective) then
        return
    end

    local text = FormatObjectiveText(objective)
    if text == "" then
        return
    end

    local control = AcquireObjectiveControl()
    control.data = {
        achievementId = achievement.id,
        objective = objective,
    }
    control.label:SetText(text)
    if control.label then
        local r, g, b, a = GetAchievementTrackerColor("objectiveText")
        control.label:SetColor(r, g, b, a)
    end
    ApplyRowMetrics(control, OBJECTIVE_INDENT_X, 0, 0, 0, OBJECTIVE_MIN_HEIGHT)
    control:SetHidden(false)
    AnchorControl(control, OBJECTIVE_INDENT_X)
end

local function LayoutAchievement(achievement)
    local control = AcquireAchievementControl()
    local hasObjectives = achievement.objectives and #achievement.objectives > 0
    control.data = {
        achievementId = achievement.id,
        hasObjectives = hasObjectives,
    }
    control.label:SetText(achievement.name or "")
    if control.label then
        local r, g, b, a = GetAchievementTrackerColor("entryTitle")
        control.label:SetColor(r, g, b, a)
    end

    local expanded = hasObjectives and IsEntryExpanded(achievement.id)
    UpdateAchievementIconSlot(control)
    ApplyRowMetrics(
        control,
        ACHIEVEMENT_INDENT_X,
        ACHIEVEMENT_ICON_SLOT_WIDTH,
        ACHIEVEMENT_ICON_SLOT_PADDING_X,
        0,
        ACHIEVEMENT_MIN_HEIGHT
    )
    control:SetHidden(false)
    AnchorControl(control, ACHIEVEMENT_INDENT_X)

    if hasObjectives and expanded then
        for index = 1, #achievement.objectives do
            LayoutObjective(achievement, achievement.objectives[index])
        end
    end
end

local function LayoutCategory()
    local achievements = (state.snapshot and state.snapshot.achievements) or {}
    local sections = state.opts.sections or {}
    local showCompleted = sections.completed ~= false
    local showFavorites = true
    local showRecent = sections.recent ~= false
    local showTodo = sections.todo ~= false

    local todoLookup = BuildTodoLookup()
    local visibleEntries = {}

    for index = 1, #achievements do
        local achievement = achievements[index]
        local include = true
        local hasTag = false
        local allowed = false

        if achievement and achievement.id then
            local achievementId = achievement.id
            local isCompleted = achievement.flags and achievement.flags.isComplete
            local isFavorite = IsFavoriteAchievement(achievementId)
            local isRecent = IsRecentAchievement(achievementId)
            local isTodo = todoLookup and todoLookup[achievementId] or false

            if isCompleted then
                hasTag = true
                if showCompleted then
                    allowed = true
                end
            end

            if isFavorite then
                hasTag = true
                if showFavorites then
                    allowed = true
                end
            else
                hasTag = true
                include = false
            end

            if isRecent then
                hasTag = true
                if showRecent then
                    allowed = true
                end
            end

            if isTodo then
                hasTag = true
                if showTodo then
                    allowed = true
                end
            end

            if hasTag then
                include = allowed
            end
        end

        if include or not hasTag then
            visibleEntries[#visibleEntries + 1] = achievement
        end
    end

    local total = #visibleEntries

    local control = AcquireCategoryControl()
    control.data = { categoryKey = CATEGORY_KEY }
    control.label:SetText(FormatCategoryHeaderText("Errungenschaften", total or 0, "achievement"))

    local expanded = IsCategoryExpanded()
    local r, g, b, a = GetAchievementTrackerColor("categoryTitle")
    ApplyBaseColor(control, r, g, b, a)
    UpdateCategoryToggle(control, expanded)
    ApplyRowMetrics(
        control,
        CATEGORY_INDENT_X,
        GetToggleWidth(control.toggle, CATEGORY_TOGGLE_WIDTH),
        TOGGLE_LABEL_PADDING_X,
        0,
        CATEGORY_MIN_HEIGHT
    )

    control:SetHidden(false)
    AnchorControl(control, CATEGORY_INDENT_X)

    if expanded then
        for index = 1, #visibleEntries do
            LayoutAchievement(visibleEntries[index])
        end
    end
end

local function Rebuild()
    if not state.container then
        return
    end

    EnsurePools()

    ReleaseAll(state.categoryPool)
    ReleaseAll(state.achievementPool)
    ReleaseAll(state.objectivePool)

    ResetLayoutState()

    LayoutCategory()

    UpdateContentSize()
    NotifyHostContentChanged()
end

local function OnSnapshotUpdated(snapshot)
    state.snapshot = snapshot
    Rebuild()
end

local function SubscribeToModel()
    if state.subscription or not Nvk3UT.AchievementModel or not Nvk3UT.AchievementModel.Subscribe then
        return
    end

    state.subscription = function(snapshot)
        OnSnapshotUpdated(snapshot)
    end

    Nvk3UT.AchievementModel.Subscribe(state.subscription)
end

local function UnsubscribeFromModel()
    if not state.subscription or not Nvk3UT.AchievementModel or not Nvk3UT.AchievementModel.Unsubscribe then
        state.subscription = nil
        return
    end

    Nvk3UT.AchievementModel.Unsubscribe(state.subscription)
    state.subscription = nil
end

function AchievementTracker.Init(parentControl, opts)
    if not parentControl then
        error("AchievementTracker.Init requires a parent control")
    end

    if state.isInitialized then
        AchievementTracker.Shutdown()
    end

    state.control = parentControl
    state.container = parentControl
    if state.control and state.control.SetResizeToFitDescendents then
        state.control:SetResizeToFitDescendents(true)
    end
    EnsureSavedVars()

    state.opts = {}
    state.fonts = {}

    AchievementTracker.ApplyTheme(state.saved or {})
    AchievementTracker.ApplySettings(state.saved or {})

    if opts then
        AchievementTracker.ApplyTheme(opts)
        AchievementTracker.ApplySettings(opts)
    end

    SubscribeToModel()

    state.snapshot = Nvk3UT.AchievementModel and Nvk3UT.AchievementModel.GetSnapshot and Nvk3UT.AchievementModel.GetSnapshot()

    state.isInitialized = true

    RefreshVisibility()
    AchievementTracker.Refresh()
end

function AchievementTracker.Refresh()
    if not state.isInitialized then
        return
    end

    if Nvk3UT.AchievementModel and Nvk3UT.AchievementModel.GetSnapshot then
        state.snapshot = Nvk3UT.AchievementModel.GetSnapshot() or state.snapshot
    end

    Rebuild()
end

function AchievementTracker.Shutdown()
    UnsubscribeFromModel()

    ReleaseAll(state.categoryPool)
    ReleaseAll(state.achievementPool)
    ReleaseAll(state.objectivePool)

    state.categoryPool = nil
    state.achievementPool = nil
    state.objectivePool = nil

    state.container = nil
    state.control = nil
    state.snapshot = nil
    state.orderedControls = {}
    state.lastAnchoredControl = nil
    state.fonts = {}
    state.opts = {}

    state.isInitialized = false
    state.pendingRefresh = false
    state.contentWidth = 0
    state.contentHeight = 0
    NotifyHostContentChanged()
end

local function EnsureSections()
    if type(state.opts.sections) ~= "table" then
        state.opts.sections = {}
    end
end

local function ApplySections(sections)
    if type(sections) ~= "table" then
        return
    end

    EnsureSections()
    for key, value in pairs(sections) do
        state.opts.sections[key] = value
    end
end

local function ApplyTooltipsSetting(value)
    state.opts.tooltips = (value ~= false)
end

function AchievementTracker.ApplySettings(settings)
    if type(settings) ~= "table" then
        return
    end

    state.opts.active = settings.active ~= false
    ApplySections(settings.sections)
    if settings.tooltips ~= nil then
        ApplyTooltipsSetting(settings.tooltips)
    end

    RefreshVisibility()
    RequestRefresh()
end

function AchievementTracker.ApplyTheme(settings)
    if type(settings) ~= "table" then
        return
    end

    state.opts.fonts = state.opts.fonts or {}

    local fonts = settings.fonts or {}
    state.opts.fonts.category = BuildFontString(fonts.category, state.opts.fonts.category or DEFAULT_FONTS.category)
    state.opts.fonts.achievement = BuildFontString(fonts.title, state.opts.fonts.achievement or DEFAULT_FONTS.achievement)
    state.opts.fonts.objective = BuildFontString(fonts.line, state.opts.fonts.objective or DEFAULT_FONTS.objective)
    state.opts.fonts.toggle = state.opts.fonts.category or DEFAULT_FONTS.toggle

    state.fonts = MergeFonts(state.opts.fonts)

    RequestRefresh()
end

function AchievementTracker.RequestRefresh()
    RequestRefresh()
end

function AchievementTracker.SetActive(active)
    state.opts.active = (active ~= false)
    RefreshVisibility()
end

function AchievementTracker.RefreshVisibility()
    RefreshVisibility()
end

function AchievementTracker.GetContentSize()
    UpdateContentSize()
    return state.contentWidth or 0, state.contentHeight or 0
end

-- Ensure the container exists before populating entries during init
Nvk3UT.AchievementTracker = AchievementTracker

return AchievementTracker
