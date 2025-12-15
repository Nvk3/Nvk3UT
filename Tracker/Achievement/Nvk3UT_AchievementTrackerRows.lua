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

local ACHIEVEMENT_ICON_SLOT_WIDTH = 18
local ACHIEVEMENT_ICON_SLOT_HEIGHT = 18
local ACHIEVEMENT_ICON_SLOT_PADDING_X = 6
local ROW_TEXT_PADDING_Y = 8
local CATEGORY_MIN_HEIGHT = 26
local ACHIEVEMENT_MIN_HEIGHT = 24
local OBJECTIVE_MIN_HEIGHT = 20
local CATEGORY_TOGGLE_WIDTH = 20

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

local function ResetCategoryControl(control)
    if not control then
        return
    end
    control:SetHidden(true)
    control.data = nil
    control.currentIndent = nil
    control.baseColor = nil
    control.isExpanded = nil

    if control.toggle then
        if control.toggle.SetTexture then
            control.toggle:SetTexture(SelectCategoryToggleTexture(false, false))
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

    if control.label then
        control.label:SetText("")
    end
end

local function GetContainerWidth(parent)
    if not parent or not parent.GetWidth then
        return 0
    end

    local width = parent:GetWidth()
    if not width or width <= 0 then
        return 0
    end

    return width
end

function Rows:Init(parent, config)
    self.parent = parent
    self.config = config or {}
    self.rows = self.rows or {}
    self.allControls = self.allControls or {}
    self.nextControlId = self.nextControlId or 1
end

local function BuildControlName(parent, controlId)
    local baseName = parent and parent.GetName and parent:GetName()
    if baseName and baseName ~= "" then
        return string.format("%sAchievementTrackerRow%d", baseName, controlId)
    end

    return string.format("%sAchievementTrackerRow%d", addonName, controlId)
end

