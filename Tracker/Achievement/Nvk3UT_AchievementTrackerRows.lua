local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local MODULE_NAME = addonName .. ".AchievementTrackerRows"

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
local OBJECTIVE_RELATIVE_INDENT = 18
local OBJECTIVE_INDENT_X = ACHIEVEMENT_LABEL_INDENT_X + OBJECTIVE_RELATIVE_INDENT
local VERTICAL_PADDING = 3

local CATEGORY_MIN_HEIGHT = 26
local ACHIEVEMENT_MIN_HEIGHT = 24
local OBJECTIVE_MIN_HEIGHT = 20
local ROW_TEXT_PADDING_Y = 8
local TOGGLE_LABEL_PADDING_X = 4
local CATEGORY_TOGGLE_WIDTH = 20

local LEFT_MOUSE_BUTTON = MOUSE_BUTTON_INDEX_LEFT or 1
local RIGHT_MOUSE_BUTTON = MOUSE_BUTTON_INDEX_RIGHT or 2

local state = {
    control = nil,
    container = nil,
    fonts = {},
    opts = {},
    saved = nil,
    deps = {},
    snapshot = nil,
    orderedControls = {},
    lastAnchoredControl = nil,
    contentWidth = 0,
    contentHeight = 0,
    lastHeight = 0,
    controlId = 1,
    controls = {},
}

local debugLogOnce = {}

local function DebugLog(fmt, ...)
    if not IsDebugLoggingEnabled() then
        return
    end

    local ok, message = pcall(string.format, fmt, ...)
    if not ok then
        message = tostring(fmt)
    end

    if d then
        d(string.format("[%s] %s", MODULE_NAME, message))
    elseif print then
        print(string.format("[%s] %s", MODULE_NAME, message))
    end
end

local function IsDebugLoggingEnabled()
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

local function DebugLogOnce(key, fmt, ...)
    if not IsDebugLoggingEnabled() then
        return
    end

    if debugLogOnce[key] then
        return
    end

    debugLogOnce[key] = true

    local ok, message = pcall(string.format, fmt, ...)
    if not ok then
        message = tostring(fmt)
    end

    if d then
        d(string.format("[%s] %s", MODULE_NAME, message))
    elseif print then
        print(string.format("[%s] %s", MODULE_NAME, message))
    end
end

local function SafeCallDependency(key, fn, ...)
    if type(fn) ~= "function" then
        return nil, false
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        DebugLogOnce(key, "%s failed: %s", tostring(key), tostring(result))
        return nil, false
    end

    return result, true
end

local function ResetLayoutState()
    state.orderedControls = {}
    state.lastAnchoredControl = nil
end

local function SelectCategoryToggleTexture(expanded, hovered)
    if expanded then
        if hovered then
            return CATEGORY_TOGGLE_TEXTURES.expanded.over
        end
        return CATEGORY_TOGGLE_TEXTURES.expanded.up
    end

    if hovered then
        return CATEGORY_TOGGLE_TEXTURES.collapsed.over
    end
    return CATEGORY_TOGGLE_TEXTURES.collapsed.up
end

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
    if not toggle then
        return
    end

    toggle:SetMouseOverTexture(CATEGORY_TOGGLE_TEXTURES.expanded.over)
    toggle:SetMouseTexture(CATEGORY_TOGGLE_TEXTURES.expanded.over)
end

local function ApplyFont(label, font)
    if not label then
        return
    end

    if type(font) ~= "string" then
        local fallbackFont = font
        if fallbackFont == nil then
            fallbackFont = label.GetFont and label:GetFont()
        end

        if type(fallbackFont) == "string" then
            font = fallbackFont
        end
    end

    if type(font) == "string" and label.SetFont then
        label:SetFont(font)
    end
end

local function ApplyBaseColor(control, r, g, b, a)
    if not control then
        return
    end

    if control.SetColor then
        control:SetColor(r or 0, g or 0, b or 0, a or 1)
    end

    if control.SetAlpha then
        control:SetAlpha(a or 1)
    end

    if control.SetDesaturation then
        control:SetDesaturation(0)
    end

    control.baseColor = control.baseColor or {}
    control.baseColor.r = r or 0
    control.baseColor.g = g or 0
    control.baseColor.b = b or 0
    control.baseColor.a = a or 0
end

