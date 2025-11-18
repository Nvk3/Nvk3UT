local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local MODULE_TAG = addonName .. ".GoldenTrackerRows"

local EndeavorRows = rawget(Nvk3UT, "EndeavorTrackerRows")

local GOLDEN_COLOR_ROLES = {
    CategoryCompleted = "categoryTitleClosed",
    CategoryOpen = "categoryTitleOpen",
    EntryName = "entryTitle",
    TargetText = "objectiveText",
    ActiveEntry = "activeTitle",
    CompletedEntry = "completed",
}
GOLDEN_COLOR_ROLES.CategoryTitleClosed = GOLDEN_COLOR_ROLES.CategoryCompleted
GOLDEN_COLOR_ROLES.CategoryTitleOpen = GOLDEN_COLOR_ROLES.CategoryOpen
GOLDEN_COLOR_ROLES.Objective = GOLDEN_COLOR_ROLES.TargetText
GOLDEN_COLOR_ROLES.Active = GOLDEN_COLOR_ROLES.ActiveEntry
GOLDEN_COLOR_ROLES.Completed = GOLDEN_COLOR_ROLES.CompletedEntry

local DEFAULT_COLOR_KIND = "goldenTracker"

local DEFAULTS = {
    CATEGORY_HEIGHT = 26,
    ENTRY_HEIGHT = 24,
    OBJECTIVE_HEIGHT = 20,
    CATEGORY_FONT = "$(BOLD_FONT)|20|soft-shadow-thick",
    ENTRY_FONT = "$(BOLD_FONT)|16|soft-shadow-thick",
    OBJECTIVE_FONT = "$(BOLD_FONT)|14|soft-shadow-thick",
    OBJECTIVE_INDENT_X = 60,
}

local CATEGORY_CHEVRON_SIZE = 20
local CATEGORY_LABEL_OFFSET_X = 4
local ENTRY_INDENT_X = 32

local CATEGORY_CHEVRON_TEXTURES = {
    expanded = "EsoUI/Art/Buttons/tree_open_up.dds",
    collapsed = "EsoUI/Art/Buttons/tree_closed_up.dds",
}

local MOUSE_BUTTON_LEFT = rawget(_G, "MOUSE_BUTTON_INDEX_LEFT") or 1

local DEFAULT_FONT_OUTLINE = "soft-shadow-thick"
local DEFAULT_FONT_FACE = "$(BOLD_FONT)"
local MIN_FONT_SIZE = 12
local MAX_FONT_SIZE = 36

local GOLDEN_FONT_DEFAULTS = {
    Category = { face = DEFAULT_FONT_FACE, size = 20, outline = DEFAULT_FONT_OUTLINE },
    Title = { face = DEFAULT_FONT_FACE, size = 16, outline = DEFAULT_FONT_OUTLINE },
    Objective = { face = DEFAULT_FONT_FACE, size = 14, outline = DEFAULT_FONT_OUTLINE },
}

local controlCounters = {
    category = 0,
    entry = 0,
    objective = 0,
}

