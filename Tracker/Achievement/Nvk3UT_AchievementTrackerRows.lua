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

local LEFT_MOUSE_BUTTON = MOUSE_BUTTON_INDEX_LEFT or 1
local RIGHT_MOUSE_BUTTON = MOUSE_BUTTON_INDEX_RIGHT or 2

local function Call(callback, ...)
    if type(callback) == "function" then
        return callback(...)
    end
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

local function SelectCategoryToggleTexture(expanded, isMouseOver)
    local textures = expanded and CATEGORY_TOGGLE_TEXTURES.expanded or CATEGORY_TOGGLE_TEXTURES.collapsed
    if isMouseOver then
        return textures.over
    end
    return textures.up
end

function Rows:Init(parent, opts)
    self.parent = parent
    self.fonts = (opts and opts.fonts) or {}
    self.callbacks = (opts and opts.callbacks) or {}
    self.rows = self.rows or {}
end

function Rows:SetFonts(fonts)
    self.fonts = fonts or {}
end

function Rows:SetCallbacks(callbacks)
    self.callbacks = callbacks or {}
end

function Rows:ReleaseAll()
    if not self.rows then
        return
    end

    for _, control in pairs(self.rows) do
        self:ResetControl(control)
    end
end

function Rows:GetRowName(rowType, rowKey)
    local parentName = self.parent and self.parent.GetName and self.parent:GetName() or addonName
    local keyText = tostring(rowKey or "row")
    return string.format("%s_%s_%s", parentName, tostring(rowType or "row"), keyText)
end

function Rows:ResetControl(control)
    if not control then
        return
    end

    control:SetHidden(true)
    control.data = nil
    control.currentIndent = nil

    if control.rowType == "category" then
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
    elseif control.rowType == "achievement" then
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
    elseif control.rowType == "objective" then
        if control.label then
            control.label:SetText("")
        end
    end
end

function Rows:UpdateCategoryToggle(control, expanded)
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

function Rows:UpdateAchievementIconSlot(control)
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

function Rows:OnCategoryClicked(control)
    local expanded = not Call(self.callbacks.IsCategoryExpanded)
    Call(self.callbacks.SetCategoryExpanded, expanded, {
        trigger = "click",
        source = "AchievementTracker:OnCategoryClick",
    })
    Call(self.callbacks.Refresh)
    Call(self.callbacks.ScheduleToggleFollowup, "achievementCategoryToggle")
end

function Rows:ApplyFonts(control, rowType)
    if not control then
        return
    end

    if rowType == "category" then
        ApplyFont(control.label, self.fonts.category)
        ApplyFont(control.toggle, self.fonts.toggle)
    elseif rowType == "achievement" then
        ApplyFont(control.label, self.fonts.achievement)
    elseif rowType == "objective" then
        ApplyFont(control.label, self.fonts.objective)
    end
end

function Rows:CreateCategoryRow(rowKey)
    local control = CreateControlFromVirtual(self:GetRowName("Category", rowKey), self.parent, "AchievementsCategoryHeader_Template")
    control.rowType = "category"
    control.label = control:GetNamedChild("Label")
    control.toggle = control:GetNamedChild("Toggle")

    ApplyLabelDefaults(control.label)
    ApplyToggleDefaults(control.toggle)
    self:ApplyFonts(control, "category")
    if control.toggle and control.toggle.SetTexture then
        control.toggle:SetTexture(SelectCategoryToggleTexture(false, false))
    end

    control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
        if not upInside or button ~= LEFT_MOUSE_BUTTON then
            return
        end
        self:OnCategoryClicked(ctrl)
    end)
    control:SetHandler("OnMouseEnter", function(ctrl)
        Call(self.callbacks.ApplyMouseoverHighlight, ctrl)
        local expanded = ctrl.isExpanded
        if expanded == nil then
            expanded = Call(self.callbacks.IsCategoryExpanded)
        end
        self:UpdateCategoryToggle(ctrl, expanded)
    end)
    control:SetHandler("OnMouseExit", function(ctrl)
        Call(self.callbacks.RestoreBaseColor, ctrl)
        local expanded = ctrl.isExpanded
        if expanded == nil then
            expanded = Call(self.callbacks.IsCategoryExpanded)
        end
        self:UpdateCategoryToggle(ctrl, expanded)
    end)

    return control
