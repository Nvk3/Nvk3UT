local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

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

local function SelectCategoryToggleTexture(expanded, isMouseOver)
    local textures = expanded and CATEGORY_TOGGLE_TEXTURES.expanded or CATEGORY_TOGGLE_TEXTURES.collapsed
    if isMouseOver then
        return textures.over
    end
    return textures.up
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

local function ApplyFont(label, font)
    if not label or not label.SetFont then
        return
    end

    if not font or font == "" then
        return
    end

    label:SetFont(font)
end

local function ResetIconSlot(control)
    if not control or not control.iconSlot then
        return
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

local function CreateCategoryRow(self, rowKey)
    local name = string.format("%sAchievementTrackerCategoryRow%d", addonName, rowKey)
    local control = CreateControlFromVirtual(name, self.parent, "AchievementsCategoryHeader_Template")
    control.label = control:GetNamedChild("Label")
    control.toggle = control:GetNamedChild("Toggle")
    control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
        if ctrl.onMouseUp then
            ctrl.onMouseUp(ctrl, button, upInside)
        end
    end)
    control:SetHandler("OnMouseEnter", function(ctrl)
        if ctrl.onMouseEnter then
            ctrl.onMouseEnter(ctrl)
        end
    end)
    control:SetHandler("OnMouseExit", function(ctrl)
        if ctrl.onMouseExit then
            ctrl.onMouseExit(ctrl)
        end
    end)
    ApplyLabelDefaults(control.label)
    ApplyToggleDefaults(control.toggle)
    control.rowType = "category"
    return control
end

local function CreateAchievementRow(self, rowKey)
    local name = string.format("%sAchievementTrackerAchievementRow%d", addonName, rowKey)
    local control = CreateControlFromVirtual(name, self.parent, "AchievementHeader_Template")
    control.label = control:GetNamedChild("Label")
    control.iconSlot = control:GetNamedChild("IconSlot")
    if control.iconSlot then
        ResetIconSlot(control)
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
    control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
        if ctrl.onMouseUp then
            ctrl.onMouseUp(ctrl, button, upInside)
        end
    end)
    control:SetHandler("OnMouseEnter", function(ctrl)
        if ctrl.onMouseEnter then
            ctrl.onMouseEnter(ctrl)
        end
    end)
    control:SetHandler("OnMouseExit", function(ctrl)
        if ctrl.onMouseExit then
            ctrl.onMouseExit(ctrl)
        end
    end)
    ApplyLabelDefaults(control.label)
    control.rowType = "achievement"
    return control
end

local function CreateObjectiveRow(self, rowKey)
    local name = string.format("%sAchievementTrackerObjectiveRow%d", addonName, rowKey)
    local control = CreateControlFromVirtual(name, self.parent, "AchievementObjective_Template")
    control.label = control:GetNamedChild("Label")
    ApplyLabelDefaults(control.label)
    control.rowType = "objective"
    return control
end

local function EnsureParent(self, parent)
    if parent and parent ~= self.parent then
        self.parent = parent
    end
end

function Rows:Init(parent)
    EnsureParent(self, parent)
    self.rows = self.rows or {}
end

local function ResetCategoryRow(control)
    if control.toggle and control.toggle.SetTexture then
        control.toggle:SetTexture(SelectCategoryToggleTexture(false, false))
    end
    control.isExpanded = nil
end

local function ResetAchievementRow(control)
    if control.label and control.label.SetText then
        control.label:SetText("")
    end
    ResetIconSlot(control)
end

local function ResetObjectiveRow(control)
    if control.label and control.label.SetText then
        control.label:SetText("")
    end
end

local function ResetRow(control)
    control.data = nil
    control.currentIndent = nil
    control.onMouseEnter = nil
    control.onMouseExit = nil
    control.onMouseUp = nil
    control.baseColor = nil
    control.__nvk3RestoreHoverColor = nil

    if control.SetHidden then
        control:SetHidden(true)
    end

    if control.rowType == "category" then
        ResetCategoryRow(control)
    elseif control.rowType == "achievement" then
        ResetAchievementRow(control)
    elseif control.rowType == "objective" then
        ResetObjectiveRow(control)
    end
end

