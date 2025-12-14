local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local ROW_HEIGHT = 26
local ICON_SIZE = 18
local ICON_OFFSET_X = 0
local LABEL_OFFSET_X = 6

local function applyLabelDefaults(label)
    if not label then
        return
    end

    if label.SetHorizontalAlignment then
        label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    end

    if label.SetVerticalAlignment then
        label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    end

    if label.SetWrapMode then
        label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    end
end

local function createRow(parent)
    local control = WINDOW_MANAGER:CreateControl(nil, parent, CT_CONTROL)
    control:SetHeight(ROW_HEIGHT)
    control:SetResizeToFitDescendents(false)

    control.icon = WINDOW_MANAGER:CreateControl(nil, control, CT_TEXTURE)
    control.icon:SetDimensions(ICON_SIZE, ICON_SIZE)
    control.icon:SetAnchor(TOPLEFT, control, TOPLEFT, ICON_OFFSET_X, (ROW_HEIGHT - ICON_SIZE) / 2)

    control.label = WINDOW_MANAGER:CreateControl(nil, control, CT_LABEL)
    control.label:SetFont("ZoFontGame")
    applyLabelDefaults(control.label)
    control.label:SetAnchor(LEFT, control.icon, RIGHT, LABEL_OFFSET_X, 0)
    control.label:SetAnchor(RIGHT, control, RIGHT, -80, 0)

    control.progress = WINDOW_MANAGER:CreateControl(nil, control, CT_LABEL)
    control.progress:SetFont("ZoFontGameSmall")
    applyLabelDefaults(control.progress)
    control.progress:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    control.progress:SetAnchor(RIGHT, control, RIGHT, 0, 0)

    return control
end

function Rows:Init(parent)
    self.parent = parent
    self.rows = {}
end

function Rows:ReleaseAll()
    if not self.rows then
        return
    end

    for _, control in ipairs(self.rows) do
        if control and control.ClearAnchors then
            control:ClearAnchors()
        end
        if control and control.SetParent then
            control:SetParent(nil)
        end
        if control and control.SetHidden then
            control:SetHidden(true)
        end
    end

    self.rows = {}
end

function Rows:EnsureRow(index)
    if not self.parent then
        return nil
    end

    self.rows = self.rows or {}

    if self.rows[index] then
        return self.rows[index]
    end

    local control = createRow(self.parent)

    if index == 1 then
        control:SetAnchor(TOPLEFT, self.parent, TOPLEFT, 0, 0)
        control:SetAnchor(TOPRIGHT, self.parent, TOPRIGHT, 0, 0)
    else
        local previous = self.rows[index - 1]
        control:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, 0)
        control:SetAnchor(TOPRIGHT, previous, BOTTOMRIGHT, 0, 0)
    end

    self.rows[index] = control
    return control
end

function Rows:ApplyRowData(row, rowData)
    if not row or not rowData then
        return
    end

    if row.SetHidden then
        row:SetHidden(false)
    end

    if row.icon and rowData.icon then
        row.icon:SetTexture(rowData.icon)
        row.icon:SetHidden(false)
    elseif row.icon then
        row.icon:SetTexture(nil)
        row.icon:SetHidden(true)
    end

    if row.label and row.label.SetText then
        row.label:SetText(rowData.name or "")
    end

    if row.progress then
        if rowData.progressText and row.progress.SetText then
            row.progress:SetHidden(false)
            row.progress:SetText(rowData.progressText)
        elseif row.progress.SetHidden then
            row.progress:SetHidden(true)
            row.progress:SetText("")
        end
    end
end

Rows.ROW_HEIGHT = ROW_HEIGHT

Nvk3UT.AchievementTrackerRows = Rows

return Rows
