Nvk3UT = Nvk3UT or {}

local M = Nvk3UT

M.QuestTrackerView = M.QuestTrackerView or {}
local Module = M.QuestTrackerView

local WM = WINDOW_MANAGER

local HEADER_TEMPLATE = "Nvk3UT_QuestTrackerHeaderTemplate"
local CONDITION_TEMPLATE = "Nvk3UT_QuestTrackerConditionTemplate"

local CARET_OPEN = "EsoUI/Art/Buttons/tree_open_up.dds"
local CARET_CLOSED = "EsoUI/Art/Buttons/tree_closed_up.dds"

local HEADER_HEIGHT = 32
local CONDITION_HEIGHT = 26
local PADDING = 6
local CONTENT_PADDING_X = 8

Module._root = Module._root or nil
Module._scroll = Module._scroll or nil
Module._scrollChild = Module._scrollChild or nil
Module._headerPool = Module._headerPool or nil
Module._conditionPool = Module._conditionPool or nil
Module._activeHeaders = Module._activeHeaders or {}
Module._activeConditions = Module._activeConditions or {}
Module._collapse = Module._collapse or {}
Module._tooltipsEnabled = Module._tooltipsEnabled or true
Module._autoGrowV = Module._autoGrowV or true
Module._autoGrowH = Module._autoGrowH or false
Module._autoExpand = Module._autoExpand or true
Module._questHashes = Module._questHashes or {}

local function debugLog(message)
    if not (M.QuestTracker and M.QuestTracker._sv and M.QuestTracker._sv.debug) then
        return
    end

    if d then
        d(string.format("[Nvk3UT] QuestTrackerView: %s", tostring(message)))
    end
end

local function sanitizeText(text)
    if text == nil or text == "" then
        return ""
    end

    if zo_strformat then
        local ok, formatted = pcall(zo_strformat, "<<1>>", text)
        if ok and formatted then
            return formatted
        end
    end

    return text
end

local function conditionProgressText(condition)
    if condition.cur and condition.max and condition.max > 0 then
        return string.format("%d/%d", condition.cur, condition.max)
    end

    return ""
end

local function computeQuestProgress(quest)
    local total = 0
    local complete = 0

    for stepIndex = 1, #quest.steps do
        local step = quest.steps[stepIndex]
        for condIndex = 1, #step.conditions do
            local condition = step.conditions[condIndex]
            total = total + 1
            if condition.isComplete then
                complete = complete + 1
            end
        end
    end

    if total == 0 then
        return ""
    end

    return string.format("%d/%d", complete, total)
end