local function RestoreBaseColor(control)
    if not control then
        return
    end

    local baseColor = control.baseColor
    if baseColor then
        if control.SetAlpha then
            control:SetAlpha(baseColor.a or 1)
        end
        if control.SetDesaturation then
            control:SetDesaturation(0)
        end
        if control.SetColor then
            control:SetColor(baseColor.r or 0, baseColor.g or 0, baseColor.b or 0, baseColor.a or 1)
        end
    end

    if control.textColor then
        local color = control.textColor
        if control.SetColor then
            control:SetColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
        end
    end

    if control.borderColor then
        local color = control.borderColor
        if control.SetCenterColor then
            control:SetCenterColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
        end
        if control.SetEdgeColor then
            control:SetEdgeColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
        end
    end
end

local function ApplyMouseoverHighlight(control)
    if not control then
        return
    end

    local highlight = control.hoverColor or (Nvk3UT and Nvk3UT.DEFAULT_MOUSEOVER_HIGHLIGHT_COLOR)
    if type(highlight) == "table" and #highlight >= 3 and control.SetColor then
        control:SetColor(highlight[1], highlight[2], highlight[3], highlight[4] or 1)
        if control.SetAlpha then
            control:SetAlpha(highlight[4] or 1)
        end
        if control.SetDesaturation then
            control:SetDesaturation(0)
        end
        return
    end

    local defaultHighlight = state.deps.DefaultHighlight
    if type(defaultHighlight) == "table" then
        local color = defaultHighlight
        local alpha = color[4] or 1
        if control.SetAlpha then
            control:SetAlpha(alpha)
        end
        if control.SetDesaturation then
            control:SetDesaturation(1)
        end
        if control.SetColor then
            control:SetColor(color[1] or 1, color[2] or 1, color[3] or 1, alpha)
        end
        return
    end

    RestoreBaseColor(control)
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
    local container = state.container
    if not container or not container.GetWidth then
        return 0
    end

    local width = container:GetWidth()
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

local function UpdateCategoryToggle(control, expanded)
    if not control or not control.toggle then
        return
    end

    local hovered = control:IsMouseOver() == true
    control.toggle:SetTexture(SelectCategoryToggleTexture(expanded, hovered))
end

local function UpdateAchievementIconSlot(control)
    if not control or not control.iconSlot then
        return
    end

    if not control.data or control.data.isFavorite ~= true then
        control.iconSlot:SetTexture(nil)
        control.iconSlot:SetAlpha(0)
        return
    end

    local iconPath = Nvk3UT and Nvk3UT.FAVORITE_ICON
    if not iconPath then
        return
    end

    control.iconSlot:SetTexture(iconPath)
    control.iconSlot:SetAlpha(1)
end

local function FormatDisplayString(text)
    if text == nil then
        return ""
    end

    local value = text
    if type(value) ~= "string" then
        value = tostring(value)
    end

    if value == "" then
        return ""
    end

    if type(ZO_CachedStrFormat) == "function" then
        local ok, formatted = pcall(ZO_CachedStrFormat, "<<1>>", value)
        if ok and formatted ~= nil then
            return formatted
        end
    end

    if type(zo_strformat) == "function" then
        local ok, formatted = pcall(zo_strformat, "<<1>>", value)
        if ok and formatted ~= nil then
            return formatted
        end
    end

    return value
end

local function ShouldShowObjectiveCounter(objective)
    if not objective then
        return false
    end

    local maxValue = tonumber(objective.max)
    if not maxValue then
        return false
    end

    if maxValue <= 1 then
        return false
    end

    local current = objective.current
    if current == nil or current == "" then
        return false
    end

    return true
end

local function FormatObjectiveText(objective)
    local description = FormatDisplayString(objective.description)
    if description == "" then
        return ""
    end

    local text = description
    if ShouldShowObjectiveCounter(objective) then
        text = string.format("%s (%s/%s)", description, tostring(objective.current), tostring(objective.max))
    end

    return FormatDisplayString(text)
end

local function ShouldDisplayObjective(objective)
    if not objective then
        return false
    end

    if objective.isVisible == false then
        return false
    end

    if objective.isComplete then
        return false
    end

    local current = tonumber(objective.current)
    local maxValue = tonumber(objective.max)
    if current and maxValue and maxValue > 0 and current >= maxValue then
        return false
    end

    local text = objective.description
    if not text or text == "" then
        return false
    end

    return true
end

local function GetAchievementTrackerColor(role)
    local addon = rawget(_G, addonName)
    if addon and type(addon.GetColor) == "function" then
        return addon.GetColor(role, addon.DEFAULT_COLOR_KIND)
    end

    return 1, 1, 1, 1
