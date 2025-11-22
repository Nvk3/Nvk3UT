
local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local MODULE_TAG = addonName .. ".EndeavorTrackerRows"

local ROWS_HEIGHTS = {
    category = 26,
    entry = 20,
    sub_info = 18,
    sub_counter = 18,
    sub_progress = 20,
    sub_warning = 18,
    spacing_entry_to_first_sub = 2,
    spacing_between_subrows = 1,
    spacing_after_last_sub = 2,
}

local CATEGORY_TOP_PAD = 0
local CATEGORY_BOTTOM_PAD_EXPANDED = 6
local CATEGORY_BOTTOM_PAD_COLLAPSED = 6
local CATEGORY_ENTRY_SPACING = 3

local ENTRY_TOP_PAD = 0
local ENTRY_BOTTOM_PAD = 0
local ENTRY_ROW_SPACING = 3
local ENTRY_INDENT_X = 32

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

local DEFAULT_OBJECTIVE_FONT = "ZoFontGameSmall"
local DEFAULT_FONT_OUTLINE = "soft-shadow-thick"
local DEFAULT_OBJECTIVE_COLOR_ROLE = "objectiveText"
local DEFAULT_TRACKER_COLOR_KIND = "endeavorTracker"
local COMPLETED_COLOR_ROLE = "completed"
local ENTRY_COLOR_ROLE = "entryTitle"
local OBJECTIVE_INDENT_X = 60

local SUBROW_ICON_SIZE = 16
local SUBROW_ICON_GAP = 4
local SUBROW_RIGHT_COLUMN_GAP = 8

local SUBROW_KIND_ALIASES = {
    info = "sub_info",
    description = "sub_info",
    detail = "sub_info",
    text = "sub_info",
    counter = "sub_counter",
    value = "sub_counter",
    count = "sub_counter",
    progress = "sub_progress",
    bar = "sub_progress",
    warning = "sub_warning",
    hint = "sub_warning",
    error = "sub_warning",
    alert = "sub_warning",
}

local CATEGORY_CHEVRON_SIZE = 20
local CATEGORY_LABEL_OFFSET_X = 4
local DEFAULT_CATEGORY_COLOR_ROLE_EXPANDED = "activeTitle"
local DEFAULT_CATEGORY_COLOR_ROLE_COLLAPSED = "categoryTitle"

local DEFAULT_CATEGORY_CHEVRON_TEXTURES = {
    expanded = "EsoUI/Art/Buttons/tree_open_up.dds",
    collapsed = "EsoUI/Art/Buttons/tree_closed_up.dds",
}

local MOUSE_BUTTON_LEFT = rawget(_G, "MOUSE_BUTTON_INDEX_LEFT") or 1

local resolvedEntryHeight = ROWS_HEIGHTS.entry
local ROW_TEXT_PADDING_Y = 8

local function coerceHeight(value)
    local numeric = tonumber(value)
    if numeric == nil or numeric ~= numeric then
        return 0
    end

    return numeric
end

local function coerceWidth(value)
    local numeric = tonumber(value)
    if numeric == nil or numeric ~= numeric then
        return 0
    end

    if numeric < 0 then
        return 0
    end

    return numeric
end

local function getCategoryHeight(expanded)
    if expanded and type(ROWS_HEIGHTS.categoryExpanded) == "number" then
        return ROWS_HEIGHTS.categoryExpanded
    end

    return ROWS_HEIGHTS.category
end

local function resolveEntryHeight(options)
    local height = ROWS_HEIGHTS.entry
    if type(options) == "table" then
        local override = tonumber(options.rowHeight)
        if override and override > 0 then
            height = override
        end
    end

    resolvedEntryHeight = height
    return height
end

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

local categoryPool = {
    free = {},
    used = {},
    nextId = 1,
}

local entryPool = {
    free = {},
    used = {},
    nextId = 1,
}

local loggedSubrowsOnce = false

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

local function onEntryMouseUp(control, button, upInside)
    if control == nil or upInside ~= true then
        return
    end

    if button == MOUSE_BUTTON_LEFT then
        local onLeftClick = control._entryOnLeftClick
        if type(onLeftClick) == "function" then
            onLeftClick(control)
        end
    end
end

