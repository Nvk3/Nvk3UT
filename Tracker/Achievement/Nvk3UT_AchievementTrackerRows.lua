local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local AchievementTrackerRows = {}
AchievementTrackerRows.__index = AchievementTrackerRows

local DEFAULT_ROW_TEXT_PADDING_Y = 8

local function applyFont(label, font)
    if label and label.SetFont and font and font ~= "" then
        label:SetFont(font)
    end
end

local function applyLabelDefaults(label)
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

local function applyToggleDefaults(toggle)
    if toggle and toggle.SetVerticalAlignment then
        toggle:SetVerticalAlignment(TEXT_ALIGN_TOP)
    end
end

local function applyBaseColor(control, baseColor)
    if not (control and control.label and baseColor) then
        return
    end

    local r = baseColor[1] or 1
    local g = baseColor[2] or 1
    local b = baseColor[3] or 1
    local a = baseColor[4] or 1

    control.baseColor = { r, g, b, a }
    control.label:SetColor(r, g, b, a)
end

local function applyMouseoverHighlight(control, hoverColor)
    if not (control and control.label and hoverColor) then
        return
    end

    control.label:SetColor(hoverColor[1] or 1, hoverColor[2] or 1, hoverColor[3] or 1, hoverColor[4] or 1)
end

local function restoreBaseColor(control)
    if not (control and control.label and control.baseColor) then
        return
    end

    control.label:SetColor(unpack(control.baseColor))
end

local function selectToggleTexture(rowData, isMouseOver)
    if type(rowData.toggleSelector) == "function" then
        local expanded = rowData.getExpandedState and rowData.getExpandedState()
        if expanded == nil then
            expanded = rowData.expanded
        end
        return rowData.toggleSelector(expanded, isMouseOver)
    end

    return nil
end

local function updateCategoryToggle(control, rowData, isMouseOver)
    if not (control and control.toggle) then
        return
    end

    if control.toggle.SetHidden then
        control.toggle:SetHidden(false)
    end

    local expanded = rowData and rowData.getExpandedState and rowData.getExpandedState()
    if expanded == nil then
        expanded = rowData and rowData.expanded
    end
    control.isExpanded = expanded

    local texture = selectToggleTexture(rowData or {}, isMouseOver)
    if texture and control.toggle.SetTexture then
        control.toggle:SetTexture(texture)
    end
end

local function buildControlName(parent, rowKey, suffix)
    local prefix = parent and parent:GetName() or addonName
    return string.format("%s_%s_%s", prefix, tostring(suffix), tostring(rowKey))
end

local function createCategoryControl(self, rowKey)
    local control = CreateControlFromVirtual(buildControlName(self.parent, rowKey, "Category"), self.parent, "AchievementsCategoryHeader_Template")
    control.label = control:GetNamedChild("Label")
    control.toggle = control:GetNamedChild("Toggle")
    applyLabelDefaults(control.label)
    applyToggleDefaults(control.toggle)
    control.rowType = "category"
    return control
end

local function createAchievementControl(self, rowKey)
    local control = CreateControlFromVirtual(buildControlName(self.parent, rowKey, "Achievement"), self.parent, "AchievementHeader_Template")
    control.label = control:GetNamedChild("Label")
    control.iconSlot = control:GetNamedChild("IconSlot")

    if control.iconSlot then
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
            control.label:SetAnchor(TOPLEFT, control.iconSlot, TOPRIGHT, 0, 0)
        else
            control.label:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
        end
        control.label:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
    end

    applyLabelDefaults(control.label)
    control.rowType = "achievement"
    return control
end

local function createObjectiveControl(self, rowKey)
    local control = CreateControlFromVirtual(buildControlName(self.parent, rowKey, "Objective"), self.parent, "AchievementObjective_Template")
    control.label = control:GetNamedChild("Label")
    applyLabelDefaults(control.label)
    control.rowType = "objective"
    return control
end

local function ensureControl(self, rowKey, rowType)
    self.controls = self.controls or {}
    local control = self.controls[rowKey]
    if control and control.rowType ~= rowType then
        control:SetHidden(true)
        control = nil
    end

    if not control then
        if rowType == "category" then
            control = createCategoryControl(self, rowKey)
        elseif rowType == "achievement" then
            control = createAchievementControl(self, rowKey)
        else
            control = createObjectiveControl(self, rowKey)
        end
        self.controls[rowKey] = control
    end

    return control
end

local function getContainerWidth(parent)
    if not parent or not parent.GetWidth then
        return 0
    end

    local width = parent:GetWidth()
    if not width or width <= 0 then
        return 0
    end

    return width
end

