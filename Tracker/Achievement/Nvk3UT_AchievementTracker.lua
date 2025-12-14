local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Rows = Nvk3UT and Nvk3UT.AchievementTrackerRows

local AchievementTracker = {}
AchievementTracker.__index = AchievementTracker

local MODULE_NAME = addonName .. "AchievementTracker"

local state = {
    isInitialized = false,
    container = nil,
    rowsModule = nil,
    snapshot = nil,
    subscription = nil,
    favoritesRowData = {},
    saved = nil,
    opts = {},
    lastHeight = 0,
    warnedMissingFavorites = false,
}

local function isDebugEnabled()
    local utils = (Nvk3UT and Nvk3UT.Utils) or Nvk3UT_Utils
    if utils and type(utils.IsDebugEnabled) == "function" then
        return utils:IsDebugEnabled()
    end

    local diagnostics = (Nvk3UT and Nvk3UT.Diagnostics) or Nvk3UT_Diagnostics
    if diagnostics and type(diagnostics.IsDebugEnabled) == "function" then
        return diagnostics:IsDebugEnabled()
    end

    local root = Nvk3UT
    if root and type(root.IsDebugEnabled) == "function" then
        return root:IsDebugEnabled()
    end

    return false
end

local function DebugLog(fmt, ...)
    if not isDebugEnabled() then
        return
    end

    local payload = tostring(fmt)
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, tostring(fmt), ...)
        if ok then
            payload = formatted
        end
    end

    if d then
        d(string.format("[%s] %s", MODULE_NAME, payload))
    elseif print then
        print(string.format("[%s] %s", MODULE_NAME, payload))
    end
end

local function Warn(fmt, ...)
    local message = tostring(fmt)
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, tostring(fmt), ...)
        if ok then
            message = formatted
        end
    end

    local diagnostics = Nvk3UT and Nvk3UT.Diagnostics
    if diagnostics and type(diagnostics.Warn) == "function" then
        pcall(diagnostics.Warn, diagnostics, string.format("[%s] %s", MODULE_NAME, message))
        return
    end

    if d then
        d(string.format("[%s] %s", MODULE_NAME, message))
        return
    end

    if print then
        print(string.format("[%s] %s", MODULE_NAME, message))
    end
end

local function NotifyHostContentChanged()
    local host = Nvk3UT and Nvk3UT.TrackerHost
    if not (host and host.NotifyContentChanged) then
        return
    end

    pcall(host.NotifyContentChanged)
end

local function EnsureSavedVars()
    Nvk3UT.sv = Nvk3UT.sv or {}
    local root = Nvk3UT.sv

    root.AchievementTracker = root.AchievementTracker or {}
    state.saved = root.AchievementTracker

    if state.saved.active == nil then
        state.saved.active = true
    end
end

local function applySettings(settings)
    if type(settings) ~= "table" then
        return
    end

    if settings.active ~= nil then
       state.opts = state.opts or {}
        EnsureSavedVars()
        state.saved.active = settings.active ~= false
    end

    state.opts = state.opts or {}
    for key, value in pairs(settings) do
        state.opts[key] = value
    end
end

local function getRowsModule()
    if Rows and type(Rows.EnsureRow) == "function" then
        return Rows
    end

    Rows = Nvk3UT and Nvk3UT.AchievementTrackerRows
    if Rows and type(Rows.EnsureRow) == "function" then
        return Rows
    end

    return nil
end

local function getRowHeight()
    local rows = getRowsModule()
    if rows and rows.ROW_HEIGHT then
        return rows.ROW_HEIGHT
    end

    return 0
end

local function formatProgress(progress)
    if type(progress) ~= "table" then
        return nil
    end

    local current = tonumber(progress.current)
    local maximum = tonumber(progress.max)

    if current and maximum and maximum > 0 then
        return string.format("%d/%d", current, maximum)
    end

    if progress.text ~= nil then
        return tostring(progress.text)
    end

    return nil
end

