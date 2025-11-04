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
    visible = true,
    hasEntries = false,
    activeRows = {},
    achievementCache = {},
    batchCallId = nil,
    pendingBuild = nil,
}

local ROW_HEIGHT = 36
local ROW_ICON_SIZE = 28
local ROW_ICON_OFFSET_X = 6
local ROW_LABEL_OFFSET_X = 12
local ROW_SPACING = 4
local INITIAL_BATCH_SIZE = 8
local BATCH_SIZE = 8
local BATCH_DELAY_MS = 15
local DEFAULT_MAX_VISIBLE = 20
local HARD_MAX_VISIBLE = 100
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

local function logShim(action)
    if Diagnostics and Diagnostics.Debug then
        Diagnostics.Debug("Favorites SHIM -> %s", tostring(action))
    end
end

local function isDebugEnabled()
    return Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug and Utils and Utils.d
end

local function debugLog(fmt, ...)
    if not isDebugEnabled() then
        return
    end

    local ok, message = pcall(string.format, fmt, ...)
    if not ok then
        message = tostring(fmt)
    end

    if Diagnostics and Diagnostics.Debug then
        Diagnostics.Debug("FavoritesCategory %s", message)
    elseif Utils and Utils.d then
        Utils.d(string.format("[Favorites][Category] %s", message))
    end
end

local function ensureData()
    if Data and Data.InitSavedVars then
        safeCall(Data.InitSavedVars)
    end
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

local function getFavoritesCap()
    local root = Nvk3UT and Nvk3UT.sv
    local general = root and root.General
    local configured = general and (general.favoritesCap or general.favoritesVisibleCap)
    local numeric = tonumber(configured)
    if not numeric or numeric <= 0 then
        numeric = DEFAULT_MAX_VISIBLE
    end
    numeric = math.max(1, math.min(math.floor(numeric + 0.5), HARD_MAX_VISIBLE))
    if general then
        general.favoritesCap = numeric
        general.favoritesVisibleCap = numeric
    end
    return numeric
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

local function clearPendingBatch()
    if state.batchCallId and type(zo_removeCallLater) == "function" then
        zo_removeCallLater(state.batchCallId)
    end
    state.batchCallId = nil
    state.pendingBuild = nil
end

local function applyVisibility()
    local container = state.container
    if not (container and container.SetHidden) then
        return
    end

    local shouldShow = (state.visible ~= false) and state.hasEntries
    container:SetHidden(not shouldShow)
end

local function detachAllRows()
    for index = #state.activeRows, 1, -1 do
        local row = state.activeRows[index]
        if row then
            if row.SetHidden then
                row:SetHidden(true)
            end
            if row.SetParent then
                row:SetParent(nil)
            end
        end
        state.activeRows[index] = nil
    end
end

local function resolveContainer()
    local host = resolveHostControl(state.parent) or state.host
    if host and host ~= state.host then
        state.host = host
        if state.container and state.container.SetParent then
            state.container:SetParent(nil)
        end
        state.container = nil
        state.scrollChild = nil
    end

    if state.container and state.container.GetParent and state.container:GetParent() ~= state.host then
        state.container = nil
        state.scrollChild = nil
    end

    if state.container then
        return state.container
    end

    if not state.host or type(state.host) ~= "userdata" then
        return nil
    end

    local wm = WINDOW_MANAGER
    if not (wm and type(wm.CreateControlFromVirtual) == "function") then
        return nil
    end

    local control = wm:CreateControlFromVirtual(SCROLL_CONTROL_NAME, state.host, "ZO_ScrollContainer")
    if not control then
        return nil
    end

    control:ClearAnchors()
    control:SetAnchor(TOPLEFT, state.host, TOPLEFT, 0, 0)
    control:SetAnchor(BOTTOMRIGHT, state.host, BOTTOMRIGHT, 0, 0)
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

local function restoreScroll(offset)
    local container = state.container
    if container and container.SetVerticalScroll and type(offset) == "number" then
        container:SetVerticalScroll(offset)
    end
end