local function computeQuestHash(quest)
    local parts = {
        tostring(quest.journalIndex or ""),
        quest.name or "",
        tostring(quest.isTracked),
        tostring(quest.isAssisted),
    }

    for stepIndex = 1, #quest.steps do
        local step = quest.steps[stepIndex]
        parts[#parts + 1] = tostring(step.stepText)
        parts[#parts + 1] = tostring(step.isComplete)
        for condIndex = 1, #step.conditions do
            local condition = step.conditions[condIndex]
            parts[#parts + 1] = tostring(condition.text)
            parts[#parts + 1] = tostring(condition.cur or "")
            parts[#parts + 1] = tostring(condition.max or "")
        end
    end

    return table.concat(parts, "|")
end

local function getCollapseKey(journalIndex)
    return tostring(journalIndex)
end

local function isCollapsed(view, journalIndex)
    local key = getCollapseKey(journalIndex)
    if view._collapse then
        return view._collapse[key] == true
    end
    return false
end

local function setCollapsed(view, journalIndex, collapsed)
    if not view._collapse then
        return
    end

    view._collapse[getCollapseKey(journalIndex)] = collapsed == true

    if M.QuestTracker and M.QuestTracker.SetCollapseState then
        M.QuestTracker.SetCollapseState(journalIndex, collapsed == true)
    end
end

local function toggleCollapsed(view, journalIndex)
    local collapsed = not isCollapsed(view, journalIndex)
    setCollapsed(view, journalIndex, collapsed)
    view:Refresh(view._lastSnapshot or { quests = {} }, {
        collapse = view._collapse,
        autoGrowV = view._autoGrowV,
        autoGrowH = view._autoGrowH,
        autoExpand = view._autoExpand,
        tooltips = view._tooltipsEnabled,
    })
end

local function releaseControls(pool, active)
    if not pool then
        return
    end

    for _, control in ipairs(active) do
        pool:ReleaseObject(control)
    end

    ZO_ClearNumericallyIndexedTable(active)
end

local function addMenuItem(label, callback)
    if not label or label == "" or type(callback) ~= "function" then
        return
    end

    AddMenuItem(label, callback)
end

local function showQuestOnMap(journalIndex)
    if type(journalIndex) ~= "number" then
        return
    end

    if ZO_WorldMap_ShowQuestOnMap then
        ZO_WorldMap_ShowQuestOnMap(journalIndex)
    elseif ZO_QuestTracker_ShowOnMap then
        ZO_QuestTracker_ShowOnMap(journalIndex)
    else
        if SetTrackedIsAssisted then
            SetTrackedIsAssisted(journalIndex)
        end
        if ZO_WorldMap_ShowWorldMap then
            ZO_WorldMap_ShowWorldMap()
        end
    end
end

local function openQuestContextMenu(view, quest)
    if not quest then
        return
    end

    ClearMenu()

    if quest.isAssisted then
        addMenuItem(GetString(SI_QUEST_TRACKER_MENU_STOP_TRACK), function()
            if SetTrackedIsAssisted then
                SetTrackedIsAssisted(0)
            end
        end)
    else
        addMenuItem(GetString(SI_QUEST_TRACKER_MENU_SET_FOCUS), function()
            if SetTrackedIsAssisted then
                SetTrackedIsAssisted(quest.journalIndex)
            end
        end)
    end

    addMenuItem(GetString(SI_QUEST_TRACKER_MENU_UNTRACK), function()
        if SetJournalQuestTracked then
            SetJournalQuestTracked(quest.journalIndex, false)
        elseif ToggleJournalQuestTracked then
            ToggleJournalQuestTracked(quest.journalIndex)
        end
    end)

    addMenuItem(GetString(SI_QUEST_TRACKER_MENU_SHOW_ON_MAP), function()
        showQuestOnMap(quest.journalIndex)
    end)

    ShowMenu(view._root)
end

local function questTooltipLines(quest)
    local lines = {}
    lines[#lines + 1] = quest.name
    if quest.zoneName and quest.zoneName ~= "" then
        lines[#lines + 1] = quest.zoneName
    end

    for stepIndex = 1, #quest.steps do
        local step = quest.steps[stepIndex]
        if step.stepText and step.stepText ~= "" then
            lines[#lines + 1] = string.format("  %s", step.stepText)
        end
        for condIndex = 1, #step.conditions do
            local condition = step.conditions[condIndex]
            local progress = conditionProgressText(condition)
            if progress ~= "" then
                lines[#lines + 1] = string.format("    • %s (%s)", condition.text, progress)
            else
                lines[#lines + 1] = string.format("    • %s", condition.text)
            end
        end
    end

    return lines
end

local function showTooltip(view, control, quest)
    if not view._tooltipsEnabled or not InformationTooltip then
        return
    end

    InitializeTooltip(InformationTooltip, control, LEFT, -16, 0, RIGHT)
    InformationTooltip:ClearLines()

    local lines = questTooltipLines(quest)
    for index = 1, #lines do
        InformationTooltip:AddLine(lines[index])
    end
end

local function hideTooltip()
    if InformationTooltip then
        ClearTooltip(InformationTooltip)
    end
end

local function configureHeader(view, control, quest, collapsed)
    local caret = control.caret or control:GetNamedChild("Caret")
    local label = control.label or control:GetNamedChild("Label")
    local progress = control.progress or control:GetNamedChild("Progress")

    if not control._initialized then
        control._initialized = true
        control:SetHandler("OnMouseEnter", function()
            showTooltip(view, control, control.data)
        end)
        control:SetHandler("OnMouseExit", hideTooltip)
        control:SetHandler("OnMouseUp", function(_, button, upInside)
            if not upInside then
                return
            end
            if button == MOUSE_BUTTON_INDEX_LEFT then
                toggleCollapsed(view, control.data.journalIndex)
            elseif button == MOUSE_BUTTON_INDEX_RIGHT then
                openQuestContextMenu(view, control.data)
            end
        end)
    end

    control:SetHeight(HEADER_HEIGHT)
    control.data = quest

    if caret then
        caret:SetTexture(collapsed and CARET_CLOSED or CARET_OPEN)
    end

    if label then
        label:SetText(quest.name)
    end

    if progress then
        progress:SetText(computeQuestProgress(quest))
    end
end

local function configureCondition(view, control, quest, condition)
    local label = control.label or control:GetNamedChild("Label")
    local progress = control.progress or control:GetNamedChild("Progress")

    if not control._initialized then
        control._initialized = true
        control:SetHandler("OnMouseEnter", function()
            showTooltip(view, control, quest)
        end)
        control:SetHandler("OnMouseExit", hideTooltip)
    end

    control:SetHeight(CONDITION_HEIGHT)

    if label then
        label:SetText(string.format("• %s", condition.text))
    end

    if progress then
        progress:SetText(conditionProgressText(condition))
    end
end

local function ensurePools(view)
    if not view._headerPool then
        view._headerPool = ZO_ControlPool:New(HEADER_TEMPLATE, view._scrollChild, "Header")
    end

    if not view._conditionPool then
        view._conditionPool = ZO_ControlPool:New(CONDITION_TEMPLATE, view._scrollChild, "Condition")
    end
end

local function computeContentWidth(view)
    local width = 0
    local childCount = view._scrollChild:GetNumChildren()
    for index = 1, childCount do
        local control = view._scrollChild:GetChild(index)
        if control and control:IsHidden() == false then
            width = math.max(width, control:GetRight() - control:GetLeft())
        end
    end
    return width
end

local function applyAutoGrow(view)
    if not view._root then
        return
    end

    local height = 0
    local childCount = view._scrollChild:GetNumChildren()
    for index = 1, childCount do
        local control = view._scrollChild:GetChild(index)
        if control and control:IsHidden() == false then
            height = math.max(height, control:GetTop() + control:GetHeight())
        end
    end

    if view._autoGrowV then
        local targetHeight = height > 0 and (height + PADDING * 2) or view._root:GetHeight()
        view._root:SetHeight(targetHeight)
    end

    if view._autoGrowH then
        local contentWidth = computeContentWidth(view)
        if contentWidth > 0 then
            view._root:SetWidth(contentWidth + CONTENT_PADDING_X * 2)
        end
    end
end

function Module:Init(rootControl, opts)
    self._root = rootControl
    self._collapse = opts and opts.collapse or {}
    self._tooltipsEnabled = opts and opts.tooltips ~= false
    self._autoGrowV = opts and opts.autoGrowV ~= false
    self._autoGrowH = opts and opts.autoGrowH == true
    self._autoExpand = opts and opts.autoExpand ~= false

    self._scroll = WM:CreateControlFromVirtual("Nvk3UT_QuestTrackerScroll", rootControl, "ZO_ScrollContainer")
    self._scroll:SetAnchorFill(rootControl)
    self._scroll:SetHidden(false)

    self._scrollChild = self._scroll:GetNamedChild("ScrollChild")
    self._scrollChild:ClearAnchors()
    self._scrollChild:SetAnchor(TOPLEFT, self._scroll, TOPLEFT, 0, 0)
    self._scrollChild:SetAnchor(TOPRIGHT, self._scroll, TOPRIGHT, 0, 0)

    ensurePools(self)
end

function Module:SetTooltipsEnabled(flag)
    self._tooltipsEnabled = flag ~= false
end

function Module:ApplyAutoGrow(autoGrowV, autoGrowH)
    self._autoGrowV = autoGrowV ~= false
    self._autoGrowH = autoGrowH == true
    applyAutoGrow(self)
end

local function anchorControls(view, previous, control)
    control:ClearAnchors()
    if previous then
        control:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, 0)
        control:SetAnchor(TOPRIGHT, previous, BOTTOMRIGHT, 0, 0)
    else
        control:SetAnchor(TOPLEFT, view._scrollChild, TOPLEFT, CONTENT_PADDING_X, PADDING)
        control:SetAnchor(TOPRIGHT, view._scrollChild, TOPRIGHT, -CONTENT_PADDING_X, PADDING)
    end
end

function Module:Refresh(snapshot, opts)
    self._lastSnapshot = snapshot
    self._collapse = opts and opts.collapse or self._collapse or {}
    self._autoGrowV = opts and opts.autoGrowV ~= false
    self._autoGrowH = opts and opts.autoGrowH == true
    self._autoExpand = opts and opts.autoExpand ~= false
    self._tooltipsEnabled = opts and opts.tooltips ~= false

    ensurePools(self)

    releaseControls(self._headerPool, self._activeHeaders)
    releaseControls(self._conditionPool, self._activeConditions)

    local previousControl = nil

    local quests = snapshot and snapshot.quests or {}

    for questIndex = 1, #quests do
        local quest = quests[questIndex]
        quest.name = sanitizeText(quest.name)
        quest.zoneName = sanitizeText(quest.zoneName)

        local hash = computeQuestHash(quest)
        local wasKnown = self._questHashes[quest.journalIndex]

        if self._autoExpand and wasKnown and wasKnown ~= hash then
            setCollapsed(self, quest.journalIndex, false)
        elseif self._autoExpand and not wasKnown then
            setCollapsed(self, quest.journalIndex, false)
        end

        self._questHashes[quest.journalIndex] = hash

        local headerControl = self._headerPool:AcquireObject()
        table.insert(self._activeHeaders, headerControl)

        headerControl.data = quest
        headerControl:SetHidden(false)

        anchorControls(self, previousControl, headerControl)
        configureHeader(self, headerControl, quest, isCollapsed(self, quest.journalIndex))

        previousControl = headerControl

        if not isCollapsed(self, quest.journalIndex) then
            for stepIndex = 1, #quest.steps do
                local step = quest.steps[stepIndex]
                for condIndex = 1, #step.conditions do
                    local condition = step.conditions[condIndex]

                    local condControl = self._conditionPool:AcquireObject()
                    table.insert(self._activeConditions, condControl)

                    condControl:SetHidden(false)
                    anchorControls(self, previousControl, condControl)
                    configureCondition(self, condControl, quest, condition)
                    previousControl = condControl
                end
            end
        end
    end

    applyAutoGrow(self)

    if previousControl then
        local bottom = previousControl:GetTop() + previousControl:GetHeight()
        self._scrollChild:SetHeight(bottom + PADDING)
    else
        self._scrollChild:SetHeight(self._root:GetHeight())
    end
end

function Module:Dispose()
    releaseControls(self._headerPool, self._activeHeaders)
    releaseControls(self._conditionPool, self._activeConditions)

    if self._headerPool then
        self._headerPool:Reset()
    end

    if self._conditionPool then
        self._conditionPool:Reset()
    end

    if self._scroll then
        self._scroll:SetHidden(true)
    end

    hideTooltip()
end

