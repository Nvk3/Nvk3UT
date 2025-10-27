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
            local numericCount = math_floor(count + 0.5)
            return string_format("%s (%d)", text, numericCount)
        end
        return text
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

local string_format = string.format
local math_floor = math.floor
local math_max = math.max
local tostring = tostring
local type = type
local pairs = pairs
local WINDOW_MANAGER = WINDOW_MANAGER

local STRUCTURE_REBUILD_BATCH_SIZE = 12
local ACHIEVEMENT_REBUILD_TASK_NAME = MODULE_NAME .. "_StructureRebuild"
local Async = LibAsync

local DEFAULT_FONTS = {
    category = "$(BOLD_FONT)|20|soft-shadow-thick",
    achievement = "$(BOLD_FONT)|16|soft-shadow-thick",
    objective = "$(BOLD_FONT)|14|soft-shadow-thick",
    toggle = "$(BOLD_FONT)|20|soft-shadow-thick",
}

local unpack = table.unpack or unpack
local LEFT_MOUSE_BUTTON = MOUSE_BUTTON_INDEX_LEFT or 1
local RIGHT_MOUSE_BUTTON = MOUSE_BUTTON_INDEX_RIGHT or 2

local DEFAULT_FONT_OUTLINE = "soft-shadow-thick"
local COLOR_ROW_HOVER = { 1, 1, 0.6, 1 }
local FOCUS_HIGHLIGHT_DURATION_MS = 1600

local FAVORITES_LOOKUP_KEY = "NVK3UT_FAVORITES_ROOT"
local FAVORITES_CATEGORY_ID = "Nvk3UT_Favorites"

local function GenerateControlName(controlType)
    local counters = state.controlNameCounters
    if not counters then
        counters = {}
        state.controlNameCounters = counters
    end

    counters[controlType] = (counters[controlType] or 0) + 1

    local container = state.container
    local baseName = (container and container.GetName and container:GetName()) or MODULE_NAME

    return string_format("%s_%s_%d", baseName, controlType or "control", counters[controlType])
end

local NormalizeAchievementKey -- forward declaration for achievement row registry keys
local ApplyAchievementRowVisuals -- forward declaration for the achievement row refresh helper
local ResolveAchievementRowData -- forward declaration for row data resolution
local EnsurePools -- forward declaration for achievement control pooling
local AcquireCategoryControlFromPool -- forward declaration for category pool access
local AcquireAchievementControlFromPool -- forward declaration for achievement pool access
local ReleaseObjectiveControls -- forward declaration for releasing pooled objective controls

--[=[
AchievementTrackerRow encapsulates the data and controls for a single
achievement entry row. The instance keeps a stable reference to the
achievement it represents and the control that renders it so future updates
can refresh the row in isolation, mirroring the per-row strategy used by
Ravalox without altering behaviour yet.
]=]
local AchievementTrackerRow = {}
AchievementTrackerRow.__index = AchievementTrackerRow

function AchievementTrackerRow:New(options)
    local opts = options or {}
    local instance = setmetatable({}, AchievementTrackerRow)
    instance.achievementKey = opts.achievementKey
    instance.achievement = opts.achievement
    instance.control = opts.control
    instance.hasObjectives = false
    instance.isExpanded = false
    instance.isFavorite = false
    instance.lastHeight = 0
    return instance
end

function AchievementTrackerRow:SetControl(control)
    self.control = control
end

function AchievementTrackerRow:ClearControl()
    self.control = nil
    self.lastHeight = 0
end

function AchievementTrackerRow:DetachControl()
    local control = self.control
    self:ClearControl()
    return control
end

function AchievementTrackerRow:SetAchievement(achievementData)
    self.achievement = achievementData
    if NormalizeAchievementKey then
        local key = NormalizeAchievementKey(achievementData and achievementData.id)
        if key then
            self.achievementKey = key
        end
    end
end

function AchievementTrackerRow:Refresh(achievementData)
    local resolvedData = achievementData
    if resolvedData == nil and ResolveAchievementRowData then
        resolvedData = ResolveAchievementRowData(self.achievementKey)
    end

    if resolvedData ~= nil then
        self:SetAchievement(resolvedData)
    end

    local control = self.control
    local achievement = self.achievement

    if not (control and achievement) then
        return false, false
    end

    if not (ApplyAchievementRowVisuals and achievement) then
        return false, false
    end

    local hasObjectives, isExpanded, isFavorite = ApplyAchievementRowVisuals(control, achievement)
    self.hasObjectives = hasObjectives and true or false
    self.isExpanded = isExpanded and true or false
    self.isFavorite = isFavorite and true or false
    local getHeight = control.GetHeight
    if getHeight then
        self.lastHeight = getHeight(control) or 0
    end
    return self.hasObjectives, self.isExpanded
end

function AchievementTrackerRow:GetHeight()
    if self.control and self.control.GetHeight then
        self.lastHeight = self.control:GetHeight() or self.lastHeight or 0
    end

    return self.lastHeight or 0
end

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
    objectiveActiveControls = {},
    orderedControls = {},
    categoryControls = {},
    achievementControls = {},
    achievementControlsByKey = {},
    achievementRows = {}, -- registry of AchievementTrackerRow instances keyed by normalized achievement id
    lastAnchoredControl = nil,
    snapshot = nil,
    subscription = nil,
    contentWidth = 0,
    contentHeight = 0,
    pendingFocusAchievementId = nil,
    reusableCategoryControls = nil,
    reusableAchievementControls = nil,
    rebuildJob = nil,
    activeRebuildContext = nil,
    isRebuildInProgress = false,
}

ResolveAchievementRowData = function(achievementKey)
    local key = NormalizeAchievementKey and NormalizeAchievementKey(achievementKey)
    if not key then
        return nil
    end

    local cachedRow = state.achievementRows and state.achievementRows[key]
    if cachedRow and cachedRow.achievement then
        return cachedRow.achievement
    end

    local snapshot = state.snapshot
    local achievements = snapshot and snapshot.achievements
    if not achievements then
        return nil
    end

    for index = 1, #achievements do
        local achievement = achievements[index]
        if achievement then
            local normalized = NormalizeAchievementKey and NormalizeAchievementKey(achievement.id)
            if normalized == key then
                return achievement
            end
        end
    end

    return nil
end

local function QueueAchievementStructureUpdate(context)
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host and host.MarkAchievementsStructureDirty then
        host.MarkAchievementsStructureDirty(context)
    end
end

local function QueueLayoutUpdate(context)
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host and host.MarkLayoutDirty then
        host.MarkLayoutDirty(context)
    end
end

