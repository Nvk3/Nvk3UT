Nvk3UT = Nvk3UT or {}

local M = Nvk3UT

M.QuestTracker = M.QuestTracker or {}
local Module = M.QuestTracker

local EM = EVENT_MANAGER
local WM = WINDOW_MANAGER

local EVENT_NAMESPACE = "Nvk3UT_QuestTracker"

local DEFAULT_LAYOUT = {
    x = 400,
    y = 200,
    width = 320,
    height = 420,
    scale = 1,
}

local DEFAULT_SETTINGS = {
    enabled = true,
    hideDefault = false,
    hideInCombat = false,
    lock = false,
    autoGrowV = true,
    autoGrowH = false,
    autoExpand = true,
    tooltips = true,
}

Module._initialized = Module._initialized or false
Module._sv = Module._sv or nil
Module._settings = Module._settings or nil
Module._layout = Module._layout or nil
Module._collapse = Module._collapse or nil
Module._root = Module._root or nil
Module._view = Module._view or nil
Module._modelCallback = Module._modelCallback or nil
Module._lastSnapshot = Module._lastSnapshot or nil
Module._dragging = false
Module._inCombat = false

local DEFAULT_TRACKER_FRAGMENTS = {
    "FOCUSED_QUEST_TRACKER_FRAGMENT",
    "FOCUSED_QUEST_TRACKER_ALWAYS_SHOW_FRAGMENT",
    "FOCUSED_QUEST_TRACKER_TRACKED_FRAGMENT",
    "FOCUSED_QUEST_TRACKER_FOCUSED_FRAGMENT",
    "GAMEPAD_QUEST_TRACKER_FRAGMENT",
}

local DEFAULT_TRACKER_REASON = "Nvk3UT_QuestTracker"

local function debugLog(message)
    if not (Module._sv and Module._sv.debug) then
        return
    end

    if type(message) ~= "string" then
        message = tostring(message)
    end

    if d then
        d(string.format("[Nvk3UT] QuestTracker: %s", message))
    end
end

local function copyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            target[key] = target[key] or {}
            copyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function ensureSavedVars()
    local root = M.sv
    if not root then
        return
    end

    root.questTracker = root.questTracker or {}
    local sv = root.questTracker

    sv.layout = sv.layout or {}
    sv.settings = sv.settings or {}
    sv.collapse = sv.collapse or {}

    copyDefaults(sv.layout, DEFAULT_LAYOUT)
    copyDefaults(sv.settings, DEFAULT_SETTINGS)

    Module._sv = sv
    Module._settings = sv.settings
    Module._layout = sv.layout
    Module._collapse = sv.collapse
end

local function setDefaultTrackerHidden(hidden)
    for index = 1, #DEFAULT_TRACKER_FRAGMENTS do
        local fragment = _G and _G[DEFAULT_TRACKER_FRAGMENTS[index]]
        if fragment and fragment.SetHiddenForReason then
            fragment:SetHiddenForReason(DEFAULT_TRACKER_REASON, hidden)
        end
    end

    local tracker = _G and _G.FOCUSED_QUEST_TRACKER
    if tracker and tracker.SetHiddenForReason then
        tracker:SetHiddenForReason(DEFAULT_TRACKER_REASON, hidden)
    end

    local trackerControl = tracker and tracker.control
    if trackerControl and trackerControl.SetHidden then
        trackerControl:SetHidden(hidden)
    end
end

local function applyDefaultTrackerVisibility()
    if not Module._settings then
        return
    end

    setDefaultTrackerHidden(Module._settings.hideDefault == true)
end

local function applyLockState()
    if not Module._root then
        return
    end

    local locked = Module._settings.lock == true
    Module._root:SetMovable(not locked)
    Module._root:SetMouseEnabled(true)
end

local function applyScale()
    if not Module._root or not Module._layout then
        return
    end

    Module._root:SetScale(Module._layout.scale or 1)
end

local function clampToScreen()
    if not Module._root then
        return
    end

    Module._root:SetClampedToScreen(true)
end

