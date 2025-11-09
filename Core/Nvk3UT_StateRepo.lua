Nvk3UT = Nvk3UT or {}

local Repo = {}
Nvk3UT.StateRepo = Repo
Nvk3UT_StateRepo = Repo

local state = {
    addon = nil,
    account = nil,
    defaults = {
        ui = nil,
        host = nil,
    },
}

local function getAddon()
    if state.addon then
        return state.addon
    end
    if Nvk3UT then
        return Nvk3UT
    end
    return nil
end

local function isDebugEnabled()
    local addon = getAddon()
    if not addon then
        return false
    end
    if addon.IsDebugEnabled then
        return addon:IsDebugEnabled() == true
    end
    return addon.debugEnabled == true
end

local function debugLog(fmt, ...)
    if not isDebugEnabled() then
        return
    end

    local addon = getAddon()
    if addon and addon.Debug then
        addon.Debug("[StateRepo] " .. tostring(fmt), ...)
        return
    end

    if d then
        local ok, message = pcall(string.format, tostring(fmt), ...)
        if not ok then
            message = tostring(fmt)
        end
        d(string.format("[Nvk3UT][StateRepo] %s", message))
    end
end

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[key] = deepCopy(child)
    end
    return copy
end

local function ensureDefaults()
    if state.defaults.ui and state.defaults.host then
        return
    end

    local init = Nvk3UT_StateInit
    if not init then
        return
    end

    if not state.defaults.ui and init.GetUIDefaults then
        state.defaults.ui = init.GetUIDefaults()
    end

    if not state.defaults.host and init.GetHostDefaults then
        state.defaults.host = init.GetHostDefaults()
    end
end

local function ensureAccount()
    if state.account then
        return state.account
    end

    local addon = getAddon()
    local account = addon and addon.SV
    if type(account) == "table" then
        state.account = account
        return account
    end

    return nil
end

local function ensureTable(parent, key)
    if type(parent) ~= "table" then
        return nil
    end

    local value = parent[key]
    if type(value) ~= "table" then
        value = {}
        parent[key] = value
    end

    return value
end

