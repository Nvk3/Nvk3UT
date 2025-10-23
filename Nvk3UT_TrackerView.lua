Nvk3UT = Nvk3UT or {}

local M = Nvk3UT

M.QuestTrackerView = M.QuestTrackerView or {}
local Module = M.QuestTrackerView

local WM = WINDOW_MANAGER

local CATEGORY_TEMPLATE = "Nvk3UT_QuestTrackerCategoryTemplate"
local HEADER_TEMPLATE = "Nvk3UT_QuestTrackerHeaderTemplate"
local CONDITION_TEMPLATE = "Nvk3UT_QuestTrackerConditionTemplate"

local CARET_OPEN = "EsoUI/Art/Buttons/tree_open_up.dds"
local CARET_CLOSED = "EsoUI/Art/Buttons/tree_closed_up.dds"

local CATEGORY_HEIGHT = 28
local HEADER_HEIGHT = 32
local CONDITION_HEIGHT = 26
local PADDING = 6
local CONTENT_PADDING_X = 8
local QUEST_INDENT = 24
local CONDITION_INDENT = 48

Module._root = Module._root or nil
Module._scroll = Module._scroll or nil
Module._scrollChild = Module._scrollChild or nil
Module._categoryPool = Module._categoryPool or nil
Module._headerPool = Module._headerPool or nil
Module._conditionPool = Module._conditionPool or nil
Module._activeCategories = Module._activeCategories or {}
Module._activeHeaders = Module._activeHeaders or {}
Module._activeConditions = Module._activeConditions or {}
Module._questCollapse = Module._questCollapse or {}
Module._categoryCollapse = Module._categoryCollapse or {}
Module._tooltipsEnabled = Module._tooltipsEnabled or true
Module._autoGrowV = Module._autoGrowV or true
Module._autoGrowH = Module._autoGrowH or false
Module._autoExpand = Module._autoExpand or true
Module._questHashes = Module._questHashes or {}
Module._categoryHashes = Module._categoryHashes or {}
Module._categoryLookup = Module._categoryLookup or nil
Module._typeToCategory = Module._typeToCategory or nil
Module._defaultCategoryId = Module._defaultCategoryId or nil

local RAW_CATEGORY_DEFINITIONS = {
    {
        id = "main",
        order = 10,
        stringIds = { "SI_QUEST_JOURNAL_CATEGORY_MAIN_STORY", "SI_QUESTTYPE5" },
        fallback = "Main Story",
        types = { "QUEST_TYPE_MAIN_STORY" },
    },
    {
        id = "zone",
        order = 20,
        stringIds = { "SI_QUEST_JOURNAL_CATEGORY_ZONE_STORY", "SI_QUESTTYPE4" },
        fallback = "Zone Story",
        types = {
            "QUEST_TYPE_ZONE_STORY",
            "QUEST_TYPE_CLASS",
            "QUEST_TYPE_COMPANION",
            "QUEST_TYPE_PROLOGUE",
            "QUEST_TYPE_HERALDRY",
            "QUEST_TYPE_HOUSING",
            "QUEST_TYPE_RELIC",
        },
    },
    {
        id = "guild",
        order = 30,
        stringIds = { "SI_QUEST_JOURNAL_CATEGORY_GUILD", "SI_QUESTTYPE6" },
        fallback = "Guild",
        types = { "QUEST_TYPE_GUILD" },
    },
    {
        id = "crafting",
        order = 40,
        stringIds = { "SI_QUEST_JOURNAL_CATEGORY_CRAFTING", "SI_QUESTTYPE8" },
        fallback = "Crafting",
        types = { "QUEST_TYPE_CRAFTING" },
    },
    {
        id = "dungeon",
        order = 50,
        stringIds = { "SI_QUEST_JOURNAL_CATEGORY_DUNGEON", "SI_QUESTTYPE2" },
        fallback = "Dungeon",
        types = { "QUEST_TYPE_DUNGEON", "QUEST_TYPE_RAID", "QUEST_TYPE_UNDAUNTED" },
    },
    {
        id = "alliance",
        order = 60,
        stringIds = { "SI_QUEST_JOURNAL_CATEGORY_ALLIANCE_WAR", "SI_QUESTTYPE3" },
        fallback = "Alliance War",
        types = { "QUEST_TYPE_AVA", "QUEST_TYPE_AVA_GROUP", "QUEST_TYPE_AVA_GRAND", "QUEST_TYPE_BATTLEFIELD" },
    },
    {
        id = "holiday",
        order = 70,
        stringIds = { "SI_QUEST_JOURNAL_CATEGORY_HOLIDAY_EVENT" },
        fallback = "Holiday Events",
        types = { "QUEST_TYPE_HOLIDAY_EVENT" },
    },
    {
        id = "repeatable",
        order = 80,
        stringIds = { "SI_QUEST_JOURNAL_CATEGORY_REPEATABLE", "SI_QUESTTYPE7" },
        fallback = "Repeatable",
        types = { "QUEST_TYPE_REPEATABLE", "QUEST_TYPE_DAILY", "QUEST_TYPE_WEEKLY" },
    },
    {
        id = "misc",
        order = 90,
        stringIds = { "SI_QUEST_JOURNAL_CATEGORY_MISC", "SI_QUESTTYPE1" },
        fallback = "Miscellaneous",
        types = { "QUEST_TYPE_NONE", "QUEST_TYPE_MISCELLANEOUS", "default" },
    },
}

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