function Rows:CreateRowControl(rowType)
    if not self.parent then
        return nil
    end

    local template
    if rowType == "category" then
        template = "AchievementsCategoryHeader_Template"
    elseif rowType == "achievement" then
        template = "AchievementHeader_Template"
    elseif rowType == "objective" then
        template = "AchievementObjective_Template"
    end

    if not template then
        return nil
    end

    local controlName = BuildControlName(self.parent, self.nextControlId or 1)
    self.nextControlId = (self.nextControlId or 1) + 1

    local control = CreateControlFromVirtual(controlName, self.parent, template)
    if not control then
        return nil
    end

    control.rowType = rowType

    if rowType == "category" then
        control.label = control:GetNamedChild("Label")
        control.toggle = control:GetNamedChild("Toggle")
        if control.toggle and control.toggle.SetTexture then
            control.toggle:SetTexture(SelectCategoryToggleTexture(false, false))
        end
        ApplyLabelDefaults(control.label)
        ApplyToggleDefaults(control.toggle)
    elseif rowType == "achievement" then
        control.label = control:GetNamedChild("Label")
        control.iconSlot = control:GetNamedChild("IconSlot")
        if control.iconSlot then
            control.iconSlot:SetDimensions(
                self.config.iconSlotWidth or ACHIEVEMENT_ICON_SLOT_WIDTH,
                self.config.iconSlotHeight or ACHIEVEMENT_ICON_SLOT_HEIGHT
            )
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
                control.label:SetAnchor(
                    TOPLEFT,
                    control.iconSlot,
                    TOPRIGHT,
                    self.config.iconSlotPaddingX or ACHIEVEMENT_ICON_SLOT_PADDING_X,
                    0
                )
            else
                control.label:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
            end
            control.label:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
        end
        ApplyLabelDefaults(control.label)
    elseif rowType == "objective" then
        control.label = control:GetNamedChild("Label")
        ApplyLabelDefaults(control.label)
    end

    self.allControls[#self.allControls + 1] = control

    return control
end

function Rows:AcquireRow(rowKey, rowType)
    if not rowKey or not rowType then
        return nil
    end

    self.rows = self.rows or {}

    local control = self.rows[rowKey]
    if control and control.rowType ~= rowType then
        control:SetHidden(true)
        control = nil
    end

    if not control then
        control = self:CreateRowControl(rowType)
        self.rows[rowKey] = control
    end

    return control
end

local function ApplyRowMetrics(parent, control, metrics)
    if not control or not control.label then
        return
    end

    if not metrics then
        return
    end

    local indent = metrics.indent or 0
    local toggleWidth = metrics.toggleWidth or 0
    local leftPadding = metrics.leftPadding or 0
    local rightPadding = metrics.rightPadding or 0
    local minHeight = metrics.minHeight

    local containerWidth = GetContainerWidth(parent)
    local availableWidth = containerWidth - indent - toggleWidth - leftPadding - rightPadding
    if availableWidth < 0 then
        availableWidth = 0
    end

    control.label:SetWidth(availableWidth)

    local textHeight = control.label:GetTextHeight() or 0
    local targetHeight = textHeight + (metrics.textPaddingY or ROW_TEXT_PADDING_Y)
    if minHeight then
        targetHeight = math.max(minHeight, targetHeight)
    end

    control:SetHeight(targetHeight)
    control.__nvk3Metrics = {
        indent = indent,
        toggleWidth = toggleWidth,
        leftPadding = leftPadding,
        rightPadding = rightPadding,
        minHeight = minHeight,
        textPaddingY = metrics.textPaddingY or ROW_TEXT_PADDING_Y,
    }
end

local function ApplyHandlers(control, handlers)
    if not control or type(handlers) ~= "table" then
        return
    end

    if handlers.OnMouseUp then
        control:SetHandler("OnMouseUp", handlers.OnMouseUp)
    end
    if handlers.OnMouseEnter then
        control:SetHandler("OnMouseEnter", handlers.OnMouseEnter)
    end
    if handlers.OnMouseExit then
        control:SetHandler("OnMouseExit", handlers.OnMouseExit)
    end
end

local function ApplyCategoryRow(self, control, rowData)
    if not control then
        return
    end

    control.data = rowData and rowData.data or nil

    if rowData and rowData.fonts then
        ApplyFont(control.label, rowData.fonts.label)
        ApplyFont(control.toggle, rowData.fonts.toggle)
    end

    if rowData and rowData.handlers then
        ApplyHandlers(control, rowData.handlers)
    end

    if control.toggle then
        if rowData and rowData.toggle and rowData.toggle.update then
            rowData.toggle.update(control, rowData.toggle.expanded)
        elseif control.toggle.SetTexture then
            control.toggle:SetTexture(SelectCategoryToggleTexture(false, false))
        end
    end

    if control.label then
        control.label:SetText(rowData and rowData.text or "")
    end

    if rowData and rowData.baseColor then
        ApplyBaseColor(control, unpack(rowData.baseColor))
    end

    ApplyRowMetrics(self.parent, control, rowData and rowData.metrics)
end

local function ApplyAchievementRow(self, control, rowData)
    if not control then
        return
    end

    control.data = rowData and rowData.data or nil

    if rowData and rowData.fonts then
        ApplyFont(control.label, rowData.fonts.label)
    end

    if rowData and rowData.handlers then
        ApplyHandlers(control, rowData.handlers)
    end

    if rowData and rowData.iconUpdate then
        rowData.iconUpdate(control)
    end

    if control.label then
        control.label:SetText(rowData and rowData.text or "")
    end

    if rowData and rowData.baseColor then
        ApplyBaseColor(control, unpack(rowData.baseColor))
    end

    ApplyRowMetrics(self.parent, control, rowData and rowData.metrics)
end

local function ApplyObjectiveRow(self, control, rowData)
    if not control then
        return
    end

    control.data = rowData and rowData.data or nil

    if rowData and rowData.fonts then
        ApplyFont(control.label, rowData.fonts.label)
    end

    if control.label then
        control.label:SetText(rowData and rowData.text or "")
    end

    if rowData and rowData.baseColor then
        ApplyBaseColor(control, unpack(rowData.baseColor))
    end

    ApplyRowMetrics(self.parent, control, rowData and rowData.metrics)
end

function Rows:ApplyRow(control, rowType, rowData)
    if rowType == "category" then
        ApplyCategoryRow(self, control, rowData)
    elseif rowType == "achievement" then
        ApplyAchievementRow(self, control, rowData)
    elseif rowType == "objective" then
        ApplyObjectiveRow(self, control, rowData)
    end
end

function Rows:RefreshControlMetrics(control)
    if not control or not control.__nvk3Metrics then
        return
    end

    local metrics = control.__nvk3Metrics
    ApplyRowMetrics(self.parent, control, metrics)
end

local function ResetAllControls(rows)
    if not rows or not rows.allControls then
        return
    end

    for index = 1, #rows.allControls do
        local control = rows.allControls[index]
        if control then
            if control.rowType == "category" then
                ResetCategoryControl(control)
            elseif control.rowType == "achievement" then
                ResetAchievementControl(control)
            elseif control.rowType == "objective" then
                ResetObjectiveControl(control)
            end
        end
    end
end

function Rows:ReleaseAll()
    ResetAllControls(self)
    if self.rows then
        for key in pairs(self.rows) do
            self.rows[key] = nil
        end
    end
end

Nvk3UT.AchievementTrackerRows = Rows

return Rows