local function isDebugEnabled()
    local utils = (Nvk3UT and Nvk3UT.Utils) or Nvk3UT_Utils
    if utils and type(utils.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(utils.IsDebugEnabled)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local diagnostics = (Nvk3UT and Nvk3UT.Diagnostics) or Nvk3UT_Diagnostics
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return diagnostics:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local addon = rawget(_G, addonName)
    if type(addon) == "table" and type(addon.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return addon:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    return false
end

local function safeDebug(message, ...)
    if not isDebugEnabled() then
        return
    end

    local debugFn = Nvk3UT and Nvk3UT.Debug
    if type(debugFn) ~= "function" then
        return
    end

    local payload = message
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, message, ...)
        if ok then
            payload = formatted
        end
    end

    pcall(debugFn, string.format("%s: %s", MODULE_TAG, tostring(payload)))
end

local function getWindowManager()
    local wm = rawget(_G, "WINDOW_MANAGER")
    if wm == nil then
        safeDebug("WINDOW_MANAGER unavailable; skipping row creation")
    end
    return wm
end

local function resolveParentName(parent)
    if parent and type(parent.GetName) == "function" then
        local ok, name = pcall(parent.GetName, parent)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end

    return "Nvk3UT_Golden"
end

local function nextControlName(parent, kind)
    controlCounters[kind] = (controlCounters[kind] or 0) + 1
    local parentName = resolveParentName(parent)
    return string.format("%s_%sRow%u", parentName, kind, controlCounters[kind])
end

local function applyLabelDefaults(label, font, color)
    if not label then
        return
    end

    if label.SetFont and font then
        label:SetFont(font)
    end

    if label.SetColor and type(color) == "table" then
        local r = color[1] or color.r or 1
        local g = color[2] or color.g or 1
        local b = color[3] or color.b or 1
        local a = color[4] or color.a or 1
        label:SetColor(r, g, b, a)
    end

    if label.SetWrapMode and rawget(_G, "TEXT_WRAP_MODE_ELLIPSIS") then
        label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    end
end

local function formatObjectiveCounter(current, max)
    local currentNum = tonumber(current)
    if currentNum == nil then
        return nil
    end

    currentNum = math.floor(currentNum + 0.5)
    if currentNum < 0 then
        currentNum = 0
    end

    local maxNum = tonumber(max)
    if maxNum ~= nil then
        maxNum = math.floor(maxNum + 0.5)
        if maxNum < 1 then
            maxNum = 1
        end

        if currentNum > maxNum then
            currentNum = maxNum
        end

        return string.format("(%d/%d)", currentNum, maxNum)
    end

    return string.format("(%d)", currentNum)
end

local function getAddon()
    return rawget(_G, addonName)
end

local function clampFontSize(value)
    local numeric = tonumber(value)
    if numeric == nil then
        return nil
    end

    numeric = math.floor(numeric + 0.5)
    if numeric < MIN_FONT_SIZE then
        numeric = MIN_FONT_SIZE
    elseif numeric > MAX_FONT_SIZE then
        numeric = MAX_FONT_SIZE
    end

    return numeric
end

local function buildFontString(face, size, outline)
    if type(face) ~= "string" or face == "" then
        return nil
    end

    local resolvedSize = clampFontSize(size)
    if resolvedSize == nil then
        return nil
    end

    local resolvedOutline = outline
    if type(resolvedOutline) ~= "string" or resolvedOutline == "" then
        resolvedOutline = DEFAULT_FONT_OUTLINE
    end

    return string.format("%s|%d|%s", face, resolvedSize, resolvedOutline)
end

local function getConfiguredFonts()
    local addon = getAddon()
    if type(addon) ~= "table" then
        return nil
    end

    local sv = addon.SV or addon.sv
    if type(sv) ~= "table" then
        return nil
    end

    local golden = sv.Golden
    if type(golden) ~= "table" then
        return nil
    end

    local tracker = golden.Tracker
    if type(tracker) ~= "table" then
        return nil
    end

    return tracker.Fonts
end

local function selectFontGroup(fonts, key)
    if type(fonts) ~= "table" then
        return nil
    end

    local group = fonts[key]
    if type(group) ~= "table" then
        local altKey = type(key) == "string" and string.lower(key)
        if altKey and type(fonts[altKey]) == "table" then
            group = fonts[altKey]
        end
    end

    return group
end

local function resolveGoldenFont(key)
    local defaults = GOLDEN_FONT_DEFAULTS[key]
    if type(defaults) ~= "table" then
        defaults = GOLDEN_FONT_DEFAULTS.Objective
    end

    local face = defaults.face
    local size = defaults.size
    local outline = defaults.outline

    local fonts = getConfiguredFonts()
    local group = selectFontGroup(fonts, key)
    if type(group) == "table" then
        local candidateFace = group.Face or group.face
        if type(candidateFace) == "string" and candidateFace ~= "" then
            face = candidateFace
        end

        local candidateSize = clampFontSize(group.Size or group.size)
        if candidateSize ~= nil then
            size = candidateSize
        end

        local candidateOutline = group.Outline or group.outline
        if type(candidateOutline) == "string" and candidateOutline ~= "" then
            outline = candidateOutline
        end
    end

    return buildFontString(face, size, outline)
end

local function getGoldenCategoryFont()
    return resolveGoldenFont("Category") or DEFAULTS.CATEGORY_FONT
end

local function getGoldenTitleFont()
    return resolveGoldenFont("Title") or DEFAULTS.ENTRY_FONT
end

local function getGoldenObjectiveFont()
    return resolveGoldenFont("Objective") or DEFAULTS.OBJECTIVE_FONT
end

Nvk3UT.GetGoldenCategoryFont = getGoldenCategoryFont
Nvk3UT.GetGoldenTitleFont = getGoldenTitleFont
Nvk3UT.GetGoldenRowFont = getGoldenObjectiveFont

local function resolveCategoryCounts(categoryData)
    if type(categoryData) ~= "table" then
        return nil, nil
    end

    local completed = tonumber(
        categoryData.completedObjectives
            or categoryData.countCompleted
            or categoryData.completedCount
            or categoryData.completedActivities
    )

    local capstoneCount = tonumber(
        categoryData.capstoneCount
            or categoryData.maxRewardTier
            or categoryData.capstoneCompletionThreshold
            or categoryData.capLimit
            or categoryData.totalCount
            or categoryData.countTotal
    )

    return completed, capstoneCount
end

local function isEntryActive(entryData)
    if type(entryData) ~= "table" then
        return false
    end

    return entryData.isFocused == true or entryData.isActive == true or entryData.active == true
end

local function isObjectiveCompleted(objectiveData)
    if type(objectiveData) ~= "table" then
        return false
    end

    local completed = objectiveData.isComplete == true or objectiveData.isCompleted == true or objectiveData.completed == true
    if completed then
        return true
    end

    local progress = tonumber(objectiveData.progress or objectiveData.progressDisplay or objectiveData.current)
    local maxProgress = tonumber(objectiveData.max or objectiveData.maxDisplay)
    if progress ~= nil and maxProgress ~= nil then
        return math.floor(progress + 0.5) >= math.floor(maxProgress + 0.5)
    end

    return false
end

local function resolveCategoryColorRole(categoryData)
    local completed, capstoneCount = resolveCategoryCounts(categoryData)
    local capstoneReached = completed ~= nil and capstoneCount ~= nil and completed == capstoneCount

    local categoryId = nil
    if type(categoryData) == "table" then
        categoryId = categoryData.categoryId or categoryData.id or categoryData.campaignId or categoryData.campaignKey
    end
    safeDebug("Golden[%s].capstoneReached = %s", tostring(categoryId or "category"), tostring(capstoneReached == true))

    local role
    if isEntryActive(categoryData) then
        role = GOLDEN_COLOR_ROLES.ActiveEntry
    elseif capstoneReached then
        role = GOLDEN_COLOR_ROLES.CategoryCompleted
    else
        role = GOLDEN_COLOR_ROLES.CategoryOpen
    end

    safeDebug("Golden[%s].colorRole = %s", tostring(categoryId or "category"), tostring(role))

    return role
end

local function getTrackerColor(role)
    local addon = getAddon()
    if type(addon) ~= "table" then
        return 1, 1, 1, 1
    end

    local host = rawget(addon, "TrackerHost")
    if type(host) ~= "table" then
        return 1, 1, 1, 1
    end

    if type(host.EnsureAppearanceDefaults) == "function" then
        pcall(host.EnsureAppearanceDefaults, host)
    end

    local getColor = host.GetTrackerColor
    if type(getColor) ~= "function" then
        return 1, 1, 1, 1
    end

    local ok, r, g, b, a = pcall(getColor, host, DEFAULT_COLOR_KIND, role)
    if ok and type(r) == "number" then
        return r or 1, g or 1, b or 1, a or 1
    end

    return 1, 1, 1, 1
end

local function applyTrackerColor(label, role, completedRole, useCompletedStyle)
    if not (label and label.SetColor) then
        return
    end

    local applied = false
    if EndeavorRows and type(EndeavorRows.ApplyGroupLabelColor) == "function" then
        local ok, result = pcall(EndeavorRows.ApplyGroupLabelColor, label, {
            entryRole = role,
            completedRole = completedRole or role,
            colorKind = DEFAULT_COLOR_KIND,
        }, useCompletedStyle)
        if ok then
            applied = result == true
        end
    end

    if not applied then
        local r, g, b, a = getTrackerColor(useCompletedStyle and (completedRole or role) or role)
        label:SetColor(r or 1, g or 1, b or 1, a or 1)
        if label.SetAlpha then
            label:SetAlpha(1)
        end
    end
end

local function resolveCategoryColorRole(categoryData)
    if type(categoryData) ~= "table" then
        return GOLDEN_COLOR_ROLES.CategoryTitleClosed
    end

    local completed = tonumber(categoryData.completedCount or categoryData.countCompleted)
    local total = tonumber(categoryData.totalCount or categoryData.countTotal)
    local isComplete = categoryData.isComplete == true or categoryData.isCompleted == true
    if completed ~= nil and total ~= nil and total > 0 and completed >= total then
        isComplete = true
    end

    if isComplete then
        return GOLDEN_COLOR_ROLES.Completed
    end

    local expanded = categoryData.isExpanded
    if expanded == nil then
        expanded = categoryData.expanded
    end

    local collapsed = expanded == false or categoryData.isCollapsed == true
    if collapsed and total ~= nil and completed ~= nil and total > 0 and completed < total then
        return GOLDEN_COLOR_ROLES.CategoryTitleOpen
    end

    return GOLDEN_COLOR_ROLES.CategoryTitleClosed
end

local function createControl(parent, kind)
    local wm = getWindowManager()
    if wm == nil then
        return nil
    end

    if parent == nil then
        safeDebug("createControl skipped; parent missing for kind '%s'", tostring(kind))
        return nil
    end

    local controlName = nextControlName(parent, kind)
    local control = wm:CreateControl(controlName, parent, CT_CONTROL)
    if control and control.SetResizeToFitDescendents then
        control:SetResizeToFitDescendents(true)
    end
    if control and control.SetHidden then
        control:SetHidden(false)
    end

    if control and control.SetMouseEnabled then
        control:SetMouseEnabled(true)
    end

    return control
end

local function createLabel(parent, suffix)
    local wm = getWindowManager()
    if wm == nil or parent == nil then
        return nil
    end

    local baseName = resolveParentName(parent)
    local labelName = string.format("%s_%sLabel", baseName, suffix)
    local label = wm:CreateControl(labelName, parent, CT_LABEL)
    if label and label.SetHidden then
        label:SetHidden(false)
    end

    return label
end

function Rows.CreateCategoryRow(parent, categoryData)
    if parent == nil then
        return nil
    end

    local wm = getWindowManager()
    if wm == nil then
        return nil
    end

    local control = createControl(parent, "category")
    if not control then
        return nil
    end

    control.__height = DEFAULTS.CATEGORY_HEIGHT
    if control.SetHeight then
        control:SetHeight(DEFAULTS.CATEGORY_HEIGHT)
    end

    local chevron = nil
    local controlName = control.GetName and control:GetName() or resolveParentName(control)
    if controlName then
        local chevronName = string.format("%s_CategoryChevron", controlName)
        chevron = wm:CreateControl(chevronName, control, CT_TEXTURE)
        if chevron.SetMouseEnabled then
            chevron:SetMouseEnabled(false)
        end
        if chevron.SetHidden then
            chevron:SetHidden(false)
        end
        if chevron.SetDimensions then
            chevron:SetDimensions(CATEGORY_CHEVRON_SIZE, CATEGORY_CHEVRON_SIZE)
        end
        if chevron.ClearAnchors then
            chevron:ClearAnchors()
            chevron:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
        end
    end

    local label = createLabel(control, "Category")
    if label then
        label:ClearAnchors()
        if label.SetAnchor then
            local anchorTarget = chevron or control
            label:SetAnchor(TOPLEFT, anchorTarget, TOPRIGHT, CATEGORY_LABEL_OFFSET_X, 0)
            label:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
        end
        applyLabelDefaults(label, getGoldenCategoryFont())
        applyTrackerColor(label, resolveCategoryColorRole(categoryData), GOLDEN_COLOR_ROLES.CategoryCompleted)

        local text = ""
        if type(categoryData) == "table" then
            local remaining = tonumber(categoryData.remainingObjectivesToNextReward) or 0
            text = string.format("GOLDENE VORHABEN (%d)", remaining)
        end
        if label.SetText then
            label:SetText(text)
        end
    end

    if chevron and chevron.SetTexture then
        local expanded = categoryData and categoryData.isExpanded ~= false
        local textures = categoryData and categoryData.textures or CATEGORY_CHEVRON_TEXTURES
        local fallback = expanded and CATEGORY_CHEVRON_TEXTURES.expanded or CATEGORY_CHEVRON_TEXTURES.collapsed
        chevron:SetTexture(
            (expanded and textures.expanded) or (not expanded and textures.collapsed) or fallback
        )
    end

    if control and control.SetHandler then
        control:SetHandler("OnMouseUp", function(rowControl, button, upInside)
            if button == MOUSE_BUTTON_LEFT and upInside then
                local controller = rawget(Nvk3UT, "GoldenTrackerController")
                if controller and type(controller.ToggleHeaderExpanded) == "function" then
                    controller:ToggleHeaderExpanded()
                end
            end
        end)
    end

    return control
end

function Rows.CreateCampaignRow(parent, entryData)
    if parent == nil then
        return nil
    end

    local control = createControl(parent, "entry")
    if not control then
        return nil
    end

    control.__height = DEFAULTS.ENTRY_HEIGHT
    if control.SetHeight then
        control:SetHeight(DEFAULTS.ENTRY_HEIGHT)
    end

    local label = createLabel(control, "EntryTitle")
    if label then
        label:ClearAnchors()
        if label.SetAnchor then
            label:SetAnchor(TOPLEFT, control, TOPLEFT, ENTRY_INDENT_X, 0)
            label:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, 0, 0)
        end
        applyLabelDefaults(label, getGoldenTitleFont())
        local entryRole = isEntryActive(entryData) and GOLDEN_COLOR_ROLES.ActiveEntry or GOLDEN_COLOR_ROLES.EntryName
        applyTrackerColor(label, entryRole, GOLDEN_COLOR_ROLES.CompletedEntry, entryRole == GOLDEN_COLOR_ROLES.CompletedEntry)

        local text = ""
        if type(entryData) == "table" then
            local display = entryData.campaignName or entryData.displayName or entryData.title or entryData.name
            local completed = tonumber(entryData.completedObjectives or entryData.countCompleted)
            local total = tonumber(entryData.maxRewardTier or entryData.countTotal)
            if completed == nil then
                completed = tonumber(entryData.count) or tonumber(entryData.progressDisplay)
            end
            if total == nil then
                total = tonumber(entryData.max) or tonumber(entryData.maxDisplay)
            end

            if completed ~= nil and total ~= nil then
                text = string.format("%s (%d/%d)", tostring(display or ""), completed, total)
            else
                text = tostring(display or "")
            end
        end
        if label.SetText then
            label:SetText(text)
        end
    end

    if control and control.SetHandler then
        control:SetHandler("OnMouseUp", function(_, button, upInside)
            if button == MOUSE_BUTTON_LEFT and upInside then
                local controller = rawget(Nvk3UT, "GoldenTrackerController")
                if controller and type(controller.ToggleEntryExpanded) == "function" then
                    controller:ToggleEntryExpanded()
                end
            end
        end)
    end

    return control
