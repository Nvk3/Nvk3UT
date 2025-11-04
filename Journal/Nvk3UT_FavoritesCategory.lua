Nvk3UT = Nvk3UT or {}

local Category = {}
Nvk3UT.FavoritesCategory = Category

local Diagnostics = Nvk3UT and Nvk3UT.Diagnostics
local Utils = Nvk3UT and Nvk3UT.Utils
local Data = Nvk3UT and Nvk3UT.FavoritesData

local state = {
    parent = nil,
    host = nil,
    container = nil,
    scrollChild = nil,
    rowPool = nil,
    visible = true,
    hasEntries = false,
    rowOrder = {},
    rowByAchievementId = {},
    sortedIds = {},
    sortedLookup = {},
    achievementCache = {},
    pendingRowUpdateIds = {},
    pendingRowUpdateLookup = {},
    batchCallId = nil,
}

local ROW_HEIGHT = 36
local ROW_ICON_SIZE = 28
local ROW_ICON_OFFSET_X = 6
local ROW_ICON_OFFSET_Y = 4
local ROW_LABEL_OFFSET_X = 12
local ROW_SPACING = 4
local ROW_BATCH_SIZE = 6
local DEFAULT_MAX_VISIBLE = 20
local SCROLL_CONTROL_NAME = "Nvk3UT_FavoritesScroll"

local tableUnpack = table.unpack or unpack

local function safeCall(func, ...)
    local SafeCall = Nvk3UT and Nvk3UT.SafeCall
    if type(SafeCall) == "function" then
        return SafeCall(func, ...)
    end

    if type(func) ~= "function" then
        return nil
    end

    local results = { pcall(func, ...) }
    if not results[1] then
        return nil
    end

    table.remove(results, 1)
    return tableUnpack(results)
end

local function ensureData()
    if Data and Data.InitSavedVars then
        safeCall(Data.InitSavedVars)
    end
end

local function logShim(action)
    if Diagnostics and Diagnostics.Debug then
        Diagnostics.Debug("Favorites SHIM -> %s", tostring(action))
    end
end

local function isDebugEnabled()
    return Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug and Utils and Utils.d
end

local function resolveFavoritesScope()
    local root = Nvk3UT and Nvk3UT.sv
    local general = root and root.General
    local scope = general and general.favScope
    if type(scope) == "string" and scope ~= "" then
        return scope
    end
    return "account"
end

local function getMaxVisibleFavorites()
    local root = Nvk3UT and Nvk3UT.sv
    local general = root and root.General
    local configured = general and general.favoritesVisibleCap
    local numeric = tonumber(configured)
    if not numeric or numeric <= 0 then
        numeric = DEFAULT_MAX_VISIBLE
    end
    return math.floor(numeric)
end

local function normalizeAchievementId(id)
    local normalized = safeCall(Utils and Utils.NormalizeAchievementId, id)
    if type(normalized) ~= "number" or normalized <= 0 then
        normalized = safeCall(Data and Data.NormalizeId, id)
    end
    if type(normalized) ~= "number" or normalized <= 0 then
        local numeric = tonumber(id)
        if numeric and numeric > 0 then
            normalized = math.floor(numeric)
        end
    end
    if type(normalized) ~= "number" or normalized <= 0 then
        return nil
    end
    return normalized
end

local function debugLog(fmt, ...)
    if not isDebugEnabled() then
        return
    end

    local message
    local ok, formatted = pcall(string.format, fmt, ...)
    if ok then
        message = formatted
    else
        message = tostring(fmt)
    end

    if Diagnostics and Diagnostics.Debug then
        Diagnostics.Debug("FavoritesCategory %s", message)
    elseif Utils and Utils.d then
        Utils.d(string.format("[Favorites][Category] %s", message))
    end
end

