-- Tracker/Golden/Nvk3UT_GoldenTrackerController.lua
-- Provides a stub controller for the Golden tracker mirroring the Endeavor tracker API.

local addonName = "Nvk3UT"

Nvk3UT = Nvk3UT or {}

local Controller = Nvk3UT.GoldenTrackerController or {}
Nvk3UT.GoldenTrackerController = Controller

local state = {
    dirty = true,
    viewModel = nil,
}

local MODULE_TAG = addonName .. ".GoldenTrackerController"

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

local function ensureViewModel()
    if type(state.viewModel) ~= "table" then
        state.viewModel = { categories = {} }
    else
        local categories = state.viewModel.categories
        if type(categories) ~= "table" then
            state.viewModel.categories = {}
        end
    end

    return state.viewModel
end

function Controller:Init()
    state.dirty = true
    state.viewModel = nil
    safeDebug("Init")
end

function Controller:MarkDirty()
    state.dirty = true
end

function Controller:IsDirty()
    return state.dirty == true
end

function Controller:ClearDirty()
    state.dirty = false
end

function Controller:BuildViewModel()
    local categories = {
        {
            id = "GOLDEN_DAILY",
            name = "GOLDEN — DAILY",
            entries = {
                {
                    id = "GOLDEN_SAMPLE_ENTRY_1",
                    title = "Example Golden Daily",
                    count = 0,
                    max = 1,
                    objectives = {
                        {
                            id = "obj1",
                            title = "Do a golden thing",
                            progress = 0,
                            max = 1,
                        },
                    },
                },
            },
        },
        {
            id = "GOLDEN_WEEKLY",
            name = "GOLDEN — WEEKLY",
            entries = {},
        },
    }

    state.viewModel = {
        categories = categories,
    }

    local viewModel = ensureViewModel()
    state.dirty = false

    local count = #(viewModel.categories or {})
    safeDebug("BuildViewModel done, cats=%d", count)

    return viewModel
end

function Controller:GetViewModel()
    return ensureViewModel()
end

return Controller