local function getStringSafe(idName)
    if not idName or idName == "" then
        return nil
    end

    local stringId = rawget(_G, idName)
    if not stringId then
        return nil
    end

    if not GetString then
        return nil
    end

    local ok, value = pcall(GetString, stringId)
    if ok and value and value ~= "" then
        return value
    end

    return nil
end

local function resolveCategoryDefinitions()
    if Module._categoryLookup and Module._typeToCategory and Module._defaultCategoryId then
        return
    end

    Module._categoryLookup = {}
    Module._typeToCategory = {}
    Module._defaultCategoryId = "misc"

    for index = 1, #RAW_CATEGORY_DEFINITIONS do
        local def = RAW_CATEGORY_DEFINITIONS[index]
        local label = nil

        if def.stringIds then
            for strIdx = 1, #def.stringIds do
                label = getStringSafe(def.stringIds[strIdx])
                if label and label ~= "" then
                    break
                end
            end
        end

        if not label or label == "" then
            label = def.fallback or def.id
        end

        Module._categoryLookup[def.id] = {
            id = def.id,
            order = def.order or (index * 10),
            label = label,
            types = {},
        }

        if def.types then
            for typeIndex = 1, #def.types do
                local typeName = def.types[typeIndex]
                if typeName == "default" then
                    Module._defaultCategoryId = def.id
                else
                    local questType = rawget(_G, typeName)
                    if questType ~= nil then
                        Module._typeToCategory[questType] = def.id
                        table.insert(Module._categoryLookup[def.id].types, questType)
                    end
                end
            end
        end
    end
end

local function getCategoryInfo(questType)
    resolveCategoryDefinitions()

    local categoryId = Module._typeToCategory[questType]
    if not categoryId then
        categoryId = Module._defaultCategoryId
    end

    return Module._categoryLookup[categoryId]
end