local function gatherChainIds(achievementId)
    local ids = {}
    if type(achievementId) ~= "number" then
        return ids
    end

    local normalize = Utils and Utils.NormalizeAchievementId
    local baseId = normalize and normalize(achievementId) or achievementId
    local seen = {}

    local function push(id)
        if type(id) == "number" and id ~= 0 and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end

    push(baseId)

    local current = baseId
    while type(GetNextAchievementInLine) == "function" do
        local okNext, nextId = pcall(GetNextAchievementInLine, current)
        if not okNext or type(nextId) ~= "number" or nextId == 0 or seen[nextId] then
            break
        end
        push(nextId)
        current = nextId
    end

    if baseId ~= achievementId then
        push(achievementId)
    end

    return ids
end

local function resolveHostControl(target)
    if type(target) == "userdata" then
        return target
    end

    if target and type(target.GetControl) == "function" then
        local ok, control = pcall(target.GetControl, target)
        if ok and type(control) == "userdata" then
            return control
        end
    end

    if target and type(target.GetNamedChild) == "function" then
        local ok, control = pcall(target.GetNamedChild, target, "Contents")
        if ok and type(control) == "userdata" then
            return control
        end
    end

    return nil
end

local function ensureContainer()
    if state.container and type(state.container) == "userdata" then
        return state.container
    end

    local host = state.host or resolveHostControl(state.parent)
    if not host or type(host) ~= "userdata" then
        return nil
    end

    local wm = WINDOW_MANAGER
    if not (wm and type(wm.CreateControlFromVirtual) == "function") then
        return nil
    end

    local control = wm:CreateControlFromVirtual(SCROLL_CONTROL_NAME, host, "ZO_ScrollContainer")
    if not control then
        return nil
    end

    control:ClearAnchors()
    control:SetAnchor(TOPLEFT, host, TOPLEFT, 0, 0)
    control:SetAnchor(BOTTOMRIGHT, host, BOTTOMRIGHT, 0, 0)
    control:SetHidden(true)

    local scrollChild = control:GetNamedChild("ScrollChild")
    if scrollChild then
        scrollChild:SetResizeToFitDescendents(true)
        scrollChild:SetAnchor(TOPLEFT, control, TOPLEFT, 0, 0)
        scrollChild:SetAnchor(TOPRIGHT, control, TOPRIGHT, 0, 0)
    end

    state.container = control
    state.scrollChild = scrollChild

    return control
end

local function goToAchievement(achievementId)
    if type(achievementId) ~= "number" then
        return
    end

    local achievements = (SYSTEMS and SYSTEMS:GetObject("achievements")) or ACHIEVEMENTS
    if not achievements then
        return
    end

    local categoryIndex, subCategoryIndex = GetCategoryInfoFromAchievementId(achievementId)
    if not achievements:OpenCategory(categoryIndex, subCategoryIndex) then
        if achievements.contentSearchEditBox and achievements.contentSearchEditBox:GetText() ~= "" then
            achievements.contentSearchEditBox:SetText("")
            ACHIEVEMENTS_MANAGER:ClearSearch(true)
        end
    end
    if achievements:OpenCategory(categoryIndex, subCategoryIndex) then
        if not achievements.achievementsById then
            return
        end
        local parentAchievementIndex = achievements:GetBaseAchievementId(achievementId)
        if not achievements.achievementsById[parentAchievementIndex] then
            achievements:ResetFilters()
        end
        if achievements.achievementsById[parentAchievementIndex] then
            achievements.achievementsById[parentAchievementIndex]:Expand()
            ZO_Scroll_ScrollControlIntoCentralView(
                achievements.contentList,
                achievements.achievementsById[parentAchievementIndex]:GetControl()
            )
        end
    end
end

local function releaseRow(control)
    if not control then
        return
    end

    if control.highlight then
        control.highlight:SetHidden(true)
    end

    if control.icon then
        control.icon:SetTexture("")
    end

    control.achievementId = nil
    control.currentName = nil
    control.currentProgress = nil
    control.currentIcon = nil
    control.currentCompleted = nil

    control:ClearAnchors()
    control:SetHidden(true)

    local pool = state.rowPool
    if pool and control.poolKey then
        pool:ReleaseObject(control.poolKey)
        control.poolKey = nil
    end