local function buildRowDataFromEntry(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local rowData = {
        icon = entry.icon,
        name = entry.name or "",
        progressText = formatProgress(entry.progress),
    }

    return rowData
end

local function buildFavoritesRowData(entries)
    local rows = {}

    if type(entries) ~= "table" then
        DebugLog("Favorites built: favorites=%d", #rows)
        return rows
    end

    for index = 1, #entries do
        local data = buildRowDataFromEntry(entries[index])
        if data then
            rows[#rows + 1] = data
        end
    end

    DebugLog("Favorites built: favorites=%d", #rows)
    return rows
end

local function renderRows(rowData)
    local rowsModule = getRowsModule()
    if not (rowsModule and rowsModule.Init) then
        return
    end

    if rowsModule.ReleaseAll then
        rowsModule:ReleaseAll()
    end

    local totalHeight = 0

    for index = 1, #rowData do
        local row = rowsModule:EnsureRow(index)
        rowsModule:ApplyRowData(row, rowData[index])

        if row and row.GetHeight then
            local ok, height = pcall(row.GetHeight, row)
            if ok and type(height) == "number" then
                totalHeight = totalHeight + math.max(0, height)
            end
        else
            totalHeight = totalHeight + getRowHeight()
        end
    end

    state.lastHeight = totalHeight

    if state.container and state.container.SetHeight then
        state.container:SetHeight(math.max(0, totalHeight))
    end

    DebugLog("Rows rendered/cleared: rows=%d", #rowData)
    NotifyHostContentChanged()
end

local function onSnapshotUpdated(snapshot)
    state.snapshot = snapshot

    local achievements = (snapshot and snapshot.achievements) or {}
    DebugLog("Snapshot received: achievements=%d", #achievements)

    state.favoritesRowData = buildFavoritesRowData(achievements)
    renderRows(state.favoritesRowData)
end

local function subscribeToSnapshot()
    local Model = Nvk3UT and Nvk3UT.AchievementModel
    if not (Model and Model.Subscribe) then
        if not state.warnedMissingFavorites then
            Warn("Achievement favorites unavailable (missing model)")
            state.warnedMissingFavorites = true
        end
        return
    end

    if state.subscription then
        return
    end

    local function callback(snapshot)
        onSnapshotUpdated(snapshot)
    end

    state.subscription = callback
    Model.Subscribe(callback)
end

local function unsubscribeFromSnapshot()
    if not state.subscription then
        return
    end

    local Model = Nvk3UT and Nvk3UT.AchievementModel
    if Model and Model.Unsubscribe then
        pcall(Model.Unsubscribe, state.subscription)
    end

    state.subscription = nil
end

local function ensureInitialSnapshot()
    if state.snapshot then
        return state.snapshot
    end

    local Model = Nvk3UT and Nvk3UT.AchievementModel
    if Model and Model.GetViewData then
        local snapshot = Model.GetViewData()
        state.snapshot = snapshot
        return snapshot
    end

    return nil
end

local function extractFavoritesFromViewModel(viewModel)
    if type(viewModel) ~= "table" then
        return nil
    end

    if type(viewModel.favorites) == "table" then
        return viewModel.favorites
    end

    if type(viewModel.entries) == "table" and viewModel.kind == "favorites" then
        return viewModel.entries
    end

    return nil
end

local function refreshRows(viewModel)
    local favorites = extractFavoritesFromViewModel(viewModel)

    if favorites then
        state.favoritesRowData = buildFavoritesRowData(favorites)
        renderRows(state.favoritesRowData)
        return
    end

    local snapshot = ensureInitialSnapshot()
    local achievements = (snapshot and snapshot.achievements) or {}

    if (not snapshot or not achievements) and (not state.warnedMissingFavorites) then
        Warn("Achievement favorites unavailable (no snapshot)")
        state.warnedMissingFavorites = true
    end

    state.favoritesRowData = buildFavoritesRowData(achievements)
    renderRows(state.favoritesRowData)
end

function AchievementTracker.Init(parentControl, opts)
    if not parentControl then
        error("AchievementTracker.Init requires a parent control")
    end

    AchievementTracker.Shutdown()

    state.container = parentControl
    state.lastHeight = 0

    if state.container and state.container.SetResizeToFitDescendents then
        state.container:SetResizeToFitDescendents(true)
    end

    EnsureSavedVars()

    state.opts = {}
    applySettings(state.saved or {})
    applySettings(opts)

    state.rowsModule = getRowsModule()
    if state.rowsModule and state.rowsModule.Init then
        state.rowsModule:Init(parentControl)
    end

    state.isInitialized = true

    subscribeToSnapshot()
    ensureInitialSnapshot()

    AchievementTracker.Refresh()
    AchievementTracker.RefreshVisibility()
end

function AchievementTracker.Refresh(viewModel)
    if not state.isInitialized then
        return
    end

    refreshRows(viewModel)
end

function AchievementTracker.RequestRefresh()
    AchievementTracker.Refresh()
end

function AchievementTracker.Shutdown()
    unsubscribeFromSnapshot()

    local rowsModule = getRowsModule()
    if rowsModule and rowsModule.ReleaseAll then
        rowsModule:ReleaseAll()
    end

    state.isInitialized = false
    state.container = nil
    state.rowsModule = nil
    state.snapshot = nil
    state.favoritesRowData = {}
    state.lastHeight = 0
    state.warnedMissingFavorites = false
end

function AchievementTracker.ApplySettings(settings)
    applySettings(settings)
    AchievementTracker.Refresh()
end

function AchievementTracker.ApplyTheme(settings)
    applySettings(settings)
    AchievementTracker.Refresh()
end

function AchievementTracker.SetActive(active)
    EnsureSavedVars()
    state.saved.active = active ~= false
    AchievementTracker.RefreshVisibility()
end

function AchievementTracker.RefreshVisibility()
    if not state.container then
        return
    end

    local hidden = state.saved and state.saved.active == false
    state.container:SetHidden(hidden)
    NotifyHostContentChanged()
end

function AchievementTracker.GetHeight()
    return state.lastHeight or 0
end

function AchievementTracker.GetContentSize()
    local width = 0
    if state.container and state.container.GetWidth then
        local ok, measured = pcall(state.container.GetWidth, state.container)
        if ok and type(measured) == "number" then
            width = measured
        end
    end

    return width, state.lastHeight or 0
end

Nvk3UT.AchievementTracker = AchievementTracker

return AchievementTracker