local function normalizeSubrowKind(kind)
    local key = kind
    if type(key) ~= "string" then
        key = tostring(key or "")
    end
    key = key or ""
    if key ~= "" then
        local lowered = string.lower(key)
        if SUBROW_KIND_ALIASES[lowered] then
            return SUBROW_KIND_ALIASES[lowered]
        end
        if ROWS_HEIGHTS[lowered] then
            return lowered
        end
        if ROWS_HEIGHTS[key] then
            return key
        end
    end

    return "sub_info"
end

local function resolveSubrowSpacing(key)
    local value = ROWS_HEIGHTS[key]
    if type(value) ~= "number" then
        return 0
    end
    if value ~= value then
        return 0
    end
    if value < 0 then
        return 0
    end
    return value
end

local function getBaseSubrowHeight(kind)
    local resolvedKind = normalizeSubrowKind(kind)
    local height = ROWS_HEIGHTS[resolvedKind] or ROWS_HEIGHTS[kind]
    if type(height) ~= "number" or height ~= height or height < 0 then
        return 0
    end

    return height
end

local function sanitizeSubrows(source)
    local sanitized = {}
    local visibleCount = 0

    if type(source) == "table" then
        for _, entry in ipairs(source) do
            if type(entry) == "table" then
                local normalizedKind = normalizeSubrowKind(entry.kind or entry.type or entry[1])
                local visible
                if entry.visible ~= nil then
                    visible = entry.visible ~= false
                elseif entry.hidden ~= nil then
                    visible = entry.hidden ~= true
                else
                    visible = true
                end

                local sanitizedEntry = {
                    kind = normalizedKind,
                    source = entry,
                    visible = visible,
                    hidden = not visible,
                }

                if visible then
                    visibleCount = visibleCount + 1
                end

                sanitized[#sanitized + 1] = sanitizedEntry
            end
        end
    end

    return sanitized, visibleCount
end

local function acquireSubrowControl(row, container, index)
    if row == nil or container == nil then
        return nil
    end

    local wm = WINDOW_MANAGER
    if wm == nil then
        return nil
    end

    local prefix = row._subrowPrefix
    if type(prefix) ~= "string" or prefix == "" then
        local rowName = type(row.GetName) == "function" and row:GetName() or "Nvk3UT_Endeavor_Row"
        prefix = string.format("%s_Subrow", tostring(rowName))
        row._subrowPrefix = prefix
    end

    row._subrowControls = row._subrowControls or {}

    local existing = row._subrowControls[index]
    if existing then
        if existing.SetParent then
            existing:SetParent(container)
        end
        if existing.SetMouseEnabled then
            existing:SetMouseEnabled(true)
        end
        if existing.SetHidden then
            existing:SetHidden(true)
        end
        if existing.SetHandler then
            existing:SetHandler("OnMouseUp", ignoreObjectiveMouseUp)
        end
        return existing
    end

    local controlName = string.format("%s%d", prefix, index)
    local control = GetControl(controlName)
    if not control then
        control = wm:CreateControl(controlName, container, CT_CONTROL)
    else
        control:SetParent(container)
    end

    control:SetResizeToFitDescendents(false)
    control:SetMouseEnabled(true)
    control:SetHidden(true)
    if control.SetHandler then
        control:SetHandler("OnMouseUp", ignoreObjectiveMouseUp)
    end
    control._subrowOwner = row

    row._subrowControls[index] = control

    return control
end

local function hideUnusedSubrows(row, startIndex)
    if row == nil then
        return
    end

    local controls = row._subrowControls
    if type(controls) ~= "table" then
        return
    end

    for index = startIndex, #controls do
        local control = controls[index]
        if control then
            if control.SetHidden then
                control:SetHidden(true)
            end
            if control.ClearAnchors then
                control:ClearAnchors()
            end
            control._measuredHeight = nil
        end
    end
end

local function ignoreObjectiveMouseUp()
    -- Intentionally ignore clicks on Endeavor objective subrows; only entry rows should react.
end

local function getContainerWidthFromControl(control)
    if not control then
        return 0
    end

    local parent = control._poolParent
    if not parent and control.GetParent then
        parent = control:GetParent()
    end

    if parent and parent.GetWidth then
        local ok, width = pcall(parent.GetWidth, parent)
        if ok then
            return coerceWidth(width)
        end
    end

    if control.GetWidth then
        local ok, width = pcall(control.GetWidth, control)
        if ok then
            return coerceWidth(width)
        end
    end

    return 0
end

local function computeAvailableWidth(container, leftPadding, rightPadding)
    local containerWidth = getContainerWidthFromControl(container)
    local availableWidth = containerWidth - (leftPadding or 0) - (rightPadding or 0)
    if availableWidth < 0 then
        availableWidth = 0
    end

    return availableWidth, containerWidth
end

local function ensureSubrowLeftLabel(control)
    if control == nil then
        return nil
    end

    local wm = WINDOW_MANAGER
    if wm == nil then
        return nil
    end

    local label = control.Label
    if label then
        label:SetParent(control)
    else
        local controlName = type(control.GetName) == "function" and control:GetName() or ""
        local labelName = controlName ~= "" and (controlName .. "Label") or nil
        if labelName then
            label = GetControl(labelName)
        end
        if not label then
            local fallbackBase = controlName ~= "" and controlName or string.gsub(tostring(control or "subrow"), "[^%w_]", "_")
            label = wm:CreateControl((labelName or (fallbackBase .. "Label")), control, CT_LABEL)
        else
            label:SetParent(control)
        end
    end

    label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    if label.SetWrapMode then
        label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    end
    if label.SetMaxLineCount then
        label:SetMaxLineCount(0)
    end

    control.Label = label

    return label
end

local function ensureSubrowRightLabel(control)
    if control == nil then
        return nil
    end

    local wm = WINDOW_MANAGER
    if wm == nil then
        return nil
    end

    local label = control.RightLabel
    if label then
        label:SetParent(control)
    else
        local controlName = type(control.GetName) == "function" and control:GetName() or ""
        local labelName = controlName ~= "" and (controlName .. "Right") or nil
        if labelName then
            label = GetControl(labelName)
        end
        if not label then
            local fallbackBase = controlName ~= "" and controlName or string.gsub(tostring(control or "subrow"), "[^%w_]", "_")
            label = wm:CreateControl((labelName or (fallbackBase .. "Right")), control, CT_LABEL)
        else
            label:SetParent(control)
        end
    end

    label:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    if label.SetWrapMode then
        label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    end
    if label.SetMaxLineCount then
        label:SetMaxLineCount(0)
    end

    control.RightLabel = label

    return label
end

local function ensureSubrowIcon(control)
    if control == nil then
        return nil
    end

    local wm = WINDOW_MANAGER
    if wm == nil then
        return nil
    end

    local icon = control.Icon
    if icon then
        icon:SetParent(control)
    else
        local controlName = type(control.GetName) == "function" and control:GetName() or ""
        local iconName = controlName ~= "" and (controlName .. "Icon") or nil
        if iconName then
            icon = GetControl(iconName)
        end
        if not icon then
            local fallbackBase = controlName ~= "" and controlName or string.gsub(tostring(control or "subrow"), "[^%w_]", "_")
            icon = wm:CreateControl((iconName or (fallbackBase .. "Icon")), control, CT_TEXTURE)
        else
            icon:SetParent(control)
        end
    end

    if icon.SetMouseEnabled then
        icon:SetMouseEnabled(false)
    end
    if icon.SetHidden then
        icon:SetHidden(true)
    end
    if icon.SetDimensions then
        icon:SetDimensions(SUBROW_ICON_SIZE, SUBROW_ICON_SIZE)
    end

    control.Icon = icon

    return icon
end

function Rows.ApplySubrow(control, kind, data, options)
    if control == nil then
        return
    end

    local resolvedKind = normalizeSubrowKind(kind)
    local source = type(data) == "table" and data or {}

    local height = Rows.GetSubrowHeight(resolvedKind)
    if control.SetHeight then
        control:SetHeight(height)
    end
    control._measuredHeight = nil

    local icon = ensureSubrowIcon(control)
    local iconTexture = type(source.icon) == "string" and source.icon or nil
    if icon then
        if iconTexture and iconTexture ~= "" then
            icon:SetHidden(false)
            if icon.SetTexture then
                icon:SetTexture(iconTexture)
            end
            if icon.ClearAnchors then
                icon:ClearAnchors()
            end
            icon:SetAnchor(LEFT, control, LEFT, OBJECTIVE_INDENT_X - SUBROW_ICON_SIZE - SUBROW_ICON_GAP, 0)
        else
            if icon.SetTexture then
                icon:SetTexture(nil)
            end
            icon:SetHidden(true)
        end
    end

    local leftLabel = ensureSubrowLeftLabel(control)
    local rightLabel = ensureSubrowRightLabel(control)

    if leftLabel then
        leftLabel:ClearAnchors()
        if icon and icon.IsHidden and not icon:IsHidden() then
            leftLabel:SetAnchor(TOPLEFT, icon, TOPRIGHT, SUBROW_ICON_GAP, 0)
        else
            leftLabel:SetAnchor(TOPLEFT, control, TOPLEFT, OBJECTIVE_INDENT_X, 0)
        end
    end

    local rightText = ""
    if type(source) == "table" then
        rightText = source.rightText or source.value or source.counterText or ""
    end
    rightText = tostring(rightText or "")

    if rightLabel then
        rightLabel:ClearAnchors()
        if rightText ~= "" then
            if rightLabel.SetHidden then
                rightLabel:SetHidden(false)
            end
            rightLabel:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
            rightLabel:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, 0, 0)
            if leftLabel then
                leftLabel:SetAnchor(BOTTOMRIGHT, rightLabel, BOTTOMLEFT, -SUBROW_RIGHT_COLUMN_GAP, 0)
            end
        else
            if rightLabel.SetHidden then
                rightLabel:SetHidden(true)
            end
            if rightLabel.SetText then
                rightLabel:SetText("")
            end
            if leftLabel then
                leftLabel:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, 0, 0)
            end
        end
    elseif leftLabel then
        leftLabel:SetAnchor(BOTTOMRIGHT, control, BOTTOMRIGHT, 0, 0)
    end

    local text = ""
    if type(source) == "table" then
        text = source.text or source.label or source.description or ""
    end
    text = tostring(text or "")
    local font = type(source) == "table" and source.font or nil
    local fallbackFont = options and options.font or DEFAULT_OBJECTIVE_FONT
    if leftLabel then
        applyFontString(leftLabel, font, fallbackFont)
    end

    if rightLabel then
        local rightFont = type(source) == "table" and (source.rightFont or source.font) or nil
        applyFontString(rightLabel, rightFont, fallbackFont)
    end

    local r, g, b, a
    if type(source) == "table" then
        r, g, b, a = extractColorComponents(source.color)
    end
    if r == nil then
        local colorRole
        if type(source) == "table" and type(source.colorRole) == "string" then
            colorRole = source.colorRole
        else
            colorRole = DEFAULT_OBJECTIVE_COLOR_ROLE
        end
        r, g, b, a = getTrackerColor(colorRole, options and options.colorKind)
    end
    r, g, b, a = r or 1, g or 1, b or 1, a or 1

    if leftLabel and leftLabel.SetColor then
        leftLabel:SetColor(r, g, b, a)
    end
    if rightLabel and rightLabel.SetColor then
        rightLabel:SetColor(r, g, b, a)
    end

    local iconVisible = icon and icon.IsHidden and not icon:IsHidden()
    local leftPadding = OBJECTIVE_INDENT_X
    if iconVisible then
        leftPadding = leftPadding + SUBROW_ICON_SIZE + SUBROW_ICON_GAP
    end

    local availableWidth, containerWidth = computeAvailableWidth(control, leftPadding, 0)
    local rightWidth = 0
    local rightVisible = true
    if rightLabel and rightLabel.IsHidden then
        rightVisible = not rightLabel:IsHidden()
    end
    if rightLabel then
        if rightText ~= "" and rightLabel.SetText then
            rightLabel:SetText(rightText)
        end
        if rightVisible and rightLabel.GetTextWidth then
            rightWidth = coerceWidth(rightLabel:GetTextWidth())
        end
        if rightLabel.SetWidth then
            rightLabel:SetWidth(rightWidth)
        end
    end

    local leftWidth = availableWidth - rightWidth
    if rightWidth > 0 then
        leftWidth = leftWidth - SUBROW_RIGHT_COLUMN_GAP
    end
    leftWidth = math.max(0, leftWidth)

    if leftLabel and leftLabel.SetWidth then
        leftLabel:SetWidth(leftWidth)
    end

    if leftLabel and leftLabel.SetText then
        leftLabel:SetText(text)
    end

    local leftHeight = (leftLabel and leftLabel.GetTextHeight and leftLabel:GetTextHeight()) or 0
    local rightHeight = 0
    if rightLabel and rightVisible and rightLabel.GetTextHeight then
        rightHeight = rightLabel:GetTextHeight()
    end

    local baseHeight = getBaseSubrowHeight(resolvedKind)
    local targetHeight = math.max(baseHeight, math.max(leftHeight, rightHeight) + ROW_TEXT_PADDING_Y)

    if control.SetHeight then
        control:SetHeight(targetHeight)
    end

    control._measuredHeight = targetHeight
    safeDebug(
        "[Subrow] kind=%s containerWidth=%d leftPadding=%d width=%d textHeight=%d rightHeight=%d height=%d",
        tostring(resolvedKind),
        containerWidth,
        leftPadding,
        leftWidth,
        leftHeight,
        rightHeight,
        targetHeight
    )

    if control.SetAlpha then
        control:SetAlpha(1)
    end
    if control.SetHidden then
        control:SetHidden(false)
    end

    control._subrowKind = resolvedKind
    control._subrowSource = source

    return control
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