end

local function createRow(pool)
    local scrollChild = state.scrollChild
    if not scrollChild then
        return nil
    end

    local wm = WINDOW_MANAGER
    local rowControl = wm:CreateControl(nil, scrollChild, CT_CONTROL)
    rowControl:SetMouseEnabled(true)
    rowControl:SetHeight(ROW_HEIGHT)
    rowControl:SetHidden(false)

    local bg = wm:CreateControl(nil, rowControl, CT_TEXTURE)
    bg:SetAnchorFill(rowControl)
    bg:SetTexture("EsoUI/Art/Miscellaneous/listItem_highlight.dds")
    bg:SetColor(1, 1, 1, 0.15)
    bg:SetHidden(true)

    local icon = wm:CreateControl(nil, rowControl, CT_TEXTURE)
    icon:SetDimensions(ROW_ICON_SIZE, ROW_ICON_SIZE)
    icon:SetAnchor(LEFT, rowControl, LEFT, ROW_ICON_OFFSET_X, ROW_ICON_OFFSET_Y)
    icon:SetTextureReleaseOption(RELEASE_TEXTURE_AT_ZERO_REFERENCES)

    local label = wm:CreateControl(nil, rowControl, CT_LABEL)
    label:SetFont("ZoFontGame")
    label:SetAnchor(LEFT, icon, RIGHT, ROW_LABEL_OFFSET_X, 0)
    label:SetAnchor(RIGHT, rowControl, RIGHT, -120, 0)
    label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    label:SetVerticalAlignment(TEXT_ALIGN_CENTER)

    local progress = wm:CreateControl(nil, rowControl, CT_LABEL)
    progress:SetFont("ZoFontGameSmall")
    progress:SetAnchor(RIGHT, rowControl, RIGHT, -10, 0)
    progress:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    progress:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    progress:SetColor(0.7, 0.7, 0.7, 1)

    rowControl.highlight = bg
    rowControl.icon = icon
    rowControl.label = label
    rowControl.progress = progress

    rowControl:SetHandler("OnMouseEnter", function(ctrl)
        if ctrl.highlight then
            ctrl.highlight:SetHidden(false)
        end
    end)
    rowControl:SetHandler("OnMouseExit", function(ctrl)
        if ctrl.highlight then
            ctrl.highlight:SetHidden(true)
        end
    end)
    rowControl:SetHandler("OnMouseDoubleClick", function(ctrl)
        if ctrl.achievementId then
            goToAchievement(ctrl.achievementId)
        end
    end)
    rowControl:SetHandler("OnMouseUp", function(ctrl, button, upInside)
        if button ~= MOUSE_BUTTON_INDEX_RIGHT or not upInside or not ctrl.achievementId then
            return
        end

        ClearMenu()
        AddCustomMenuItem(GetString(SI_ITEM_ACTION_LINK_TO_CHAT), function()
            local link = ZO_LinkHandler_CreateChatLink(GetAchievementLink, ctrl.achievementId)
            ZO_LinkHandler_InsertLink(link)
        end)
        AddCustomMenuItem(GetString(SI_ITEM_ACTION_OPEN), function()
            goToAchievement(ctrl.achievementId)
        end)
        AddCustomMenuItem("Aus Favoriten entfernen", function()
            local scope = resolveFavoritesScope()
            local removed = false
            if Data and Data.SetFavorited then
                local ok, changed = pcall(Data.SetFavorited, ctrl.achievementId, false, "FavoritesCategory:ContextRemove", scope)
                removed = ok and changed ~= false
            end
            if removed then
                local journal = Nvk3UT and Nvk3UT.Journal
                if journal and type(journal.RefreshFavoritesIfVisible) == "function" then
                    pcall(journal.RefreshFavoritesIfVisible, journal, {
                        changedIds = { ctrl.achievementId },
                        reason = "FavoritesCategory:ContextRemove",
                    })
                end
            end
        end)
        ShowMenu(ctrl)
    end)

    return rowControl
