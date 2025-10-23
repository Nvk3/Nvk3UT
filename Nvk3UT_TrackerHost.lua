local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}
Nvk3UT.UI = Nvk3UT.UI or {}

local TrackerHost = {}
TrackerHost.__index = TrackerHost

local ROOT_CONTROL_NAME = addonName .. "_UI_Root"
local QUEST_CONTAINER_NAME = addonName .. "_QuestContainer"
local ACHIEVEMENT_CONTAINER_NAME = addonName .. "_AchievementContainer"

local DEFAULT_WINDOW = {
    left = 200,
    top = 200,
    width = 360,
    height = 640,
    locked = false,
}

local MIN_WIDTH = 260
local MIN_HEIGHT = 240
local SECTION_SPACING = 12
local RESIZE_HANDLE_SIZE = 12

local LEFT_MOUSE_BUTTON = _G.MOUSE_BUTTON_INDEX_LEFT or 1

local state = {
    initialized = false,
    root = nil,
    questContainer = nil,
    achievementContainer = nil,
    window = nil,
}

local function cloneTable(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, entry in pairs(value) do
        copy[key] = cloneTable(entry)
    end
    return copy
end

local function getSavedVars()
    return Nvk3UT and Nvk3UT.sv
end

local function ensureWindowSettings()
    local sv = getSavedVars()
    if not sv then
        return cloneTable(DEFAULT_WINDOW)
    end

    sv.General = sv.General or {}
    sv.General.window = sv.General.window or {}

    local window = sv.General.window
    if type(window.left) ~= "number" then
        window.left = tonumber(window.left) or DEFAULT_WINDOW.left
    end
    if type(window.top) ~= "number" then
        window.top = tonumber(window.top) or DEFAULT_WINDOW.top
    end
    if type(window.width) ~= "number" then
        window.width = tonumber(window.width) or DEFAULT_WINDOW.width
    end
    if type(window.height) ~= "number" then
        window.height = tonumber(window.height) or DEFAULT_WINDOW.height
    end
    if window.locked == nil then
        window.locked = DEFAULT_WINDOW.locked
    end

    return window
end

local function clampWindowToScreen(width, height)
    if not GuiRoot then
        return
    end

    local rootWidth = GuiRoot:GetWidth() or 0
    local rootHeight = GuiRoot:GetHeight() or 0

    local window = state.window
    if not window then
        return
    end

    local maxLeft = math.max(0, rootWidth - width)
    local maxTop = math.max(0, rootHeight - height)

    window.left = math.min(math.max(window.left or 0, 0), maxLeft)
    window.top = math.min(math.max(window.top or 0, 0), maxTop)
end

local function saveWindowPosition()
    if not (state.root and state.window) then
        return
    end

    local left = state.root:GetLeft() or state.window.left or 0
    local top = state.root:GetTop() or state.window.top or 0

    state.window.left = math.floor(left + 0.5)
    state.window.top = math.floor(top + 0.5)
end

local function saveWindowSize()
    if not (state.root and state.window) then
        return
    end

    local width = math.max(state.root:GetWidth() or state.window.width or MIN_WIDTH, MIN_WIDTH)
    local height = math.max(state.root:GetHeight() or state.window.height or MIN_HEIGHT, MIN_HEIGHT)

    state.window.width = math.floor(width + 0.5)
    state.window.height = math.floor(height + 0.5)
end

local function updateSectionLayout()
    if not state.root then
        return
    end

    local baseWidth = math.max(state.root:GetWidth() or MIN_WIDTH, MIN_WIDTH)
    local questWidth = baseWidth

    if state.questContainer then
        local currentWidth = state.questContainer:GetWidth() or 0
        if currentWidth < baseWidth then
            state.questContainer:SetWidth(baseWidth)
            questWidth = baseWidth
        else
            questWidth = currentWidth
        end
    end

    if state.achievementContainer then
        state.achievementContainer:SetWidth(questWidth)
    end
end

local function applyWindowLock()
    if not (state.root and state.window) then
        return
    end

    local locked = state.window.locked == true
    state.root:SetMovable(not locked)
    state.root:SetResizeHandleSize(locked and 0 or RESIZE_HANDLE_SIZE)
end

local function applyWindowGeometry()
    if not (state.root and state.window) then
        return
    end

    local width = math.max(tonumber(state.window.width) or DEFAULT_WINDOW.width, MIN_WIDTH)
    local height = math.max(tonumber(state.window.height) or DEFAULT_WINDOW.height, MIN_HEIGHT)
    clampWindowToScreen(width, height)

    local left = tonumber(state.window.left) or DEFAULT_WINDOW.left
    local top = tonumber(state.window.top) or DEFAULT_WINDOW.top

    state.window.left = left
    state.window.top = top
    state.window.width = width
    state.window.height = height

    state.root:ClearAnchors()
    state.root:SetAnchor(TOPLEFT, GuiRoot or state.root:GetParent(), TOPLEFT, left, top)
    state.root:SetDimensions(width, height)
    state.root:SetHidden(false)
    state.root:SetClampedToScreen(true)
end

local function applyWindowSettings()
    state.window = ensureWindowSettings()

    if not state.root then
        return
    end

    applyWindowGeometry()
    applyWindowLock()
    updateSectionLayout()
end

local function createRootControl()
    if state.root or not WINDOW_MANAGER then
        return
    end

    local control = WINDOW_MANAGER:CreateTopLevelWindow(ROOT_CONTROL_NAME)
    if not control then
        return
    end

    control:SetMouseEnabled(true)
    control:SetMovable(true)
    control:SetClampedToScreen(true)
    control:SetResizeHandleSize(RESIZE_HANDLE_SIZE)
    if control.SetDimensionConstraints then
        control:SetDimensionConstraints(MIN_WIDTH, MIN_HEIGHT)
    end
    control:SetDrawLayer(DL_BACKGROUND)
    control:SetDrawTier(DT_LOW)
    control:SetDrawLevel(0)

    control:SetHandler("OnMouseDown", function(ctrl, button)
        if button ~= LEFT_MOUSE_BUTTON then
            return
        end
        if state.window and state.window.locked then
            return
        end
        ctrl:StartMoving()
    end)

    control:SetHandler("OnMouseUp", function(ctrl, button)
        if button == LEFT_MOUSE_BUTTON then
            ctrl:StopMovingOrResizing()
            saveWindowPosition()
        end
    end)

    control:SetHandler("OnMoveStop", function()
        saveWindowPosition()
    end)

    control:SetHandler("OnResizeStop", function()
        saveWindowSize()
        applyWindowGeometry()
        updateSectionLayout()
    end)

    state.root = control
    Nvk3UT.UI.Root = control
end

local function createContainers()
    if not (state.root and WINDOW_MANAGER) then
        return
    end

    if not state.questContainer then
        local questContainer = WINDOW_MANAGER:CreateControl(QUEST_CONTAINER_NAME, state.root, CT_CONTROL)
        questContainer:SetAnchor(TOPLEFT, state.root, TOPLEFT, 0, 0)
        questContainer:SetMouseEnabled(false)
        state.questContainer = questContainer
        Nvk3UT.UI.QuestContainer = questContainer
    end

    if not state.achievementContainer then
        local achievementContainer = WINDOW_MANAGER:CreateControl(ACHIEVEMENT_CONTAINER_NAME, state.root, CT_CONTROL)
        achievementContainer:SetAnchor(TOPLEFT, state.questContainer or state.root, BOTTOMLEFT, 0, SECTION_SPACING)
        achievementContainer:SetMouseEnabled(false)
        state.achievementContainer = achievementContainer
        Nvk3UT.UI.AchievementContainer = achievementContainer
    end

    updateSectionLayout()
end

local function initModels(debugEnabled)
    if Nvk3UT.QuestModel and Nvk3UT.QuestModel.Init then
        pcall(Nvk3UT.QuestModel.Init, { debug = debugEnabled })
    end

    if Nvk3UT.AchievementModel and Nvk3UT.AchievementModel.Init then
        pcall(Nvk3UT.AchievementModel.Init, { debug = debugEnabled })
    end
end

local function initTrackers(debugEnabled)
    local sv = getSavedVars()
    if not sv then
        return
    end

    local questOpts = cloneTable(sv.QuestTracker or {})
    questOpts.debug = debugEnabled
    if Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.Init and state.questContainer then
        pcall(Nvk3UT.QuestTracker.Init, state.questContainer, questOpts)
    end

    local achievementOpts = cloneTable(sv.AchievementTracker or {})
    achievementOpts.debug = debugEnabled
    if Nvk3UT.AchievementTracker and Nvk3UT.AchievementTracker.Init and state.achievementContainer then
        pcall(Nvk3UT.AchievementTracker.Init, state.achievementContainer, achievementOpts)
    end
end

function TrackerHost.Init()
    if state.initialized then
        return
    end

    if not getSavedVars() then
        return
    end

    state.window = ensureWindowSettings()

    createRootControl()
    createContainers()
    applyWindowSettings()

    local debugEnabled = (Nvk3UT and Nvk3UT.sv and Nvk3UT.sv.debug) == true

    initModels(debugEnabled)
    initTrackers(debugEnabled)

    TrackerHost.ApplySettings()
    TrackerHost.ApplyTheme()
    TrackerHost.Refresh()

    if Nvk3UT.UI and Nvk3UT.UI.BuildLAM then
        Nvk3UT.UI.BuildLAM()
    elseif Nvk3UT.LAM and Nvk3UT.LAM.Build then
        Nvk3UT.LAM.Build(addonName)
    end

    state.initialized = true
end

function TrackerHost.ApplySettings()
    if not getSavedVars() then
        return
    end

    applyWindowSettings()

    local sv = getSavedVars()

    if Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.ApplySettings then
        pcall(Nvk3UT.QuestTracker.ApplySettings, cloneTable(sv.QuestTracker or {}))
    end

    if Nvk3UT.AchievementTracker and Nvk3UT.AchievementTracker.ApplySettings then
        pcall(Nvk3UT.AchievementTracker.ApplySettings, cloneTable(sv.AchievementTracker or {}))
    end
end

function TrackerHost.ApplyTheme()
    if not getSavedVars() then
        return
    end

    local sv = getSavedVars()

    if Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.ApplyTheme then
        pcall(Nvk3UT.QuestTracker.ApplyTheme, cloneTable(sv.QuestTracker or {}))
    end

    if Nvk3UT.AchievementTracker and Nvk3UT.AchievementTracker.ApplyTheme then
        pcall(Nvk3UT.AchievementTracker.ApplyTheme, cloneTable(sv.AchievementTracker or {}))
    end

    updateSectionLayout()
end

function TrackerHost.Refresh()
    if Nvk3UT.QuestTracker then
        if Nvk3UT.QuestTracker.RequestRefresh then
            pcall(Nvk3UT.QuestTracker.RequestRefresh)
        elseif Nvk3UT.QuestTracker.Refresh then
            pcall(Nvk3UT.QuestTracker.Refresh)
        end
    end

    if Nvk3UT.AchievementTracker then
        if Nvk3UT.AchievementTracker.RequestRefresh then
            pcall(Nvk3UT.AchievementTracker.RequestRefresh)
        elseif Nvk3UT.AchievementTracker.Refresh then
            pcall(Nvk3UT.AchievementTracker.Refresh)
        end
    end

    updateSectionLayout()
end

function TrackerHost.Shutdown()
    if Nvk3UT.QuestTracker and Nvk3UT.QuestTracker.Shutdown then
        pcall(Nvk3UT.QuestTracker.Shutdown)
    end

    if Nvk3UT.AchievementTracker and Nvk3UT.AchievementTracker.Shutdown then
        pcall(Nvk3UT.AchievementTracker.Shutdown)
    end

    if Nvk3UT.QuestModel and Nvk3UT.QuestModel.Shutdown then
        pcall(Nvk3UT.QuestModel.Shutdown)
    end

    if Nvk3UT.AchievementModel and Nvk3UT.AchievementModel.Shutdown then
        pcall(Nvk3UT.AchievementModel.Shutdown)
    end

    if state.achievementContainer then
        state.achievementContainer:SetHidden(true)
        state.achievementContainer:SetParent(nil)
    end
    state.achievementContainer = nil
    Nvk3UT.UI.AchievementContainer = nil

    if state.questContainer then
        state.questContainer:SetHidden(true)
        state.questContainer:SetParent(nil)
    end
    state.questContainer = nil
    Nvk3UT.UI.QuestContainer = nil

    if state.root then
        state.root:SetHandler("OnMouseDown", nil)
        state.root:SetHandler("OnMouseUp", nil)
        state.root:SetHandler("OnMoveStop", nil)
        state.root:SetHandler("OnResizeStop", nil)
        state.root:SetHidden(true)
        state.root:SetParent(nil)
    end
    state.root = nil
    Nvk3UT.UI.Root = nil

    state.initialized = false
end

Nvk3UT.TrackerHost = TrackerHost

return TrackerHost
