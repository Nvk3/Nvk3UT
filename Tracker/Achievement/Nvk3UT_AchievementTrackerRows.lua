local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = {}
Rows.__index = Rows

local MODULE_TAG = addonName .. ".AchievementTrackerRows"

local ROW_HEIGHT = 24
local ICON_SIZE = 18
local ICON_Y_OFFSET = math.floor((ROW_HEIGHT - ICON_SIZE) / 2 + 0.5)
local LABEL_PADDING_X = 6
local ROW_VERTICAL_PADDING = 3

local function safeDebug(message, ...)
    local addon = rawget(_G, addonName)
    local debugFn = addon and addon.Debug

    if type(debugFn) ~= "function" then
        return
    end

    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, message, ...)
        if ok then
            debugFn(formatted)
            return
        end
    end

    debugFn(message)
end

local function formatText(value)
    if value == nil then
        return ""
    end

    if type(value) ~= "string" then
        local ok, coerced = pcall(tostring, value)
        if ok and coerced ~= nil then
            value = coerced
        end
    end

    return value or ""
end

local function anchorRow(self, row, parent)
    if not row or not parent then
        return
    end

    row:ClearAnchors()

    local previous = self.rows[#self.rows]
    if previous then
        row:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, ROW_VERTICAL_PADDING)
        row:SetAnchor(TOPRIGHT, previous, BOTTOMRIGHT, 0, ROW_VERTICAL_PADDING)
    else
        row:SetAnchor(TOPLEFT, parent, TOPLEFT, 0, 0)
        row:SetAnchor(TOPRIGHT, parent, TOPRIGHT, 0, 0)
    end
end

local function createLabel(name, parent, alignment)
    local label = CreateControl(name, parent, CT_LABEL)
    label:SetHidden(false)
    label:SetHorizontalAlignment(alignment or TEXT_ALIGN_LEFT)
    label:SetVerticalAlignment(TEXT_ALIGN_TOP)
    label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    return label
end

function Rows:CreateRow(parent, index)
    if not parent then
        safeDebug("%s: CreateRow aborted (missing parent)", MODULE_TAG)
        return nil
    end

    self.rows = self.rows or {}

    local rowName = string.format("%s_AchievementRow_%d", parent.GetName and parent:GetName() or MODULE_TAG, index or (#self.rows + 1))
    local row = CreateControl(rowName, parent, CT_CONTROL)
    row:SetHidden(false)
    row:SetMouseEnabled(false)
    row:SetHeight(ROW_HEIGHT)

    row.icon = CreateControl(rowName .. "_Icon", row, CT_TEXTURE)
    row.icon:SetDimensions(ICON_SIZE, ICON_SIZE)
    row.icon:SetAnchor(TOPLEFT, row, TOPLEFT, 0, ICON_Y_OFFSET)
    row.icon:SetHidden(true)

    row.label = createLabel(rowName .. "_Label", row)
    row.label:SetAnchor(TOPLEFT, row.icon, TOPRIGHT, LABEL_PADDING_X, 0)

    row.progressLabel = createLabel(rowName .. "_Progress", row, TEXT_ALIGN_RIGHT)
    row.progressLabel:SetAnchor(TOPRIGHT, row, TOPRIGHT, 0, 0)
    row.label:SetAnchor(TOPRIGHT, row.progressLabel, TOPLEFT, -LABEL_PADDING_X, 0)

    row.currentIndent = 0

    anchorRow(self, row, parent)

    self.rows[#self.rows + 1] = row

    return row
end

function Rows:ApplyRowData(row, favoriteData)
    if not row then
        return
    end

    if favoriteData == nil then
        row:SetHidden(true)
        return
    end

    local icon = favoriteData.icon or favoriteData.iconTexture
    if row.icon then
        row.icon:SetHidden(icon == nil)
        if icon then
            row.icon:SetTexture(icon)
        else
            row.icon:SetTexture(nil)
        end
    end

    if row.label then
        row.label:SetText(formatText(favoriteData.name))
    end

    if row.progressLabel then
        row.progressLabel:SetText(formatText(favoriteData.progressText))
    end

    row:SetHidden(false)
end

function Rows:ReleaseAll()
    if not self.rows then
        return
    end

    for index = #self.rows, 1, -1 do
        local row = table.remove(self.rows, index)
        if row then
            row:SetHidden(true)
            if DestroyControl then
                DestroyControl(row)
            end
        end
    end
end

Rows.rows = Rows.rows or {}

Nvk3UT.AchievementTrackerRows = Rows

return Rows
