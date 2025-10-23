local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local AchievementTracker = {}
AchievementTracker.__index = AchievementTracker

local MODULE_NAME = addonName .. "AchievementTracker"

local ICON_EXPANDED = "\226\150\190" -- ▼
local ICON_COLLAPSED = "\226\150\182" -- ▶

local CATEGORY_INDENT_X = 0
local ACHIEVEMENT_INDENT_X = 18
local OBJECTIVE_INDENT_X = 36
local VERTICAL_PADDING = 3

local CATEGORY_KEY = "achievements"

local DEFAULT_FONTS = {
    category = "ZoFontGameBold",
    achievement = "ZoFontGame",
    objective = "ZoFontGameSmall",
    toggle = "ZoFontGame",
}

local DEFAULT_BACKDROP = {
    centerColor = { 0, 0, 0, 0.35 },
    edgeColor = { 0, 0, 0, 0.5 },
    edgeTexture = "EsoUI/Art/Tooltips/UI-Border.dds",
    tileSize = 64,
    edgeFileWidth = 16,
}

local unpack = table.unpack or unpack
local LEFT_MOUSE_BUTTON = MOUSE_BUTTON_INDEX_LEFT or 1

local DEFAULT_FONT_OUTLINE = "soft-shadow-thin"
local REFRESH_DEBOUNCE_MS = 80

local state = {
    isInitialized = false,
    opts = {},
    fonts = {},
    saved = nil,
    control = nil,
    container = nil,
    backdrop = nil,
    categoryPool = nil,
    achievementPool = nil,
    objectivePool = nil,
    orderedControls = {},
    lastAnchoredControl = nil,
    snapshot = nil,
    subscription = nil,
    padding = 0,
    theme = nil,
    pendingRefresh = false,
}

local function DebugLog(...)
    if not state.opts.debug then
        return
    end

    if d then
        d(string.format("[%s]", MODULE_NAME), ...)
    elseif print then
        print("[" .. MODULE_NAME .. "]", ...)
    end
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

local function ApplyContainerPadding()
    if not state.container or not state.control then
        return
    end

    local inset = tonumber(state.padding) or 0
    state.container:ClearAnchors()
    state.container:SetAnchor(TOPLEFT, state.control, TOPLEFT, inset, inset)
    state.container:SetAnchor(BOTTOMRIGHT, state.control, BOTTOMRIGHT, -inset, -inset)
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

local function EnsureBackdrop()
    if not state.control then
        return
    end

    local theme = state.theme or {}
    local background = theme.backdrop

    if not background then
        if state.backdrop then
            if state.backdrop.Destroy then
                state.backdrop:Destroy()
            else
                state.backdrop:SetHidden(true)
                state.backdrop:SetParent(nil)
            end
        end
        state.backdrop = nil
        if state.control then
            state.control.backdrop = nil
        end
        return
    end

    if not state.backdrop then
        local control = WINDOW_MANAGER and WINDOW_MANAGER:CreateControl(nil, state.control, CT_BACKDROP)
        if not control then
            return
        end

        control:SetAnchorFill()
        control:SetDrawLayer(DL_BACKGROUND)
        control:SetDrawTier(DT_LOW)
        control:SetDrawLevel(0)
        if control.SetExcludeFromResizeToFitExtents then
            control:SetExcludeFromResizeToFitExtents(true)
        end
        state.backdrop = control
    end

    local control = state.backdrop
    if control.SetInsets then
        control:SetInsets(0, 0, 0, 0)
    end
    if background.edgeTexture then
        control:SetEdgeTexture(background.edgeTexture, background.tileSize or 128, background.edgeFileWidth or 16)
    end

    if background.centerColor then
        control:SetCenterColor(unpack(background.centerColor))
    end

    if background.edgeColor then
        control:SetEdgeColor(unpack(background.edgeColor))
    end

    control:SetHidden(false)
    if state.control then
        state.control.backdrop = control
    end
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
        control:SetAnchor(TOPLEFT, state.lastAnchoredControl, BOTTOMLEFT, indentX, VERTICAL_PADDING)
        control:SetAnchor(TOPRIGHT, state.lastAnchoredControl, BOTTOMRIGHT, 0, VERTICAL_PADDING)
    else
        control:SetAnchor(TOPLEFT, state.container, TOPLEFT, indentX, 0)
        control:SetAnchor(TOPRIGHT, state.container, TOPRIGHT, 0, 0)
    end

    state.lastAnchoredControl = control
    state.orderedControls[#state.orderedControls + 1] = control
    control.currentIndent = indentX
end

local function UpdateAutoSize()
    if not state.control then
        return
    end

    local paddingWidth = 0
    local paddingHeight = 0

    if state.padding and state.padding > 0 then
        local inset = state.padding * 2
        paddingWidth = paddingWidth + inset
        paddingHeight = paddingHeight + inset
    end

    local maxWidth = 0
    local totalHeight = 0
    local visibleCount = 0

    for index = 1, #state.orderedControls do
        local control = state.orderedControls[index]
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

    if state.opts.autoGrowH and maxWidth > 0 and state.control.SetWidth then
        state.control:SetWidth(maxWidth + paddingWidth)
    end

    if state.opts.autoGrowV and totalHeight > 0 and state.control.SetHeight then
        state.control:SetHeight(totalHeight + paddingHeight)
    end
end

local function AttachBackdrop()
    EnsureBackdrop()
end

local function EnsureContainer()
    if state.container or not WINDOW_MANAGER then
        return
    end

    local container = WINDOW_MANAGER:CreateControl(nil, state.control, CT_CONTROL)
    if not container then
        return
    end

    container:SetAnchorFill()
    container:SetResizeToFitDescendents(true)
    state.container = container
    if state.control then
        state.control.holder = container
    end
end

local function SetCategoryExpanded(expanded)
    if not state.saved then
        return
    end
    state.saved.categoryExpanded = expanded and true or false
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

local function UpdateCategoryToggle(control, expanded)
    if not control or not control.toggle then
        return
    end
    control.toggle:SetHidden(false)
    control.toggle:SetText(expanded and ICON_EXPANDED or ICON_COLLAPSED)
end

local function UpdateAchievementToggle(control, expanded, hasObjectives)
    if not control or not control.toggle then
        return
    end
    if not hasObjectives then
        control.toggle:SetHidden(true)
        control.toggle:SetText("")
        return
    end
    control.toggle:SetHidden(false)
    control.toggle:SetText(expanded and ICON_EXPANDED or ICON_COLLAPSED)
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
        control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
            if not upInside or button ~= LEFT_MOUSE_BUTTON then
                return
            end
            local expanded = not IsCategoryExpanded()
            SetCategoryExpanded(expanded)
            AchievementTracker.Refresh()
        end)
        control.initialized = true
    end
    ApplyFont(control.label, state.fonts.category)
    ApplyFont(control.toggle, state.fonts.toggle)
    return control
