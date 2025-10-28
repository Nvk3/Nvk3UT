local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local AchievementTrackerController = {}
AchievementTrackerController.__index = AchievementTrackerController

local MODULE_NAME = addonName .. "AchievementTrackerController"

local Utils = Nvk3UT and Nvk3UT.Utils
local TrackerLayout = Nvk3UT and Nvk3UT.TrackerLayout
local AchievementTrackerRow = Nvk3UT and Nvk3UT.AchievementTrackerRow
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
local REFRESH_DEBOUNCE_MS = 80

local COLOR_ROW_HOVER = { 1, 1, 0.6, 1 }
local FOCUS_HIGHLIGHT_DURATION_MS = 1600

local FAVORITES_LOOKUP_KEY = "NVK3UT_FAVORITES_ROOT"
local FAVORITES_CATEGORY_ID = "Nvk3UT_Favorites"

local state = {
    isInitialized = false,
    opts = {},
    fonts = {},
    saved = nil,
    control = nil,
    container = nil,
    lastKnownContainerWidth = 0,
    categoryPool = nil,
    achievementPool = nil,
    objectivePool = nil,
    orderedControls = {},
    rows = {},
    lastAnchoredControl = nil,
    snapshot = nil,
    subscription = nil,
    pendingRefresh = false,
    contentWidth = 0,
    contentHeight = 0,
    pendingFocusAchievementId = nil,
    hostHidden = false,
    structureDirty = true,
}

local function HasValidControl(control)
    return type(control) == "userdata"
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

local function CacheContainerWidth(width)
    if type(width) == "number" and width > 0 then
        state.lastKnownContainerWidth = width
    end
end

local function GetContainerWidth()
    if not state.container or not state.container.GetWidth then
        return state.lastKnownContainerWidth or 0
    end

    local width = state.container:GetWidth()
    if type(width) == "number" and width > 0 then
        CacheContainerWidth(width)
        return width
    end

    return state.lastKnownContainerWidth or 0
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
    CacheContainerWidth(containerWidth)
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

local function SafeCall(func, ...)
    if type(func) ~= "function" then
        return nil, "no function"
    end

    local ok, result = pcall(func, ...)
    if not ok then
        DebugLog(string.format("SafeCall failure: %s", tostring(result)))
        return nil, result
    end

    return result, nil
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

    if AchievementTracker and AchievementTrackerController.RequestRefresh then
        AchievementTrackerController.RequestRefresh()
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
        AchievementTrackerController.Refresh()
    end

    if zo_callLater then
        zo_callLater(execute, REFRESH_DEBOUNCE_MS)
    else
        execute()
    end
end

local function ApplyHostVisibilityInternal(hidden, reason)
    local normalized = hidden and true or false

    if state.hostHidden == normalized then
        return
    end

    state.hostHidden = normalized

    if HasValidControl(state.control) and state.control.SetHidden then
        state.control:SetHidden(normalized)
        NotifyHostContentChanged()
    end

    if IsDebugLoggingEnabled() then
        DebugLog(string.format("HOST_VISIBILITY -> %s (%s)", normalized and "hidden" or "shown", tostring(reason)))
    end
end

local function ResetLayoutState()
    if TrackerLayout and TrackerLayout.ResetAchievementLayout then
        TrackerLayout.ResetAchievementLayout(state)
    end
    state.orderedControls = {}
    state.rows = {}
    state.lastAnchoredControl = nil
end

local function FlagStructureDirtyInternal(reason)
    if state.structureDirty then
        return
    end

    state.structureDirty = true

    if IsDebugLoggingEnabled() then
        DebugLog(string.format("STRUCTURE_DIRTY reason=%s", tostring(reason)))
    end
end

local function ReleaseAll(pool)
    if pool then
        pool:ReleaseAllObjects()
    end
end

