
local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local MODULE_TAG = addonName .. ".EndeavorTrackerRows"

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

local OBJECTIVE_ROW_DEFAULT_HEIGHT = 20
local DEFAULT_OBJECTIVE_FONT = "ZoFontGameSmall"
local DEFAULT_FONT_OUTLINE = "soft-shadow-thick"
local DEFAULT_OBJECTIVE_COLOR_ROLE = "objectiveText"
local DEFAULT_TRACKER_COLOR_KIND = "endeavorTracker"
local COMPLETED_COLOR_ROLE = "completed"
local ROW_GAP = 3
local OBJECTIVE_INDENT_X = 60

local CATEGORY_ROW_HEIGHT = 26
local CATEGORY_CHEVRON_SIZE = 20
local CATEGORY_LABEL_OFFSET_X = 4
local DEFAULT_CATEGORY_COLOR_ROLE_EXPANDED = "activeTitle"
local DEFAULT_CATEGORY_COLOR_ROLE_COLLAPSED = "categoryTitle"

local DEFAULT_CATEGORY_CHEVRON_TEXTURES = {
    expanded = "EsoUI/Art/Buttons/tree_open_up.dds",
    collapsed = "EsoUI/Art/Buttons/tree_closed_up.dds",
}

local MOUSE_BUTTON_LEFT = rawget(_G, "MOUSE_BUTTON_INDEX_LEFT") or 1

local function FormatParensCount(a, b)
    local aNum = tonumber(a) or 0
    if aNum < 0 then
        aNum = 0
    end

    local bNum = tonumber(b) or 1
    if bNum < 1 then
        bNum = 1
    end

    if aNum > bNum then
        aNum = bNum
    end

    return string.format("(%d/%d)", math.floor(aNum + 0.5), math.floor(bNum + 0.5))
end

Rows._cache = Rows._cache or setmetatable({}, { __mode = "k" })

local categoryPool = {
    free = {},
    used = {},
    nextId = 1,
}

local lastHeight = 0

local function safeDebug(fmt, ...)
    if not isDebugEnabled() then
        return
    end

    local root = rawget(_G, addonName)
    if type(root) ~= "table" then
        return
    end

    local diagnostics = root.Diagnostics
    if diagnostics and type(diagnostics.DebugIfEnabled) == "function" then
        diagnostics:DebugIfEnabled("EndeavorTrackerRows", fmt, ...)
        return
    end

    if fmt == nil then
        return
    end

    local message = string.format(tostring(fmt), ...)
    local prefix = string.format("[%s]", MODULE_TAG)
    if type(root.Debug) == "function" then
        root:Debug("%s %s", prefix, message)
    elseif type(d) == "function" then
        d(prefix, message)
    elseif type(print) == "function" then
        print(prefix, message)
    end
end

local function coerceNumber(value)
    if type(value) == "number" then
        if value ~= value then
            return 0
        end
        return value
    end

    return 0
end

local function getAddon()
    return rawget(_G, addonName)
end

local function getTrackerColor(role, colorKind)
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

    local ok, r, g, b, a = pcall(getColor, host, colorKind or DEFAULT_TRACKER_COLOR_KIND, role)
    if ok and type(r) == "number" then
        return r, g or 1, b or 1, a or 1
    end

    return 1, 1, 1, 1
end

local function applyFontString(label, font, fallback)
    if not (label and label.SetFont) then
        return
    end

    local resolved = font
    if resolved == nil or resolved == "" then
        resolved = fallback
    end

    if resolved and resolved ~= "" then
        label:SetFont(resolved)
    end
end

local function clampFontSize(value)
    local numeric = tonumber(value)
    if numeric == nil then
        return nil
    end

    numeric = math.floor(numeric + 0.5)
    if numeric < 12 then
        numeric = 12
    elseif numeric > 36 then
        numeric = 36
    end

    return numeric
end

local function BuildFontString(face, size, outline)
    return string.format("%s|%d|%s", face, size, outline)
end