end

function Rows.CreateObjectiveRow(parent, objectiveData)
    if parent == nil then
        return nil
    end

    local control = createControl(parent, "objective")
    if not control then
        return nil
    end

    control.__height = DEFAULTS.OBJECTIVE_HEIGHT
    if control.SetHeight then
        control:SetHeight(DEFAULTS.OBJECTIVE_HEIGHT)
    end

    local label = createLabel(control, "Objective")
    if label then
        label:ClearAnchors()
        if label.SetAnchor then
            label:SetAnchor(TOPLEFT, control, TOPLEFT, DEFAULTS.OBJECTIVE_INDENT_X, 0)
            label:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, 0, 0)
        end
        local objectiveCompleted = isObjectiveCompleted(objectiveData)
        local objectiveActive = isEntryActive(objectiveData)
        local role = GOLDEN_COLOR_ROLES.TargetText
        if objectiveActive then
            role = GOLDEN_COLOR_ROLES.ActiveEntry
        elseif objectiveCompleted then
            role = GOLDEN_COLOR_ROLES.CompletedEntry
        end
        applyLabelDefaults(label, getGoldenObjectiveFont())
        applyTrackerColor(label, role, GOLDEN_COLOR_ROLES.CompletedEntry, objectiveCompleted)

        local text = ""
        if type(objectiveData) == "table" then
            local display = objectiveData.displayName or objectiveData.title or objectiveData.name or objectiveData.text
            if display == nil or display == "" then
                display = "Objective"
            end

            local baseText = tostring(display or "")
            local counterText = formatObjectiveCounter(
                objectiveData.progressDisplay or objectiveData.progress or objectiveData.current,
                objectiveData.maxDisplay or objectiveData.max
            )
            if counterText == nil then
                local fallbackCounter = objectiveData.counterText
                if type(fallbackCounter) == "string" and fallbackCounter ~= "" then
                    counterText = string.format("(%s)", fallbackCounter)
                end
            end

            text = baseText
            if counterText and counterText ~= "" then
                text = string.format("%s %s", baseText, counterText)
            end

            text = text:gsub("%s+", " "):gsub("%s+%)", ")")
        end

        if label.SetText then
            label:SetText(text)
        end
    end

    return control
end

Nvk3UT.GoldenTrackerRows = Rows

return Rows