end

local function resetRow(pool, control)
    releaseRow(control)
end

local function ensureRowPool()
    if not state.rowPool then
        state.rowPool = ZO_ObjectPool:New(createRow, resetRow)
    end
    return state.rowPool
end

local function acquireRow()
    local container = ensureContainer()
    if not container then
        return nil
    end

    ensureRowPool()
    local key, control = state.rowPool:AcquireObject()
    if not control then
        return nil
    end

    control.poolKey = key
    control:SetHidden(false)
    return control
end

local function applyVisibility()
    local container = state.container
    if not (container and container.SetHidden) then
        return
    end

    local shouldShow = (state.visible ~= false) and state.hasEntries
    container:SetHidden(not shouldShow)
end

local function layoutRows()
    local scrollChild = state.scrollChild
    if not scrollChild then
        return
    end

    local previous
    for index = 1, #state.rowOrder do
        local row = state.rowOrder[index]
        if row then
            row:ClearAnchors()
            if previous then
                row:SetAnchor(TOPLEFT, previous, BOTTOMLEFT, 0, ROW_SPACING)
                row:SetAnchor(TOPRIGHT, previous, BOTTOMRIGHT, 0, ROW_SPACING)
            else
                row:SetAnchor(TOPLEFT, scrollChild, TOPLEFT, 0, 0)
                row:SetAnchor(TOPRIGHT, scrollChild, TOPRIGHT, 0, 0)
            end
            previous = row
        end
    end
end

local function ensureSortedStructures()
    state.sortedIds = state.sortedIds or {}
    state.sortedLookup = state.sortedLookup or {}
end

local function invalidateRowBatches()
    if state.batchCallId and type(zo_removeCallLater) == "function" then
        zo_removeCallLater(state.batchCallId)
    end
    state.batchCallId = nil
    state.pendingRowUpdateIds = {}
    state.pendingRowUpdateLookup = {}
end

local function clearRows()
    for index = #state.rowOrder, 1, -1 do
        local row = state.rowOrder[index]
        releaseRow(row)
        state.rowOrder[index] = nil
    end

    for key in pairs(state.rowByAchievementId) do
        state.rowByAchievementId[key] = nil
    end

    invalidateRowBatches()

    state.hasEntries = false
    applyVisibility()
end

