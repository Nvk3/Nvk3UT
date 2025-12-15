local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local AchievementTrackerRows = {}
AchievementTrackerRows.__index = AchievementTrackerRows

local state = {
    parent = nil,
    rows = {},
    rowTypes = {},
}

local DEFAULT_MOUSEOVER_HIGHLIGHT_COLOR = { 1, 1, 0.6, 1 }

local LEFT_MOUSE_BUTTON = MOUSE_BUTTON_INDEX_LEFT or 1
local RIGHT_MOUSE_BUTTON = MOUSE_BUTTON_INDEX_RIGHT or 2

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

local function ApplyBaseColor(control, color)
    if not (control and control.label and color) then
        return
    end

    local r = color[1] or 1
    local g = color[2] or 1
    local b = color[3] or 1
    local a = color[4] or 1

    control.baseColor = control.baseColor or {}
    control.baseColor[1] = r
    control.baseColor[2] = g
    control.baseColor[3] = b
    control.baseColor[4] = a

    control.label:SetColor(r, g, b, a)
end

local function GetMouseoverHighlightColor()
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if host then
        if host.EnsureAppearanceDefaults then
            host.EnsureAppearanceDefaults()
        end
        if host.GetMouseoverHighlightColor then
            local r, g, b, a = host.GetMouseoverHighlightColor("achievementTracker")
            if r and g and b and a then
                return r, g, b, a
            end
        end
    end

    return unpack(DEFAULT_MOUSEOVER_HIGHLIGHT_COLOR)
end

local function ApplyMouseoverHighlight(ctrl)
    if not (ctrl and ctrl.label) then
        return
    end

    local r, g, b, a = GetMouseoverHighlightColor()
    ctrl.label:SetColor(r, g, b, a)
end

local function RestoreBaseColor(ctrl)
    if not (ctrl and ctrl.label and ctrl.baseColor) then
        return
    end

    ctrl.label:SetColor(unpack(ctrl.baseColor))
end

local function BuildControlName(baseKey)
    local parentName = (state.parent and state.parent.GetName and state.parent:GetName()) or addonName
    local cleanKey = tostring(baseKey or ""):gsub("%W", "_")
    return string.format("%sRow%s", parentName, cleanKey)
end

local function ResolveRowKey(rowKey)
    if type(rowKey) == "table" then
        return rowKey.key or rowKey.id or rowKey.rowKey or tostring(rowKey)
    end
    return rowKey
end

local function ResolveRowType(rowKey)
    if type(rowKey) == "table" then
        return rowKey.rowType or rowKey.type
    end
    return nil
end

local function GetRowEntry(rowKey)
    local key = ResolveRowKey(rowKey)
    if not key then
        return nil, nil
    end

    return state.rows[key], key
end

local function InitializeCategoryControl(control)
    control.label = control:GetNamedChild("Label")
    control.toggle = control:GetNamedChild("Toggle")
    control.isExpanded = false

    ApplyLabelDefaults(control.label)
    ApplyToggleDefaults(control.toggle)

    control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
        if ctrl.__nvk3OnMouseUp then
            ctrl:__nvk3OnMouseUp(button, upInside)
        end
    end)
    control:SetHandler("OnMouseEnter", function(ctrl)
        if ctrl.__nvk3OnMouseEnter then
            ctrl:__nvk3OnMouseEnter()
        end
    end)
    control:SetHandler("OnMouseExit", function(ctrl)
        if ctrl.__nvk3OnMouseExit then
            ctrl:__nvk3OnMouseExit()
        end
    end)
end

local function InitializeAchievementControl(control)
    control.label = control:GetNamedChild("Label")
    control.iconSlot = control:GetNamedChild("IconSlot")

    if control.iconSlot then
        control.iconSlot:SetDimensions(18, 18)
        control.iconSlot:ClearAnchors()
        control.iconSlot:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
    end

    if control.label then
        control.label:ClearAnchors()
        if control.iconSlot then
            control.label:SetAnchor(TOPLEFT, control.iconSlot, TOPRIGHT, 6, 0)
        else
            control.label:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
        end
        control.label:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
    end

    ApplyLabelDefaults(control.label)

    control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
        if ctrl.__nvk3OnMouseUp then
            ctrl:__nvk3OnMouseUp(button, upInside)
        end
    end)
    control:SetHandler("OnMouseEnter", function(ctrl)
        if ctrl.__nvk3OnMouseEnter then
            ctrl:__nvk3OnMouseEnter()
        end
    end)
    control:SetHandler("OnMouseExit", function(ctrl)
        if ctrl.__nvk3OnMouseExit then
            ctrl:__nvk3OnMouseExit()
        end
    end)