local function getOrderedCategories()
    resolveCategoryDefinitions()

    if Module._orderedCategories then
        return Module._orderedCategories
    end

    Module._orderedCategories = {}

    for _, info in pairs(Module._categoryLookup) do
        Module._orderedCategories[#Module._orderedCategories + 1] = info
    end

    table.sort(Module._orderedCategories, function(a, b)
        return a.order < b.order
    end)

    return Module._orderedCategories
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

    local steps = quest.steps or {}
    for stepIndex = 1, #steps do
        local step = steps[stepIndex]
        local conditions = (step and step.conditions) or {}
        for condIndex = 1, #conditions do
            local condition = conditions[condIndex]
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

local function getQuestCollapseKey(journalIndex)
    return tostring(journalIndex)
end

local function isQuestCollapsed(view, journalIndex)
    if not view._questCollapse then
        return false
    end

    return view._questCollapse[getQuestCollapseKey(journalIndex)] == true
end

local function setQuestCollapsed(view, journalIndex, collapsed)
    view._questCollapse = view._questCollapse or {}
    view._questCollapse[getQuestCollapseKey(journalIndex)] = collapsed == true

    if M.QuestTracker then
        if M.QuestTracker.SetQuestCollapseState then
            M.QuestTracker.SetQuestCollapseState(journalIndex, collapsed == true)
        elseif M.QuestTracker.SetCollapseState then
            M.QuestTracker.SetCollapseState(journalIndex, collapsed == true)
        end
    end
end

local function toggleQuestCollapsed(view, journalIndex)
    local collapsed = not isQuestCollapsed(view, journalIndex)
    setQuestCollapsed(view, journalIndex, collapsed)
    view:Refresh(view._lastSnapshot or { quests = {} }, {
        collapse = {
            quests = view._questCollapse,
            categories = view._categoryCollapse,
        },
        autoGrowV = view._autoGrowV,
        autoGrowH = view._autoGrowH,
        autoExpand = view._autoExpand,
        tooltips = view._tooltipsEnabled,
    })
end

local function isCategoryCollapsed(view, categoryId)
    if not view._categoryCollapse then
        return false
    end

    return view._categoryCollapse[categoryId] == true
end

local function setCategoryCollapsed(view, categoryId, collapsed)
    view._categoryCollapse = view._categoryCollapse or {}
    view._categoryCollapse[categoryId] = collapsed == true

    if M.QuestTracker and M.QuestTracker.SetCategoryCollapseState then
        M.QuestTracker.SetCategoryCollapseState(categoryId, collapsed == true)
    end
end

local function toggleCategoryCollapsed(view, categoryId)
    local collapsed = not isCategoryCollapsed(view, categoryId)
    setCategoryCollapsed(view, categoryId, collapsed)
    view:Refresh(view._lastSnapshot or { quests = {} }, {
        collapse = {
            quests = view._questCollapse,
            categories = view._categoryCollapse,
        },
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

    local steps = quest.steps or {}
    for stepIndex = 1, #steps do
        local step = steps[stepIndex]
        if step.stepText and step.stepText ~= "" then
            lines[#lines + 1] = string.format("  %s", step.stepText)
        end
        local conditions = (step and step.conditions) or {}
        for condIndex = 1, #conditions do
            local condition = conditions[condIndex]
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

local function configureQuestHeader(view, control, quest, collapsed)
    local caret = control.caret or control:GetNamedChild("Caret")
    local label = control.label or control:GetNamedChild("Label")
    local progress = control.progress or control:GetNamedChild("Progress")

    control.caret = caret
    control.label = label
    control.progress = progress

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
                toggleQuestCollapsed(view, control.data.journalIndex)
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

local function configureCategoryHeader(view, control, categoryInfo, count, collapsed)
    local caret = control.caret or control:GetNamedChild("Caret")
    local label = control.label or control:GetNamedChild("Label")
    local countLabel = control.count or control:GetNamedChild("Count")

    control.caret = caret
    control.label = label
    control.count = countLabel

    if not control._initialized then
        control._initialized = true
        control:SetHandler("OnMouseUp", function(_, button, upInside)
            if not upInside then
                return
            end

            if button == MOUSE_BUTTON_INDEX_LEFT then
                toggleCategoryCollapsed(view, control.data.id)
            end
        end)
    end

    control:SetHeight(CATEGORY_HEIGHT)
    control.data = {
        id = categoryInfo.id,
        label = categoryInfo.label,
        count = count,
    }

    if caret then
        caret:SetTexture(collapsed and CARET_CLOSED or CARET_OPEN)
    end

    if label then
        label:SetText(categoryInfo.label)
    end

    if countLabel then
        countLabel:SetText(count or 0)
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
    if not view._categoryPool then
        view._categoryPool = ZO_ControlPool:New(CATEGORY_TEMPLATE, view._scrollChild, "Category")
    end

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
    local scrollLeft = view._scrollChild:GetLeft()
    for index = 1, childCount do
        local control = view._scrollChild:GetChild(index)
        if control and control:IsHidden() == false then
            local controlRight = control:GetRight()
            if scrollLeft and controlRight then
                width = math.max(width, controlRight - scrollLeft)
            end
        end
    end
    return width
end

local function applyAutoGrow(view, contentHeight)
    if not view._root then
        return
    end

    if view._autoGrowV then
        local targetHeight = contentHeight and contentHeight > 0 and (contentHeight + PADDING * 2) or view._root:GetHeight()
        view._root:SetHeight(targetHeight)
    end

    if view._autoGrowH then
        local contentWidth = computeContentWidth(view)
        if contentWidth > 0 then
            view._root:SetWidth(contentWidth + CONTENT_PADDING_X)
        end
    end
end

function Module:Init(rootControl, opts)
    self._root = rootControl
    if opts and opts.collapse then
        self._questCollapse = opts.collapse.quests or {}
        self._categoryCollapse = opts.collapse.categories or {}
    else
        self._questCollapse = self._questCollapse or {}
        self._categoryCollapse = self._categoryCollapse or {}
    end
    self._tooltipsEnabled = opts and opts.tooltips ~= false
    self._autoGrowV = opts and opts.autoGrowV ~= false
    self._autoGrowH = opts and opts.autoGrowH == true
    self._autoExpand = opts and opts.autoExpand ~= false
    self._lastContentHeight = 0

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
    applyAutoGrow(self, self._lastContentHeight)
end

local function anchorControl(view, control, offsetY, inset)
    local leftOffset = inset or CONTENT_PADDING_X
    control:ClearAnchors()
    control:SetAnchor(TOPLEFT, view._scrollChild, TOPLEFT, leftOffset, offsetY)
    control:SetAnchor(TOPRIGHT, view._scrollChild, TOPRIGHT, -CONTENT_PADDING_X, offsetY)
end

function Module:Refresh(snapshot, opts)
    self._lastSnapshot = snapshot
    if opts and opts.collapse then
        self._questCollapse = opts.collapse.quests or self._questCollapse or {}
        self._categoryCollapse = opts.collapse.categories or self._categoryCollapse or {}
    end
    self._autoGrowV = opts and opts.autoGrowV ~= false
    self._autoGrowH = opts and opts.autoGrowH == true
    self._autoExpand = opts and opts.autoExpand ~= false
    self._tooltipsEnabled = opts and opts.tooltips ~= false

    ensurePools(self)

    releaseControls(self._categoryPool, self._activeCategories)
    releaseControls(self._headerPool, self._activeHeaders)
    releaseControls(self._conditionPool, self._activeConditions)

    local quests = snapshot and snapshot.quests or {}

    local cursorY = PADDING

    local categoryBuckets = {}
    local categoryHashes = {}
    local seenQuests = {}

    local orderedCategories = getOrderedCategories()
    for index = 1, #orderedCategories do
        local categoryInfo = orderedCategories[index]
        categoryBuckets[categoryInfo.id] = {
            info = categoryInfo,
            quests = {},
        }
        categoryHashes[categoryInfo.id] = {}
    end

    for questIndex = 1, #quests do
        local quest = quests[questIndex]
        quest.name = sanitizeText(quest.name)
        quest.zoneName = sanitizeText(quest.zoneName)

        local hash = computeQuestHash(quest)
        local previousHash = self._questHashes[quest.journalIndex]

        if self._autoExpand and (not previousHash or previousHash ~= hash) then
            setQuestCollapsed(self, quest.journalIndex, false)
            local categoryInfo = getCategoryInfo(quest.questType)
            if categoryInfo then
                setCategoryCollapsed(self, categoryInfo.id, false)
            end
        end

        self._questHashes[quest.journalIndex] = hash
        seenQuests[quest.journalIndex] = true

        local categoryInfo = getCategoryInfo(quest.questType)
        local bucket = categoryBuckets[categoryInfo.id]
        bucket.quests[#bucket.quests + 1] = quest
        categoryHashes[categoryInfo.id][#categoryHashes[categoryInfo.id] + 1] = hash
    end

    for questId in pairs(self._questHashes) do
        if not seenQuests[tonumber(questId)] and not seenQuests[questId] then
            self._questHashes[questId] = nil
        end
    end

    for categoryId, hashes in pairs(categoryHashes) do
        local joined = table.concat(hashes, "|")
        self._categoryHashes[categoryId] = joined
    end

    local function sortQuestsForBucket(bucket)
        table.sort(bucket.quests, function(a, b)
            if a.isAssisted ~= b.isAssisted then
                return a.isAssisted
            end

            if a.isTracked ~= b.isTracked then
                return a.isTracked and not b.isTracked
            end

            if a.zoneName ~= b.zoneName then
                return a.zoneName < b.zoneName
            end

            if a.name ~= b.name then
                return a.name < b.name
            end

            return a.journalIndex < b.journalIndex
        end)
    end

    for index = 1, #orderedCategories do
        local categoryInfo = orderedCategories[index]
        local bucket = categoryBuckets[categoryInfo.id]
        if bucket and #bucket.quests > 0 then
            sortQuestsForBucket(bucket)

            local collapsed = isCategoryCollapsed(self, categoryInfo.id)
            local categoryControl = self._categoryPool:AcquireObject()
            categoryControl:SetHidden(false)
            configureCategoryHeader(self, categoryControl, categoryInfo, #bucket.quests, collapsed)
            table.insert(self._activeCategories, categoryControl)
            anchorControl(self, categoryControl, cursorY, CONTENT_PADDING_X)
            cursorY = cursorY + categoryControl:GetHeight()

            if not collapsed then
                for questIndex = 1, #bucket.quests do
                    local quest = bucket.quests[questIndex]
                    local questCollapsed = isQuestCollapsed(self, quest.journalIndex)
                    local headerControl = self._headerPool:AcquireObject()
                    headerControl:SetHidden(false)
                    table.insert(self._activeHeaders, headerControl)

                    configureQuestHeader(self, headerControl, quest, questCollapsed)
                    anchorControl(self, headerControl, cursorY, CONTENT_PADDING_X + QUEST_INDENT)
                    cursorY = cursorY + headerControl:GetHeight()

                    if not questCollapsed then
                        local steps = quest.steps or {}
                        for stepIndex = 1, #steps do
                            local step = steps[stepIndex]
                            local conditions = (step and step.conditions) or {}
                            for condIndex = 1, #conditions do
                                local condition = conditions[condIndex]
                                local condControl = self._conditionPool:AcquireObject()
                                condControl:SetHidden(false)
                                table.insert(self._activeConditions, condControl)

                                configureCondition(self, condControl, quest, condition)
                                anchorControl(self, condControl, cursorY, CONTENT_PADDING_X + CONDITION_INDENT)
                                cursorY = cursorY + condControl:GetHeight()
                            end
                        end
                    end
                end
            end
        end
    end

    local contentHeight = cursorY - PADDING
    self._lastContentHeight = contentHeight
    applyAutoGrow(self, contentHeight)

    if contentHeight > 0 then
        self._scrollChild:SetHeight(cursorY + PADDING)
    else
        self._scrollChild:SetHeight(self._root:GetHeight())
    end
end

function Module:Dispose()
    releaseControls(self._categoryPool, self._activeCategories)
    releaseControls(self._headerPool, self._activeHeaders)
    releaseControls(self._conditionPool, self._activeConditions)

    if self._categoryPool then
        self._categoryPool:Reset()
    end

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

function Module:GetRootControl()
    return self._root
end