function Rows:ReleaseAll()
    if not self.rows then
        return
    end

    for _, control in pairs(self.rows) do
        ResetRow(control)
    end
end

local function AcquireRowControl(self, rowKey, rowType)
    local control = self.rows[rowKey]
    if control and rowType and control.rowType ~= rowType then
        ResetRow(control)
        control = nil
    end

    if not control then
        if rowType == "category" then
            control = CreateCategoryRow(self, rowKey)
        elseif rowType == "objective" then
            control = CreateObjectiveRow(self, rowKey)
        else
            control = CreateAchievementRow(self, rowKey)
        end
        self.rows[rowKey] = control
    end

    return control
end

function Rows:AcquireRow(rowKey, rowType)
    if not self.parent then
        return nil
    end

    return AcquireRowControl(self, rowKey, rowType)
end

local function UpdateCategoryToggle(control, expanded, selectTexture)
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
        local texture
        if selectTexture then
            texture = selectTexture(expanded, isMouseOver)
        else
            texture = SelectCategoryToggleTexture(expanded, isMouseOver)
        end
        control.toggle:SetTexture(texture)
    end
    control.isExpanded = expanded and true or false
end

local function ApplyBaseColor(control, color)
    if not control then
        return
    end

    local target = control.baseColor
    if type(target) ~= "table" then
        target = {}
        control.baseColor = target
    end

    target[1] = color and color[1] or 1
    target[2] = color and color[2] or 1
    target[3] = color and color[3] or 1
    target[4] = color and color[4] or 1

    if control.label and control.label.SetColor then
        control.label:SetColor(target[1], target[2], target[3], target[4])
    end
end

local function ApplyCategoryRow(control, rowData)
    if not control then
        return
    end

    ApplyLabelDefaults(control.label)
    ApplyToggleDefaults(control.toggle)
    ApplyFont(control.label, rowData.font)
    ApplyFont(control.toggle, rowData.toggleFont)

    control.data = rowData.data
    control.onMouseUp = rowData.onMouseUp
    control.onMouseEnter = rowData.onMouseEnter
    control.onMouseExit = rowData.onMouseExit
    control.isExpanded = rowData.expanded and true or false

    if control.label and control.label.SetText and rowData.text then
        control.label:SetText(rowData.text)
    end

    if rowData.baseColor then
        ApplyBaseColor(control, rowData.baseColor)
    end

    UpdateCategoryToggle(control, control.isExpanded, rowData.selectCategoryToggleTexture)

    if control.SetHidden then
        control:SetHidden(false)
    end
end

local function ApplyAchievementRow(control, rowData)
    if not control then
        return
    end

    ApplyLabelDefaults(control.label)
    ApplyFont(control.label, rowData.font)

    control.data = rowData.data
    control.onMouseUp = rowData.onMouseUp
    control.onMouseEnter = rowData.onMouseEnter
    control.onMouseExit = rowData.onMouseExit

    if rowData.updateIconSlot then
        rowData.updateIconSlot(control)
    else
        ResetIconSlot(control)
    end

    if control.label and control.label.SetText and rowData.text then
        control.label:SetText(rowData.text)
    end

    if rowData.baseColor then
        ApplyBaseColor(control, rowData.baseColor)
    end

    if control.SetHidden then
        control:SetHidden(false)
    end
end

local function ApplyObjectiveRow(control, rowData)
    if not control then
        return
    end

    ApplyLabelDefaults(control.label)
    ApplyFont(control.label, rowData.font)

    control.data = rowData.data

    if control.label and control.label.SetText and rowData.text then
        control.label:SetText(rowData.text)
    end

    if rowData.color and control.label and control.label.SetColor then
        control.label:SetColor(rowData.color[1], rowData.color[2], rowData.color[3], rowData.color[4])
    end

    if control.SetHidden then
        control:SetHidden(false)
    end
end

function Rows:ApplyRow(control, rowType, rowData)
    if not control then
        return
    end

    control.rowType = rowType
    rowData = rowData or {}

    if rowType == "category" then
        ApplyCategoryRow(control, rowData)
    elseif rowType == "objective" then
        ApplyObjectiveRow(control, rowData)
    else
        ApplyAchievementRow(control, rowData)
    end
end

Nvk3UT.AchievementTrackerRows = Rows

return Rows
