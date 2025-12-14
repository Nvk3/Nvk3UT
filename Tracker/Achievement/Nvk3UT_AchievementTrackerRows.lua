local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local DEFAULT_CATEGORY_TOGGLE_TEXTURES = {
    expanded = {
        up = "EsoUI/Art/Buttons/tree_open_up.dds",
        over = "EsoUI/Art/Buttons/tree_open_over.dds",
    },
    collapsed = {
        up = "EsoUI/Art/Buttons/tree_closed_up.dds",
        over = "EsoUI/Art/Buttons/tree_closed_over.dds",
    },
}

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

local function SelectCategoryToggleTexture(callbacks, expanded, isMouseOver)
    local selector = callbacks and callbacks.SelectCategoryToggleTexture
    if selector then
        return selector(expanded, isMouseOver)
    end

    local textures = expanded and DEFAULT_CATEGORY_TOGGLE_TEXTURES.expanded or DEFAULT_CATEGORY_TOGGLE_TEXTURES.collapsed
    if isMouseOver then
        return textures.over
    end
    return textures.up
end

local function UpdateCategoryToggle(callbacks, control, expanded)
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
        local texture = SelectCategoryToggleTexture(callbacks, expanded, isMouseOver)
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

local function ResetControl(control)
    control:SetHidden(true)
    control.data = nil
    control.currentIndent = nil
end

local function ExecuteCallback(control, callbacks, key, ...)
    local rowCallbacks = control and control.rowCallbacks
    if rowCallbacks and rowCallbacks[key] then
        return rowCallbacks[key](control, ...)
    end
    if callbacks and callbacks[key] then
        return callbacks[key](control, ...)
    end
end

local function SetupCategoryHandlers(control, callbacks)
    control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
        ExecuteCallback(ctrl, callbacks, "OnCategoryMouseUp", button, upInside)
    end)
    control:SetHandler("OnMouseEnter", function(ctrl)
        ExecuteCallback(ctrl, callbacks, "ApplyMouseoverHighlight")
        local expanded = ctrl.isExpanded
        if expanded == nil then
            expanded = ExecuteCallback(ctrl, callbacks, "IsCategoryExpanded")
        end
        UpdateCategoryToggle(callbacks, ctrl, expanded)
    end)
    control:SetHandler("OnMouseExit", function(ctrl)
        ExecuteCallback(ctrl, callbacks, "RestoreBaseColor")
        local expanded = ctrl.isExpanded
        if expanded == nil then
            expanded = ExecuteCallback(ctrl, callbacks, "IsCategoryExpanded")
        end
        UpdateCategoryToggle(callbacks, ctrl, expanded)
    end)
end

local function SetupAchievementHandlers(control, callbacks)
    control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
        ExecuteCallback(ctrl, callbacks, "OnAchievementMouseUp", button, upInside)
    end)
    control:SetHandler("OnMouseEnter", function(ctrl)
        ExecuteCallback(ctrl, callbacks, "ApplyMouseoverHighlight")
    end)
    control:SetHandler("OnMouseExit", function(ctrl)
        ExecuteCallback(ctrl, callbacks, "RestoreBaseColor")
    end)
end

local function CreateCategoryControl(self, rowKey)
    if not self.parent then
        return nil
    end

    local parentName = self.parent:GetName() or addonName
    local name = string.format("%s_CategoryRow_%s", parentName, tostring(rowKey))
    local control = CreateControlFromVirtual(name, self.parent, "AchievementsCategoryHeader_Template")
    control.label = control:GetNamedChild("Label")
    control.toggle = control:GetNamedChild("Toggle")
    if control.toggle and control.toggle.SetTexture then
        control.toggle:SetTexture(SelectCategoryToggleTexture(self.callbacks, false, false))
    end
    control.isExpanded = false

    SetupCategoryHandlers(control, self.callbacks)

    ApplyLabelDefaults(control.label)
    ApplyToggleDefaults(control.toggle)

    return control
end