local function AppendRow(row)
    if not row then
        return
    end

    state.rows = state.rows or {}

    state.rows[#state.rows + 1] = row

    local control = row.GetControl and row:GetControl()
    if control then
        state.orderedControls[#state.orderedControls + 1] = control
    end
end

local function RefreshRowVisuals()
    if not state.rows then
        return
    end

    for index = 1, #state.rows do
        local row = state.rows[index]
        if row then
            if type(row.SetContainer) == "function" then
                row:SetContainer(state.container)
            end

            if type(row.RefreshVisual) == "function" then
                SafeCall(row.RefreshVisual, row)
            end
        end
    end
end

local function ApplyAchievementLayout()
    state.rows = state.rows or {}

    if TrackerLayout and TrackerLayout.LayoutAchievementTrackerRows then
        local width, height = TrackerLayout.LayoutAchievementTrackerRows(
            state.container,
            state.rows,
            { verticalPadding = VERTICAL_PADDING }
        )
        state.contentWidth = width or 0
        state.contentHeight = height or 0
        return
    end

    local maxWidth = 0
    local currentY = 0
    local visibleCount = 0

    for index = 1, #state.rows do
        local row = state.rows[index]
        if row and type(row.IsRenderable) == "function" and row:IsRenderable() then
            if type(row.SetContainer) == "function" then
                row:SetContainer(state.container)
            end

            local height = 0
            if type(row.MeasureHeight) == "function" then
                local ok, measured = pcall(row.MeasureHeight, row)
                if ok and type(measured) == "number" and measured > 0 then
                    height = measured
                end
            end

            local hidden = true
            if type(row.IsHidden) == "function" then
                local ok, isHidden = pcall(row.IsHidden, row)
                hidden = not ok or isHidden == true
            end

            if not hidden and height > 0 then
                if visibleCount > 0 then
                    currentY = currentY + VERTICAL_PADDING
                end

                if type(row.ApplyLayout) == "function" then
                    local ok, applied = pcall(row.ApplyLayout, row, currentY)
                    if ok and type(applied) == "number" and applied >= 0 then
                        height = applied
                    end
                end

                currentY = currentY + height
                visibleCount = visibleCount + 1

                if type(row.GetWidthContribution) == "function" then
                    local ok, width = pcall(row.GetWidthContribution, row)
                    if ok and type(width) == "number" and width > maxWidth then
                        maxWidth = width
                    end
                end
            end
        end
    end

    if state.container and state.container.SetHeight then
        state.container:SetHeight(currentY)
    end

    state.contentWidth = maxWidth
    state.contentHeight = currentY
end

local function UpdateContentSize()
    ApplyAchievementLayout()
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
        FlagStructureDirtyInternal("achievement-category")
    end
end

local function SetEntryExpanded(achievementId, expanded)
    if not state.saved or not achievementId then
        return
    end
    state.saved.entryExpanded = state.saved.entryExpanded or {}
    local normalized = expanded and true or false
    local previous = state.saved.entryExpanded[achievementId]
    if previous == normalized then
        return
    end

    state.saved.entryExpanded[achievementId] = normalized
    FlagStructureDirtyInternal(string.format("achievement:%s", tostring(achievementId)))
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
            AchievementTrackerController.Refresh()
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
                AchievementTrackerController.Refresh()
            elseif button == RIGHT_MOUSE_BUTTON then
                if not ctrl.data or not ctrl.data.achievementId then
                    return
                end
                ShowAchievementContextMenu(ctrl, ctrl.data)
            end
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

    if not HasValidControl(state.container) then
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
    if AchievementTrackerRow then
        local row = AchievementTrackerRow:New({
            rowType = "objective",
            key = string.format("%s:%s", tostring(achievement.id or "?"), tostring(objective.index or "?")),
            control = control,
            indent = OBJECTIVE_INDENT_X,
        })

        row:SetRefreshFunction(function(r)
            local ctrl = r:GetControl()
            if not ctrl then
                return
            end

            ctrl.data = {
                achievementId = achievement.id,
                objective = objective,
            }

            if ctrl.label then
                ctrl.label:SetText(text)
                local colorR, colorG, colorB, colorA = GetAchievementTrackerColor("objectiveText")
                ctrl.label:SetColor(colorR, colorG, colorB, colorA)
            end

            if type(r.SetHidden) == "function" then
                r:SetHidden(false)
            elseif ctrl.SetHidden then
                ctrl:SetHidden(false)
            end
        end)

        row:SetMeasureFunction(function(r)
            local ctrl = r:GetControl()
            if not ctrl then
                return 0
            end

            ctrl.currentIndent = r:GetIndent()
            RefreshControlMetrics(ctrl)

            if type(ctrl.GetHeight) == "function" then
                return ctrl:GetHeight() or OBJECTIVE_MIN_HEIGHT
            end

            return OBJECTIVE_MIN_HEIGHT
        end)

        row:SetLayoutFunction(function(r, yOffset)
            local ctrl = r:GetControl()
            local container = state.container
            if not (ctrl and container and ctrl.SetAnchor) then
                return r:GetCachedHeight()
            end

            ctrl:ClearAnchors()
            ctrl:SetAnchor(TOPLEFT, container, TOPLEFT, r:GetIndent(), yOffset)
            ctrl:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, yOffset)
            ctrl.currentIndent = r:GetIndent()

            local height = r:GetCachedHeight()
            if height <= 0 and type(ctrl.GetHeight) == "function" then
                height = ctrl:GetHeight() or 0
            end

            return height
        end)

        row:SetWidthFunction(function(r)
            local ctrl = r:GetControl()
            if not ctrl then
                return 0
            end

            local width = (type(ctrl.GetWidth) == "function" and ctrl:GetWidth()) or 0
            if width <= 0 and type(ctrl.GetDesiredWidth) == "function" then
                width = ctrl:GetDesiredWidth() or 0
            end
            if width <= 0 and type(ctrl.minWidth) == "number" then
                width = ctrl.minWidth
            end

            return width + r:GetIndent()
        end)

        row:SetDefaultHeight(OBJECTIVE_MIN_HEIGHT)
        row:SetTextPadding(ROW_TEXT_PADDING_Y)

        AppendRow(row)
        return
    end

    control.label:SetText(text)
    if control.label then
        local fallbackR, fallbackG, fallbackB, fallbackA = GetAchievementTrackerColor("objectiveText")
        control.label:SetColor(fallbackR, fallbackG, fallbackB, fallbackA)
    end
    ApplyRowMetrics(control, OBJECTIVE_INDENT_X, 0, 0, 0, OBJECTIVE_MIN_HEIGHT)
    control:SetHidden(false)
    state.orderedControls[#state.orderedControls + 1] = control
end

local function LayoutAchievement(achievement)
    local control = AcquireAchievementControl()
    local hasObjectives = achievement.objectives and #achievement.objectives > 0
    local isFavorite = IsFavoriteAchievement(achievement.id)
    control.data = {
        achievementId = achievement.id,
        hasObjectives = hasObjectives,
        isFavorite = isFavorite,
    }
    local expanded = hasObjectives and IsEntryExpanded(achievement.id)

    if AchievementTrackerRow then
        local row = AchievementTrackerRow:New({
            rowType = "achievement",
            key = achievement.id,
            control = control,
            indent = ACHIEVEMENT_INDENT_X,
        })

        row:SetRefreshFunction(function(r)
            local ctrl = r:GetControl()
            if not ctrl then
                return
            end

            ctrl.data = {
                achievementId = achievement.id,
                hasObjectives = hasObjectives,
                isFavorite = IsFavoriteAchievement(achievement.id),
            }

            if ctrl.label then
                ctrl.label:SetText(FormatDisplayString(achievement.name))
            end

            local colorR, colorG, colorB, colorA = GetAchievementTrackerColor("entryTitle")
            ApplyBaseColor(ctrl, colorR, colorG, colorB, colorA)
            UpdateAchievementIconSlot(ctrl)

            if type(r.SetHidden) == "function" then
                r:SetHidden(false)
            elseif ctrl.SetHidden then
                ctrl:SetHidden(false)
            end
        end)

        row:SetMeasureFunction(function(r)
            local ctrl = r:GetControl()
            if not ctrl then
                return 0
            end

            ctrl.currentIndent = r:GetIndent()
            RefreshControlMetrics(ctrl)

            if type(ctrl.GetHeight) == "function" then
                return ctrl:GetHeight() or ACHIEVEMENT_MIN_HEIGHT
            end

            return ACHIEVEMENT_MIN_HEIGHT
        end)

        row:SetLayoutFunction(function(r, yOffset)
            local ctrl = r:GetControl()
            local container = state.container
            if not (ctrl and container and ctrl.SetAnchor) then
                return r:GetCachedHeight()
            end

            ctrl:ClearAnchors()
            ctrl:SetAnchor(TOPLEFT, container, TOPLEFT, r:GetIndent(), yOffset)
            ctrl:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, yOffset)
            ctrl.currentIndent = r:GetIndent()

            local height = r:GetCachedHeight()
            if height <= 0 and type(ctrl.GetHeight) == "function" then
                height = ctrl:GetHeight() or 0
            end

            return height
        end)

        row:SetWidthFunction(function(r)
            local ctrl = r:GetControl()
            if not ctrl then
                return 0
            end

            local width = (type(ctrl.GetWidth) == "function" and ctrl:GetWidth()) or 0
            if width <= 0 and type(ctrl.GetDesiredWidth) == "function" then
                width = ctrl:GetDesiredWidth() or 0
            end
            if width <= 0 and type(ctrl.minWidth) == "number" then
                width = ctrl.minWidth
            end

            return width + r:GetIndent()
        end)

        row:SetDefaultHeight(ACHIEVEMENT_MIN_HEIGHT)
        row:SetTextPadding(ROW_TEXT_PADDING_Y)

        AppendRow(row)

        if hasObjectives and expanded then
            for index = 1, #achievement.objectives do
                LayoutObjective(achievement, achievement.objectives[index])
            end
        end

        return
    end

    control.label:SetText(FormatDisplayString(achievement.name))
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
    control:SetHidden(false)
    state.orderedControls[#state.orderedControls + 1] = control

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

    local control = AcquireCategoryControl()
    control.data = { categoryKey = CATEGORY_KEY }
    local expanded = IsCategoryExpanded()

    if AchievementTrackerRow then
        local row = AchievementTrackerRow:New({
            rowType = "category",
            key = CATEGORY_KEY,
            control = control,
            indent = CATEGORY_INDENT_X,
        })

        row:SetRefreshFunction(function(r)
            local ctrl = r:GetControl()
            if not ctrl then
                return
            end

            ctrl.data = { categoryKey = CATEGORY_KEY }

            if ctrl.label then
                ctrl.label:SetText(FormatCategoryHeaderText("Errungenschaften", total or 0, "achievement"))
            end

            local colorRole = expanded and "activeTitle" or "categoryTitle"
            local colorR, colorG, colorB, colorA = GetAchievementTrackerColor(colorRole)
            ApplyBaseColor(ctrl, colorR, colorG, colorB, colorA)
            UpdateCategoryToggle(ctrl, expanded)

            if type(r.SetHidden) == "function" then
                r:SetHidden(false)
            elseif ctrl.SetHidden then
                ctrl:SetHidden(false)
            end
        end)

        row:SetMeasureFunction(function(r)
            local ctrl = r:GetControl()
            if not ctrl then
                return 0
            end

            ctrl.currentIndent = r:GetIndent()
            RefreshControlMetrics(ctrl)

            if type(ctrl.GetHeight) == "function" then
                return ctrl:GetHeight() or CATEGORY_MIN_HEIGHT
            end

            return CATEGORY_MIN_HEIGHT
        end)

        row:SetLayoutFunction(function(r, yOffset)
            local ctrl = r:GetControl()
            local container = state.container
            if not (ctrl and container and ctrl.SetAnchor) then
                return r:GetCachedHeight()
            end

            ctrl:ClearAnchors()
            ctrl:SetAnchor(TOPLEFT, container, TOPLEFT, r:GetIndent(), yOffset)
            ctrl:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, yOffset)
            ctrl.currentIndent = r:GetIndent()

            local height = r:GetCachedHeight()
            if height <= 0 and type(ctrl.GetHeight) == "function" then
                height = ctrl:GetHeight() or 0
            end

            return height
        end)

        row:SetWidthFunction(function(r)
            local ctrl = r:GetControl()
            if not ctrl then
                return 0
            end

            local width = (type(ctrl.GetWidth) == "function" and ctrl:GetWidth()) or 0
            if width <= 0 and type(ctrl.GetDesiredWidth) == "function" then
                width = ctrl:GetDesiredWidth() or 0
            end
            if width <= 0 and type(ctrl.minWidth) == "number" then
                width = ctrl.minWidth
            end

            return width + r:GetIndent()
        end)

        row:SetDefaultHeight(CATEGORY_MIN_HEIGHT)
        row:SetTextPadding(ROW_TEXT_PADDING_Y)

        AppendRow(row)

        if expanded then
            for index = 1, #visibleEntries do
                LayoutAchievement(visibleEntries[index])
            end
        end

        return
    end

    control.label:SetText(FormatCategoryHeaderText("Errungenschaften", total or 0, "achievement"))

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
    state.orderedControls[#state.orderedControls + 1] = control

    if expanded then
        for index = 1, #visibleEntries do
            LayoutAchievement(visibleEntries[index])
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

local function RebuildStructure(reason)
    if not HasValidControl(state.container) then
        return false
    end

    if IsDebugLoggingEnabled() then
        DebugLog(string.format("REBUILD_STRUCTURE_START reason=%s", tostring(reason)))
    end

    EnsurePools()

    ReleaseAll(state.categoryPool)
    ReleaseAll(state.achievementPool)
    ReleaseAll(state.objectivePool)

    ResetLayoutState()

    LayoutCategory()

    state.structureDirty = false

    if IsDebugLoggingEnabled() then
        DebugLog(string.format("REBUILD_STRUCTURE_END rows=%d", state.rows and #state.rows or 0))
    end

    return true
end

local function RefreshFromStructure(reason)
    if not HasValidControl(state.container) then
        return
    end

    RefreshRowVisuals()
    UpdateContentSize()
    NotifyHostContentChanged()
    ApplyPendingFocus()

    if IsDebugLoggingEnabled() then
        DebugLog(string.format("REFRESH_FROM_STRUCTURE reason=%s rows=%d", tostring(reason), state.rows and #state.rows or 0))
    end
end

local function OnSnapshotUpdated(snapshot, context)
    state.snapshot = snapshot

    local reason = (context and context.trigger) or "snapshot"
    FlagStructureDirtyInternal(reason)

    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if runtime and type(runtime.MarkAchievementDirty) == "function" then
        if IsDebugLoggingEnabled() then
            DebugLog(string.format(
                "Achievement snapshot -> delegating refresh to runtime (reason=%s)",
                tostring(reason)
            ))
        end

        runtime.MarkAchievementDirty(reason)
        return
    end

    AchievementTrackerController.Refresh(reason)
end

local function SubscribeToModel()
    if state.subscription or not Nvk3UT.AchievementModel or not Nvk3UT.AchievementModel.Subscribe then
        return
    end

    state.subscription = function(snapshot)
        OnSnapshotUpdated(snapshot, { trigger = "model" })
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

function AchievementTrackerController.Init(parentControl, opts)
    if state.isInitialized then
        AchievementTrackerController.Shutdown()
    end

    if not HasValidControl(parentControl) then
        DebugLog("Init aborted: invalid parent control")
        return
    end

    state.control = parentControl
    state.container = parentControl
    if parentControl and parentControl.GetWidth then
        local width = parentControl:GetWidth()
        if type(width) == "number" and width > 0 then
            state.lastKnownContainerWidth = width
        else
            state.lastKnownContainerWidth = 0
        end
    else
        state.lastKnownContainerWidth = 0
    end
    if state.control and state.control.SetResizeToFitDescendents then
        state.control:SetResizeToFitDescendents(true)
    end
    if state.control and state.control.IsHidden then
        state.hostHidden = state.control:IsHidden() == true
    else
        state.hostHidden = false
    end
    EnsureSavedVars()

    state.opts = {}
    state.fonts = {}
    state.structureDirty = true

    AchievementTrackerController.ApplyTheme(state.saved or {})
    AchievementTrackerController.ApplySettings(state.saved or {})

    if opts then
        AchievementTrackerController.ApplyTheme(opts)
        AchievementTrackerController.ApplySettings(opts)
    end

    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if runtime and runtime.RegisterAchievementTracker then
        runtime.RegisterAchievementTracker({
            tracker = AchievementTrackerController,
            control = state.control,
        })
    end

    SubscribeToModel()

    state.snapshot = Nvk3UT.AchievementModel and Nvk3UT.AchievementModel.GetSnapshot and Nvk3UT.AchievementModel.GetSnapshot()

    state.isInitialized = true

    if runtime and runtime.UpdateAchievementVisibility then
        runtime.UpdateAchievementVisibility("init")
    end

    AchievementTrackerController.Refresh()

    if runtime and type(runtime.ProcessUpdates) == "function" then
        runtime.ProcessUpdates("achievement-init")
    end
end

function AchievementTrackerController.Refresh(reason)
    if not state.isInitialized then
        return
    end

    if Nvk3UT.AchievementModel and Nvk3UT.AchievementModel.GetSnapshot then
        state.snapshot = Nvk3UT.AchievementModel.GetSnapshot() or state.snapshot
    end

    local refreshReason = reason or "refresh"

    if state.structureDirty then
        RebuildStructure(refreshReason)
    end

    RefreshFromStructure(refreshReason)
end

function AchievementTrackerController.Shutdown()
    UnsubscribeFromModel()

    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if runtime and runtime.UnregisterAchievementTracker then
        runtime.UnregisterAchievementTracker()
    end

    ReleaseAll(state.categoryPool)
    ReleaseAll(state.achievementPool)
    ReleaseAll(state.objectivePool)

    state.categoryPool = nil
    state.achievementPool = nil
    state.objectivePool = nil

    state.container = nil
    state.lastKnownContainerWidth = 0
    state.control = nil
    state.snapshot = nil
    state.orderedControls = {}
    state.rows = {}
    state.lastAnchoredControl = nil
    state.fonts = {}
    state.opts = {}
    state.pendingFocusAchievementId = nil

    state.isInitialized = false
    state.pendingRefresh = false
    state.contentWidth = 0
    state.contentHeight = 0
    state.hostHidden = false
    state.structureDirty = true
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

function AchievementTrackerController.ApplySettings(settings)
    if type(settings) ~= "table" then
        return
    end

    state.opts.active = settings.active ~= false
    ApplySections(settings.sections)
    if settings.tooltips ~= nil then
        ApplyTooltipsSetting(settings.tooltips)
    end

    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if runtime and runtime.UpdateAchievementVisibility then
        runtime.UpdateAchievementVisibility("settings")
    end
    RequestRefresh()
end

function AchievementTrackerController.ApplyTheme(settings)
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

function AchievementTrackerController.FocusAchievement(achievementId)
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
        return true
    end

    RequestRefresh()
    return false
end

function AchievementTrackerController.RequestRefresh()
    RequestRefresh()
end

function AchievementTrackerController.SetActive(active)
    state.opts.active = (active ~= false)
    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if runtime and runtime.UpdateAchievementVisibility then
        runtime.UpdateAchievementVisibility("active-toggle")
    end
end

function AchievementTrackerController.RefreshVisibility()
    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if runtime and runtime.UpdateAchievementVisibility then
        runtime.UpdateAchievementVisibility("external")
    end
end

function AchievementTrackerController.FlagStructureDirty(reason)
    FlagStructureDirtyInternal(reason or "external")
end

function AchievementTrackerController.HasPendingStructureChanges()
    return state.structureDirty == true
end

function AchievementTrackerController.SyncStructureIfDirty(reason)
    if not state.structureDirty then
        return false
    end

    local achievementModel = Nvk3UT and Nvk3UT.AchievementModel
    if achievementModel and type(achievementModel.GetSnapshot) == "function" then
        local ok, snapshot = pcall(achievementModel.GetSnapshot, achievementModel)
        if ok then
            state.snapshot = snapshot
        elseif IsDebugLoggingEnabled() then
            DebugLog(string.format("SyncStructureIfDirty snapshot failed: %s", tostring(snapshot)))
        end
    end

    local syncReason = reason or "sync"
    local rebuilt = RebuildStructure(syncReason)

    if not rebuilt then
        FlagStructureDirtyInternal(syncReason)
        return false
    end

    if IsDebugLoggingEnabled() then
        DebugLog(string.format(
            "Achievement SyncStructureIfDirty(%s) rows=%d",
            tostring(syncReason),
            state.rows and #state.rows or 0
        ))
    end

    return true
end

function AchievementTrackerController.IsActive()
    return state.opts.active ~= false
end

function AchievementTrackerController.ApplyHostVisibility(hidden, reason)
    ApplyHostVisibilityInternal(hidden, reason)
end

function AchievementTrackerController.RefreshNow(reason)
    if IsDebugLoggingEnabled() then
        DebugLog(string.format("REFRESH_NOW reason=%s", tostring(reason)))
    end
    AchievementTrackerController.Refresh(reason)
end

function AchievementTrackerController.OnAchievementProgress(...)
    local runtime = Nvk3UT and Nvk3UT.TrackerRuntime
    if not (runtime and type(runtime.MarkAchievementDirty) == "function") then
        RequestRefresh()
    end
end

function AchievementTrackerController.GetContentSize()
    UpdateContentSize()
    return state.contentWidth or 0, state.contentHeight or 0
end

function AchievementTrackerController:IsInitialized()
    return state.isInitialized == true
end

-- Ensure the container exists before populating entries during init
Nvk3UT.AchievementTrackerController = AchievementTrackerController

return AchievementTrackerController