local function applyPosition()
    if not Module._root or not Module._layout then
        return
    end

    Module._root:ClearAnchors()
    Module._root:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, Module._layout.x or DEFAULT_LAYOUT.x, Module._layout.y or DEFAULT_LAYOUT.y)
    Module._root:SetDimensions(Module._layout.width or DEFAULT_LAYOUT.width, Module._layout.height or DEFAULT_LAYOUT.height)
end

local function savePosition()
    if not Module._root or not Module._layout then
        return
    end

    Module._layout.x = math.floor(Module._root:GetLeft())
    Module._layout.y = math.floor(Module._root:GetTop())
end

local function saveDimensions()
    if not Module._root or not Module._layout then
        return
    end

    Module._layout.width = math.floor(Module._root:GetWidth())
    Module._layout.height = math.floor(Module._root:GetHeight())
end

local function shouldHideTracker()
    if not Module._settings then
        return false
    end

    if Module._settings.enabled == false then
        return true
    end

    if Module._settings.hideInCombat and Module._inCombat then
        return true
    end

    return false
end

local function updateRootHidden()
    if Module._root then
        Module._root:SetHidden(shouldHideTracker())
    end
end

local function ensureRootControl()
    if Module._root then
        return Module._root
    end

    local existing = _G and _G.Nvk3UT_QuestTrackerRoot
    local control

    if existing then
        control = existing
    else
        control = WM:CreateTopLevelWindow("Nvk3UT_QuestTrackerRoot")
        debugLog("Created quest tracker root control")
    end

    control:SetMouseEnabled(true)
    control:SetMovable(true)
    control:SetResizeHandleSize(8)
    control:SetClampedToScreen(true)
    control:SetDrawTier(DT_HIGH)
    control:SetHidden(true)

    control:SetHandler("OnMoveStop", function()
        savePosition()
    end)

    control:SetHandler("OnResizeStop", function()
        saveDimensions()
    end)

    Module._root = control

    return control
end

local function onSnapshot(snapshot)
    Module._lastSnapshot = snapshot

    if Module._view then
        Module._view:Refresh(snapshot, {
            collapse = Module._collapse,
            autoGrowV = Module._settings.autoGrowV,
            autoGrowH = Module._settings.autoGrowH,
            autoExpand = Module._settings.autoExpand,
            tooltips = Module._settings.tooltips,
        })
    end

    updateRootHidden()

    saveDimensions()
end

local function subscribeToModel()
    if Module._modelCallback then
        return
    end

    Module._modelCallback = function(snapshot)
        onSnapshot(snapshot)
    end

    if M.QuestModel and M.QuestModel.Subscribe then
        M.QuestModel.Subscribe(Module._modelCallback)
    end
end

local function unsubscribeFromModel()
    if not Module._modelCallback then
        return
    end

    if M.QuestModel and M.QuestModel.Unsubscribe then
        M.QuestModel.Unsubscribe(Module._modelCallback)
    end

    Module._modelCallback = nil
end

local function ensureView()
    if Module._view then
        return Module._view
    end

    if not M.QuestTrackerView or not M.QuestTrackerView.Init then
        return nil
    end

    Module._view = M.QuestTrackerView
    Module._view:Init(ensureRootControl(), {
        collapse = Module._collapse,
        autoGrowV = Module._settings.autoGrowV,
        autoGrowH = Module._settings.autoGrowH,
        tooltips = Module._settings.tooltips,
    })

    return Module._view
end

local function onCombatState(_, inCombat)
    Module._inCombat = inCombat
    updateRootHidden()
end

local function registerEvents()
    EM:RegisterForEvent(EVENT_NAMESPACE, EVENT_PLAYER_COMBAT_STATE, onCombatState)
end

local function unregisterEvents()
    EM:UnregisterForEvent(EVENT_NAMESPACE, EVENT_PLAYER_COMBAT_STATE)
end

function Module.Init(opts)
    if Module._initialized then
        return
    end

    ensureSavedVars()

    opts = opts or {}
    if opts.debug then
        Module._sv.debug = true
    end

    ensureRootControl()
    applyPosition()
    clampToScreen()
    applyScale()
    applyLockState()

    ensureView()

    subscribeToModel()
    registerEvents()

    Module._initialized = true

    applyDefaultTrackerVisibility()
    updateRootHidden()

    if opts.runSelfTest and Module.RunSelfTest then
        Module.RunSelfTest()
    end