local function rebuildSortedFavorites()
    ensureData()
    ensureSortedStructures()

    local ids = {}
    state.sortedLookup = {}

    if Data and Data.GetAllFavorites then
        local scope = resolveFavoritesScope()
        local iterator, iterState, key = safeCall(Data.GetAllFavorites, scope)
        if type(iterator) == "function" then
            for rawId, flagged in iterator, iterState, key do
                if flagged then
                    local normalized = normalizeAchievementId(rawId)
                    if normalized then
                        state.sortedLookup[normalized] = true
                        ids[#ids + 1] = normalized
                    end
                end
            end
        end
    end

    table.sort(ids)

    state.sortedIds = ids
end

local function sortedInsert(achievementId)
    ensureSortedStructures()
    if state.sortedLookup[achievementId] then
        return false
    end

    local ids = state.sortedIds
    local inserted = false
    for index = 1, #ids do
        if achievementId < ids[index] then
            table.insert(ids, index, achievementId)
            inserted = true
            break
        end
    end

    if not inserted then
        ids[#ids + 1] = achievementId
    end

    state.sortedLookup[achievementId] = true
    return true
end

local function sortedRemove(achievementId)
    ensureSortedStructures()
    if not state.sortedLookup[achievementId] then
        return false
    end

    state.sortedLookup[achievementId] = nil

    local ids = state.sortedIds
    for index = 1, #ids do
        if ids[index] == achievementId then
            table.remove(ids, index)
            return true
        end
    end

    return false
end

local function applyDeltaChanges(changedIds)
    if type(changedIds) ~= "table" or #changedIds == 0 then
        rebuildSortedFavorites()
        return 0, 0
    end

    ensureData()
    ensureSortedStructures()

    local scope = resolveFavoritesScope()
    local addedToList = 0
    local removedFromList = 0

    for index = 1, #changedIds do
        local normalized = normalizeAchievementId(changedIds[index])
        if normalized then
            local isFavorited = false
            if Data and Data.IsFavorited then
                local ok, favorited = pcall(Data.IsFavorited, normalized, scope)
                isFavorited = ok and favorited == true
            end
            if isFavorited then
                if sortedInsert(normalized) then
                    addedToList = addedToList + 1
                end
            else
                if sortedRemove(normalized) then
                    removedFromList = removedFromList + 1
                end
            end
            state.achievementCache[normalized] = nil
        end
    end

    return addedToList, removedFromList
end

local function getAchievementPresentation(achievementId)
    if state.achievementCache[achievementId] then
        return state.achievementCache[achievementId]
    end

    local okInfo, name, description, points, icon, completed = pcall(GetAchievementInfo, achievementId)
    if not okInfo or not name then
        return nil
    end

    local progressText = nil
    local completedCriteria = 0
    local totalCriteria = 0

    if type(GetAchievementNumCriteria) == "function" and type(GetAchievementCriterion) == "function" then
        local okNum, total = pcall(GetAchievementNumCriteria, achievementId)
        if okNum and type(total) == "number" and total > 0 then
            totalCriteria = 0
            completedCriteria = 0
            for index = 1, total do
                local okCriterion, _, current, maxValue = pcall(GetAchievementCriterion, achievementId, index)
                if okCriterion then
                    local required = tonumber(maxValue) or 0
                    local progress = tonumber(current) or 0
                    if required > 0 then
                        totalCriteria = totalCriteria + required
                        completedCriteria = completedCriteria + math.min(progress, required)
                    else
                        totalCriteria = totalCriteria + 1
                        if progress > 0 then
                            completedCriteria = completedCriteria + 1
                        end
                    end
                end
            end
            progressText = string.format("%d/%d", completedCriteria, totalCriteria)
        end
    end

    local displayName = zo_strformat("<<1>>", name)
    local data = {
        name = displayName,
        icon = icon,
        completed = completed == true,
        progressText = progressText,
        completedValue = completedCriteria,
        totalValue = totalCriteria,
    }
    state.achievementCache[achievementId] = data
    return data
end

local function applyRowData(rowControl, achievementId, forceRefresh)
    if not (rowControl and achievementId) then
        return
    end

    if forceRefresh then
        state.achievementCache[achievementId] = nil
    end

    local presentation = getAchievementPresentation(achievementId)
    if not presentation then
        rowControl.label:SetText(tostring(achievementId))
        rowControl.progress:SetText("")
        if rowControl.icon then
            rowControl.icon:SetTexture("")
        end
        return
    end

    if rowControl.icon and rowControl.currentIcon ~= presentation.icon then
        rowControl.icon:SetTexture(presentation.icon or "")
        rowControl.currentIcon = presentation.icon
    end

    if rowControl.label and rowControl.currentName ~= presentation.name then
        rowControl.label:SetText(presentation.name)
        rowControl.currentName = presentation.name
    end

    local progressText = presentation.progressText
    if not progressText or progressText == "0/0" then
        progressText = presentation.completed and GetString(SI_ACHIEVEMENTS_COMPLETED) or ""
    end

    if rowControl.progress and rowControl.currentProgress ~= progressText then
        rowControl.progress:SetText(progressText)
        rowControl.currentProgress = progressText
    end

    local completed = presentation.completed == true
    if rowControl.currentCompleted ~= completed then
        if completed then
            rowControl.label:SetColor(0.6, 0.85, 0.5, 1)
        else
            rowControl.label:SetColor(1, 1, 1, 1)
        end
        rowControl.currentCompleted = completed
    end
end

Category.ApplyRowData = applyRowData

local function processRowBatch()
    state.batchCallId = nil

    local processed = 0
    while #state.pendingRowUpdateIds > 0 and processed < ROW_BATCH_SIZE do
        local achievementId = table.remove(state.pendingRowUpdateIds, 1)
        state.pendingRowUpdateLookup[achievementId] = nil

        local row = state.rowByAchievementId[achievementId]
        if row then
            applyRowData(row, achievementId, false)
        end

        processed = processed + 1
    end

    if #state.pendingRowUpdateIds > 0 and type(zo_callLater) == "function" then
        state.batchCallId = zo_callLater(processRowBatch, 0)
    end
end

local function queueRowUpdate(row, achievementId, forceRefresh)
    if not row or not achievementId then
        return
    end

    row.achievementId = achievementId

    if forceRefresh then
        state.achievementCache[achievementId] = nil
    end

    if state.pendingRowUpdateLookup[achievementId] then
        return
    end

    state.pendingRowUpdateLookup[achievementId] = true
    state.pendingRowUpdateIds[#state.pendingRowUpdateIds + 1] = achievementId

    if type(zo_callLater) ~= "function" then
        applyRowData(row, achievementId, forceRefresh)
        state.pendingRowUpdateLookup[achievementId] = nil
        state.pendingRowUpdateIds[#state.pendingRowUpdateIds] = nil
        return
    end

    if not state.batchCallId then
        state.batchCallId = zo_callLater(processRowBatch, 0)
    end
end

local function syncVisibleRows(maxVisible)
    local desiredIds = {}
    local ids = state.sortedIds or {}
    local limit = math.min(#ids, maxVisible)
    for index = 1, limit do
        desiredIds[index] = ids[index]
    end

    local desiredLookup = {}
    for index = 1, #desiredIds do
        desiredLookup[desiredIds[index]] = true
    end

    local removedRows = 0
    for index = #state.rowOrder, 1, -1 do
        local row = state.rowOrder[index]
        if not row or not desiredLookup[row.achievementId] then
            if row then
                state.rowByAchievementId[row.achievementId] = nil
                releaseRow(row)
                removedRows = removedRows + 1
            end
            table.remove(state.rowOrder, index)
        end
    end

    local addedRows = 0
    for orderIndex = 1, #desiredIds do
        local achievementId = desiredIds[orderIndex]
        local row = state.rowByAchievementId[achievementId]
        if not row then
            row = acquireRow()
            if not row then
                break
            end
            addedRows = addedRows + 1
            state.rowByAchievementId[achievementId] = row
        end

        local existingIndex
        for index = 1, #state.rowOrder do
            if state.rowOrder[index] == row then
                existingIndex = index
                break
            end
        end
        if existingIndex then
            table.remove(state.rowOrder, existingIndex)
        end
        table.insert(state.rowOrder, orderIndex, row)

        queueRowUpdate(row, achievementId, true)
    end

    layoutRows()

    state.hasEntries = (#state.rowOrder > 0)
    applyVisibility()

    return addedRows, removedRows, #state.rowOrder, maxVisible
end

local function refreshInternal(context)
    local changedIds = nil
    local reason = nil
    if type(context) == "table" then
        changedIds = context.changedIds
        reason = context.reason
    elseif context ~= nil then
        reason = context
    end

    local addedFavorites, removedFavorites = applyDeltaChanges(changedIds)

    if not ensureContainer() then
        clearRows()
        return nil
    end

    local maxVisible = getMaxVisibleFavorites()
    local addedRows, removedRows, materialized, cap = syncVisibleRows(maxVisible)

    if isDebugEnabled() then
        debugLog(
            "Favorites Δ-update: +%d / -%d (materialized %d / capped %d, favorites Δlist +%d / -%d, reason=%s)",
            addedRows,
            removedRows,
            materialized,
            cap,
            addedFavorites,
            removedFavorites,
            tostring(reason or "n/a")
        )
    end

    return state.container
end

---Initialize the favorites category container.
---@param parentOrContainer Control|any
---@return any
function Category:Init(parentOrContainer)
    state.parent = parentOrContainer

    local resolvedHost = resolveHostControl(parentOrContainer)
    if resolvedHost and resolvedHost ~= state.host then
        clearRows()
        state.rowPool = nil
        state.achievementCache = {}
        state.sortedIds = {}
        state.sortedLookup = {}
        state.pendingRowUpdateIds = {}
        state.pendingRowUpdateLookup = {}
        if state.container and state.container.SetHidden then
            state.container:SetHidden(true)
        end
        state.container = nil
        state.scrollChild = nil
    end

    state.host = resolvedHost or state.host

    rebuildSortedFavorites()
    local container = refreshInternal({ reason = "init" })

    return container or state.host or parentOrContainer
end

---Refresh the favorites category view.
---@param context any
---@return any
function Category:Refresh(context)
    return refreshInternal(context)
end

---Set the visibility of the favorites category container.
---@param isVisible boolean
function Category:SetVisible(isVisible)
    state.visible = isVisible ~= false
    applyVisibility()
end

---Get the measured height of the favorites container.
---@return number
function Category:GetHeight()
    local container = state.container or state.host
    if container and container.GetHeight then
        return container:GetHeight()
    end
    return 0
end

---Remove an achievement (and its chain siblings) from the favorites lists.
---@param achievementId number
---@return boolean removed
function Category:Remove(achievementId)
    ensureData()
    if type(achievementId) ~= "number" or not Data then
        return false
    end

    if not (Data.SetFavorited and Data.IsFavorited) then
        return false
    end

    local scopes = { "account", "character" }
    local removedAny = false
    local chainIds = gatherChainIds(achievementId)

    for _, candidateId in ipairs(chainIds) do
        for _, scope in ipairs(scopes) do
            if Data.IsFavorited(candidateId, scope) then
                Data.SetFavorited(candidateId, false, "Favorites:Remove", scope)
                removedAny = true
            end
        end
    end

    if removedAny then
        debugLog("Removed completed achievement %d", achievementId)
        local ui = Nvk3UT and Nvk3UT.UI
        if ui and ui.RefreshAchievements then
            safeCall(ui.RefreshAchievements)
        end
        if ui and ui.UpdateStatus then
            safeCall(ui.UpdateStatus)
        end
    end

    return removedAny
end

local Shim = {}
Nvk3UT.Favorites = Shim

function Shim.Init(...)
    logShim("Init")
    if type(Category.Init) ~= "function" then
        return nil
    end
    return safeCall(Category.Init, Category, ...)
end

function Shim.Refresh(...)
    logShim("Refresh")
    if type(Category.Refresh) ~= "function" then
        return nil
    end
    return safeCall(Category.Refresh, Category, ...)
end

function Shim.SetVisible(...)
    logShim("SetVisible")
    if type(Category.SetVisible) ~= "function" then
        return nil
    end
    return safeCall(Category.SetVisible, Category, ...)
end

function Shim.GetHeight(...)
    if type(Category.GetHeight) ~= "function" then
        return 0
    end
    local height = safeCall(Category.GetHeight, Category, ...)
    return tonumber(height) or 0
end

function Shim.Remove(...)
    logShim("Remove")
    if type(Category.Remove) ~= "function" then
        return false
    end
    local result = safeCall(Category.Remove, Category, ...)
    return result and true or false
end

return Category