end

local function InitializeObjectiveControl(control)
    control.label = control:GetNamedChild("Label")
    ApplyLabelDefaults(control.label)
end

local function ResetCategoryControl(control)
    if not control then
        return
    end

    control:SetHidden(true)
    control.data = nil
    control.currentIndent = nil
    control.isExpanded = nil
    control.__nvk3OnMouseUp = nil
    control.__nvk3OnMouseEnter = nil
    control.__nvk3OnMouseExit = nil
    control.baseColor = nil

    if control.label and control.label.SetText then
        control.label:SetText("")
    end
    if control.toggle then
        if control.toggle.SetTexture then
            control.toggle:SetTexture(nil)
        end
        if control.toggle.SetHidden then
            control.toggle:SetHidden(false)
        end
    end
end

local function ResetAchievementControl(control)
    if not control then
        return
    end

    control:SetHidden(true)
    control.data = nil
    control.currentIndent = nil
    control.__nvk3OnMouseUp = nil
    control.__nvk3OnMouseEnter = nil
    control.__nvk3OnMouseExit = nil
    control.baseColor = nil

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
end

local function ResetObjectiveControl(control)
    if not control then
        return
    end

    control:SetHidden(true)
    control.data = nil
    control.currentIndent = nil
    control.baseColor = nil

    if control.label and control.label.SetText then
        control.label:SetText("")
    end
end

local function InitializeControlForType(control, rowType)
    if rowType == "category" then
        InitializeCategoryControl(control)
    elseif rowType == "achievement" then
        InitializeAchievementControl(control)
    elseif rowType == "objective" then
        InitializeObjectiveControl(control)
    end

    control.rowType = rowType
end

local function ResetControlForType(control, rowType)
    if rowType == "category" then
        ResetCategoryControl(control)
    elseif rowType == "achievement" then
        ResetAchievementControl(control)
    elseif rowType == "objective" then
        ResetObjectiveControl(control)
    end
end

local function EnsureControl(rowKey, rowType)
    local entry, key = GetRowEntry(rowKey)
    if entry then
        entry.rowType = entry.rowType or rowType
        return entry.control
    end

    if not state.parent then
        return nil
    end

    local resolvedType = rowType or ResolveRowType(rowKey)
    if not resolvedType then
        return nil
    end

    local template
    if resolvedType == "category" then
        template = "AchievementsCategoryHeader_Template"
    elseif resolvedType == "achievement" then
        template = "AchievementHeader_Template"
    elseif resolvedType == "objective" then
        template = "AchievementObjective_Template"
    end

    if not template then
        return nil
    end

    local controlName = BuildControlName(key)
    local control = CreateControlFromVirtual(controlName, state.parent, template)
    InitializeControlForType(control, resolvedType)

    state.rows[key] = {
        control = control,
        rowType = resolvedType,
    }
    state.rowTypes[key] = resolvedType

    return control
end

function AchievementTrackerRows.Init(parent)
    state.parent = parent
    state.rows = {}
    state.rowTypes = {}
end

function AchievementTrackerRows.ReleaseAll()
    for key, entry in pairs(state.rows) do
        if entry and entry.control then
            ResetControlForType(entry.control, entry.rowType)
        end
    end
end

function AchievementTrackerRows.AcquireRow(rowKey)
    local key = ResolveRowKey(rowKey)
    local rowType = ResolveRowType(rowKey)
    return EnsureControl(key, rowType)
end

