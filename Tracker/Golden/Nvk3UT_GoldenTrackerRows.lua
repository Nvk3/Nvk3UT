local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local MODULE_TAG = addonName .. ".GoldenTrackerRows"
local GOLDEN_COLOR_DEBUG_TAG = "GoldenColor"

local GOLDEN_COLOR_ROLES = {
    CategoryTitleClosed = "categoryTitleClosed",
    CategoryTitleOpen = "categoryTitleOpen",
    EntryName = "entryTitle",
    Objective = "objectiveText",
    Active = "activeTitle",
    Completed = "completed",
}

local DEFAULT_COLOR_KIND = "goldenTracker"

local GOLDEN_COLOR_ROLE_LIST = {
    GOLDEN_COLOR_ROLES.CategoryTitleClosed,
    GOLDEN_COLOR_ROLES.CategoryTitleOpen,
    GOLDEN_COLOR_ROLES.EntryName,
    GOLDEN_COLOR_ROLES.Objective,
    GOLDEN_COLOR_ROLES.Active,
    GOLDEN_COLOR_ROLES.Completed,
}

local DEFAULT_GOLDEN_COLOR_VALUES = {
    [GOLDEN_COLOR_ROLES.CategoryTitleClosed] = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
    [GOLDEN_COLOR_ROLES.CategoryTitleOpen] = { r = 1, g = 1, b = 0, a = 1 },
    [GOLDEN_COLOR_ROLES.EntryName] = { r = 1, g = 1, b = 0, a = 1 },
    [GOLDEN_COLOR_ROLES.Objective] = { r = 0.7725, g = 0.7608, b = 0.6196, a = 1 },
    [GOLDEN_COLOR_ROLES.Active] = { r = 1, g = 1, b = 1, a = 1 },
    [GOLDEN_COLOR_ROLES.Completed] = { r = 0.6, g = 0.6, b = 0.6, a = 1 },
}

local DEFAULTS = {
    CATEGORY_HEIGHT = 26,
    ENTRY_HEIGHT = 24,
    OBJECTIVE_HEIGHT = 20,
    CATEGORY_FONT = "$(BOLD_FONT)|20|soft-shadow-thick",
    ENTRY_FONT = "$(BOLD_FONT)|16|soft-shadow-thick",
    OBJECTIVE_FONT = "$(BOLD_FONT)|14|soft-shadow-thick",
    OBJECTIVE_INDENT_X = 60,
}

local GOLDEN_HEADER_TITLE = "GOLDENE VORHABEN"

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

local function getAddon()
    return rawget(_G, addonName)
end

