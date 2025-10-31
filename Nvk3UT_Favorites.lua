Nvk3UT = Nvk3UT or {}

local function logShim(action)
    local diagnostics = Nvk3UT and Nvk3UT.Diagnostics
    if diagnostics and diagnostics.Debug then
        diagnostics.Debug("Favorites SHIM -> %s", tostring(action))
    end
end

local function resolveCategory()
    return Nvk3UT and Nvk3UT.FavoritesCategory
end

local function safeCall(method, ...)
    local SafeCall = Nvk3UT and Nvk3UT.SafeCall
    if type(SafeCall) == "function" then
        return SafeCall(method, ...)
    end

    if type(method) ~= "function" then
        return nil
    end

    local ok, result = pcall(method, ...)
    if ok then
        return result
    end

    return nil
end

local Shim = {}
Nvk3UT.Favorites = Shim

function Shim.Init(...)
    logShim("Init")
    local category = resolveCategory()
    if not category or type(category.Init) ~= "function" then
        return nil
    end
    return safeCall(category.Init, category, ...)
end

function Shim.Refresh(...)
    logShim("Refresh")
    local category = resolveCategory()
    if not category or type(category.Refresh) ~= "function" then
        return nil
    end
    return safeCall(category.Refresh, category, ...)
end

function Shim.SetVisible(...)
    logShim("SetVisible")
    local category = resolveCategory()
    if not category or type(category.SetVisible) ~= "function" then
        return nil
    end
    return safeCall(category.SetVisible, category, ...)
end

function Shim.GetHeight(...)
    local category = resolveCategory()
    if not category or type(category.GetHeight) ~= "function" then
        return 0
    end
    local height = safeCall(category.GetHeight, category, ...)
    return tonumber(height) or 0
end

function Shim.Remove(...)
    logShim("Remove")
    local category = resolveCategory()
    if not category or type(category.Remove) ~= "function" then
        return false
    end
    local result = safeCall(category.Remove, category, ...)
    return result and true or false
end

return Shim
