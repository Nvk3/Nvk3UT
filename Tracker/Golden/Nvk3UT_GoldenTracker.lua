local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local GoldenTracker = {}
GoldenTracker.__index = GoldenTracker

local MODULE_TAG = addonName .. ".GoldenTracker"

local state = {
    container = nil,
    currentHeight = 0,
    isInitialized = false,
    isDisposed = false,
    ui = nil,
}

local debugFlags = {
    refreshLogged = false,
}

local function safeDebug(message, ...)
    local debugFn = Nvk3UT and Nvk3UT.Debug
    if type(debugFn) ~= "function" then
        return
    end

    local payload = message
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, message, ...)
        if ok then
            payload = formatted
        end
    end

    pcall(debugFn, string.format("%s: %s", MODULE_TAG, tostring(payload)))
end

local function coerceHeight(value)
    if type(value) == "number" then
        if value ~= value then
            return 0
        end
        return value
    end

    return 0
end

local function ensureUi(container)
    if container == nil then
        return state.ui
    end

    local wm = rawget(_G, "WINDOW_MANAGER")
    if wm == nil then
        return state.ui
    end

    local ui = state.ui
    if type(ui) ~= "table" then
        ui = {}
        state.ui = ui
    end

    local containerName
    if type(container.GetName) == "function" then
        local ok, name = pcall(container.GetName, container)
        if ok and type(name) == "string" then
            containerName = name
        end
    end

    local baseName = (containerName or "Nvk3UT_Golden") .. "_"
    ui.baseName = baseName

    local root = ui.root
    if root == nil then
        local rootControlName = baseName .. "Root"
        local ok, control = pcall(function()
            return wm:CreateControl(rootControlName, container, CT_CONTROL)
        end)
        if ok and control then
            root = control
            if root.SetResizeToFitDescendents then
                root:SetResizeToFitDescendents(true)
            end
            if root.SetHidden then
                root:SetHidden(true)
            end
            if root.SetMouseEnabled then
                root:SetMouseEnabled(false)
            end
            ui.root = root
        end
    else
        if root.SetParent then
            root:SetParent(container)
        end
    end

    local content = ui.content
    local parentForContent = root or container
    if content == nil and parentForContent ~= nil then
        local contentControlName = baseName .. "Content"
        local ok, control = pcall(function()
            return wm:CreateControl(contentControlName, parentForContent, CT_CONTROL)
        end)
        if ok and control then
            content = control
            if content.SetResizeToFitDescendents then
                content:SetResizeToFitDescendents(true)
            end
            if content.SetHidden then
                content:SetHidden(true)
            end
            if content.SetMouseEnabled then
                content:SetMouseEnabled(false)
            end
            ui.content = content
        end
    elseif content and parentForContent and content.SetParent then
        content:SetParent(parentForContent)
    end

    return ui
end

function GoldenTracker.Init(sectionContainer)
    state.container = sectionContainer
    state.currentHeight = 0
    state.isDisposed = false
    GoldenTracker._disposed = false
    state.ui = nil

    if sectionContainer == nil then
        state.isInitialized = false
        safeDebug("Init skipped (no container)")
        return
    end

    state.isInitialized = true

    ensureUi(sectionContainer)

    if sectionContainer.SetHeight then
        sectionContainer:SetHeight(0)
    end

    if sectionContainer.SetHidden then
        sectionContainer:SetHidden(false)
    end

    local debugFn = Nvk3UT and Nvk3UT.Debug
    if type(debugFn) == "function" then
        pcall(debugFn, "GoldenTracker: Init")
    end
end

function GoldenTracker.Refresh(viewModel)
    if not state.isInitialized or state.isDisposed then
        return
    end

    local container = state.container
    if container == nil then
        state.currentHeight = 0
        return
    end

    local ui = ensureUi(container)

    local vm = type(viewModel) == "table" and viewModel or {}
    local settings = type(vm.settings) == "table" and vm.settings or {}
    local sectionVm = type(vm.section) == "table" and vm.section or {}

    local enabled = settings.enabled ~= false
    local hideEntireSection = sectionVm.hideEntireSection == true
    local shouldHide = not enabled or hideEntireSection

    if container.SetHidden then
        container:SetHidden(shouldHide)
    end

    local root = type(ui) == "table" and ui.root or nil
    if root and root.SetHidden then
        root:SetHidden(shouldHide)
    end

    local content = type(ui) == "table" and ui.content or nil
    if content and content.SetHidden then
        content:SetHidden(true)
    end

    if content and content.SetHeight then
        content:SetHeight(0)
    end

    state.currentHeight = 0
    if container.SetHeight then
        container:SetHeight(0)
    end

    if not debugFlags.refreshLogged then
        debugFlags.refreshLogged = true
        local debugFn = Nvk3UT and Nvk3UT.Debug
        if type(debugFn) == "function" then
            pcall(debugFn, "GoldenTracker: Refresh (stub)")
        end
    end
end

function GoldenTracker.GetHeight()
    return coerceHeight(state.currentHeight)
end

Nvk3UT.GoldenTracker = GoldenTracker

return GoldenTracker