local function extractColorComponents(color)
    if type(color) ~= "table" then
        return nil
    end

    local r = tonumber(color.r or color[1])
    local g = tonumber(color.g or color[2])
    local b = tonumber(color.b or color[3])
    local a = tonumber(color.a or color[4] or 1)

    if r == nil or g == nil or b == nil then
        return nil
    end

    if r < 0 then
        r = 0
    elseif r > 1 then
        r = 1
    end

    if g < 0 then
        g = 0
    elseif g > 1 then
        g = 1
    end

    if b < 0 then
        b = 0
    elseif b > 1 then
        b = 1
    end

    if a < 0 then
        a = 0
    elseif a > 1 then
        a = 1
    end

    return r, g, b, a
end

local function ApplyFont(control, cfg)
    if not (control and control.SetFont) then
        return false
    end

    if type(cfg) ~= "table" then
        return false
    end

    local face = cfg.Face or cfg.face
    if type(face) ~= "string" or face == "" then
        return false
    end

    local size = clampFontSize(cfg.Size or cfg.size)
    if size == nil then
        return false
    end

    local outline = cfg.Outline or cfg.outline or DEFAULT_FONT_OUTLINE
    if type(outline) ~= "string" or outline == "" then
        outline = DEFAULT_FONT_OUTLINE
    end

    control:SetFont(BuildFontString(face, size, outline))
    return true
end

local function getContainerName(parent)
    if parent and type(parent.GetName) == "function" then
        local ok, name = pcall(parent.GetName, parent)
        if ok and type(name) == "string" and name ~= "" then
            return name
        end
    end

    return "Nvk3UT_Endeavor"
end

local function buildCategoryControlName(parent, index)
    local containerName = getContainerName(parent)
    local controlName = string.format("%s_Category", containerName)

    if type(index) == "number" and index > 1 then
        controlName = string.format("%s%d", controlName, index)
    end

    return controlName
end

local function ensureCategoryChild(control, childName, childType)
    local wm = WINDOW_MANAGER
    if wm == nil or control == nil then
        return nil
    end

    local child = GetControl(childName)
    if not child then
        child = wm:CreateControl(childName, control, childType)
    else
        child:SetParent(control)
    end

    return child
end

local function createCategoryRow(parent)
    local wm = WINDOW_MANAGER
    if wm == nil then
        return nil
    end

    local index = categoryPool.nextId or 1
    local controlName = buildCategoryControlName(parent, index)
    categoryPool.nextId = index + 1

    local control = GetControl(controlName)
    if not control then
        control = wm:CreateControl(controlName, parent, CT_CONTROL)
    else
        control:SetParent(parent)
    end

    control:SetResizeToFitDescendents(false)
    control:SetHeight(CATEGORY_ROW_HEIGHT)
    control:SetMouseEnabled(true)
    control:SetHidden(false)

    local chevronName = controlName .. "Chevron"
    local chevron = ensureCategoryChild(control, chevronName, CT_TEXTURE)
    if chevron then
        chevron:SetMouseEnabled(false)
        chevron:SetHidden(false)
        chevron:SetDimensions(CATEGORY_CHEVRON_SIZE, CATEGORY_CHEVRON_SIZE)
        if chevron.ClearAnchors then
            chevron:ClearAnchors()
        end
        chevron:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
        if chevron.SetTexture then
            chevron:SetTexture(DEFAULT_CATEGORY_CHEVRON_TEXTURES.collapsed)
        end
    end

    local labelName = controlName .. "Label"
    local label = ensureCategoryChild(control, labelName, CT_LABEL)
    if label then
        label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
        label:SetVerticalAlignment(TEXT_ALIGN_TOP)
        if label.SetWrapMode then
            label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
        end
        if label.ClearAnchors then
            label:ClearAnchors()
        end
        label:SetAnchor(TOPLEFT, chevron, TOPRIGHT, CATEGORY_LABEL_OFFSET_X, 0)
        label:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
        if label.SetHidden then
            label:SetHidden(false)
        end
    end

    local row = {
        control = control,
        label = label,
        chevron = chevron,
        name = controlName,
        _poolState = "fresh",
    }

    if control and control.SetHandler then
        local function onMouseUp(_, button, upInside)
            if button == MOUSE_BUTTON_LEFT and upInside then
                local callback = row._onToggle
                if type(callback) == "function" then
                    callback()
                end
            end
        end
        control:SetHandler("OnMouseUp", onMouseUp)
        row._mouseHandler = onMouseUp
    end

    safeDebug("[CategoryPool] create %s", controlName)

    return row