local function splitKey(key)
    if type(key) ~= "string" or key == "" then
        return {}
    end

    local segments = {}
    for segment in string.gmatch(key, "[^%.]+") do
        segments[#segments + 1] = segment
    end

    return segments
end

local function resolvePath(root, segments, create)
    local parent = root
    for index = 1, (#segments - 1) do
        if type(parent) ~= "table" then
            return nil, nil
        end
        local segment = segments[index]
        local child = parent[segment]
        if type(child) ~= "table" then
            if not create then
                return nil, nil
            end
            child = {}
            parent[segment] = child
        end
        parent = child
    end
    local last = segments[#segments]
    return parent, last
end

local function isHexColor(text)
    if type(text) ~= "string" then
        return false
    end
    return text:match("^#%x%x%x%x%x%x%x%x$") ~= nil
end

local function clamp01(value)
    if value == nil then
        return nil
    end
    local numeric = tonumber(value)
    if not numeric then
        return nil
    end
    if numeric > 1 then
        if numeric <= 255 then
            numeric = numeric / 255
        end
    end
    if numeric < 0 then
        numeric = 0
    elseif numeric > 1 then
        numeric = 1
    end
    return numeric
end

local function normalizeColor(value, fallback)
    if type(value) == "string" then
        local sanitized = value:match("^#?([%x]+)$")
        if sanitized and (#sanitized == 6 or #sanitized == 8) then
            if #sanitized == 6 then
                sanitized = sanitized .. "FF"
            end
            return "#" .. sanitized:upper()
        end
        return fallback
    end

    if type(value) == "table" then
        local r = clamp01(value.r or value[1])
        local g = clamp01(value.g or value[2])
        local b = clamp01(value.b or value[3])
        local a = clamp01(value.a or value[4])
        if not r or not g or not b then
            return fallback
        end
        if not a then
            if type(fallback) == "string" then
                local suffix = fallback:sub(-2)
                if suffix:match("^%x%x$") then
                    a = tonumber(suffix, 16) / 255
                end
            end
            a = a or 1
        end
        local function toHex(component)
            return string.format("%02X", math.floor(component * 255 + 0.5))
        end
        return string.format("#%s%s%s%s", toHex(r), toHex(g), toHex(b), toHex(a))
    end

    if type(value) == "number" then
        local component = clamp01(value)
        if not component then
            return fallback
        end
        local hex = string.format("%02X", math.floor(component * 255 + 0.5))
        return string.format("#%s%s%s", hex, hex, hex) .. "FF"
    end

    return fallback
end

local function deepEqual(a, b)
    if a == b then
        return true
    end

    if type(a) ~= type(b) then
        return false
    end

    if type(a) ~= "table" then
        return false
    end

    for key, value in pairs(a) do
        if not deepEqual(value, b[key]) then
            return false
        end
    end

    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end

    return true
end

local function getDefaultForPath(segments)
    ensureDefaults()
    local defaults = state.defaults.ui
    if not defaults then
        return nil
    end

    local node = defaults
    for index = 1, #segments do
        if type(node) ~= "table" then
            return nil
        end
        node = node[segments[index]]
        if node == nil then
            return nil
        end
    end

    return deepCopy(node)
end

local function readFromPath(container, defaults, segments)
    local node = container
    local defaultNode = defaults

    for index = 1, #segments do
        local segment = segments[index]
        if type(node) == "table" then
            node = node[segment]
        else
            node = nil
        end

        if type(defaultNode) == "table" then
            defaultNode = defaultNode[segment]
        else
            defaultNode = nil
        end

        if node == nil and defaultNode == nil then
            return nil
        end

        if node == nil then
            node = defaultNode
            defaultNode = nil
        end
    end

    if type(node) == "table" then
        return deepCopy(node)
    end

    if type(defaultNode) == "table" then
        return deepCopy(defaultNode)
    end

    if type(defaultNode) == "string" and isHexColor(defaultNode) then
        return normalizeColor(node, defaultNode)
    end

    if node ~= nil then
        return node
    end

    return defaultNode
end

local function sanitizeForWrite(value, default)
    local defaultType = type(default)
    if defaultType == "table" then
        local sanitized = {}
        local source = type(value) == "table" and value or {}
        for key, defValue in pairs(default) do
            sanitized[key] = sanitizeForWrite(source[key], defValue)
        end
        for key, child in pairs(source) do
            if default[key] == nil then
                sanitized[key] = sanitizeForWrite(child, nil)
            end
        end
        return sanitized
    elseif defaultType == "number" then
        local numeric = tonumber(value)
        if not numeric then
            return default
        end
        return numeric
    elseif defaultType == "boolean" then
        if default then
            return value == true
        end
        return value ~= false
    elseif defaultType == "string" then
        if isHexColor(default) then
            return normalizeColor(value, default)
        end
        if value == nil then
            return default
        end
        return tostring(value)
    elseif default ~= nil then
        if value == nil then
            return default
        end
    end

    return value
end

local function applySanitized(parent, key, sanitized, default)
    if default == nil then
        parent[key] = sanitized
        return
    end

    local defaultType = type(default)
    if defaultType == "table" then
        local target = parent[key]
        if type(target) ~= "table" then
            target = {}
            parent[key] = target
        end

        local empty = true
        for childKey, defValue in pairs(default) do
            applySanitized(target, childKey, sanitized and sanitized[childKey], defValue)
            if target[childKey] ~= nil then
                empty = false
            end
        end

        if type(sanitized) == "table" then
            for childKey, childValue in pairs(sanitized) do
                if default[childKey] == nil then
                    if childValue == nil then
                        target[childKey] = nil
                    else
                        target[childKey] = childValue
                        empty = false
                    end
                end
            end
        end

        if empty and next(target) == nil then
            parent[key] = nil
        end
        return
    end

    if sanitized == nil or sanitized == default then
        parent[key] = nil
    else
        parent[key] = sanitized
    end
end

function Repo.UI_GetOption(key)
    if key == nil or key == "" then
        ensureDefaults()
        local account = ensureAccount()
        if not account then
            return deepCopy(state.defaults.ui or {})
        end
        local ui = ensureTable(account, "ui")
        return deepCopy(ui)
    end

    local segments = splitKey(key)
    if #segments == 0 then
        return nil
    end

    local account = ensureAccount()
    if not account then
        return getDefaultForPath(segments)
    end

    ensureDefaults()
    local ui = ensureTable(account, "ui")
    local defaults = state.defaults.ui or {}
    local value = readFromPath(ui, defaults, segments)
    if type(value) == "string" and isHexColor(value) then
        return value:upper()
    end
    return value
end

function Repo.UI_SetOption(key, value)
    local segments = splitKey(key)
    if #segments == 0 then
        return
    end

    local account = ensureAccount()
    if not account then
        return
    end

    ensureDefaults()
    local ui = ensureTable(account, "ui")
    local defaults = state.defaults.ui or {}
    local defaultValue = readFromPath(defaults, nil, segments)
    local sanitized = sanitizeForWrite(value, defaultValue)
    local parent, finalKey = resolvePath(ui, segments, true)
    if not parent or not finalKey then
        return
    end

    applySanitized(parent, finalKey, sanitized, defaultValue)
    debugLog("UI option %s updated", key)
end

local function ensureHostTable()
    local account = ensureAccount()
    if not account then
        return nil
    end
    return ensureTable(account, "host")
end

local function sanitizeHostField(key, value, default)
    local kind = type(default)
    if kind == "number" then
        local numeric = tonumber(value)
        if not numeric then
            return default
        end
        return math.floor(numeric + 0.5)
    elseif kind == "boolean" then
        if key == "visible" or key == "clamp" then
            return value ~= false
        else
            return value == true
        end
    end
    return value == nil and default or value
end

function Repo.Host_GetRect()
    ensureDefaults()
    local defaults = state.defaults.host
    local fallback = defaults and deepCopy(defaults) or {}
    local host = ensureHostTable()
    if not host then
        return fallback
    end

    local rect = {}
    if defaults then
        for key, default in pairs(defaults) do
            local stored = host[key]
            if stored == nil then
                rect[key] = default
            else
                rect[key] = sanitizeHostField(key, stored, default)
            end
        end
    end

    for key, value in pairs(host) do
        if defaults == nil or defaults[key] == nil then
            rect[key] = value
        end
    end

    return rect
end

function Repo.Host_SetRect(partial)
    if type(partial) ~= "table" then
        return Repo.Host_GetRect()
    end

    ensureDefaults()
    local defaults = state.defaults.host or {}
    local host = ensureHostTable()
    if not host then
        return Repo.Host_GetRect()
    end

    local changed = false
    for key, default in pairs(defaults) do
        if partial[key] ~= nil then
            local sanitized = sanitizeHostField(key, partial[key], default)
            local current = host[key]
            if current == nil then
                current = default
            else
                current = sanitizeHostField(key, current, default)
            end

            if sanitized == default then
                if host[key] ~= nil then
                    host[key] = nil
                    changed = true
                end
            elseif current ~= sanitized or host[key] ~= sanitized then
                host[key] = sanitized
                changed = true
            end
        end
    end

    if changed then
        debugLog("Host rect updated (%s fields)", tostring(next(partial) ~= nil))
    end

    return Repo.Host_GetRect()
end

function Repo.Host_MergeRect(partial)
    if type(partial) ~= "table" then
        return Repo.Host_GetRect()
    end

    local rect = Repo.Host_GetRect() or {}
    for key, value in pairs(partial) do
        rect[key] = value
    end
    return Repo.Host_SetRect(rect)
end

function Repo.Init(accountSaved)
    ensureDefaults()

    if type(accountSaved) == "table" then
        state.account = accountSaved
    else
        state.account = ensureAccount()
    end

    local addon = getAddon()
    if addon and addon.SV and addon.SV ~= state.account then
        state.account = addon.SV
    end

    debugLog("State repository initialised")
end

function Repo.AttachToRoot(addon)
    if type(addon) ~= "table" then
        return
    end

    state.addon = addon
    addon.StateRepo = Repo
end

return Repo