local function applyRowMetrics(self, control, metrics)
    if not (control and control.label and metrics) then
        return
    end

    local indent = metrics.indent or 0
    local toggleWidth = metrics.toggleWidth or 0
    if control.toggle then
        if control.toggle.IsHidden and control.toggle:IsHidden() then
            toggleWidth = 0
        elseif control.toggle.GetWidth then
            local width = control.toggle:GetWidth()
            if width and width > 0 then
                toggleWidth = width
            end
        end
    end
    local leftPadding = metrics.leftPadding or 0
    local rightPadding = metrics.rightPadding or 0

    local availableWidth = getContainerWidth(self.parent) - indent - toggleWidth - leftPadding - rightPadding
    if availableWidth < 0 then
        availableWidth = 0
    end

    control.label:SetWidth(availableWidth)

    local textHeight = control.label:GetTextHeight() or 0
    local padding = metrics.textPadding or DEFAULT_ROW_TEXT_PADDING_Y
    local targetHeight = textHeight + padding
    if metrics.minHeight then
        targetHeight = math.max(metrics.minHeight, targetHeight)
    end

    control:SetHeight(targetHeight)
    control.currentIndent = indent
end

local function updateIconSlot(control, iconSlot)
    if not (control and control.iconSlot) then
        return
    end

    if iconSlot and iconSlot.width and iconSlot.height then
        control.iconSlot:SetDimensions(iconSlot.width, iconSlot.height)
    end

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

function AchievementTrackerRows:Init(parent)
    self.parent = parent
    self.controls = {}
end

function AchievementTrackerRows:ReleaseAll()
    if not self.controls then
        return
    end

    for _, control in pairs(self.controls) do
        if control then
            control:SetHidden(true)
            control.data = nil
            control.currentIndent = nil
            control.metrics = nil
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
    end

    self.controls = {}
end

function AchievementTrackerRows:AcquireRow(rowKey, rowType)
    if not self.parent then
        return nil
    end

    return ensureControl(self, rowKey, rowType or "objective")
end

function AchievementTrackerRows:RefreshControlMetrics(control)
    if control then
        applyRowMetrics(self, control, control.metrics)
    end
end

function AchievementTrackerRows:ApplyRow(control, rowType, rowData)
    if not (control and rowData) then
        return control
    end

    control.rowType = rowType
    control.data = rowData.data
    control.metrics = {
        indent = rowData.indent,
        toggleWidth = rowData.toggleWidth,
        leftPadding = rowData.leftPadding,
        rightPadding = rowData.rightPadding,
        minHeight = rowData.minHeight,
        textPadding = rowData.textPadding,
    }

    if rowType == "category" then
        applyFont(control.label, rowData.fonts and rowData.fonts.label)
        applyFont(control.toggle, rowData.fonts and rowData.fonts.toggle)
        applyBaseColor(control, rowData.baseColor)
        control.hoverColor = rowData.hoverColor
        if control.label and control.label.SetText then
            control.label:SetText(rowData.labelText or "")
        end
        updateCategoryToggle(control, rowData, control:IsMouseOver())

        control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
            if rowData.onMouseUp then
                rowData.onMouseUp(ctrl, button, upInside)
            end
        end)
        control:SetHandler("OnMouseEnter", function(ctrl)
            applyMouseoverHighlight(ctrl, rowData.hoverColor)
            updateCategoryToggle(ctrl, rowData, true)
            if rowData.onMouseEnter then
                rowData.onMouseEnter(ctrl, rowData)
            end
        end)
        control:SetHandler("OnMouseExit", function(ctrl)
            restoreBaseColor(ctrl)
            updateCategoryToggle(ctrl, rowData, false)
            if rowData.onMouseExit then
                rowData.onMouseExit(ctrl, rowData)
            end
        end)
    elseif rowType == "achievement" then
        applyFont(control.label, rowData.fonts and rowData.fonts.label)
        applyBaseColor(control, rowData.baseColor)
        control.hoverColor = rowData.hoverColor
        if control.label and control.label.SetText then
            control.label:SetText(rowData.labelText or "")
        end
        updateIconSlot(control, rowData.iconSlot)
        if control.label then
            control.label:ClearAnchors()
            if control.iconSlot then
                local paddingX = (rowData.iconSlot and rowData.iconSlot.paddingX) or 0
                control.label:SetAnchor(TOPLEFT, control.iconSlot, TOPRIGHT, paddingX, 0)
            else
                control.label:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
            end
            control.label:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
        end

        control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
            if rowData.onMouseUp then
                rowData.onMouseUp(ctrl, button, upInside)
            end
        end)
        control:SetHandler("OnMouseEnter", function(ctrl)
            applyMouseoverHighlight(ctrl, rowData.hoverColor)
            if rowData.onMouseEnter then
                rowData.onMouseEnter(ctrl, rowData)
            end
        end)
        control:SetHandler("OnMouseExit", function(ctrl)
            restoreBaseColor(ctrl)
            if rowData.onMouseExit then
                rowData.onMouseExit(ctrl, rowData)
            end
        end)
    else
        applyFont(control.label, rowData.fonts and rowData.fonts.label)
        applyBaseColor(control, rowData.baseColor)
        if control.label and control.label.SetText then
            control.label:SetText(rowData.labelText or "")
        end
        control:SetHandler("OnMouseUp", nil)
        control:SetHandler("OnMouseEnter", nil)
        control:SetHandler("OnMouseExit", nil)
    end

    applyRowMetrics(self, control, control.metrics)

    return control
end

Nvk3UT.AchievementTrackerRows = AchievementTrackerRows

return AchievementTrackerRows