end

function Module.Shutdown()
    if not Module._initialized then
        return
    end

    unregisterEvents()
    unsubscribeFromModel()

    if Module._view and Module._view.Dispose then
        Module._view:Dispose()
    end

    Module._view = nil
    Module._root = nil
    Module._initialized = false

    setDefaultTrackerHidden(false)
end

function Module.Refresh()
    if not Module._initialized then
        return
    end

    if Module._view and Module._lastSnapshot then
        onSnapshot(Module._lastSnapshot)
    elseif Module._view and M.QuestModel and M.QuestModel.GetSnapshot then
        onSnapshot(M.QuestModel.GetSnapshot())
    end
end

function Module.SetEnabled(enabled)
    if not Module._settings then
        return
    end

    Module._settings.enabled = enabled == true
    updateRootHidden()
end

function Module.SetHideDefaultTracker(flag)
    if not Module._settings then
        return
    end

    Module._settings.hideDefault = flag == true
    applyDefaultTrackerVisibility()
end

function Module.SetHideInCombat(flag)
    if not Module._settings then
        return
    end

    Module._settings.hideInCombat = flag == true
    updateRootHidden()
end

function Module.SetLock(flag)
    if not Module._settings then
        return
    end

    Module._settings.lock = flag == true
    applyLockState()
end

function Module.SetAutoGrowVertical(flag)
    if not Module._settings then
        return
    end

    Module._settings.autoGrowV = flag ~= false
    if Module._view and Module._view.ApplyAutoGrow then
        Module._view:ApplyAutoGrow(Module._settings.autoGrowV, Module._settings.autoGrowH)
    end
    Module.Refresh()
end

function Module.SetAutoGrowHorizontal(flag)
    if not Module._settings then
        return
    end

    Module._settings.autoGrowH = flag == true
    if Module._view and Module._view.ApplyAutoGrow then
        Module._view:ApplyAutoGrow(Module._settings.autoGrowV, Module._settings.autoGrowH)
    end
    Module.Refresh()
end

function Module.SetAutoExpand(flag)
    if not Module._settings then
        return
    end

    Module._settings.autoExpand = flag ~= false
    Module.Refresh()
end

function Module.SetTooltips(flag)
    if not Module._settings then
        return
    end

    Module._settings.tooltips = flag ~= false
    if Module._view and Module._view.SetTooltipsEnabled then
        Module._view:SetTooltipsEnabled(Module._settings.tooltips)
    end
end

function Module.SetScale(scale)
    if not Module._layout then
        return
    end

    Module._layout.scale = math.max(0.5, math.min(2.0, tonumber(scale) or 1))
    applyScale()
end

function Module.GetCollapseTable()
    return Module._collapse or {}
end

function Module.ToggleCollapseState(journalIndex)
    if not Module._collapse then
        return
    end

    local key = tostring(journalIndex)
    Module._collapse[key] = not Module._collapse[key]
end

function Module.SetCollapseState(journalIndex, collapsed)
    if not Module._collapse then
        return
    end

    Module._collapse[tostring(journalIndex)] = collapsed == true
end

function Module.ShouldCollapse(journalIndex)
    if not Module._collapse then
        return false
    end

    return Module._collapse[tostring(journalIndex)] == true
end

function Module.ApplySnapshot(snapshot)
    onSnapshot(snapshot)
end

function Module.RunSelfTest()
    if not Module._sv or not Module._sv.debug then
        return
    end

    local snapshot = M.QuestModel and M.QuestModel.GetSnapshot and M.QuestModel.GetSnapshot()
    if snapshot then
        debugLog(string.format("SelfTest: quests=%d", #snapshot.quests))
    else
        debugLog("SelfTest: snapshot unavailable")
    end
end

function Module.RegisterLamPanel(panelControl)
    Module._lamPanel = panelControl
end