local function ApplyCategory(control, rowData)
    if not control then
        return
    end

    control.data = rowData and rowData.data or nil
    control.isExpanded = rowData and rowData.expanded or nil
    control.__nvk3OnMouseUp = function(button, upInside)
        if not upInside then
            return
        end

        if button == LEFT_MOUSE_BUTTON then
            if rowData and rowData.onLeftClick then
                rowData.onLeftClick(control)
            end
        elseif button == RIGHT_MOUSE_BUTTON then
            if rowData and rowData.onRightClick then
                rowData.onRightClick(control)
            end
        end
    end
    control.__nvk3OnMouseEnter = function()
        ApplyMouseoverHighlight(control)
        if rowData and rowData.onMouseEnter then
            rowData.onMouseEnter(control)
        end
    end
    control.__nvk3OnMouseExit = function()
        RestoreBaseColor(control)
        if rowData and rowData.onMouseExit then
            rowData.onMouseExit(control)
        end
    end

    if control.label then
        if rowData and rowData.labelText and control.label.SetText then
            control.label:SetText(rowData.labelText)
        end
        if rowData and rowData.labelFont then
            control.label:SetFont(rowData.labelFont)
        end
    end

    if control.toggle then
        if rowData and rowData.toggleFont then
            control.toggle:SetFont(rowData.toggleFont)
        end
        if rowData and rowData.toggleTexture and control.toggle.SetTexture then
            control.toggle:SetTexture(rowData.toggleTexture)
        end
        if rowData and control.toggle.SetHidden then
            control.toggle:SetHidden(rowData.toggleHidden == true)
        end
    end

    if rowData and rowData.baseColor then
        ApplyBaseColor(control, rowData.baseColor)
    end
end

local function ApplyAchievement(control, rowData)
    if not control then
        return
    end

    control.data = rowData and rowData.data or nil
    control.__nvk3OnMouseUp = function(button, upInside)
        if not upInside then
            return
        end

        if button == LEFT_MOUSE_BUTTON then
            if rowData and rowData.onLeftClick then
                rowData.onLeftClick(control)
            end
        elseif button == RIGHT_MOUSE_BUTTON then
            if rowData and rowData.onRightClick then
                rowData.onRightClick(control)
            end
        end
    end
    control.__nvk3OnMouseEnter = function()
        ApplyMouseoverHighlight(control)
        if rowData and rowData.onMouseEnter then
            rowData.onMouseEnter(control)
        end
    end
    control.__nvk3OnMouseExit = function()
        RestoreBaseColor(control)
        if rowData and rowData.onMouseExit then
            rowData.onMouseExit(control)
        end
    end

    if control.label then
        if rowData and rowData.labelText and control.label.SetText then
            control.label:SetText(rowData.labelText)
        end
        if rowData and rowData.labelFont then
            control.label:SetFont(rowData.labelFont)
        end
    end

    if control.iconSlot and rowData and rowData.icon then
        if control.iconSlot.SetTexture then
            control.iconSlot:SetTexture(rowData.icon.texture)
        end
        if control.iconSlot.SetAlpha and rowData.icon.alpha ~= nil then
            control.iconSlot:SetAlpha(rowData.icon.alpha)
        end
        if control.iconSlot.SetHidden and rowData.icon.hidden ~= nil then
            control.iconSlot:SetHidden(rowData.icon.hidden)
        end
    end

    if rowData and rowData.baseColor then
        ApplyBaseColor(control, rowData.baseColor)
    end
end

local function ApplyObjective(control, rowData)
    if not control then
        return
    end

    control.data = rowData and rowData.data or nil

    if control.label then
        if rowData and rowData.labelText and control.label.SetText then
            control.label:SetText(rowData.labelText)
        end
        if rowData and rowData.labelFont then
            control.label:SetFont(rowData.labelFont)
        end
        if rowData and rowData.labelColor and control.label.SetColor then
            local color = rowData.labelColor
            control.label:SetColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        end
    end

    if rowData and rowData.baseColor then
        ApplyBaseColor(control, rowData.baseColor)
    end
end

function AchievementTrackerRows.ApplyRow(control, rowType, rowData)
    if not control then
        return
    end

    control.rowType = rowType

    if rowType == "category" then
        ApplyCategory(control, rowData)
    elseif rowType == "achievement" then
        ApplyAchievement(control, rowData)
    elseif rowType == "objective" then
        ApplyObjective(control, rowData)
    end
end

Nvk3UT.AchievementTrackerRows = AchievementTrackerRows

return AchievementTrackerRows