local function collectFavorites()
    ensureData()

    local ids = {}
    local scope = resolveFavoritesScope()
    if Data and Data.GetAllFavorites then
        local iterator, iterState, key = safeCall(Data.GetAllFavorites, scope)
        if type(iterator) == "function" then
            for rawId, flagged in iterator, iterState, key do
                if flagged then
                    local normalized = normalizeAchievementId(rawId)
                    if normalized then
                        ids[#ids + 1] = normalized
                    end
                end
            end
        end
    end

    table.sort(ids)
    return ids
end

local function getAchievementPresentation(achievementId)
    local cached = state.achievementCache[achievementId]
    if cached then
        return cached
    end

    local okInfo, name, description, points, icon, completed = pcall(GetAchievementInfo, achievementId)
    if not okInfo or not name then
        return nil
    end

    local progressText
    local completedCriteria = 0
    local totalCriteria = 0

    if type(GetAchievementNumCriteria) == "function" and type(GetAchievementCriterion) == "function" then
        local okNum, total = pcall(GetAchievementNumCriteria, achievementId)
        if okNum and type(total) == "number" and total > 0 then
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
            if totalCriteria > 0 then
                progressText = string.format("%d/%d", completedCriteria, totalCriteria)
            end
        end
    end

    local displayName = zo_strformat("<<1>>", name)
    local data = {
        name = displayName,
        icon = icon,
        completed = completed == true,
        progressText = progressText,
    }

    state.achievementCache[achievementId] = data
    return data
end

local function applyRowData(row, achievementId)
    row.achievementId = achievementId

    local presentation = getAchievementPresentation(achievementId)
    if not presentation then
        if row.label then
            row.label:SetText(tostring(achievementId))
            row.label:SetColor(1, 1, 1, 1)
        end
        if row.progress then
            row.progress:SetText("")
        end
        if row.icon then
            row.icon:SetTexture("")
        end
        return
    end

    if row.label then
        row.label:SetText(presentation.name or tostring(achievementId))
        if presentation.completed then
            row.label:SetColor(0.6, 0.85, 0.5, 1)
        else
            row.label:SetColor(1, 1, 1, 1)
        end
    end

    if row.progress then
        local progressText = presentation.progressText
        if not progressText or progressText == "0/0" then
            progressText = presentation.completed and GetString(SI_ACHIEVEMENTS_COMPLETED) or ""
        end
        row.progress:SetText(progressText or "")
    end

    if row.icon then
        row.icon:SetTexture(presentation.icon or "")
    end
end

local function createRowControl(scrollChild, previousRow)
    local wm = WINDOW_MANAGER
    if not (wm and scrollChild) then
        return nil
    end

    local row = wm:CreateControl(nil, scrollChild, CT_CONTROL)
    row:SetHeight(ROW_HEIGHT)
    row:SetMouseEnabled(true)
    row:SetHitInsets(0, 0, 0, 0)

    row:ClearAnchors()
    if previousRow then
        row:SetAnchor(TOPLEFT, previousRow, BOTTOMLEFT, 0, ROW_SPACING)
        row:SetAnchor(TOPRIGHT, previousRow, BOTTOMRIGHT, 0, ROW_SPACING)
    else
        row:SetAnchor(TOPLEFT, scrollChild, TOPLEFT, 0, 0)
        row:SetAnchor(TOPRIGHT, scrollChild, TOPRIGHT, 0, 0)
    end

    local bg = wm:CreateControl(nil, row, CT_TEXTURE)
    bg:SetTexture("EsoUI/Art/Miscellaneous/listItem_highlight.dds")
    bg:SetColor(1, 1, 1, 0.25)
    bg:SetAnchorFill(row)
    bg:SetHidden(true)

    local icon = wm:CreateControl(nil, row, CT_TEXTURE)
    icon:SetDimensions(ROW_ICON_SIZE, ROW_ICON_SIZE)
    icon:SetAnchor(LEFT, row, LEFT, ROW_ICON_OFFSET_X, 0)
    icon:SetMouseEnabled(false)

    local label = wm:CreateControl(nil, row, CT_LABEL)
    label:SetFont("ZoFontGameBold")
    label:SetAnchor(LEFT, icon, RIGHT, ROW_LABEL_OFFSET_X, 0)
    label:SetAnchor(RIGHT, row, RIGHT, -120, 0)
    label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    label:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)

    local progress = wm:CreateControl(nil, row, CT_LABEL)
    progress:SetFont("ZoFontGameSmall")
    progress:SetAnchor(RIGHT, row, RIGHT, -10, 0)
    progress:SetHorizontalAlignment(TEXT_ALIGN_RIGHT)
    progress:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    progress:SetColor(0.7, 0.7, 0.7, 1)
    progress:SetMouseEnabled(false)

    row.highlight = bg
    row.icon = icon
    row.label = label
    row.progress = progress

    row:SetHandler("OnMouseEnter", function(ctrl)
        if ctrl.highlight then
            ctrl.highlight:SetHidden(false)
        end
    end)
    row:SetHandler("OnMouseExit", function(ctrl)
        if ctrl.highlight then
            ctrl.highlight:SetHidden(true)
        end
    end)
    row:SetHandler("OnMouseDoubleClick", function(ctrl)
        if ctrl.achievementId then
            goToAchievement(ctrl.achievementId)
        end
    end)
    row:SetHandler("OnMouseUp", function(ctrl, button, upInside)
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

    return row
end

local function buildRow(scrollChild, achievementId)
    local previousRow = state.activeRows[#state.activeRows]
    local row = createRowControl(scrollChild, previousRow)
    if not row then
        return nil
    end

    applyRowData(row, achievementId)
    state.activeRows[#state.activeRows + 1] = row
    return row
end

local function processPendingBatch()
    state.batchCallId = nil

    local context = state.pendingBuild
    if not context then
        return
    end

    local processed = 0
    while context.nextIndex <= #context.ids and processed < BATCH_SIZE do
        local achievementId = context.ids[context.nextIndex]
        buildRow(context.scrollChild, achievementId)
        context.nextIndex = context.nextIndex + 1
        processed = processed + 1
    end

    if context.nextIndex <= #context.ids then
        if type(zo_callLater) == "function" then
            state.batchCallId = zo_callLater(processPendingBatch, BATCH_DELAY_MS)
        else
            processPendingBatch()
        end
    else
        restoreScroll(context.scrollOffset)
        state.pendingBuild = nil
    end
end

local function schedulePendingBatch()
    if not state.pendingBuild then
        return
    end

    if type(zo_callLater) ~= "function" then
        processPendingBatch()
        return
    end

    state.batchCallId = zo_callLater(processPendingBatch, BATCH_DELAY_MS)
end

local function getReasonLabel(context)
    if type(context) == "table" and context.reason ~= nil then
        return tostring(context.reason)
    elseif context ~= nil then
        return tostring(context)
    end
    return "n/a"
end

function Category:RebuildList(parentOrContainer, context)
    if parentOrContainer ~= nil then
        state.parent = parentOrContainer
    end

    local container = resolveContainer()
    if not container then
        state.hasEntries = false
        applyVisibility()
        return state.host or state.parent
    end

    local scrollChild = state.scrollChild
    if not scrollChild then
        state.hasEntries = false
        applyVisibility()
        return container
    end

    clearPendingBatch()

    local previousScroll = container.GetVerticalScroll and container:GetVerticalScroll() or 0

    detachAllRows()
    state.achievementCache = {}

    local allFavorites = collectFavorites()
    local cap = getFavoritesCap()
    local visibleCount = math.min(#allFavorites, cap)

    state.hasEntries = (visibleCount > 0)
    applyVisibility()

    if visibleCount == 0 then
        restoreScroll(0)
        debugLog("Favorites rebuild: materialized %d of cap %d (reason=%s)", 0, cap, getReasonLabel(context))
        return container
    end

    local visibleIds = {}
    for index = 1, visibleCount do
        visibleIds[index] = allFavorites[index]
    end

    local immediateCount = math.min(visibleCount, INITIAL_BATCH_SIZE)
    for index = 1, immediateCount do
        buildRow(scrollChild, visibleIds[index])
    end

    restoreScroll(previousScroll)

    if immediateCount < visibleCount then
        state.pendingBuild = {
            ids = visibleIds,
            nextIndex = immediateCount + 1,
            scrollChild = scrollChild,
            scrollOffset = previousScroll,
        }
        schedulePendingBatch()
    end

    local pending = math.max(visibleCount - immediateCount, 0)
    local batchLabel = (pending > 0) and string.format("batched +%d", pending) or "no batch"
    debugLog(
        "Favorites rebuild: materialized %d of cap %d (%s, reason=%s)",
        visibleCount,
        cap,
        batchLabel,
        getReasonLabel(context)
    )

    return container
end

function Category:Refresh(context)
    return self:RebuildList(state.parent, context)
end

function Category:Init(parentOrContainer)
    return self:RebuildList(parentOrContainer, { reason = "init" })
end

function Category:SetVisible(isVisible)
    state.visible = isVisible ~= false
    applyVisibility()
end

function Category:GetHeight()
    local container = state.container or state.host
    if container and container.GetHeight then
        return container:GetHeight()
    end
    return 0
end

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