end

local function markRowUsed(row)
    if not row then
        return
    end

    row._poolState = "used"
    categoryPool.used[#categoryPool.used + 1] = row
end

local function detachFromUsed(row)
    if not row then
        return
    end

    for index = #categoryPool.used, 1, -1 do
        if categoryPool.used[index] == row then
            table.remove(categoryPool.used, index)
            break
        end
    end
end

local function clampColorComponent(value, defaultValue)
    local numeric = tonumber(value)
    if numeric == nil then
        return defaultValue
    end

    if numeric < 0 then
        numeric = 0
    elseif numeric > 1 then
        numeric = 1
    end

    return numeric
end

local function sanitizeNumericColor(r, g, b, a)
    if r == nil or g == nil or b == nil then
        return nil
    end

    return clampColorComponent(r, 1), clampColorComponent(g, 1), clampColorComponent(b, 1), clampColorComponent(a, 1)
end

local function sanitizeColorResult(value1, value2, value3, value4)
    if type(value1) == "table" and value2 == nil and value3 == nil and value4 == nil then
        local colorTable = value1
        if type(colorTable.UnpackRGBA) == "function" then
            local ok, r, g, b, a = pcall(colorTable.UnpackRGBA, colorTable)
            if ok then
                local sr, sg, sb, sa = sanitizeNumericColor(r, g, b, a)
                if sr ~= nil then
                    return sr, sg, sb, sa
                end
            end
        end

        local r, g, b, a = extractColorComponents(colorTable)
        if r ~= nil then
            return r, g, b, a
        end
    end

    return sanitizeNumericColor(value1, value2, value3, value4)
end

local function coerceFunctionColor(entry, context, role, colorKind)
    if type(entry) ~= "function" then
        return nil
    end

    local ok, value1, value2, value3, value4 = pcall(entry, context, role, colorKind)
    if not ok then
        safeDebug("[CategoryRow] color function failed for role=%s: %s", tostring(role), tostring(value1))
        return nil
    end

    return sanitizeColorResult(value1, value2, value3, value4)
end

local function resolvePaletteEntry(palette, role, colorKind)
    if type(palette) ~= "table" then
        return nil
    end

    local entry = palette[role]
    if type(entry) == "function" then
        return coerceFunctionColor(entry, palette, role, colorKind)
    elseif type(entry) == "table" then
        local r, g, b, a = extractColorComponents(entry)
        if r ~= nil then
            return r, g, b, a
        end
    end

    return nil
end

local function resolveColor(role, overrideColors, colorKind)
    local resolvedKind = colorKind
    if type(resolvedKind) ~= "string" or resolvedKind == "" then
        resolvedKind = DEFAULT_TRACKER_COLOR_KIND
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

    local addon = getAddon()
    local colors = addon and addon.Colors
    if type(colors) == "table" then
        local r, g, b, a = resolvePaletteEntry(colors[resolvedKind], role, resolvedKind)
        if r ~= nil then
            return r, g, b, a
        end

        r, g, b, a = resolvePaletteEntry(colors.default, role, resolvedKind)
        if r ~= nil then
            return r, g, b, a
        end
    end

    return 1, 1, 1, 1
end

local function applyCategoryColor(label, role, overrideColors, colorKind)
    if not (label and label.SetColor) then
        return
    end

    local r, g, b, a = resolveColor(role, overrideColors, colorKind)
    label:SetColor(r, g, b, a)

    if label.SetAlpha then
        label:SetAlpha(1)
    end
end

local function acquireCategoryRow(parent)
    local row = table.remove(categoryPool.free)
    if not row then
        row = createCategoryRow(parent)
    end

    if not row then
        return nil
    end

    local control = row.control
    if control then
        if parent and control.GetParent and control:GetParent() ~= parent then
            control:SetParent(parent)
        elseif parent then
            control:SetParent(parent)
        end

        if control.ClearAnchors then
            control:ClearAnchors()
        end
        if control.SetHidden then
            control:SetHidden(false)
        end
        if control.SetResizeToFitDescendents then
            control:SetResizeToFitDescendents(false)
        end
        if control.SetHeight then
            control:SetHeight(CATEGORY_ROW_HEIGHT)
        end
        if control.SetMouseEnabled then
            control:SetMouseEnabled(true)
        end
    end

    local label = row.label
    if label then
        if label.SetHidden then
            label:SetHidden(false)
        end
    end

    local chevron = row.chevron
    if chevron then
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

    markRowUsed(row)

    safeDebug("[CategoryPool] acquire %s (used=%d free=%d)", tostring(row.name), #categoryPool.used, #categoryPool.free)

    return row
end

local function releaseCategoryRow(row)
    if not row or row._poolState == "free" then
        return
    end

    local control = row.control
    if control then
        if control.SetHidden then
            control:SetHidden(true)
        end
        if control.ClearAnchors then
            control:ClearAnchors()
        end
    end

    local label = row.label
    if label then
        if label.SetText then
            label:SetText("")
        end
        if label.SetHidden then
            label:SetHidden(true)
        end
    end

    local chevron = row.chevron
    if chevron then
        if chevron.SetTexture then
            chevron:SetTexture(nil)
        end
        if chevron.SetHidden then
            chevron:SetHidden(true)
        end
    end

    row._onToggle = nil
    row._poolState = "free"

    categoryPool.free[#categoryPool.free + 1] = row

    safeDebug("[CategoryPool] release %s (used=%d free=%d)", tostring(row.name), #categoryPool.used, #categoryPool.free)
end

local function resetCategoryPool()
    for index = #categoryPool.used, 1, -1 do
        local row = categoryPool.used[index]
        categoryPool.used[index] = nil
        releaseCategoryRow(row)
    end

    safeDebug("[CategoryPool] reset (used=%d free=%d)", #categoryPool.used, #categoryPool.free)
end

local function applyCategoryRow(row, data)
    if type(row) ~= "table" then
        return
    end

    local control = row.control
    local label = row.label
    local chevron = row.chevron
    if not (control and label and chevron) then
        return
    end

    local info = type(data) == "table" and data or {}
    local title = tostring(info.title or "Bestrebungen")
    if title == "" then
        title = "Bestrebungen"
    end

    local remaining = tonumber(info.remaining)
    if remaining == nil then
        remaining = 0
    end
    remaining = math.max(0, math.floor(remaining + 0.5))

    local showCounts = info.showCounts == true
    local formattedText

    local formatHeader = info.formatHeader
    if type(formatHeader) == "function" then
        local result = formatHeader(title, remaining, showCounts)
        if result ~= nil and result ~= "" then
            formattedText = tostring(result)
        end
    end

    if formattedText == nil then
        if showCounts then
            formattedText = string.format("%s (%d)", title, remaining)
        else
            formattedText = title
        end
    end

    if label.SetText then
        label:SetText(formattedText)
    end

    local colorRoles = type(info.colorRoles) == "table" and info.colorRoles or {}
    local expanded = info.expanded == true
    local role
    if expanded then
        role = colorRoles.expanded or DEFAULT_CATEGORY_COLOR_ROLE_EXPANDED
    else
        role = colorRoles.collapsed or DEFAULT_CATEGORY_COLOR_ROLE_COLLAPSED
    end

    local rowsOptions = type(info.rowsOptions) == "table" and info.rowsOptions or nil
    if rowsOptions == nil then
        rowsOptions = {}
        info.rowsOptions = rowsOptions
    end

    local colorKind = rowsOptions.colorKind
    if type(colorKind) ~= "string" or colorKind == "" then
        if type(info.colorKind) == "string" and info.colorKind ~= "" then
            colorKind = info.colorKind
        else
            colorKind = DEFAULT_TRACKER_COLOR_KIND
        end
        rowsOptions.colorKind = colorKind
    end

    local ok, err = pcall(applyCategoryColor, label, role, info.overrideColors, colorKind)
    if not ok then
        safeDebug("[CategoryRow] applyCategoryColor failed for role=%s: %s", tostring(role), tostring(err))
        label:SetColor(1, 1, 1, 1)
        if label.SetAlpha then
            label:SetAlpha(1)
        end
    end

    local textures = type(info.textures) == "table" and info.textures or DEFAULT_CATEGORY_CHEVRON_TEXTURES
    local texturePath = expanded and textures.expanded or textures.collapsed
    if chevron.SetTexture then
        if type(texturePath) == "string" and texturePath ~= "" then
            chevron:SetTexture(texturePath)
        else
            local fallback = expanded and DEFAULT_CATEGORY_CHEVRON_TEXTURES.expanded or DEFAULT_CATEGORY_CHEVRON_TEXTURES.collapsed
            chevron:SetTexture(fallback)
        end
    end

    if control.SetMouseEnabled then
        control:SetMouseEnabled(true)
    end

    row._onToggle = info.onToggle

    safeDebug(
        "[CategoryRow] apply title=%s expanded=%s remaining=%d counts=%s",
        tostring(formattedText),
        tostring(expanded),
        remaining,
        tostring(showCounts)
    )
end

function Rows.AcquireCategoryRow(parent)
    return acquireCategoryRow(parent)
end

function Rows.ReleaseCategoryRow(row)
    detachFromUsed(row)
    releaseCategoryRow(row)
end

function Rows.ResetCategoryPool()
    resetCategoryPool()
end

function Rows.ApplyCategoryRow(row, data)
    applyCategoryRow(row, data)
end

local function getConfiguredFonts(options)
    if type(options) == "table" and type(options.fontConfig) == "table" then
        return options.fontConfig
    end

    local addon = getAddon()
    if type(addon) ~= "table" then
        return nil
    end

    local sv = addon.SV or addon.sv
    if type(sv) ~= "table" then
        return nil
    end

    local endeavor = sv.Endeavor
    if type(endeavor) ~= "table" then
        return nil
    end

    local tracker = endeavor.Tracker
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
        local altKey = type(key) == "string" and string.lower(key) or nil
        if altKey and type(fonts[altKey]) == "table" then
            group = fonts[altKey]
        end
    end

    return group
end

local function applyConfiguredFontForKind(control, kind, options)
    local fonts = getConfiguredFonts(options)
    if type(fonts) ~= "table" then
        return false
    end

    local targetKey
    if kind == "endeavorCategoryHeader" then
        targetKey = "Category"
    elseif kind == "dailyHeader" or kind == "weeklyHeader" then
        targetKey = "Title"
    else
        targetKey = "Objective"
    end

    local group = selectFontGroup(fonts, targetKey)
    if type(group) ~= "table" then
        return false
    end

    return ApplyFont(control, group)
end

local function applyObjectiveColor(label, options, objective)
    if not label or not label.SetColor then
        return
    end

    local opts = type(options) == "table" and options or {}
    local colors = type(opts.colors) == "table" and opts.colors or nil
    local role = opts.defaultRole or DEFAULT_OBJECTIVE_COLOR_ROLE

    if opts.completedHandling == "recolor" and objective and objective.completed then
        role = opts.completedRole or COMPLETED_COLOR_ROLE
    end

    local r, g, b, a
    if colors then
        r, g, b, a = extractColorComponents(colors[role])
    end

    if r == nil then
        r, g, b, a = getTrackerColor(role, opts.colorKind or DEFAULT_TRACKER_COLOR_KIND)
    end

    label:SetColor(r or 1, g or 1, b or 1, a or 1)

    if label and label.SetAlpha then
        label:SetAlpha(1)
    end
end

local function getContainerCache(container)
    if container == nil then
        return nil
    end

    local cache = Rows._cache[container]
    if type(cache) ~= "table" then
        cache = { rows = {}, lastHeight = 0 }
        Rows._cache[container] = cache
    elseif type(cache.rows) ~= "table" then
        cache.rows = {}
    end

    return cache
end

local function ensureObjectiveRow(container, baseName, index, previous, options)
    local wm = WINDOW_MANAGER
    if wm == nil then
        return nil
    end

    local cache = getContainerCache(container)
    if cache == nil then
        return nil
    end

    local rows = cache.rows
    local row = rows[index]
    if row and (type(row.GetName) ~= "function" or GetControl(row:GetName()) ~= row) then
        row = nil
    end

    local controlName = baseName .. index
    if not row then
        row = GetControl(controlName)
        if not row then
            row = wm:CreateControl(controlName, container, CT_CONTROL)
        end
        rows[index] = row
    end

    row:SetParent(container)
    row:SetResizeToFitDescendents(false)
    row:SetMouseEnabled(false)
    row:SetHidden(false)

    local rowHeight = OBJECTIVE_ROW_DEFAULT_HEIGHT
    if type(options) == "table" then
        local override = tonumber(options.rowHeight)
        if override and override > 0 then
            rowHeight = override
        end
    end

    row:SetHeight(rowHeight)
    row:ClearAnchors()
    if previous then
        row:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, ROW_GAP)
        row:SetAnchor(TOPRIGHT, previous, BOTTOMRIGHT, 0, ROW_GAP)
    else
        row:SetAnchor(TOPLEFT, container, TOPLEFT, 0, 0)
        row:SetAnchor(TOPRIGHT, container, TOPRIGHT, 0, 0)
    end

    return row, rowHeight
end

function Rows.ApplyObjectiveRow(row, objective, options)
    if row == nil then
        return
    end

    local wm = WINDOW_MANAGER
    if wm == nil then
        return
    end

    local data = type(objective) == "table" and objective or {}
    local baseText = tostring(data.text or "")
    if baseText == "" then
        baseText = "Objective"
    end

    local combinedText = baseText
    if data.progress ~= nil and data.max ~= nil then
        combinedText = string.format("%s %s", combinedText, FormatParensCount(data.progress, data.max))
    end

    combinedText = combinedText:gsub("%s+", " "):gsub("%s+%)", ")")

    local rowName = type(row.GetName) == "function" and row:GetName() or ""
    local titleName = rowName .. "Title"
    local progressName = rowName .. "Progress"

    if row.GetNamedChild then
        local bullet = row:GetNamedChild("Bullet")
        if bullet and bullet.SetHidden then
            bullet:SetHidden(true)
        end
        local icon = row:GetNamedChild("Icon")
        if icon and icon.SetHidden then
            icon:SetHidden(true)
        end
        local dot = row:GetNamedChild("Dot")
        if dot and dot.SetHidden then
            dot:SetHidden(true)
        end
    end

    local title = GetControl(titleName)
    if not title then
        title = wm:CreateControl(titleName, row, CT_LABEL)
    end
    title:SetParent(row)
    local rowKind = type(objective) == "table" and objective.kind or nil
    local appliedConfiguredFont = applyConfiguredFontForKind and applyConfiguredFontForKind(title, rowKind, options)
    if not appliedConfiguredFont then
        applyFontString(title, options and options.font, DEFAULT_OBJECTIVE_FONT)
    end
    title:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    title:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    if title.SetWrapMode then
        title:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    end
    title:ClearAnchors()
    title:SetAnchor(TOPLEFT, row, TOPLEFT, OBJECTIVE_INDENT_X, 0)
    title:SetAnchor(TOPRIGHT, row, TOPRIGHT, 0, 0)
    if title.SetHeight then
        local titleHeight = OBJECTIVE_ROW_DEFAULT_HEIGHT
        if type(options) == "table" then
            local override = tonumber(options.rowHeight)
            if override and override > 0 then
                titleHeight = override
            end
        end
        title:SetHeight(titleHeight)
    end
    title:SetText(combinedText)
    row.Label = title

    local progress = GetControl(progressName)
    if not progress then
        progress = wm:CreateControl(progressName, row, CT_LABEL)
    end
    progress:SetParent(row)
    if progress.SetHidden then
        progress:SetHidden(true)
    end
    if progress.SetText then
        progress:SetText("")
    end

    applyObjectiveColor(title, options, data)

    if row.SetAlpha then
        row:SetAlpha(1)
    end

    safeDebug("[EndeavorRows] objective inline: \"%s\"", combinedText)
end

function Rows.Init()
    Rows._cache = setmetatable({}, { __mode = "k" })
    categoryPool.free = categoryPool.free or {}
    categoryPool.used = categoryPool.used or {}
    if type(categoryPool.nextId) ~= "number" or categoryPool.nextId < 1 then
        categoryPool.nextId = (#categoryPool.free or 0) + 1
    end
    Rows.ResetCategoryPool()
    lastHeight = 0
end

function Rows.ClearObjectives(container)
    local cache = getContainerCache(container)
    if cache then
        local rows = cache.rows or {}
        for index = 1, #rows do
            local row = rows[index]
            if row and row.SetHidden then
                row:SetHidden(true)
            end
        end
        cache.lastHeight = 0
    end

    if container and container.SetHeight then
        container:SetHeight(0)
    end

    lastHeight = 0

    safeDebug("[EndeavorRows.ClearObjectives] container=%s", container and (container.GetName and select(2, pcall(container.GetName, container))) or "<nil>")

    return 0
end

function Rows.BuildObjectives(container, list, options)
    if container == nil then
        lastHeight = 0
        return 0
    end

    local cache = getContainerCache(container)
    if cache == nil then
        lastHeight = 0
        return 0
    end

    local sequence = {}
    if type(list) == "table" then
        for index = 1, #list do
            sequence[#sequence + 1] = list[index]
        end
    end

    local count = #sequence
    if count == 0 then
        Rows.ClearObjectives(container)
        safeDebug("[EndeavorRows.BuildObjectives] count=0")
        return 0
    end

    local containerName = nil
    if type(container.GetName) == "function" then
        local ok, name = pcall(container.GetName, container)
        if ok and type(name) == "string" then
            containerName = name
        end
    end
    local baseName = (containerName or "Nvk3UT_Endeavor") .. "Obj"

    local rowHeight = OBJECTIVE_ROW_DEFAULT_HEIGHT
    if type(options) == "table" then
        local override = tonumber(options.rowHeight)
        if override and override > 0 then
            rowHeight = override
        end
    end

    local totalHeight = 0
    local previous

    for index = 1, count do
        local row, appliedHeight = ensureObjectiveRow(container, baseName, index, previous, options)
        if row then
            Rows.ApplyObjectiveRow(row, sequence[index], options)
            previous = row
            if index > 1 then
                totalHeight = totalHeight + ROW_GAP
            end
            totalHeight = totalHeight + (appliedHeight or rowHeight)
        end
    end

    local rows = cache.rows
    for index = count + 1, #rows do
        local extra = rows[index]
        if extra and extra.SetHidden then
            extra:SetHidden(true)
        end
    end

    if container.SetHeight then
        container:SetHeight(totalHeight)
    end

    cache.lastHeight = totalHeight
    lastHeight = totalHeight

    safeDebug("[EndeavorRows.BuildObjectives] count=%d height=%d", count, totalHeight)

    return totalHeight
end

function Rows.GetMeasuredHeight(container)
    local cache = getContainerCache(container)
    if cache then
        return coerceNumber(cache.lastHeight)
    end
    return 0
end

function Rows.GetLastHeight()
    return coerceNumber(lastHeight)
end

Nvk3UT.EndeavorTrackerRows = Rows

return Rows