end

local function IsFavoriteAchievement(achievementId)
    local achievementState = Nvk3UT and Nvk3UT.AchievementState
    if not achievementState then
        return false
    end

    local result, ok = SafeCallDependency("AchievementState.IsFavorite", achievementState.IsFavorite, achievementId)
    if ok and result ~= nil then
        return result == true
    end

    result, ok = SafeCallDependency("AchievementState.IsTodo", achievementState.IsTodo, achievementId)
    if ok and result ~= nil then
        return result == true
    end

    return false
end

local function IsRecentAchievement(achievementId)
    local achievementState = Nvk3UT and Nvk3UT.AchievementState
    if not achievementState then
        return false
    end

    local result, ok = SafeCallDependency("AchievementState.IsRecent", achievementState.IsRecent, achievementId)
    if ok then
        return result == true
    end

    return false
end

local function BuildTodoLookup()
    local achievementState = Nvk3UT and Nvk3UT.AchievementState
    if achievementState and achievementState.GetTodoLookup then
        local result, ok = SafeCallDependency("AchievementState.GetTodoLookup", achievementState.GetTodoLookup)
        if ok and type(result) == "table" then
            return result
        end
    end

    return nil
end

local function HasAnyFavoriteAchievements()
    local achievementState = Nvk3UT and Nvk3UT.AchievementState
    if not achievementState then
        return false
    end

    local result, ok = SafeCallDependency("AchievementState.HasAnyFavorites", achievementState.HasAnyFavorites)
    if ok and result then
        return true
    end

    local favoritesData
    result, ok = SafeCallDependency("AchievementState.GetFavoritesData", achievementState.GetFavoritesData)
    if ok then
        favoritesData = result
    end

    if favoritesData then
        result, ok = SafeCallDependency("FavoritesData.GetTotalFavoriteCount", favoritesData.GetTotalFavoriteCount)
        if ok and result and result > 0 then
            return true
        end
    end

    result, ok = SafeCallDependency("AchievementState.HasAnyTodos", achievementState.HasAnyTodos)
    if ok and result then
        return true
    end

    return false
end

local function LogCategoryExpansion(action, trigger, beforeExpanded, afterExpanded, source)
    local tracker = Nvk3UT and Nvk3UT.AchievementTracker
    local fn = tracker and tracker.LogCategoryExpansion
    if type(fn) == "function" then
        fn(action, trigger, beforeExpanded, afterExpanded, source)
    end
end

local function GetAchievementState()
    return Nvk3UT and Nvk3UT.AchievementState
end

local function IsCategoryExpanded()
    local achievementState = GetAchievementState()
    if achievementState and achievementState.IsGroupExpanded then
        local expanded = achievementState.IsGroupExpanded("achievements")
        if expanded ~= nil then
            return expanded ~= false
        end
    end

    local saved = state.saved
    if not saved then
        return true
    end
    if saved.categoryExpanded == nil then
        saved.categoryExpanded = true
    end
    return saved.categoryExpanded ~= false
end

local function SetCategoryExpanded(expanded, context)
    local beforeExpanded = IsCategoryExpanded()
    local afterExpanded = beforeExpanded
    local source = (context and context.source) or "AchievementTracker:SetCategoryExpanded"
    local achievementState = GetAchievementState()

    if achievementState and achievementState.SetGroupExpanded then
        achievementState.SetGroupExpanded("achievements", expanded, source)
        if achievementState.IsGroupExpanded then
            afterExpanded = achievementState.IsGroupExpanded("achievements") ~= false
        end
    elseif state.saved then
        state.saved.categoryExpanded = expanded and true or false
        afterExpanded = IsCategoryExpanded()
    end

    if beforeExpanded ~= afterExpanded then
        LogCategoryExpansion(
            afterExpanded and "expand" or "collapse",
            (context and context.trigger) or "unknown",
            beforeExpanded,
            afterExpanded,
            source
        )
    end
end

local function IsEntryExpanded(achievementId)
    local achievementState = GetAchievementState()

    if achievementState and achievementState.IsGroupExpanded then
        local expanded = achievementState.IsGroupExpanded(achievementId)
        if expanded ~= nil then
            return expanded ~= false
        end
    end

    return true
end