end

local function AcquireAchievementControl()
    local control = state.achievementPool:AcquireObject()
    if not control.initialized then
        control.label = control:GetNamedChild("Label")
        control.toggle = control:GetNamedChild("Toggle")
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
    ApplyFont(control.label, state.fonts.achievement)
    ApplyFont(control.toggle, state.fonts.toggle)
    return control
end

local function AcquireObjectiveControl()
    local control = state.objectivePool:AcquireObject()
    if not control.initialized then
        control.label = control:GetNamedChild("Label")
        control.initialized = true
    end
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
    end)

    state.achievementPool:SetCustomResetBehavior(function(control)
        resetControl(control)
        if control.toggle then
            control.toggle:SetText("")
            control.toggle:SetHidden(false)
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

    local expanded = hasObjectives and IsEntryExpanded(achievement.id)
    UpdateAchievementToggle(control, expanded, hasObjectives)

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
    local showFavorites = sections.favorites ~= false
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
    control.label:SetText(string.format("Errungenschaften (%d)", total or 0))

    local expanded = IsCategoryExpanded()
    UpdateCategoryToggle(control, expanded)

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

    UpdateAutoSize()
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

local function ApplyLockState()
    if not state.control or not state.control.SetMovable then
        return
    end

    if state.opts.lock == nil then
        return
    end

    state.control:SetMovable(not state.opts.lock)
end

function AchievementTracker.Init(parentControl, opts)
    if not parentControl then
        error("AchievementTracker.Init requires a parent control")
    end

    if state.isInitialized then
        AchievementTracker.Shutdown()
    end

    state.control = parentControl
    EnsureSavedVars()

    state.opts = {}
    state.fonts = {}

    AchievementTracker.ApplyTheme(state.saved or {})
    AchievementTracker.ApplySettings(state.saved or {})

    if opts then
        AchievementTracker.ApplyTheme(opts)
        AchievementTracker.ApplySettings(opts)
    end

    EnsureContainer()
    ApplyContainerPadding()
    AttachBackdrop()
    ApplyLockState()

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

    if state.backdrop then
        if state.backdrop.Destroy then
            state.backdrop:Destroy()
        else
            state.backdrop:SetHidden(true)
            state.backdrop:SetParent(nil)
        end
    end
    state.backdrop = nil

    if state.container then
        if state.container.Destroy then
            state.container:Destroy()
        else
            state.container:SetHidden(true)
            state.container:SetParent(nil)
        end
    end
    state.container = nil

    if state.control then
        state.control.backdrop = nil
        state.control.holder = nil
    end
    state.control = nil
    state.snapshot = nil
    state.orderedControls = {}
    state.lastAnchoredControl = nil
    state.fonts = {}
    state.opts = {}

    state.isInitialized = false
    state.theme = nil
    state.padding = 0
    state.pendingRefresh = false
end

local function BuildBackdropOptions(background)
    if type(background) ~= "table" or background.enabled == false then
        return nil
    end

    local alpha = tonumber(background.alpha) or DEFAULT_BACKDROP.centerColor[4]
    local edgeAlpha = tonumber(background.edgeAlpha) or DEFAULT_BACKDROP.edgeColor[4]

    return {
        edgeTexture = DEFAULT_BACKDROP.edgeTexture,
        tileSize = DEFAULT_BACKDROP.tileSize,
        edgeFileWidth = DEFAULT_BACKDROP.edgeFileWidth,
        centerColor = { 0, 0, 0, alpha },
        edgeColor = { 0, 0, 0, edgeAlpha },
    }
end

local function ApplyAutoGrow(settings)
    if type(settings) ~= "table" then
        return
    end

    if settings.autoGrowV ~= nil then
        state.opts.autoGrowV = settings.autoGrowV and true or false
    end

    if settings.autoGrowH ~= nil then
        state.opts.autoGrowH = settings.autoGrowH and true or false
    end
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

    state.opts.lock = settings.lock ~= nil and settings.lock or state.opts.lock
    state.opts.active = settings.active ~= false
    ApplyAutoGrow(settings)
    ApplySections(settings.sections)
    if settings.tooltips ~= nil then
        ApplyTooltipsSetting(settings.tooltips)
    end

    ApplyLockState()
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

    local background = settings.background or settings.backdrop or {}
    state.theme = state.theme or {}
    state.theme.backdrop = BuildBackdropOptions(background)
    state.padding = tonumber(background.padding) or state.padding or 0

    ApplyContainerPadding()
    EnsureBackdrop()
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

-- Ensure the container exists before applying padding/backdrop during init
Nvk3UT.AchievementTracker = AchievementTracker

return AchievementTracker