local function buildEntryControlName(parent, index)
    local containerName = getContainerName(parent)
    local controlName = string.format("%s_Entry", containerName)

    if type(index) == "number" and index > 1 then
        controlName = string.format("%s%d", controlName, index)
    end

    return controlName
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

local function ensureEntryChild(control, childName, childType)
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

local function createEntryRow(parent)
    local wm = WINDOW_MANAGER
    if wm == nil then
        return nil
    end

    local index = entryPool.nextId or 1
    local controlName = buildEntryControlName(parent, index)
    entryPool.nextId = index + 1

    local control = GetControl(controlName)
    if not control then
        control = wm:CreateControl(controlName, parent, CT_CONTROL)
    else
        control:SetParent(parent)
    end

    control:SetResizeToFitDescendents(false)
    control:SetMouseEnabled(false)
    control:SetHidden(false)
    control._poolState = "fresh"
    control._poolParent = parent
    control._subrowPrefix = controlName .. "Subrow"

    safeDebug("[EntryPool] create %s", controlName)

    return control
end

local function popFreeEntryRow()
    while #entryPool.free > 0 do
        local row = table.remove(entryPool.free)
        if row then
            local isValid = true
            if type(row.GetName) == "function" then
                local name = row:GetName()
                if type(name) == "string" and name ~= "" then
                    if GetControl(name) ~= row then
                        isValid = false
                    end
                end
            end

            if isValid then
                return row
            end
        end
    end

    return nil