local function CreateAchievementControl(self, rowKey)
    if not self.parent then
        return nil
    end

    local parentName = self.parent:GetName() or addonName
    local name = string.format("%s_AchievementRow_%s", parentName, tostring(rowKey))
    local control = CreateControlFromVirtual(name, self.parent, "AchievementHeader_Template")
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

    SetupAchievementHandlers(control, self.callbacks)

    ApplyLabelDefaults(control.label)

    return control
end

local function CreateObjectiveControl(self, rowKey)
    if not self.parent then
        return nil
    end

    local parentName = self.parent:GetName() or addonName
    local name = string.format("%s_ObjectiveRow_%s", parentName, tostring(rowKey))
    local control = CreateControlFromVirtual(name, self.parent, "AchievementObjective_Template")
    control.label = control:GetNamedChild("Label")

    ApplyLabelDefaults(control.label)

    return control
end

function Rows:Init(parent, callbacks)
    self.parent = parent
    self.callbacks = callbacks or {}
    self.controls = self.controls or {}
end

function Rows:ReleaseAll()
    if not self.controls then
        return
    end

    for key, control in pairs(self.controls) do
        if control.label and control.label.SetText then
            control.label:SetText("")
        end
        if control.toggle and control.toggle.SetHidden then
            control.toggle:SetHidden(false)
        end
        if control.iconSlot then
            UpdateAchievementIconSlot(control)
        end
        ResetControl(control)
        self.controls[key] = nil
    end
end

function Rows:AcquireRow(rowKey, rowType)
    if not self.controls then
        self.controls = {}
    end

    local control = self.controls[rowKey]
    if control and rowType and control.rowType ~= rowType then
        control:SetHidden(true)
        self.controls[rowKey] = nil
        control = nil
    end

    if not control then
        if rowType == "category" then
            control = CreateCategoryControl(self, rowKey)
        elseif rowType == "achievement" then
            control = CreateAchievementControl(self, rowKey)
        elseif rowType == "objective" then
            control = CreateObjectiveControl(self, rowKey)
        end
        if control then
            self.controls[rowKey] = control
        end
    end

    return control
end

function Rows:ApplyRow(control, rowType, rowData)
    if not control then
        return
    end

    control.rowType = rowType
    control.data = rowData and rowData.data or nil
    control.rowCallbacks = rowData and rowData.callbacks

    if rowType == "category" then
        ApplyFont(control.label, rowData and rowData.fonts and rowData.fonts.label)
        ApplyFont(control.toggle, rowData and rowData.fonts and rowData.fonts.toggle)
        if control.label and control.label.SetText then
            control.label:SetText(rowData and rowData.labelText or "")
        end
        local color = rowData and rowData.color
        if color then
            ApplyBaseColor(control, color[1], color[2], color[3], color[4])
        end
        UpdateCategoryToggle(self.callbacks, control, rowData and rowData.expanded)
    elseif rowType == "achievement" then
        ApplyFont(control.label, rowData and rowData.fonts and rowData.fonts.label)
        if control.label and control.label.SetText then
            control.label:SetText(rowData and rowData.labelText or "")
        end
        local color = rowData and rowData.color
        if color then
            ApplyBaseColor(control, color[1], color[2], color[3], color[4])
        end
        UpdateAchievementIconSlot(control)
    elseif rowType == "objective" then
        ApplyFont(control.label, rowData and rowData.fonts and rowData.fonts.label)
        if control.label and control.label.SetText then
            control.label:SetText(rowData and rowData.labelText or "")
        end
        local color = rowData and rowData.color
        if color then
            control.label:SetColor(color[1], color[2], color[3], color[4])
        end
    end

    control:SetHidden(false)
end

function Rows:UpdateCategoryToggle(control, expanded)
    UpdateCategoryToggle(self.callbacks, control, expanded)
end

function Rows:UpdateAchievementIconSlot(control)
    UpdateAchievementIconSlot(control)
end

Nvk3UT.AchievementTrackerRows = Rows

return Rows