end

function Rows:CreateAchievementRow(rowKey)
    local control = CreateControlFromVirtual(self:GetRowName("Achievement", rowKey), self.parent, "AchievementHeader_Template")
    control.rowType = "achievement"
    control.label = control:GetNamedChild("Label")
    control.iconSlot = control:GetNamedChild("IconSlot")

    if control.iconSlot then
        control.iconSlot:SetDimensions(18, 18)
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
            control.label:SetAnchor(TOPLEFT, control.iconSlot, TOPRIGHT, 6, 0)
        else
            control.label:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
        end
        control.label:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
    end

    ApplyLabelDefaults(control.label)
    self:ApplyFonts(control, "achievement")

    control:SetHandler("OnMouseUp", function(ctrl, button, upInside)
        if not upInside then
            return
        end

        if button == LEFT_MOUSE_BUTTON then
            if not ctrl.data or not ctrl.data.achievementId or not ctrl.data.hasObjectives then
                return
            end
            local achievementId = ctrl.data.achievementId
            local expanded = not Call(self.callbacks.IsEntryExpanded, achievementId)
            Call(self.callbacks.SetEntryExpanded, achievementId, expanded, "AchievementTracker:ToggleAchievementObjectives")
            Call(self.callbacks.Refresh)
            Call(self.callbacks.ScheduleToggleFollowup, "achievementEntryToggle")
        elseif button == RIGHT_MOUSE_BUTTON then
            if not ctrl.data or not ctrl.data.achievementId then
                return
            end
            Call(self.callbacks.ShowAchievementContextMenu, ctrl, ctrl.data)
        end
    end)
    control:SetHandler("OnMouseEnter", function(ctrl)
        Call(self.callbacks.ApplyMouseoverHighlight, ctrl)
    end)
    control:SetHandler("OnMouseExit", function(ctrl)
        Call(self.callbacks.RestoreBaseColor, ctrl)
    end)

    return control
end

function Rows:CreateObjectiveRow(rowKey)
    local control = CreateControlFromVirtual(self:GetRowName("Objective", rowKey), self.parent, "AchievementObjective_Template")
    control.rowType = "objective"
    control.label = control:GetNamedChild("Label")

    ApplyLabelDefaults(control.label)
    self:ApplyFonts(control, "objective")

    return control
end

function Rows:AcquireRow(rowKey, rowType)
    if not self.rows then
        self.rows = {}
    end

    local control = self.rows[rowKey]
    if control then
        if rowType then
            control.rowType = rowType
            self:ApplyFonts(control, rowType)
        end
        return control
    end

    if rowType == "category" then
        control = self:CreateCategoryRow(rowKey)
    elseif rowType == "achievement" then
        control = self:CreateAchievementRow(rowKey)
    elseif rowType == "objective" then
        control = self:CreateObjectiveRow(rowKey)
    end

    if control then
        self.rows[rowKey] = control
    end

    return control
end

function Rows:ApplyRow(control, rowType, rowData)
    if not control then
        return
    end

    control.rowType = rowType
    self:ApplyFonts(control, rowType)

    if rowType == "category" then
        control.data = rowData and rowData.data or nil
        if control.label and control.label.SetText then
            control.label:SetText(rowData and rowData.labelText or "")
        end
        if rowData and rowData.baseColor then
            ApplyBaseColor(control, unpack(rowData.baseColor))
        end
        self:UpdateCategoryToggle(control, rowData and rowData.expanded)
    elseif rowType == "achievement" then
        control.data = rowData and rowData.data or nil
        if control.label and control.label.SetText then
            control.label:SetText(rowData and rowData.labelText or "")
        end
        self:UpdateAchievementIconSlot(control)
        if rowData and rowData.baseColor then
            ApplyBaseColor(control, unpack(rowData.baseColor))
        end
    elseif rowType == "objective" then
        control.data = rowData and rowData.data or nil
        if control.label and control.label.SetText then
            control.label:SetText(rowData and rowData.labelText or "")
        end
        if rowData and rowData.color and control.label and control.label.SetColor then
            control.label:SetColor(unpack(rowData.color))
        end
    end
end

Nvk3UT.AchievementTrackerRows = Rows