local function isGoldenColorDebugEnabled()
    local root = getAddon()

    local utils = (root and root.Utils) or rawget(_G, "Nvk3UT_Utils")
    if type(utils) == "table" and type(utils.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(utils.IsDebugEnabled)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local diagnostics = (root and root.Diagnostics) or rawget(_G, "Nvk3UT_Diagnostics")
    if type(diagnostics) == "table" and type(diagnostics.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return diagnostics:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    if type(root) == "table" and type(root.IsDebugEnabled) == "function" then
        local ok, enabled = pcall(function()
            return root:IsDebugEnabled()
        end)
        if ok and enabled ~= nil then
            return enabled == true
        end
    end

    local sv = root and (root.sv or root.SV)
    if type(sv) == "table" then
        local flag = sv.debug
        if flag == nil then
            flag = sv.debugEnabled
        end
        if flag ~= nil then
            return flag == true
        end
    end

    return false
end

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

local function getSavedVars()
    local addon = getAddon()
    if type(addon) ~= "table" then
        return nil
    end

    local sv = addon.SV or addon.sv
    if type(sv) ~= "table" then
        return nil
    end

    return sv
end

local function getConfiguredFonts()
    local sv = getSavedVars()
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

local function shouldShowGoldenHeaderCounter()
    local sv = getSavedVars()
    if type(sv) ~= "table" then
        return true
    end

    local config = sv.Golden
    if type(config) == "table" then
        local flag = config.ShowCountsInHeaders
        if flag == nil then
            flag = config.showCountsInHeaders
        end
        if flag ~= nil then
            return flag ~= false
        end
    end

    local trackerDefaults = sv.TrackerDefaults
    if type(trackerDefaults) == "table" then
        local goldenDefaults = trackerDefaults.GoldenDefaults
        if type(goldenDefaults) == "table" then
            local flag = goldenDefaults.ShowCountsInHeaders
            if flag == nil then
                flag = goldenDefaults.showCountsInHeaders
            end
            if flag ~= nil then
                return flag ~= false
            end
        end
    end

    return true
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

local function formatColorForLog(color)
    if type(color) ~= "table" then
        return "n/a"
    end

    local r = sanitizeColorNumber(color.r or color[1]) or 0
    local g = sanitizeColorNumber(color.g or color[2]) or 0
    local b = sanitizeColorNumber(color.b or color[3]) or 0
    local a = sanitizeColorNumber(color.a or color[4]) or 0

    return string.format("%.3f,%.3f,%.3f,%.3f", r, g, b, a)
end

local function logGoldenColorDecision(context, state, source, colorComponents, reason, metadata)
    local root = getAddon()
    local diagnostics = (root and root.Diagnostics) or rawget(_G, "Nvk3UT_Diagnostics")
    local colorText = formatColorForLog(colorComponents)
    local paletteEntry = metadata and metadata.palette
    local paletteText = formatColorForLog(paletteEntry)
    local roleKey = metadata and metadata.role or "?"
    local message = string.format(
        "[%s] ctx=%s state=%s key=%s source=%s raw=%s color=%s reason=%s",
        GOLDEN_COLOR_DEBUG_TAG,
        tostring(context or "?"),
        tostring(state or "?"),
        tostring(roleKey or "?"),
        tostring(source or "?"),
        paletteText,
        colorText,
        tostring(reason or "")
    )

    if diagnostics and type(diagnostics.DebugIfEnabled) == "function" then
        diagnostics:DebugIfEnabled(GOLDEN_COLOR_DEBUG_TAG, message)
        return
    end

    local debugFn = root and root.Debug
    if type(debugFn) == "function" then
        debugFn(message)
    end
end

local function buildColorTable(r, g, b, a, source, sourceReason)
    local color = {
        r = sanitizeColorNumber(r) or 1,
        g = sanitizeColorNumber(g) or 1,
        b = sanitizeColorNumber(b) or 1,
        a = sanitizeColorNumber(a or 1) or 1,
    }
    color[1], color[2], color[3], color[4] = color.r, color.g, color.b, color.a
    color.__source = source
    color.__sourceReason = sourceReason
    return color
end

local function getTrackerHost()
    local addon = getAddon()
    if type(addon) ~= "table" then
        return nil
    end
    local host = addon.TrackerHost
    if type(host) == "table" then
        return host
    end
    return nil
end

local function fetchTrackerColor(host, role)
    local r, g, b, a
    local source
    local sourceReason
    if type(host) == "table" then
        if type(host.EnsureAppearanceDefaults) == "function" then
            pcall(host.EnsureAppearanceDefaults, host)
        end
        if type(host.GetTrackerColor) == "function" then
            local ok, colorR, colorG, colorB, colorA = pcall(host.GetTrackerColor, DEFAULT_COLOR_KIND, role)
            if ok and type(colorR) == "number" then
                r = colorR
                g = colorG or 1
                b = colorB or 1
                a = colorA or 1
                source = string.format("savedvars.%s.%s", DEFAULT_COLOR_KIND, tostring(role))
                sourceReason = "Tracker host returned configured color"
            end
        end
    end

    if r == nil then
        local fallback = DEFAULT_GOLDEN_COLOR_VALUES[role] or DEFAULT_GOLDEN_COLOR_VALUES[GOLDEN_COLOR_ROLES.EntryName]
        if type(fallback) == "table" then
            r = fallback.r or fallback[1] or 1
            g = fallback.g or fallback[2] or 1
            b = fallback.b or fallback[3] or 1
            a = fallback.a or fallback[4] or 1
            source = string.format("defaults.golden.%s", tostring(role))
            sourceReason = "Tracker host missing color; using Golden defaults"
        else
            r, g, b, a = 1, 1, 1, 1
            source = string.format("defaults.golden.%s", tostring(role))
            sourceReason = "No defaults available; using white fallback"
        end
    end

    return buildColorTable(r, g, b, a, source, sourceReason)
end

local function getGoldenTrackerColors()
    local palette = {}
    local host = getTrackerHost()
    for index = 1, #GOLDEN_COLOR_ROLE_LIST do
        local role = GOLDEN_COLOR_ROLE_LIST[index]
        palette[role] = fetchTrackerColor(host, role)
    end
    return palette
end

local function selectFirstNumber(...)
    local argCount = select("#", ...)
    for index = 1, argCount do
        local candidate = select(index, ...)
        local numeric = tonumber(candidate)
        if numeric ~= nil and numeric == numeric then
            return numeric
        end
    end
    return nil
end

local function isCapstoneComplete(payload)
    if type(payload) ~= "table" then
        return false
    end

    if payload.isComplete == true or payload.isCompleted == true or payload.completed == true then
        return true
    end

    local completed = selectFirstNumber(
        payload.completedObjectives,
        payload.completedActivities,
        payload.countCompleted,
        payload.totalCompleted
    )
    local total = selectFirstNumber(
        payload.maxRewardTier,
        payload.capstoneCompletionThreshold,
        payload.capLimit,
        payload.totalEntries,
        payload.totalCount,
        payload.countTotal
    )

    if total and total > 0 and completed and completed >= total then
        return true
    end

    local remaining = selectFirstNumber(
        payload.remainingObjectivesToNextReward,
        payload.remainingObjectives,
        payload.totalRemaining,
        payload.remaining
    )
    if remaining ~= nil and remaining <= 0 then
        return true
    end

    return false
end

local function isObjectiveCompleted(objectiveData)
    if type(objectiveData) ~= "table" then
        return false
    end

    if objectiveData.isCompleted == true or objectiveData.isComplete == true or objectiveData.completed == true then
        return true
    end

    local progress = selectFirstNumber(objectiveData.progress, objectiveData.current, objectiveData.progressDisplay)
    local maxValue = selectFirstNumber(objectiveData.max, objectiveData.maxDisplay)
    if progress ~= nil and maxValue ~= nil and maxValue > 0 and progress >= maxValue then
        return true
    end

    return false
end

Nvk3UT.GetGoldenTrackerColors = getGoldenTrackerColors

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

local function resolveGoldenColor(role, overrideColors, colorKind, palette)
    if type(overrideColors) == "table" then
        local overrideEntry = overrideColors[role]
        if type(overrideEntry) == "function" then
            local r, g, b, a = coerceFunctionColor(overrideEntry, overrideColors, role, colorKind)
            if r ~= nil then
                return r, g, b, a, string.format("override.function.%s", tostring(role)), "Override function provided color"
            end
        elseif type(overrideEntry) == "table" then
            local r, g, b, a = extractColorComponents(overrideEntry)
            if r ~= nil then
                return r, g, b, a, string.format("override.table.%s", tostring(role)), "Override table provided color"
            end
        end
    end

    local colors = type(palette) == "table" and palette or getGoldenTrackerColors()
    local entry = colors and colors[role]
    if type(entry) == "table" then
        local r = entry.r or entry[1] or 1
        local g = entry.g or entry[2] or 1
        local b = entry.b or entry[3] or 1
        local a = entry.a or entry[4] or 1
        local source = entry.__source or string.format("palette.%s", tostring(role))
        local sourceReason = entry.__sourceReason or "Palette entry"
        return r, g, b, a, source, sourceReason
    end

    local fallback = DEFAULT_GOLDEN_COLOR_VALUES[role] or DEFAULT_GOLDEN_COLOR_VALUES[GOLDEN_COLOR_ROLES.EntryName]
    local r = fallback.r or fallback[1] or 1
    local g = fallback.g or fallback[2] or 1
    local b = fallback.b or fallback[3] or 1
    local a = fallback.a or fallback[4] or 1
    return r, g, b, a, string.format("fallback.default.%s", tostring(role)), "Palette missing entry; using Golden defaults"
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

local function applyLabelColor(label, role, palette, overrideColors, colorKind)
    if not (label and label.SetColor) then
        return nil
    end

    local r, g, b, a, source, sourceReason = resolveGoldenColor(role, overrideColors, colorKind, palette)
    label:SetColor(r or 1, g or 1, b or 1, a or 1)
    if label.SetAlpha then
        label:SetAlpha(1)
    end

    return r, g, b, a, source, sourceReason
end

function Rows.CreateCategoryRow(parent, categoryData)
    if parent == nil then
        return nil
    end

    local wm = getWindowManager()
    if wm == nil then
        return nil
    end

    local palette = getGoldenTrackerColors()
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

        local expanded = true
        if type(categoryData) == "table" then
            if categoryData.isExpanded ~= nil then
                expanded = categoryData.isExpanded ~= false
            elseif categoryData.expanded ~= nil then
                expanded = categoryData.expanded ~= false
            end
        end

        local categoryComplete = isCapstoneComplete(categoryData)
        local role
        if expanded then
            role = GOLDEN_COLOR_ROLES.Active
        elseif categoryComplete then
            role = GOLDEN_COLOR_ROLES.CategoryTitleClosed
        else
            role = GOLDEN_COLOR_ROLES.CategoryTitleOpen
        end
        local colorR, colorG, colorB, colorA, colorSource, colorSourceReason = applyLabelColor(label, role, palette)
        if colorR ~= nil and isGoldenColorDebugEnabled() then
            local stateTokens = {
                expanded and "active" or "inactive",
                categoryComplete and "capstoneComplete" or "capstoneOpen",
            }
            local reason
            if expanded then
                reason = "Category active; using focused color"
            elseif categoryComplete then
                reason = "Capstone reached; using completed category color"
            else
                reason = "Capstone open; using open category color"
            end
            if colorSourceReason and colorSourceReason ~= "" then
                reason = string.format("%s (%s)", reason, colorSourceReason)
            end

            logGoldenColorDecision(
                "golden.categoryHeader",
                table.concat(stateTokens, "+"),
                colorSource or string.format("role.%s", tostring(role)),
                { colorR, colorG, colorB, colorA },
                reason,
                { role = role, palette = palette and palette[role] }
            )
        end

        local text = GOLDEN_HEADER_TITLE
        local showCounter = shouldShowGoldenHeaderCounter()
        local remaining = nil
        local generalMode = type(categoryData) == "table" and categoryData.generalCompletedMode
        local capstoneReached = categoryData and categoryData.capstoneReached == true
        if type(categoryData) == "table" then
            if showCounter and capstoneReached and generalMode == "showOpen" then
                remaining = tonumber(categoryData.remainingAllObjectives) or 0
            else
                remaining = tonumber(categoryData.remainingObjectivesToNextReward) or 0
            end
        end

        if showCounter and remaining ~= nil then
            text = string.format("%s (%d)", GOLDEN_HEADER_TITLE, remaining)
        end

        if not showCounter then
            text = GOLDEN_HEADER_TITLE
        end

        if isGoldenColorDebugEnabled() then
            safeDebug(
                "[GoldenHeader] title='%s' count=%s showCounter=%s",
                text,
                tostring(remaining),
                tostring(showCounter)
            )
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

    local palette = getGoldenTrackerColors()
    local label = createLabel(control, "EntryTitle")
    if label then
        label:ClearAnchors()
        if label.SetAnchor then
            label:SetAnchor(TOPLEFT, control, TOPLEFT, ENTRY_INDENT_X, 0)
            label:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, 0, 0)
        end
        applyLabelDefaults(label, getGoldenTitleFont())
        local entryExpanded = true
        if type(entryData) == "table" then
            if entryData.isExpanded ~= nil then
                entryExpanded = entryData.isExpanded ~= false
            elseif entryData.expanded ~= nil then
                entryExpanded = entryData.expanded ~= false
            end
        end
        local entryComplete = isCapstoneComplete(entryData)
        local generalMode = type(entryData) == "table" and entryData.generalCompletedMode
        local useCompletedColor = entryComplete and generalMode == "recolor"
        local entryRole = useCompletedColor and GOLDEN_COLOR_ROLES.Completed or GOLDEN_COLOR_ROLES.EntryName
        local colorR, colorG, colorB, colorA, colorSource, colorSourceReason = applyLabelColor(label, entryRole, palette)
        if colorR ~= nil and isGoldenColorDebugEnabled() then
            local stateTokens = {
                entryExpanded and "active" or "inactive",
                entryComplete and "capstoneComplete" or "capstoneOpen",
                generalMode,
            }
            local reason
            if useCompletedColor then
                reason = "Capstone reached with general recolor; using completed color"
            else
                reason = "Campaign entry always uses entry title color"
                if entryExpanded or entryComplete then
                    reason = string.format("%s (active/completed state ignored for color)", reason)
                end
            end
            if colorSourceReason and colorSourceReason ~= "" then
                reason = string.format("%s (%s)", reason, colorSourceReason)
            end

            logGoldenColorDecision(
                "golden.campaignEntry",
                table.concat(stateTokens, "+"),
                colorSource or string.format("role.%s", tostring(entryRole)),
                { colorR, colorG, colorB, colorA },
                reason,
                { role = entryRole, palette = palette and palette[entryRole] }
            )
        end

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

            local overallCompleted = tonumber(entryData.totalCompletedOverall)
            local capstoneGoal = tonumber(entryData.capstoneGoal or entryData.maxRewardTier or entryData.countTotal)
            if entryComplete and generalMode == "showOpen" then
                if overallCompleted ~= nil then
                    completed = overallCompleted
                end
                if capstoneGoal ~= nil then
                    total = capstoneGoal
                end
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

    local palette = getGoldenTrackerColors()
    local label = createLabel(control, "Objective")
    if label then
        label:ClearAnchors()
        if label.SetAnchor then
            label:SetAnchor(TOPLEFT, control, TOPLEFT, DEFAULTS.OBJECTIVE_INDENT_X, 0)
            label:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, 0, 0)
        end
        local role = isObjectiveCompleted(objectiveData) and GOLDEN_COLOR_ROLES.Completed or GOLDEN_COLOR_ROLES.Objective
        applyLabelDefaults(label, getGoldenObjectiveFont())
        local colorR, colorG, colorB, colorA, colorSource, colorSourceReason = applyLabelColor(label, role, palette)
        if colorR ~= nil and isGoldenColorDebugEnabled() then
            local isCompleted = role == GOLDEN_COLOR_ROLES.Completed
            local stateTokens = {
                isCompleted and "completed" or "open",
            }
            local reason
            if isCompleted then
                reason = "Objective complete; using completed color"
            else
                reason = "Objective in progress; using target color"
            end
            if colorSourceReason and colorSourceReason ~= "" then
                reason = string.format("%s (%s)", reason, colorSourceReason)
            end

            logGoldenColorDecision(
                "golden.objectiveText",
                table.concat(stateTokens, "+"),
                colorSource or string.format("role.%s", tostring(role)),
                { colorR, colorG, colorB, colorA },
                reason,
                { role = role, palette = palette and palette[role] }
            )
        end

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
