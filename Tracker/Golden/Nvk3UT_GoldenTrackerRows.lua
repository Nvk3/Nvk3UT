local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local MODULE_TAG = addonName .. ".GoldenTrackerRows"

local GOLDEN_COLOR_ROLES = {
    CategoryTitleClosed = "categoryTitleClosed",
    CategoryTitleOpen = "categoryTitleOpen",
    EntryName = "entryTitle",
    Objective = "objectiveText",
    Active = "activeTitle",
    Completed = "completed",
}

local ROLE_FALLBACKS = {
    [GOLDEN_COLOR_ROLES.CategoryTitleClosed] = "categoryTitle",
    [GOLDEN_COLOR_ROLES.CategoryTitleOpen] = "entryTitle",
    [GOLDEN_COLOR_ROLES.EntryName] = "entryTitle",
    [GOLDEN_COLOR_ROLES.Objective] = "objectiveText",
    [GOLDEN_COLOR_ROLES.Active] = "activeTitle",
    [GOLDEN_COLOR_ROLES.Completed] = "completed",
}

local DEFAULT_COLOR_KIND = "goldenTracker"
local DEFAULT_FALLBACK_COLOR_KIND = "endeavorTracker"

local DEFAULTS = {
    CATEGORY_HEIGHT = 26,
    ENTRY_HEIGHT = 24,
    OBJECTIVE_HEIGHT = 20,
    CATEGORY_FONT = "$(BOLD_FONT)|20|soft-shadow-thick",
    ENTRY_FONT = "$(BOLD_FONT)|16|soft-shadow-thick",
    OBJECTIVE_FONT = "$(BOLD_FONT)|16|soft-shadow-thick",
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
local MIN_FONT_SIZE = 12
local MAX_FONT_SIZE = 36

local controlCounters = {
    category = 0,
    entry = 0,
    objective = 0,
}

local function safeDebug(message, ...)
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

local function applyConfiguredFont(label, key)
    if not (label and label.SetFont) then
        return false
    end

    local fonts = getConfiguredFonts()
    if type(fonts) ~= "table" then
        return false
    end

    local group = selectFontGroup(fonts, key)
    if type(group) ~= "table" then
        return false
    end

    local fontString = buildFontString(group.Face or group.face, group.Size or group.size, group.Outline or group.outline)
    if fontString == nil then
        return false
    end

    label:SetFont(fontString)
    return true
end

local function sanitizeColorNumber(value)
    local numeric = tonumber(value)
    if numeric == nil then
        return nil
    end
    if numeric < 0 then
        numeric = 0
    elseif numeric > 1 then
        numeric = 1
    end
    return numeric
end

local function extractColorComponents(color)
    if type(color) ~= "table" then
        return nil
    end

    local r = sanitizeColorNumber(color.r or color[1])
    local g = sanitizeColorNumber(color.g or color[2])
    local b = sanitizeColorNumber(color.b or color[3])
    local a = sanitizeColorNumber(color.a or color[4] or 1)

    if r == nil or g == nil or b == nil then
        return nil
    end

    return r, g, b, a or 1
end

local function coerceFunctionColor(entry, context, role, colorKind)
    if type(entry) ~= "function" then
        return nil
    end

    local ok, value1, value2, value3, value4 = pcall(entry, context, role, colorKind)
    if not ok then
        safeDebug("resolveGoldenColor failed for role=%s: %s", tostring(role), tostring(value1))
        return nil
    end

    return extractColorComponents({ value1, value2, value3, value4 })
end

local function resolveGoldenColor(role, overrideColors, colorKind)
    local resolvedKind = colorKind
    if type(resolvedKind) ~= "string" or resolvedKind == "" then
        resolvedKind = DEFAULT_COLOR_KIND
    end

    if type(overrideColors) == "table" then
        local overrideEntry = overrideColors[role]
        if type(overrideEntry) == "function" then
            local r, g, b, a = coerceFunctionColor(overrideEntry, overrideColors, role, resolvedKind)
            if r ~= nil then
                return r, g, b, a
            end
        elseif type(overrideEntry) == "table" then
            local r, g, b, a = extractColorComponents(overrideEntry)
            if r ~= nil then
                return r, g, b, a
            end
        end
    end

    local host = Nvk3UT and Nvk3UT.TrackerHost
    local function fetch(kind, requestedRole)
        if host and host.GetTrackerColor then
            return host.GetTrackerColor(kind, requestedRole or role)
        end
        return nil
    end

    local r, g, b, a = fetch(resolvedKind, role)
    if r ~= nil and g ~= nil and b ~= nil then
        return r, g, b, a
    end

    local fallbackRole = ROLE_FALLBACKS[role] or role
    r, g, b, a = fetch(DEFAULT_FALLBACK_COLOR_KIND, fallbackRole)
    if r ~= nil and g ~= nil and b ~= nil then
        return r, g, b, a
    end

    return 1, 1, 1, 1
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

local function applyLabelColor(label, role)
    if not (label and label.SetColor) then
        return
    end

    local r, g, b, a = resolveGoldenColor(role)
    label:SetColor(r or 1, g or 1, b or 1, a or 1)
    if label.SetAlpha then
        label:SetAlpha(1)
    end
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
        local appliedFont = applyConfiguredFont(label, "Category")
        applyLabelDefaults(label, appliedFont and nil or DEFAULTS.CATEGORY_FONT)

        local expanded = categoryData and categoryData.isExpanded ~= false
        applyLabelColor(label, expanded and GOLDEN_COLOR_ROLES.Active or GOLDEN_COLOR_ROLES.CategoryTitleClosed)

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
        local appliedFont = applyConfiguredFont(label, "Title")
        applyLabelDefaults(label, appliedFont and nil or DEFAULTS.ENTRY_FONT)
        applyLabelColor(label, GOLDEN_COLOR_ROLES.EntryName)

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
        local role = objectiveData and (objectiveData.isComplete == true or objectiveData.isCompleted == true)
            and GOLDEN_COLOR_ROLES.Completed
            or GOLDEN_COLOR_ROLES.Objective
        local appliedFont = applyConfiguredFont(label, "Objective")
        applyLabelDefaults(label, appliedFont and nil or DEFAULTS.OBJECTIVE_FONT)
        applyLabelColor(label, role)

        local text = ""
        if type(objectiveData) == "table" then
            local display = objectiveData.displayName or objectiveData.title or objectiveData.name or objectiveData.text
            if display == nil then
                display = ""
            end
            text = tostring(display)

            local counterText = objectiveData.counterText
            local progress = tonumber(objectiveData.progressDisplay or objectiveData.progress or objectiveData.current)
            local maxValue = tonumber(objectiveData.maxDisplay or objectiveData.max)
            if not counterText and progress and maxValue then
                counterText = string.format("%d/%d", progress, maxValue)
            end
            if counterText and counterText ~= "" then
                text = string.format("%s (%s)", text, counterText)
            end
        end

        if label.SetText then
            label:SetText(text)
        end
    end

    return control
end

Nvk3UT.GoldenTrackerRows = Rows

return Rows