local function SetEntryExpanded(achievementId, expanded, source)
    local achievementState = GetAchievementState()
    if achievementState and achievementState.SetGroupExpanded then
        achievementState.SetGroupExpanded(achievementId, expanded, source or "AchievementTracker:SetEntryExpanded")
        return
    end

    local saved = state.saved
    if not saved or not achievementId then
        return
    end

    saved.expanded = saved.expanded or {}
    saved.expanded[achievementId] = expanded and true or false
end

local function ShowAchievementContextMenu(control, data)
    if not control then
        return
    end

    local addon = rawget(_G, addonName)
    if addon and type(addon.ShowAchievementContextMenu) == "function" then
        addon.ShowAchievementContextMenu(control, data)
    end
end

local function ScheduleToggleFollowup(reason)
    local rebuild = (Nvk3UT and Nvk3UT.Rebuild) or _G.Nvk3UT_Rebuild
    if rebuild and type(rebuild.ScheduleToggleFollowup) == "function" then
        rebuild.ScheduleToggleFollowup(reason)
    end
end

local function CreateControlFromTemplate(templateName)
    local controlName = string.format("%s_Control_%s", MODULE_NAME, tostring(state.controlId))
    state.controlId = state.controlId + 1
    local control = CreateControlFromVirtual(controlName, state.container, templateName)
    state.controls[#state.controls + 1] = control
    return control
end

local function LayoutObjective(achievement, objective)
    if not ShouldDisplayObjective(objective) then
        return
    end

    local text = FormatObjectiveText(objective)
    if text == "" then
        return
    end

    local control = CreateControlFromTemplate("AchievementObjective_Template")
    control.label = control:GetNamedChild("Label")
    control.rowType = "objective"
    ApplyLabelDefaults(control.label)
    ApplyFont(control.label, state.fonts.objective)

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
    local control = CreateControlFromTemplate("AchievementHeader_Template")
    control.label = control:GetNamedChild("Label")
    control.iconSlot = control:GetNamedChild("IconSlot")
    control.rowType = "achievement"
    ApplyLabelDefaults(control.label)
    ApplyFont(control.label, state.fonts.achievement)

    local hasObjectives = achievement.objectives and #achievement.objectives > 0
    local isFavorite = IsFavoriteAchievement(achievement.id)
    control.data = {
        achievementId = achievement.id,
        hasObjectives = hasObjectives,
        isFavorite = isFavorite,
    }

    if control.iconSlot then
        control.iconSlot:SetDimensions(ACHIEVEMENT_ICON_SLOT_WIDTH, ACHIEVEMENT_ICON_SLOT_HEIGHT)
        control.iconSlot:ClearAnchors()
        control.iconSlot:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
        control.iconSlot:SetTexture(nil)
        control.iconSlot:SetAlpha(0)
        control.iconSlot:SetHidden(false)
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
        if not upInside then
            return
        end

        if button == LEFT_MOUSE_BUTTON then
            if not ctrl.data or not ctrl.data.achievementId or not ctrl.data.hasObjectives then
                return
            end
            local achievementId = ctrl.data.achievementId
            local expanded = not IsEntryExpanded(achievementId)
            SetEntryExpanded(achievementId, expanded, "AchievementTracker:ToggleAchievementObjectives")
            if Nvk3UT and Nvk3UT.AchievementTracker then
                Nvk3UT.AchievementTracker.Refresh()
            end
            ScheduleToggleFollowup("achievementEntryToggle")
        elseif button == RIGHT_MOUSE_BUTTON then
            if not ctrl.data or not ctrl.data.achievementId then
                return
            end
            ShowAchievementContextMenu(ctrl, ctrl.data)
        end
    end)
    control:SetHandler("OnMouseEnter", function(ctrl)
        ApplyMouseoverHighlight(ctrl)
    end)
    control:SetHandler("OnMouseExit", function(ctrl)
        RestoreBaseColor(ctrl)
    end)

    control.label:SetText(FormatDisplayString(achievement.name))
    local r, g, b, a = GetAchievementTrackerColor("entryTitle")
    ApplyBaseColor(control, r, g, b, a)

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

    if not HasAnyFavoriteAchievements() then
        return
    end

    local control = CreateControlFromTemplate("AchievementsCategoryHeader_Template")
    control.label = control:GetNamedChild("Label")
    control.toggle = control:GetNamedChild("Toggle")
    control.rowType = "category"
    control.isExpanded = false

    ApplyLabelDefaults(control.label)
    ApplyToggleDefaults(control.toggle)
    ApplyFont(control.label, state.fonts.category)
    ApplyFont(control.toggle, state.fonts.toggle)

    control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
        if not upInside or button ~= LEFT_MOUSE_BUTTON then
            return
        end
        local expanded = not IsCategoryExpanded()
        SetCategoryExpanded(expanded, {
            trigger = "click",
            source = "AchievementTracker:OnCategoryClick",
        })
        if Nvk3UT and Nvk3UT.AchievementTracker then
            Nvk3UT.AchievementTracker.Refresh()
        end
        ScheduleToggleFollowup("achievementCategoryToggle")
    end)
    control:SetHandler("OnMouseEnter", function(ctrl)
        ApplyMouseoverHighlight(ctrl)
        local expanded = ctrl.isExpanded
        if expanded == nil then
            expanded = IsCategoryExpanded()
        end
        UpdateCategoryToggle(ctrl, expanded)
    end)
    control:SetHandler("OnMouseExit", function(ctrl)
        RestoreBaseColor(ctrl)
        local expanded = ctrl.isExpanded
        if expanded == nil then
            expanded = IsCategoryExpanded()
        end
        UpdateCategoryToggle(ctrl, expanded)
    end)

    local formatCategoryHeader = state.deps.FormatCategoryHeaderText
    if type(formatCategoryHeader) == "function" then
        control.label:SetText(formatCategoryHeader(
            GetString(SI_NVK3UT_TRACKER_ACHIEVEMENT_CATEGORY_MAIN),
            total or 0,
            state.deps.ShouldShowAchievementCategoryCounts and state.deps.ShouldShowAchievementCategoryCounts()
        ))
    end

    local expanded = IsCategoryExpanded()
    local colorRole = expanded and "activeTitle" or "categoryTitle"
    local r, g, b, a = GetAchievementTrackerColor(colorRole)
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