end

local function markEntryUsed(row, parent)
    if not row then
        return
    end

    row._poolState = "used"
    row._poolParent = parent
    entryPool.used[#entryPool.used + 1] = row
end

local function detachEntryFromUsed(row)
    if not row then
        return
    end

    for index = #entryPool.used, 1, -1 do
        if entryPool.used[index] == row then
            table.remove(entryPool.used, index)
            break
        end
    end
end

local function acquireEntryRow(parent)
    if parent == nil then
        return nil
    end

    local row = popFreeEntryRow()
    if row then
        if row.SetParent then
            row:SetParent(parent)
        end
        if row.SetHidden then
            row:SetHidden(false)
        end
    else
        row = createEntryRow(parent)
    end

    if not row then
        return nil
    end

    if row.ClearAnchors then
        row:ClearAnchors()
    end
    if row.SetResizeToFitDescendents then
        row:SetResizeToFitDescendents(false)
    end
    if row.SetMouseEnabled then
        row:SetMouseEnabled(true)
    end

    markEntryUsed(row, parent)

    local controlName = type(row.GetName) == "function" and row:GetName() or "<unnamed>"
    safeDebug("[EntryPool] acquire %s free=%d used=%d", tostring(controlName), #entryPool.free, #entryPool.used)

    return row
end

local function resetEntryRowContent(row)
    if row == nil then
        return
    end

    local rowName = type(row.GetName) == "function" and row:GetName() or nil

    local label = row.Label
    if not label and rowName then
        label = GetControl(rowName .. "Title")
    end
    if label then
        if label.SetText then
            label:SetText("")
        end
        if label.SetHidden then
            label:SetHidden(false)
        end
    end
    row.Label = nil

    local progress = row.Progress
    if not progress and rowName then
        progress = GetControl(rowName .. "Progress")
    end
    if progress then
        if progress.SetText then
            progress:SetText("")
        end
        if progress.SetHidden then
            progress:SetHidden(true)
        end
    end
    row.Progress = nil

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
        local check = row:GetNamedChild("Check")
        if check and check.SetHidden then
            check:SetHidden(true)
        end
    end

    if type(row._subrowControls) == "table" then
        for index = 1, #row._subrowControls do
            local control = row._subrowControls[index]
            if control then
                if control.SetHidden then
                    control:SetHidden(true)
                end
                if control.ClearAnchors then
                    control:ClearAnchors()
                end
            end
        end
    end

    row._subrows = nil
    row._subrowCount = 0
    row._subrowsVisibleCount = 0
    row._entryOnLeftClick = nil
    row._entryContext = nil

    if row.SetHeight then
        row:SetHeight(resolvedEntryHeight)
    end
    row._measuredHeight = nil
end

local function releaseEntryRow(row)
    if not row then
        return
    end

    resetEntryRowContent(row)

    if row.ClearAnchors then
        row:ClearAnchors()
    end
    if row.SetHidden then
        row:SetHidden(true)
    end

    detachEntryFromUsed(row)

    row._poolParent = nil
    row._poolState = "free"

    entryPool.free[#entryPool.free + 1] = row

    local controlName = type(row.GetName) == "function" and row:GetName() or "<unnamed>"
    safeDebug("[EntryPool] release %s free=%d used=%d", tostring(controlName), #entryPool.free, #entryPool.used)
end

local function resetEntryPool(targetParent)
    if targetParent == nil then
        for index = #entryPool.used, 1, -1 do
            releaseEntryRow(entryPool.used[index])
        end
    else
        for index = #entryPool.used, 1, -1 do
            local row = entryPool.used[index]
            if row and (row._poolParent == targetParent or (row.GetParent and row:GetParent() == targetParent)) then
                releaseEntryRow(row)
            end
        end
    end

    safeDebug("[EntryPool] reset target=%s free=%d used=%d", tostring(targetParent), #entryPool.free, #entryPool.used)
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
    control:SetHeight(getCategoryHeight(false))
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
        if label.SetMaxLineCount then
            label:SetMaxLineCount(0)
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
            control:SetHeight(getCategoryHeight(false))
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

    if control and control.SetHeight then
        control:SetHeight(getCategoryHeight(false))
    end

    row._measuredHeight = nil
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

    local availableWidth, containerWidth = computeAvailableWidth(control, CATEGORY_CHEVRON_SIZE + CATEGORY_LABEL_OFFSET_X, 0)
    if label.SetWidth then
        label:SetWidth(availableWidth)
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

    if control and control.SetHeight then
        local textHeight = label.GetTextHeight and label:GetTextHeight() or 0
        local paddingBottom = expanded and CATEGORY_BOTTOM_PAD_EXPANDED or CATEGORY_BOTTOM_PAD_COLLAPSED
        local targetHeight = math.max(getCategoryHeight(expanded), textHeight + CATEGORY_TOP_PAD + paddingBottom)
        control:SetHeight(targetHeight)
        if label.SetHeight then
            label:SetHeight(math.max(0, targetHeight - CATEGORY_TOP_PAD - paddingBottom))
        end
        control._measuredHeight = targetHeight
        safeDebug(
            "[CategoryRow] containerWidth=%d width=%d textHeight=%d height=%d expanded=%s",
            containerWidth,
            availableWidth,
            textHeight,
            targetHeight,
            tostring(expanded)
        )
    end
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

function Rows.AcquireEntryRow(parent)
    return acquireEntryRow(parent)
end

function Rows.ReleaseEntryRow(row)
    releaseEntryRow(row)
end

function Rows.ResetEntryPool(targetParent)
    resetEntryPool(targetParent)
end

function Rows.ResetPools()
    Rows.ResetCategoryPool()
    Rows.ResetEntryPool()
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

local function applyGroupLabelColor(label, options, useCompletedStyle)
    if not label or not label.SetColor then
        return false
    end

    local opts = type(options) == "table" and options or {}
    local colors = type(opts.colors) == "table" and opts.colors or nil

    local role
    if useCompletedStyle then
        role = opts.completedRole or COMPLETED_COLOR_ROLE
    else
        role = opts.entryRole or ENTRY_COLOR_ROLE
    end

    local r, g, b, a
    if colors then
        r, g, b, a = extractColorComponents(colors[role])
    end

    if r == nil then
        r, g, b, a = getTrackerColor(role, opts.colorKind or DEFAULT_TRACKER_COLOR_KIND)
    end

    label:SetColor(r or 1, g or 1, b or 1, a or 1)
    if label.SetAlpha then
        label:SetAlpha(1)
    end

    return true
end

local function applyEntryRow(row, objective, options)
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

    local entryHeight = resolveEntryHeight(options)
    local minHeight = entryHeight

    row._measuredHeight = nil

    local title = ensureEntryChild(row, titleName, CT_LABEL)
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
    if title.SetMaxLineCount then
        title:SetMaxLineCount(0)
    end
    title:ClearAnchors()
    title:SetAnchor(TOPLEFT, row, TOPLEFT, ENTRY_INDENT_X, ENTRY_TOP_PAD)
    title:SetAnchor(BOTTOMRIGHT, row, BOTTOMRIGHT, 0, -ENTRY_BOTTOM_PAD)
    local availableWidth, containerWidth = computeAvailableWidth(row, ENTRY_INDENT_X, 0)
    if title.SetWidth then
        title:SetWidth(availableWidth)
    end
    row.Label = title

    title:SetText(combinedText)

    local textHeight = (title.GetTextHeight and title:GetTextHeight()) or 0
    local targetHeight = math.max(minHeight, textHeight + ENTRY_TOP_PAD + ENTRY_BOTTOM_PAD + ROW_TEXT_PADDING_Y)
    if row.SetHeight then
        row:SetHeight(targetHeight)
    end
    if title.SetHeight then
        title:SetHeight(math.max(0, targetHeight - ENTRY_TOP_PAD - ENTRY_BOTTOM_PAD))
    end
    row._measuredHeight = targetHeight
    safeDebug(
        "[EntryRow] containerWidth=%d width=%d textHeight=%d height=%d",
        containerWidth,
        availableWidth,
        textHeight,
        targetHeight
    )

    local leftClickHandler = type(objective) == "table" and objective.onLeftClick or nil
    row._entryOnLeftClick = type(leftClickHandler) == "function" and leftClickHandler or nil

    if row.SetMouseEnabled then
        row:SetMouseEnabled(true)
    end

    if row.SetHandler then
        row:SetHandler("OnMouseUp", onEntryMouseUp)
    end

    local progress = ensureEntryChild(row, progressName, CT_LABEL)
    progress:SetParent(row)
    if progress.SetHidden then
        progress:SetHidden(true)
    end
    if progress.SetText then
        progress:SetText("")
    end
    row.Progress = progress

    applyObjectiveColor(title, options, data)

    local subrowsSource = type(data) == "table" and data.subrows or nil
    local sanitizedSubrows, visibleSubrows = sanitizeSubrows(subrowsSource)
    row._subrows = sanitizedSubrows
    row._subrowCount = #sanitizedSubrows
    row._subrowsVisibleCount = visibleSubrows

    if not loggedSubrowsOnce and visibleSubrows > 0 then
        local blockHeight = Rows.GetSubrowsBlockHeight(sanitizedSubrows)
        safeDebug("[Endeavor] subrows: n=%d blockHeight=%s", visibleSubrows, tostring(blockHeight))
        loggedSubrowsOnce = true
    end

    local container = row._poolParent or (row.GetParent and row:GetParent()) or nil
    if container then
        for index, entry in ipairs(sanitizedSubrows) do
            local control = acquireSubrowControl(row, container, index)
            entry.control = control
            if control then
                if entry.visible then
                    Rows.ApplySubrow(control, entry.kind, entry.source, options)
                else
                    if control.SetHidden then
                        control:SetHidden(true)
                    end
                    if control.ClearAnchors then
                        control:ClearAnchors()
                    end
                end
            end
        end
        hideUnusedSubrows(row, #sanitizedSubrows + 1)
    else
        hideUnusedSubrows(row, 1)
    end

    if row.SetAlpha then
        row:SetAlpha(1)
    end

    safeDebug("[EndeavorRows] objective inline: \"%s\"", combinedText)
end

function Rows.ApplyEntryRow(row, objective, options)
    applyEntryRow(row, objective, options)
end

function Rows.ApplyGroupLabelColor(label, options, useCompletedStyle)
    return applyGroupLabelColor(label, options, useCompletedStyle == true)
end

function Rows.Init()
    categoryPool.free = categoryPool.free or {}
    categoryPool.used = categoryPool.used or {}
    if type(categoryPool.nextId) ~= "number" or categoryPool.nextId < 1 then
        categoryPool.nextId = (#categoryPool.free or 0) + 1
    end
    entryPool.free = entryPool.free or {}
    entryPool.used = entryPool.used or {}
    if type(entryPool.nextId) ~= "number" or entryPool.nextId < 1 then
        entryPool.nextId = (#entryPool.free or 0) + 1
    end
    Rows.ResetCategoryPool()
    Rows.ResetEntryPool()
    loggedSubrowsOnce = false
end

function Rows.GetSubrowHeight(kind)
    if type(kind) == "table" then
        local control = kind.control or kind
        if control and type(control._measuredHeight) == "number" then
            local measured = coerceHeight(control._measuredHeight)
            if measured > 0 then
                return measured
            end
        end
        kind = kind.kind or (kind.source and kind.source.kind) or kind
    end

    local height = getBaseSubrowHeight(kind)
    if height > 0 then
        return height
    end

    if type(kind) == "table" and type(kind.GetHeight) == "function" then
        local ok, measured = pcall(kind.GetHeight, kind)
        if ok then
            measured = coerceHeight(measured)
            if measured > 0 then
                return measured
            end
        end
    end

    return 0
end

function Rows.GetSubrowsBlockHeight(subrows)
    if type(subrows) ~= "table" then
        return 0
    end

    local total = 0
    local visibleCount = 0

    local firstSpacing = resolveSubrowSpacing("spacing_entry_to_first_sub")
    local betweenSpacing = resolveSubrowSpacing("spacing_between_subrows")
    local trailingSpacing = resolveSubrowSpacing("spacing_after_last_sub")

    for index = 1, #subrows do
        local entry = subrows[index]
        if type(entry) == "table" then
            local visible
            if entry.visible ~= nil then
                visible = entry.visible ~= false
            elseif entry.hidden ~= nil then
                visible = entry.hidden ~= true
            elseif type(entry.source) == "table" then
                local source = entry.source
                if source.visible ~= nil then
                    visible = source.visible ~= false
                elseif source.hidden ~= nil then
                    visible = source.hidden ~= true
                end
            end

            if visible == nil then
                visible = true
            end

            if visible then
                visibleCount = visibleCount + 1
                if visibleCount == 1 then
                    total = total + firstSpacing
                else
                    total = total + betweenSpacing
                end
                total = total + Rows.GetSubrowHeight(entry)
            end
        end
    end

    if visibleCount > 0 then
        total = total + trailingSpacing
    end

    return total
end

function Rows.GetCategoryRowHeight(expanded)
    return getCategoryHeight(expanded)
end

function Rows.GetEntryRowHeight(row)
    local control = row and row.control or row
    if control and type(control._measuredHeight) == "number" then
        local measured = coerceHeight(control._measuredHeight)
        if measured > 0 then
            return measured
        end
    end

    if control and type(control.GetHeight) == "function" then
        local ok, height = pcall(control.GetHeight, control)
        if ok then
            local coerced = coerceHeight(height)
            if coerced > 0 then
                return coerced
            end
        end
    end

    return resolvedEntryHeight
end

Nvk3UT.EndeavorTrackerRows = Rows

return Rows