local function GetAchievementRebuildJob()
    state.rebuildJob = state.rebuildJob or {
        active = false,
        restartRequested = false,
        batchSize = STRUCTURE_REBUILD_BATCH_SIZE,
        totalProcessed = 0,
        reason = nil,
    }

    return state.rebuildJob
end

local function ClearActiveRebuildContext()
    state.activeRebuildContext = nil
end

local function ShouldAbortRebuild()
    local job = state.rebuildJob
    return job and job.active and job.restartRequested == true
end

local function ConsumeStructureBudget(amount)
    local context = state.activeRebuildContext
    if not context then
        return
    end

    local processed = amount or 1
    context.pending = (context.pending or 0) + processed
    context.total = (context.total or 0) + processed

    local job = state.rebuildJob
    if job and job.active then
        job.totalProcessed = (job.totalProcessed or 0) + processed
    end

    local batchSize = context.batchSize or STRUCTURE_REBUILD_BATCH_SIZE

    if context.pending >= batchSize then
        context.pending = 0
        context.batches = (context.batches or 0) + 1

        if context.onBatchReady then
            context.onBatchReady(context)
        end

        local task = context.task
        if task and task.Yield then
            task:Yield()
        end
    end
end

local function QueueAchievementRowRefreshByKey(achievementKey, context)
    local normalized = achievementKey
    if NormalizeAchievementKey then
        normalized = NormalizeAchievementKey(achievementKey) or achievementKey
    end

    if normalized == nil then
        return false
    end

    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host and host.QueueAchievementRowRefresh then
        return host.QueueAchievementRowRefresh(normalized, context)
    end
    return false
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
    if not toggle or not toggle.SetVerticalAlignment then
        return
    end

    toggle:SetVerticalAlignment(TEXT_ALIGN_TOP)
end

function NormalizeAchievementKey(value)
    if value == nil then
        return nil
    end

    local numeric = tonumber(value)
    if numeric and numeric > 0 then
        return tostring(numeric)
    end

    if type(value) == "string" and value ~= "" then
        return value
    end

    return nil
end