local function DestroyControls()
    for index = 1, #state.controls do
        local control = state.controls[index]
        if control then
            if control.SetHidden then
                control:SetHidden(true)
            end
            if control.ClearAnchors then
                control:ClearAnchors()
            end
            if control.SetParent then
                control:SetParent(nil)
            end
        end
    end

    state.controls = {}
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
    local normalize = state.deps.NormalizeMetric
    if type(normalize) == "function" then
        state.lastHeight = normalize(totalHeight)
    else
        state.lastHeight = totalHeight
    end
end

local function Rebuild(snapshot)
    state.snapshot = snapshot or state.snapshot

    if not state.container then
        return
    end

    local achievements = (state.snapshot and state.snapshot.achievements) or {}
    local itemCount = type(achievements) == "table" and #achievements or 0
    DebugLog("AchievementRows: BuildOrRebuildRows (items=%d)", itemCount)

    DestroyControls()
    ResetLayoutState()

    LayoutCategory()

    UpdateContentSize()

    local rowsCount = #state.orderedControls
    DebugLog("AchievementRows: BuildOrRebuildRows done (rows=%d)", rowsCount)
end

function Rows.Initialize(params)
    state.control = params and params.control or state.control
    state.container = params and params.container or state.container
    state.fonts = params and params.fonts or state.fonts
    state.opts = params and params.opts or state.opts
    state.saved = params and params.saved or state.saved
    state.deps = params and params.deps or state.deps or {}
end

function Rows.SetFonts(fonts)
    state.fonts = fonts or {}
end

function Rows.SetOptions(opts)
    state.opts = opts or {}
end

function Rows.SetSaved(saved)
    state.saved = saved
end

function Rows.SetDependencies(deps)
    state.deps = deps or state.deps or {}
end

function Rows.Rebuild(snapshot)
    Rebuild(snapshot)
end

function Rows.Shutdown()
    DestroyControls()
    state.container = nil
    state.control = nil
    state.snapshot = nil
    state.fonts = {}
    state.opts = {}
    state.saved = nil
    state.deps = {}
    ResetLayoutState()
    state.contentWidth = 0
    state.contentHeight = 0
    state.lastHeight = 0
    state.controlId = 1
end

function Rows.GetContentSize()
    UpdateContentSize()
    return state.contentWidth or 0, state.contentHeight or 0, state.lastHeight or 0
end

function Rows.GetOrderedControls()
    return state.orderedControls
end

function Rows.GetLastControl()
    return state.lastAnchoredControl
end

Nvk3UT.AchievementTrackerRows = Rows

return Rows