local function GetAchievementTrackerColor(role)
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host then
        if host.EnsureAppearanceDefaults then
            host.EnsureAppearanceDefaults()
        end
        if host.GetTrackerColor then
            return host.GetTrackerColor("achievementTracker", role)
        end
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
        targetHeight = math_max(minHeight, targetHeight)
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
        local achievementId = control.data and control.data.achievementId
        local achievementKey = achievementId
        if NormalizeAchievementKey then
            achievementKey = NormalizeAchievementKey(achievementId) or achievementId
        end
        local row = achievementKey and state.achievementRows[achievementKey]
        if row then
            row:SetControl(control)
        end
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
        d(string_format("[%s]", MODULE_NAME), ...)
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
        parts[#parts + 1] = string_format("%s=nil", key)
        return
    end

    local valueType = type(value)
    if valueType == "boolean" then
        parts[#parts + 1] = string_format("%s=%s", key, value and "true" or "false")
    elseif valueType == "number" then
        parts[#parts + 1] = string_format("%s=%s", key, tostring(value))
    elseif treatAsString or valueType == "string" then
        parts[#parts + 1] = string_format('%s="%s"', key, EscapeDebugString(value))
    else
        parts[#parts + 1] = string_format("%s=%s", key, tostring(value))
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

    return string_format("%s|%d|%s", face, size, outline or DEFAULT_FONT_OUTLINE)
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

local function RemoveAchievementFromFavorites(achievementId)
    local numeric = tonumber(achievementId)
    if not numeric or numeric <= 0 then
        return
    end

    local Fav = Nvk3UT and Nvk3UT.FavoritesData
    if not (Fav and Fav.Remove) then
        return
    end

    Fav.Remove(numeric, BuildFavoritesScope())

    if AchievementTracker and AchievementTracker.RequestRefresh then
        AchievementTracker.RequestRefresh()
    end
end

local function ResolveAchievementEntry(achievementsSystem, achievementId)
    if not achievementsSystem or not achievementsSystem.achievementsById then
        return nil
    end

    local candidates = {}
    if achievementId ~= nil then
        candidates[#candidates + 1] = achievementId
    end

    local numericId = tonumber(achievementId)
    if numericId and numericId ~= achievementId then
        candidates[#candidates + 1] = numericId
    end

    local stringId = tostring(achievementId)
    if stringId ~= achievementId then
        candidates[#candidates + 1] = stringId
    end

    for index = 1, #candidates do
        local key = candidates[index]
        if key ~= nil then
            local entry = achievementsSystem.achievementsById[key]
            if entry then
                return entry
            end
        end
    end

    return nil
end

local function FocusAchievementInSystem(achievementsSystem, manager, achievementId, originalId)
    if not achievementsSystem then
        return false
    end

    local numericId = tonumber(achievementId)
    local lookupId = originalId or achievementId

    if numericId and achievementsSystem.FocusAchievement then
        local ok = pcall(achievementsSystem.FocusAchievement, achievementsSystem, numericId)
        if ok then
            return true
        end
    end

    local entry = ResolveAchievementEntry(achievementsSystem, lookupId)
    if entry then
        if entry.Expand then
            entry:Expand()
        end
        if entry.Select then
            entry:Select()
        end
        if entry.GetControl and achievementsSystem.contentList and ZO_Scroll_ScrollControlIntoCentralView then
            local control = entry:GetControl()
            if control then
                ZO_Scroll_ScrollControlIntoCentralView(achievementsSystem.contentList, control)
            end
        end
        return true
    end

    if manager and numericId then
        if manager.SelectAchievement then
            local ok, result = pcall(manager.SelectAchievement, manager, numericId)
            if ok and result ~= false then
                return true
            end
        end

        if manager.ShowAchievement then
            local ok, result = pcall(manager.ShowAchievement, manager, numericId)
            if ok and result ~= false then
                return true
            end
        end
    end

    return false
end

local function GetAchievementsSystem()
    local system
    if SYSTEMS and SYSTEMS.GetObject then
        local ok, result = pcall(SYSTEMS.GetObject, SYSTEMS, "achievements")
        if ok then
            system = result
        end
    end
    return system or ACHIEVEMENTS
end

local function CanOpenAchievement(achievementId)
    local numeric = tonumber(achievementId)
    if not numeric or numeric <= 0 then
        return false
    end

    if type(GetAchievementInfo) ~= "function" then
        return false
    end

    local ok, name = pcall(GetAchievementInfo, numeric)
    if not ok then
        return false
    end

    if type(name) == "string" then
        return name ~= ""
    end

    return true
end

local function OpenAchievementInJournal(achievementId)
    local originalId = achievementId
    local numeric = tonumber(achievementId)
    if not numeric or numeric <= 0 then
        return false
    end

    if type(GetAchievementInfo) == "function" then
        local ok, name = pcall(GetAchievementInfo, numeric)
        if not ok or (type(name) == "string" and name == "") then
            return false
        end
    end

    if SCENE_MANAGER and SCENE_MANAGER.IsShowing and not SCENE_MANAGER:IsShowing("achievements") then
        SCENE_MANAGER:Show("achievements")
    end

    local manager = ACHIEVEMENTS_MANAGER

    if manager and manager.ShowAchievement then
        local ok, result = pcall(manager.ShowAchievement, manager, numeric)
        if ok and result ~= false then
            return true
        end
    end

    local achievementsSystem = GetAchievementsSystem()
    if not achievementsSystem then
        return false
    end

    if achievementsSystem.contentSearchEditBox and achievementsSystem.contentSearchEditBox.GetText then
        if achievementsSystem.contentSearchEditBox:GetText() ~= "" then
            achievementsSystem.contentSearchEditBox:SetText("")
            if manager and manager.ClearSearch then
                manager:ClearSearch(true)
            end
        end
    end

    if type(GetCategoryInfoFromAchievementId) == "function" then
        local ok, categoryIndex, subCategoryIndex = pcall(GetCategoryInfoFromAchievementId, numeric)
        if ok and categoryIndex then
            if achievementsSystem.OpenCategory then
                local openOk, opened = pcall(achievementsSystem.OpenCategory, achievementsSystem, categoryIndex, subCategoryIndex)
                if not openOk then
                    opened = false
                end
                if not opened and achievementsSystem.SelectCategory then
                    pcall(achievementsSystem.SelectCategory, achievementsSystem, categoryIndex, subCategoryIndex)
                end
            elseif achievementsSystem.SelectCategory then
                pcall(achievementsSystem.SelectCategory, achievementsSystem, categoryIndex, subCategoryIndex)
            end
        end
    end

    if FocusAchievementInSystem(achievementsSystem, manager, numeric, originalId) then
        return true
    end

    return false
end

local function SelectFavoritesCategory(achievementsSystem)
    if not achievementsSystem then
        return false
    end

    -- Drive the same favorites node that our UI exposes so manual clicks and
    -- context menu navigation share a single code path.
    local tree = achievementsSystem.categoryTree
    local node = achievementsSystem._nvkFavoritesNode
    if not node then
        local lookup = achievementsSystem.nodeLookupData
        if lookup then
            node = lookup[FAVORITES_LOOKUP_KEY]
        end
    end

    if node and tree and tree.SelectNode then
        local ok, result = pcall(tree.SelectNode, tree, node)
        if ok and result ~= false then
            return true
        end
    end

    local data = achievementsSystem._nvkFavoritesData
    if data and achievementsSystem.SelectCategory then
        local ok, result = pcall(
            achievementsSystem.SelectCategory,
            achievementsSystem,
            data.categoryIndex,
            data.subCategoryIndex
        )
        if ok and result ~= false then
            return true
        end
    end

    if achievementsSystem.SelectCategory then
        local ok, result = pcall(achievementsSystem.SelectCategory, achievementsSystem, FAVORITES_CATEGORY_ID)
        if ok and result ~= false then
            return true
        end
    end

    return false
end

local function CanShowInAchievements(achievementId)
    return CanOpenAchievement(achievementId)
end

local function ShowAchievementInAchievements(achievementId)
    local originalId = achievementId
    local numeric = tonumber(achievementId)
    if not numeric or numeric <= 0 then
        return false
    end

    if not SCENE_MANAGER or type(SCENE_MANAGER.Show) ~= "function" then
        return false
    end

    -- Let the base Achievements scene handle visibility before steering it to
    -- our custom favorites category.
    SCENE_MANAGER:Show("achievements")

    local function focusAchievement()
        local achievementsSystem = GetAchievementsSystem()
        if not achievementsSystem then
            return
        end

        SelectFavoritesCategory(achievementsSystem)

        local manager = ACHIEVEMENTS_MANAGER
        local function attemptFocus()
            FocusAchievementInSystem(achievementsSystem, manager, numeric, originalId)
        end

        if type(zo_callLater) == "function" then
            zo_callLater(attemptFocus, 20)
        else
            attemptFocus()
        end
    end

    if type(zo_callLater) == "function" then
        zo_callLater(focusAchievement, 30)
    else
        focusAchievement()
    end

    return true
end

local function BuildAchievementContextMenuEntries(data)
    local entries = {}

    local achievementId = data and data.achievementId

    entries[#entries + 1] = {
        label = "Aus Favoriten entfernen",
        enabled = function()
            return IsFavoriteAchievement(achievementId)
        end,
        callback = function()
            if achievementId and IsFavoriteAchievement(achievementId) then
                RemoveAchievementFromFavorites(achievementId)
            end
        end,
    }

    entries[#entries + 1] = {
        label = "In den Errungenschaften anzeigen",
        enabled = function()
            return CanShowInAchievements(achievementId)
        end,
        callback = function()
            if achievementId and CanShowInAchievements(achievementId) then
                ShowAchievementInAchievements(achievementId)
            end
        end,
    }

    return entries
end

local function ShowAchievementContextMenu(control, data)
    if not control then
        return
    end

    local entries = BuildAchievementContextMenuEntries(data)
    if #entries == 0 then
        return
    end

    if Utils and Utils.ShowContextMenu and Utils.ShowContextMenu(control, entries) then
        return
    end

    if not (ClearMenu and AddCustomMenuItem and ShowMenu) then
        return
    end

    ClearMenu()

    local added = 0
    local function evaluateGate(gate)
        if gate == nil then
            return true
        end

        local gateType = type(gate)
        if gateType == "function" then
            local ok, result = pcall(gate, control)
            if not ok then
                return false
            end
            return result ~= false
        elseif gateType == "boolean" then
            return gate
        end

        return true
    end

    for index = 1, #entries do
        local entry = entries[index]
        if entry and type(entry.label) == "string" and type(entry.callback) == "function" then
            if evaluateGate(entry.visible) then
                local enabled = evaluateGate(entry.enabled)
                local itemType = (_G and _G.MENU_ADD_OPTION_LABEL) or 1
                local originalCallback = entry.callback
                local callback = originalCallback
                if type(originalCallback) == "function" then
                    callback = function(...)
                        if type(ClearMenu) == "function" then
                            pcall(ClearMenu)
                        end
                        originalCallback(...)
                    end
                end
                local beforeCount
                if type(ZO_Menu_GetNumMenuItems) == "function" then
                    local ok, count = pcall(ZO_Menu_GetNumMenuItems)
                    if ok and type(count) == "number" then
                        beforeCount = count
                    end
                end
                AddCustomMenuItem(entry.label, callback, itemType)
                local afterCount
                if type(ZO_Menu_GetNumMenuItems) == "function" then
                    local ok, count = pcall(ZO_Menu_GetNumMenuItems)
                    if ok and type(count) == "number" then
                        afterCount = count
                    end
                end
                local itemIndex = afterCount or ((type(beforeCount) == "number" and beforeCount + 1) or nil)
                if itemIndex and type(SetMenuItemEnabled) == "function" then
                    pcall(SetMenuItemEnabled, itemIndex, enabled ~= false)
                end
                added = added + 1
            end
        end
    end

    if added > 0 then
        ShowMenu(control)
    else
        ClearMenu()
    end
end

local function HasAnyFavoriteAchievements()
    local Fav = Nvk3UT and Nvk3UT.FavoritesData
    if not (Fav and Fav.Iterate) then
        return false
    end

    local function scopeHasFavorites(scope)
        if not scope then
            return false
        end

        for id, isFavorite in Fav.Iterate(scope) do
            if id and isFavorite then
                return true
            end
        end

        return false
    end

    local scope = BuildFavoritesScope()
    if scopeHasFavorites(scope) then
        return true
    end

    if scope ~= "account" and scopeHasFavorites("account") then
        return true
    end

    if scope ~= "character" and scopeHasFavorites("character") then
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

local function RequestRefresh(context)
    if not state.isInitialized then
        return
    end

    QueueAchievementStructureUpdate(context or { reason = "AchievementTracker.RequestRefresh" })
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
    state.contentWidth = 0
    state.contentHeight = 0
end

local function ClearArray(array)
    if not array then
        return
    end

    for index = #array, 1, -1 do
        array[index] = nil
    end
end

local function ClearTable(tbl)
    if not tbl then
        return
    end

    for key in pairs(tbl) do
        tbl[key] = nil
    end
end

local function ResetBaseControl(control)
    if not control then
        return
    end

    if control.SetHidden then
        control:SetHidden(true)
    end
    if control.data then
        ClearTable(control.data)
    end
    control.currentIndent = nil
    control.baseColor = nil
    control.isExpanded = nil
end

local function ResetCategoryControl(control)
    ResetBaseControl(control)
    local toggle = control and control.toggle
    if toggle then
        if toggle.SetTexture then
            toggle:SetTexture(SelectCategoryToggleTexture(false, false))
        end
        if toggle.SetHidden then
            toggle:SetHidden(false)
        end
    end
end

local function ResetAchievementControl(control)
    ResetBaseControl(control)
    local label = control and control.label
    if label and label.SetText then
        label:SetText("")
    end

    local iconSlot = control and control.iconSlot
    if iconSlot then
        if iconSlot.SetTexture then
            iconSlot:SetTexture(nil)
        end
        if iconSlot.SetAlpha then
            iconSlot:SetAlpha(0)
        end
        if iconSlot.SetHidden then
            iconSlot:SetHidden(false)
        end
    end
end

local function ResetObjectiveControl(control)
    ResetBaseControl(control)
    local label = control and control.label
    if label and label.SetText then
        label:SetText("")
    end
end

ReleaseObjectiveControls = function()
    local active = state.objectiveActiveControls
    if not active then
        return
    end

    local pool = state.objectivePool
    if not pool then
        pool = {}
        state.objectivePool = pool
    end

    for index = #active, 1, -1 do
        local control = active[index]
        if control then
            ResetObjectiveControl(control)
            pool[#pool + 1] = control
        end
        active[index] = nil
    end
end

EnsurePools = function(forceReset)
    if not (state.container and WINDOW_MANAGER and WINDOW_MANAGER.CreateControlFromVirtual) then
        return false
    end

    state.objectiveActiveControls = state.objectiveActiveControls or {}

    if forceReset then
        ReleaseObjectiveControls()

        if state.categoryPool then
            for index = 1, #state.categoryPool do
                ResetCategoryControl(state.categoryPool[index])
            end
        end

        if state.achievementPool then
            for index = 1, #state.achievementPool do
                ResetAchievementControl(state.achievementPool[index])
            end
        end

        if state.objectivePool then
            for index = 1, #state.objectivePool do
                ResetObjectiveControl(state.objectivePool[index])
            end
        end
    end

    state.categoryPool = state.categoryPool or {}
    state.achievementPool = state.achievementPool or {}
    state.objectivePool = state.objectivePool or {}

    return true
end

local function BeginStructureRebuild()
    if not state.container then
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_ABORT no achievement container")
        end
        return false
    end

    ResetLayoutState()

    if not state.reusableCategoryControls then
        state.reusableCategoryControls = {}
    else
        ClearTable(state.reusableCategoryControls)
    end

    if not state.reusableAchievementControls then
        state.reusableAchievementControls = {}
    else
        ClearTable(state.reusableAchievementControls)
    end

    for key, control in pairs(state.categoryControls) do
        if key and control then
            if control.SetHidden then
                control:SetHidden(true)
            end
            state.reusableCategoryControls[key] = control
        end
    end

    for achievementKey, row in pairs(state.achievementRows) do
        if row and row.DetachControl then
            local detached = row:DetachControl()
            if detached then
                if detached.SetHidden then
                    detached:SetHidden(true)
                end
                state.reusableAchievementControls[achievementKey] = detached
            end
        end
    end

    local poolsReady = false
    if type(EnsurePools) == "function" then
        poolsReady = EnsurePools()
    end

    if not poolsReady then
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_ABORT pools unavailable")
        end
        return false
    end

    state.categoryControls = {}
    state.achievementControls = {}
    state.achievementControlsByKey = {}

    if ReleaseObjectiveControls then
        ReleaseObjectiveControls()
    end

    return true
end

local function ReturnCategoryControl(control)
    if not control then
        return
    end

    ResetCategoryControl(control)

    if IsDebugLoggingEnabled() then
        DebugLog("POOL_RETURN category")
    end

    local pool = state.categoryPool
    if not pool then
        state.categoryPool = { control }
    else
        pool[#pool + 1] = control
    end
end

local function ReturnAchievementControl(achievementKey, control)
    if not control then
        return
    end

    ResetAchievementControl(control)

    if IsDebugLoggingEnabled() then
        DebugLog(string_format("POOL_RETURN achievement key=%s", tostring(achievementKey)))
    end

    local pool = state.achievementPool
    if not pool then
        state.achievementPool = { control }
    else
        pool[#pool + 1] = control
    end
end

local function FinalizeStructureRebuild()
    if state.reusableCategoryControls then
        for key, control in pairs(state.reusableCategoryControls) do
            ReturnCategoryControl(control)
            state.reusableCategoryControls[key] = nil
        end
    end

    if state.reusableAchievementControls then
        for achievementKey, control in pairs(state.reusableAchievementControls) do
            local row = state.achievementRows and state.achievementRows[achievementKey]
            if row and row.ClearControl then
                row:ClearControl()
                state.achievementRows[achievementKey] = nil
            end
            ReturnAchievementControl(achievementKey, control)
            state.reusableAchievementControls[achievementKey] = nil
        end
    end
end

local function RequestCategoryControl()
    local control = state.reusableCategoryControls and state.reusableCategoryControls[CATEGORY_KEY] or nil

    if control then
        state.reusableCategoryControls[CATEGORY_KEY] = nil
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_REUSE category")
        end
    elseif type(AcquireCategoryControlFromPool) == "function" then
        control = AcquireCategoryControlFromPool()
    else
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_ACQUIRE category missing helper")
        end
    end

    if control then
        control.rowType = "category"
        state.categoryControls[CATEGORY_KEY] = control
    end

    return control
end

local function RequestAchievementControl(achievementKey)
    local control = achievementKey and state.reusableAchievementControls and state.reusableAchievementControls[achievementKey] or nil

    if control then
        state.reusableAchievementControls[achievementKey] = nil
        if IsDebugLoggingEnabled() then
            DebugLog(string_format("POOL_REUSE achievement=%s", tostring(achievementKey)))
        end
    elseif type(AcquireAchievementControlFromPool) == "function" then
        control = AcquireAchievementControlFromPool()
    else
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_ACQUIRE achievement missing helper")
        end
    end

    if control then
        control.rowType = "achievement"
    end

    return control
end

local function AnchorControl(control, indentX)
    indentX = indentX or 0

    if not control then
        return
    end

    control.currentIndent = indentX
    control:ClearAnchors()

    local container = state.container
    if container then
        control:SetAnchor(TOPLEFT, container, TOPLEFT, indentX, 0)
        control:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, 0)
    end

    state.lastAnchoredControl = control
    state.orderedControls[#state.orderedControls + 1] = control
end

local function PerformLayoutPass()
    local container = state.container
    if not container then
        state.contentWidth = 0
        state.contentHeight = 0
        state.lastAnchoredControl = nil
        return 0, 0
    end

    local yOffset = 0
    local visibleCount = 0
    local maxWidth = 0
    local lastVisible = nil
    local orderedControls = state.orderedControls
    local verticalPadding = VERTICAL_PADDING

    for index = 1, #orderedControls do
        local control = orderedControls[index]
        if control then
            RefreshControlMetrics(control)

            if not control:IsHidden() then
                local indent = control.currentIndent or 0
                if control.SetParent then
                    control:SetParent(container)
                end
                control:ClearAnchors()
                control:SetAnchor(TOPLEFT, container, TOPLEFT, indent, yOffset)
                control:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, yOffset)

                local width = (control:GetWidth() or 0) + indent
                if width > maxWidth then
                    maxWidth = width
                end

                local height = control:GetHeight() or 0
                yOffset = yOffset + height
                visibleCount = visibleCount + 1
                lastVisible = control

                if visibleCount > 0 then
                    yOffset = yOffset + verticalPadding
                end
            end
        end
    end

    if visibleCount > 0 then
        yOffset = yOffset - verticalPadding
    else
        yOffset = 0
    end

    state.lastAnchoredControl = lastVisible
    state.contentWidth = maxWidth
    state.contentHeight = math_max(0, yOffset)

    if container.SetHeight then
        container:SetHeight(state.contentHeight)
    end

    if IsDebugLoggingEnabled() then
        DebugLog(string_format(
            "LAYOUT_ACH rows=%d height=%.2f",
            visibleCount,
            state.contentHeight or 0
        ))
    end

    return visibleCount, state.contentHeight
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

    QueueAchievementStructureUpdate({
        reason = "AchievementTracker:SetCategoryExpanded",
        trigger = context and context.trigger,
        source = context and context.source,
    })
end

local function SetEntryExpanded(achievementId, expanded)
    if not state.saved or not achievementId then
        return
    end
    state.saved.entryExpanded[achievementId] = expanded and true or false

    QueueAchievementStructureUpdate({
        reason = "AchievementTracker:SetEntryExpanded",
        trigger = "entry",
        source = "AchievementTracker:SetEntryExpanded",
    })
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
        text = string_format("%s (%s/%s)", description, tostring(objective.current), tostring(objective.max))
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

local function AcquireCategoryControlInternal(forceReset)
    local ensured = false
    if type(EnsurePools) == "function" then
        if forceReset then
            ensured = EnsurePools(true)
        else
            ensured = EnsurePools()
        end
    end
    if not ensured then
        return nil
    end

    local pool = state.categoryPool
    local control = nil

    if pool and #pool > 0 then
        control = pool[#pool]
        pool[#pool] = nil
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_TAKE category")
        end
        if control.SetParent then
            control:SetParent(state.container)
        end
    end

    if not control then
        if not (WINDOW_MANAGER and WINDOW_MANAGER.CreateControlFromVirtual) then
            return nil
        end
        local name = GenerateControlName("AchievementCategoryHeader")
        control = WINDOW_MANAGER:CreateControlFromVirtual(name, state.container, "AchievementsCategoryHeader_Template")
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_CREATE category")
        end
    end

    if not control then
        return nil
    end

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

    ResetCategoryControl(control)
    control.rowType = "category"
    ApplyLabelDefaults(control.label)
    ApplyToggleDefaults(control.toggle)
    ApplyFont(control.label, state.fonts.category)
    ApplyFont(control.toggle, state.fonts.toggle)
    return control
end


AcquireCategoryControlFromPool = function()
    local control = AcquireCategoryControlInternal(false)

    if not control then
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_RECOVER category start")
        end
        control = AcquireCategoryControlInternal(true)
        if control and IsDebugLoggingEnabled() then
            DebugLog("POOL_RECOVER category success")
        elseif not control and IsDebugLoggingEnabled() then
            DebugLog("POOL_RECOVER category failed")
        end
    end

    if not control and IsDebugLoggingEnabled() then
        DebugLog("POOL_MISSING category")
    end

    return control
end

local function AcquireAchievementControlInternal(forceReset)
    local ensured = false
    if type(EnsurePools) == "function" then
        if forceReset then
            ensured = EnsurePools(true)
        else
            ensured = EnsurePools()
        end
    end
    if not ensured then
        return nil
    end

    local pool = state.achievementPool
    local control = nil

    if pool and #pool > 0 then
        control = pool[#pool]
        pool[#pool] = nil
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_TAKE achievement")
        end
        if control.SetParent then
            control:SetParent(state.container)
        end
    end

    if not control then
        if not (WINDOW_MANAGER and WINDOW_MANAGER.CreateControlFromVirtual) then
            return nil
        end
        local name = GenerateControlName("AchievementHeader")
        control = WINDOW_MANAGER:CreateControlFromVirtual(name, state.container, "AchievementHeader_Template")
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_CREATE achievement")
        end
    end

    if not control then
        return nil
    end

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
            if not upInside then
                return
            end

            if button == LEFT_MOUSE_BUTTON then
                if not ctrl.data or not ctrl.data.achievementId or not ctrl.data.hasObjectives then
                    return
                end
                local achievementId = ctrl.data.achievementId
                local expanded = not IsEntryExpanded(achievementId)
                SetEntryExpanded(achievementId, expanded)
                AchievementTracker.Refresh()
            elseif button == RIGHT_MOUSE_BUTTON then
                if not ctrl.data or not ctrl.data.achievementId then
                    return
                end
                ShowAchievementContextMenu(ctrl, ctrl.data)
            end
        end)
        control.initialized = true
    end

    ResetAchievementControl(control)
    control.rowType = "achievement"
    ApplyLabelDefaults(control.label)
    ApplyFont(control.label, state.fonts.achievement)
    return control
end


AcquireAchievementControlFromPool = function()
    local control = AcquireAchievementControlInternal(false)

    if not control then
        if IsDebugLoggingEnabled() then
            DebugLog("POOL_RECOVER achievement start")
        end
        control = AcquireAchievementControlInternal(true)
        if control and IsDebugLoggingEnabled() then
            DebugLog("POOL_RECOVER achievement success")
        elseif not control and IsDebugLoggingEnabled() then
            DebugLog("POOL_RECOVER achievement failed")
        end
    end

    if not control and IsDebugLoggingEnabled() then
        DebugLog("POOL_MISSING achievement")
    end

    return control
end

local function AcquireObjectiveControl()
    if type(EnsurePools) ~= "function" or not EnsurePools() then
        return nil
    end

    local pool = state.objectivePool
    if not pool then
        return nil
    end

    local control = nil
    if #pool > 0 then
        control = pool[#pool]
        pool[#pool] = nil
        if control.SetParent then
            control:SetParent(state.container)
        end
    end

    if not control then
        if not (WINDOW_MANAGER and WINDOW_MANAGER.CreateControlFromVirtual) then
            return nil
        end
        local name = GenerateControlName("AchievementObjective")
        control = WINDOW_MANAGER:CreateControlFromVirtual(name, state.container, "AchievementObjective_Template")
    end

    if not control then
        return nil
    end

    if not control.initialized then
        control.label = control:GetNamedChild("Label")
        control.initialized = true
    end

    ResetObjectiveControl(control)
    control.rowType = "objective"
    ApplyLabelDefaults(control.label)
    ApplyFont(control.label, state.fonts.objective)

    local active = state.objectiveActiveControls
    active[#active + 1] = control

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

    local control = AcquireObjectiveControl()
    if not control then
        if state.objectivePool then
            if IsDebugLoggingEnabled() then
                DebugLog("LAYOUT objective missing control", tostring(achievement and achievement.id))
            end
            QueueAchievementStructureUpdate({ reason = "AchievementTracker.LayoutObjectiveMissingControl", trigger = "pool" })
        elseif IsDebugLoggingEnabled() then
            DebugLog("LAYOUT objective missing pool", tostring(achievement and achievement.id))
        end
        return
    end
    local data = control.data
    if not data then
        data = {}
        control.data = data
    end
    data.achievementId = achievement.id
    data.objective = objective
    control.label:SetText(text)
    if control.label then
        local r, g, b, a = GetAchievementTrackerColor("objectiveText")
        control.label:SetColor(r, g, b, a)
    end
    ApplyRowMetrics(control, OBJECTIVE_INDENT_X, 0, 0, 0, OBJECTIVE_MIN_HEIGHT)
    control:SetHidden(false)
    AnchorControl(control, OBJECTIVE_INDENT_X)
    ConsumeStructureBudget(1)

    if ShouldAbortRebuild() then
        return
    end
end

local function ApplyAchievementRowVisuals(control, achievement)
    if not (control and achievement) then
        return false, false, false
    end

    local hasObjectives = achievement.objectives and #achievement.objectives > 0
    local isFavorite = IsFavoriteAchievement(achievement.id)

    local data = control.data
    if not data then
        data = {}
        control.data = data
    end
    data.achievementId = achievement.id
    data.hasObjectives = hasObjectives
    data.isFavorite = isFavorite

    if control.label and control.label.SetText then
        control.label:SetText(FormatDisplayString(achievement.name))
    end

    local r, g, b, a = GetAchievementTrackerColor("entryTitle")
    ApplyBaseColor(control, r, g, b, a)

    UpdateAchievementIconSlot(control)

    ApplyRowMetrics(
        control,
        ACHIEVEMENT_INDENT_X,
        ACHIEVEMENT_ICON_SLOT_WIDTH,
        ACHIEVEMENT_ICON_SLOT_PADDING_X,
        0,
        ACHIEVEMENT_MIN_HEIGHT
    )

    local expanded = false
    if hasObjectives then
        expanded = IsEntryExpanded(achievement.id) and true or false
    end

    if control.data then
        control.data.isExpanded = expanded
    end

    return hasObjectives, expanded, isFavorite
end

local function LayoutAchievement(achievement)
    local achievementKey = NormalizeAchievementKey and NormalizeAchievementKey(achievement and achievement.id)
    local control = RequestAchievementControl(achievementKey)
    if not control then
        if state.achievementPool then
            if IsDebugLoggingEnabled() then
                DebugLog("LAYOUT achievement missing control", tostring(achievementKey or (achievement and achievement.id)))
            end
            QueueAchievementStructureUpdate({ reason = "AchievementTracker.LayoutAchievementMissingControl", trigger = "pool" })
        elseif IsDebugLoggingEnabled() then
            DebugLog("LAYOUT achievement missing pool", tostring(achievementKey or (achievement and achievement.id)))
        end
        return
    end

    local hasObjectives
    local expanded

    if achievementKey then
        local row = state.achievementRows[achievementKey]
        if not row then
            row = AchievementTrackerRow:New({
                achievementKey = achievementKey,
            })
            state.achievementRows[achievementKey] = row
        end
        row:SetControl(control)
        hasObjectives, expanded = row:Refresh(achievement)
    else
        hasObjectives, expanded = ApplyAchievementRowVisuals(control, achievement)
    end

    control:SetHidden(false)
    AnchorControl(control, ACHIEVEMENT_INDENT_X)
    ConsumeStructureBudget(1)

    if ShouldAbortRebuild() then
        return
    end

    if achievement and achievement.id then
        state.achievementControls[achievement.id] = control
    end

    if achievementKey then
        state.achievementControlsByKey[achievementKey] = control
    end

    if hasObjectives and expanded and type(achievement.objectives) == "table" then
        for index = 1, #achievement.objectives do
            LayoutObjective(achievement, achievement.objectives[index])
            if ShouldAbortRebuild() then
                return
            end
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

    local control = RequestCategoryControl()
    if not control then
        if state.categoryPool then
            if IsDebugLoggingEnabled() then
                DebugLog("LAYOUT achievement category missing control")
            end
            QueueAchievementStructureUpdate({ reason = "AchievementTracker.LayoutCategoryMissingControl", trigger = "pool" })
        elseif IsDebugLoggingEnabled() then
            DebugLog("LAYOUT achievement category missing pool")
        end
        return
    end
    local data = control.data
    if not data then
        data = {}
        control.data = data
    end
    data.categoryKey = CATEGORY_KEY
    control.label:SetText(FormatCategoryHeaderText("Errungenschaften", total or 0, "achievement"))

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
    ConsumeStructureBudget(1)

    if ShouldAbortRebuild() then
        return
    end

    if expanded then
        for index = 1, #visibleEntries do
            LayoutAchievement(visibleEntries[index])
            if ShouldAbortRebuild() then
                return
            end
        end
    end
end

local function HighlightControl(control)
    if not (control and control.label and control.baseColor) then
        return
    end

    local label = control.label
    if not label.SetColor then
        return
    end

    local baseColor = {
        control.baseColor[1] or 1,
        control.baseColor[2] or 1,
        control.baseColor[3] or 1,
        control.baseColor[4] or 1,
    }

    label:SetColor(unpack(COLOR_ROW_HOVER))

    if zo_callLater then
        zo_callLater(function()
            if label and label.SetColor then
                label:SetColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4])
            end
        end, FOCUS_HIGHLIGHT_DURATION_MS)
    else
        label:SetColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4])
    end
end

local function FocusAchievementRowInternal(achievementId)
    local numeric = tonumber(achievementId)
    if not numeric or numeric <= 0 then
        return false
    end

    local host = Nvk3UT and Nvk3UT.TrackerHost
    for index = 1, #state.orderedControls do
        local control = state.orderedControls[index]
        if control and control.rowType == "achievement" then
            local data = control.data
            if data and data.achievementId and tonumber(data.achievementId) == numeric then
                if host and host.ScrollControlIntoView then
                    pcall(host.ScrollControlIntoView, control)
                end
                HighlightControl(control)
                return true
            end
        end
    end

    return false
end

local function ApplyPendingFocus()
    local pending = state.pendingFocusAchievementId
    if not pending then
        return
    end

    if FocusAchievementRowInternal(pending) then
        state.pendingFocusAchievementId = nil
    end
end

local function Rebuild()
    if not state.container then
        return
    end

    state.isRebuildInProgress = true
    local rebuildReady = BeginStructureRebuild()

    if not rebuildReady then
        state.isRebuildInProgress = false
        state.lastStructureFailure = "pools"
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_DEFER prerequisites unavailable")
        end
        return
    end

    state.lastStructureFailure = nil

    if not state.snapshot or not state.snapshot.achievements then
        FinalizeStructureRebuild()
        NotifyHostContentChanged()
        ApplyPendingFocus()
        state.isRebuildInProgress = false
        return
    end

    LayoutCategory()

    FinalizeStructureRebuild()
    NotifyHostContentChanged()
    ApplyPendingFocus()
    state.isRebuildInProgress = false
end

local function RunAchievementRebuildSynchronously(reason)
    local job = GetAchievementRebuildJob()
    job.totalProcessed = 0
    job.reason = reason or job.reason or "achievementStructure"
    job.restartRequested = false
    job.active = false
    job.async = nil

    if IsDebugLoggingEnabled() then
        DebugLog(string_format("REBUILD_SYNC reason=%s", tostring(job.reason or "")))
    end

    local ok, err = pcall(Rebuild)
    if not ok then
        state.isRebuildInProgress = false
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_ERROR", tostring(err))
        end
    end

    QueueLayoutUpdate({
        reason = "AchievementTracker.StructureComplete",
        trigger = "structureComplete",
    })

    return ok == true
end

local function StartAchievementRebuildJob(reason)
    local job = GetAchievementRebuildJob()
    job.batchSize = STRUCTURE_REBUILD_BATCH_SIZE
    job.reason = reason or job.reason or "achievementStructure"
    job.restartRequested = false

    if job.active then
        job.restartRequested = true
        if IsDebugLoggingEnabled() then
            DebugLog(string_format("REBUILD_RESTART reason=%s", tostring(job.reason or "")))
        end
        return true
    end

    if not Async or not Async.Create then
        return RunAchievementRebuildSynchronously(job.reason)
    end

    local asyncTask = Async:Create(ACHIEVEMENT_REBUILD_TASK_NAME)
    if not asyncTask then
        return RunAchievementRebuildSynchronously(job.reason)
    end

    job.async = asyncTask
    job.active = true
    job.totalProcessed = 0

    if IsDebugLoggingEnabled() then
        DebugLog(string_format("REBUILD_ASYNC_START reason=%s", tostring(job.reason or "")))
    end

    asyncTask:Then(function(task)
        repeat
            job.restartRequested = false
            job.totalProcessed = 0

            state.activeRebuildContext = {
                task = task,
                batchSize = job.batchSize or STRUCTURE_REBUILD_BATCH_SIZE,
                pending = 0,
                total = 0,
                batches = 0,
                onBatchReady = function(context)
                    if IsDebugLoggingEnabled() then
                        DebugLog(string_format(
                            "REBUILD_BATCH achievement batches=%d total=%d reason=%s",
                            context.batches or 0,
                            context.total or 0,
                            tostring(job.reason or "")
                        ))
                    end
                    QueueLayoutUpdate({
                        reason = "AchievementTracker.StructureBatch",
                        trigger = "structureBatch",
                    })
                end,
            }

            local ok, err = pcall(Rebuild)
            if not ok then
                state.isRebuildInProgress = false
                if IsDebugLoggingEnabled() then
                    DebugLog("REBUILD_ERROR", tostring(err))
                end
            end

            ClearActiveRebuildContext()

            if IsDebugLoggingEnabled() then
                DebugLog(string_format(
                    "REBUILD_ITERATION_COMPLETE rows=%d restart=%s reason=%s",
                    job.totalProcessed or 0,
                    tostring(job.restartRequested),
                    tostring(job.reason or "")
                ))
            end

            QueueLayoutUpdate({
                reason = "AchievementTracker.StructureIteration",
                trigger = "structure",
            })
        until not job.restartRequested
    end)
    :Then(function()
        if IsDebugLoggingEnabled() then
            DebugLog("REBUILD_ASYNC_DONE")
        end
        QueueLayoutUpdate({
            reason = "AchievementTracker.StructureComplete",
            trigger = "structureComplete",
        })
    end)
    :Finally(function()
        ClearActiveRebuildContext()
        job.active = false
        job.async = nil

        if job.restartRequested then
            local restartReason = job.reason or "achievementStructure"
            job.restartRequested = false
            StartAchievementRebuildJob(restartReason)
        end
    end)
    :Start()

    return true
end

local function OnSnapshotUpdated(snapshot)
    state.snapshot = snapshot
    if not state.isInitialized then
        return
    end

    QueueAchievementStructureUpdate({
        reason = "AchievementTracker:OnSnapshotUpdated",
        trigger = "snapshot",
    })
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
    state.rebuildJob = nil
    ClearActiveRebuildContext()

    QueueLayoutUpdate({ reason = "AchievementTracker.Init", trigger = "init" })
    QueueAchievementStructureUpdate({ reason = "AchievementTracker.Init", trigger = "init" })

    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host and host.ProcessTrackerUpdates then
        host.ProcessTrackerUpdates()
    end
end

-- Returns the registered AchievementTrackerRow instance for the given
-- achievement id, enabling callers to refresh a single row without
-- rebuilding the tracker.
function AchievementTracker.GetAchievementRow(achievementId)
    local key = NormalizeAchievementKey and NormalizeAchievementKey(achievementId)
    if not key then
        return nil
    end

    return state.achievementRows[key]
end

function AchievementTracker.Refresh(context)
    if not state.isInitialized then
        return
    end

    QueueAchievementStructureUpdate(context or { reason = "AchievementTracker.Refresh" })
end

function AchievementTracker.ProcessStructureUpdate(context)
    if not state.isInitialized then
        return false
    end

    if Nvk3UT.AchievementModel and Nvk3UT.AchievementModel.GetSnapshot then
        state.snapshot = Nvk3UT.AchievementModel.GetSnapshot() or state.snapshot
    end

    local job = GetAchievementRebuildJob()
    local reason
    if type(context) == "table" then
        reason = context.reason or context.trigger
    elseif type(context) == "string" then
        reason = context
    end
    job.reason = reason or job.reason or "AchievementTracker.ProcessStructureUpdate"

    if job.active then
        job.restartRequested = true
        if IsDebugLoggingEnabled() then
            DebugLog(string_format(
                "REBUILD_RESTART_REQUEST reason=%s",
                tostring(job.reason or "")
            ))
        end
        return true
    end

    local started = StartAchievementRebuildJob(job.reason)
    return started == true
end

function AchievementTracker.RunLayoutPass()
    return PerformLayoutPass()
end

function AchievementTracker.ProcessLayoutUpdate()
    RefreshVisibility()
end

function AchievementTracker.Shutdown()
    UnsubscribeFromModel()

    if state.rebuildJob then
        local job = state.rebuildJob
        if job.async and job.async.Cancel then
            pcall(job.async.Cancel, job.async)
        end
        state.rebuildJob = nil
    end
    ClearActiveRebuildContext()

    if state.categoryPool then
        for index = 1, #state.categoryPool do
            ResetCategoryControl(state.categoryPool[index])
        end
    end
    if state.achievementPool then
        for index = 1, #state.achievementPool do
            ResetAchievementControl(state.achievementPool[index])
        end
    end
    ReleaseObjectiveControls()

    state.categoryPool = nil
    state.achievementPool = nil
    state.objectivePool = nil
    state.objectiveActiveControls = {}

    state.container = nil
    state.control = nil
    state.snapshot = nil
    state.orderedControls = {}
    state.categoryControls = {}
    state.achievementControls = {}
    state.achievementControlsByKey = {}
    state.lastAnchoredControl = nil
    state.achievementRows = {}
    state.reusableCategoryControls = nil
    state.reusableAchievementControls = nil
    state.fonts = {}
    state.opts = {}
    state.pendingFocusAchievementId = nil

    state.isInitialized = false
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

    QueueLayoutUpdate({ reason = "AchievementTracker.ApplySettings", trigger = "setting" })
    QueueAchievementStructureUpdate({ reason = "AchievementTracker.ApplySettings", trigger = "setting" })
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

    QueueAchievementStructureUpdate({ reason = "AchievementTracker.ApplyTheme", trigger = "theme" })
end

function AchievementTracker.FocusAchievement(achievementId)
    local numeric = tonumber(achievementId)
    if not numeric or numeric <= 0 then
        return false
    end

    EnsureSavedVars()

    SetCategoryExpanded(true, {
        trigger = "external",
        source = "AchievementTracker:FocusAchievement",
    })

    state.pendingFocusAchievementId = numeric

    local focused = FocusAchievementRowInternal(numeric)
    if focused then
        state.pendingFocusAchievementId = nil
        QueueAchievementRowRefreshByKey(
            NormalizeAchievementKey and NormalizeAchievementKey(numeric) or numeric,
            {
                reason = "AchievementTracker.FocusAchievement",
                trigger = "external",
                source = "AchievementTracker:FocusAchievement",
            }
        )
        return true
    end

    QueueAchievementStructureUpdate({
        reason = "AchievementTracker.FocusAchievement",
        trigger = "external",
        source = "AchievementTracker:FocusAchievement",
    })
    return false
end

function AchievementTracker.RequestRefresh()
    RequestRefresh()
end

function AchievementTracker.IsStructureRebuildActive()
    local job = state.rebuildJob
    if job and job.active then
        return true
    end

    return state.isRebuildInProgress == true
end

function AchievementTracker.SetActive(active)
    state.opts.active = (active ~= false)
    QueueLayoutUpdate({ reason = "AchievementTracker.SetActive", trigger = "setting" })
end

function AchievementTracker.RefreshVisibility()
    RefreshVisibility()
end

function AchievementTracker.GetContentSize()
    return state.contentWidth or 0, state.contentHeight or 0
end

-- Ensure the container exists before populating entries during init
Nvk3UT.AchievementTracker = AchievementTracker

return AchievementTracker
