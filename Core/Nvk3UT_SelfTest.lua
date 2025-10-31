-- Core/Nvk3UT_SelfTest.lua
-- Lightweight sanity checks for Nvk3UT. This module must NOT touch UI, ESO events,
-- or SavedVariables creation. It can run very early, before the addon root exists.
-- TODO: Tracker UI presence tests from the legacy SelfTest touched live controls.
--       They will move into a future debug/inspector module once the UI layer is
--       refactored.
-- TODO: Legacy hooks/Recent verification relied on EVENT_MANAGER inspection.
--       Event wiring diagnostics will migrate into the dedicated Events layer.
-- TODO: Legacy recent count consistency checks depended on tracker state.
--       Those validations will move into Model/Runtime self-tests later.

Nvk3UT_SelfTest = Nvk3UT_SelfTest or {}
local SelfTest = Nvk3UT_SelfTest

-- Attach to the addon root when Core is ready without assuming it exists now.
function SelfTest.AttachToRoot(root)
    if type(root) ~= "table" then
        return
    end

    root.SelfTest = SelfTest
    return root.SelfTest
end

local function _format(fmt, ...)
    if fmt == nil then
        return ""
    end
    return string.format(tostring(fmt), ...)
end

-- Helper for safe logging without assuming Core is initialized
local function _debug(fmt, ...)
    if Nvk3UT and type(Nvk3UT.Debug) == "function" then
        Nvk3UT.Debug(fmt, ...)
    elseif Nvk3UT_Diagnostics and type(Nvk3UT_Diagnostics.Debug) == "function" then
        Nvk3UT_Diagnostics.Debug(fmt, ...)
    elseif type(d) == "function" then
        d(_format("[Nvk3UT SelfTest] %s", _format(fmt, ...)))
    end
end

local function _info(fmt, ...)
    if Nvk3UT_Diagnostics and type(Nvk3UT_Diagnostics.Warn) == "function" then
        Nvk3UT_Diagnostics.Warn(fmt, ...)
    elseif Nvk3UT and type(Nvk3UT.Warn) == "function" then
        Nvk3UT.Warn(fmt, ...)
    elseif type(d) == "function" then
        d(_format("[Nvk3UT SelfTest] %s", _format(fmt, ...)))
    end
end

local function _error(fmt, ...)
    if Nvk3UT and type(Nvk3UT.Error) == "function" then
        Nvk3UT.Error(fmt, ...)
    elseif Nvk3UT_Diagnostics and type(Nvk3UT_Diagnostics.Error) == "function" then
        Nvk3UT_Diagnostics.Error(fmt, ...)
    elseif type(d) == "function" then
        d(_format("|cFF0000[Nvk3UT SelfTest ERROR]|r %s", _format(fmt, ...)))
    end
end

local function _newResults()
    return { passed = 0, failed = 0, skipped = 0 }
end

local function _runCheck(results, name, fn)
    local ok, status, detail = pcall(fn)
    if not ok then
        results.failed = results.failed + 1
        _error("%s check threw error: %s", name, tostring(status))
        return
    end

    if status == nil then
        results.skipped = results.skipped + 1
        _info("%s check skipped%s", name, detail and (": " .. detail) or "")
        return
    end

    if status then
        results.passed = results.passed + 1
        _info("%s check ok%s", name, detail and (": " .. detail) or "")
    else
        results.failed = results.failed + 1
        _error("%s check failed: %s", name, detail or "no details provided")
    end
end

local function checkEnvironment()
    local missing = {}
    if EVENT_MANAGER == nil then
        missing[#missing + 1] = "EVENT_MANAGER"
    end
    if ZO_SavedVars == nil then
        missing[#missing + 1] = "ZO_SavedVars"
    end

    if #missing > 0 then
        return false, "Missing globals: " .. table.concat(missing, ", ")
    end

    return true, "Core game APIs available"
end

local function checkDiagnosticsModule()
    if type(Nvk3UT_Diagnostics) ~= "table" then
        return false, "Nvk3UT_Diagnostics table missing"
    end

    local missing = {}
    local required = { "Debug", "Warn", "Error", "SetDebugEnabled" }
    for _, fnName in ipairs(required) do
        if type(Nvk3UT_Diagnostics[fnName]) ~= "function" then
            missing[#missing + 1] = fnName
        end
    end

    if #missing > 0 then
        return false, "Diagnostics missing API: " .. table.concat(missing, ", ")
    end

    return true, "Diagnostics module ready"
end

local function checkUtilsModule()
    if type(Nvk3UT_Utils) ~= "table" then
        return false, "Nvk3UT_Utils table missing"
    end

    local required = { "AttachToRoot", "Debug", "Now" }
    local missing = {}
    for _, fnName in ipairs(required) do
        if type(Nvk3UT_Utils[fnName]) ~= "function" then
            missing[#missing + 1] = fnName
        end
    end

    if #missing > 0 then
        return false, "Utils missing helpers: " .. table.concat(missing, ", ")
    end

    return true, "Utils module exposed expected helpers"
end

local function checkAddonTable()
    if type(Nvk3UT) ~= "table" then
        return nil, "Addon root not initialized yet"
    end

    local missing = {}
    if type(Nvk3UT.SafeCall) ~= "function" then
        missing[#missing + 1] = "SafeCall"
    end
    if type(Nvk3UT.RegisterModule) ~= "function" then
        missing[#missing + 1] = "RegisterModule"
    end
    if type(Nvk3UT.InitSavedVariables) ~= "function" then
        missing[#missing + 1] = "InitSavedVariables"
    end

    if #missing > 0 then
        return false, "Addon root missing functions: " .. table.concat(missing, ", ")
    end

    return true, "Addon root initialized"
end

local function checkSavedVariables()
    if type(Nvk3UT) ~= "table" then
        return nil, "Addon root missing; cannot inspect SavedVariables"
    end

    local sv = rawget(Nvk3UT, "SV")
    if sv == nil then
        return nil, "SavedVariables not initialized yet"
    end

    if type(sv) ~= "table" then
        return false, "Nvk3UT.SV is not a table"
    end

    local general = sv.General
    local questTracker = sv.QuestTracker
    local achievementTracker = sv.AchievementTracker
    local appearance = sv.appearance

    local missing = {}
    if type(general) ~= "table" then
        missing[#missing + 1] = "General"
    end
    if type(questTracker) ~= "table" then
        missing[#missing + 1] = "QuestTracker"
    end
    if type(achievementTracker) ~= "table" then
        missing[#missing + 1] = "AchievementTracker"
    end
    if type(appearance) ~= "table" then
        missing[#missing + 1] = "appearance"
    end

    if #missing > 0 then
        return false, "SavedVariables missing tables: " .. table.concat(missing, ", ")
    end

    if rawget(Nvk3UT, "sv") ~= sv then
        return false, "Legacy alias Nvk3UT.sv not pointing at Nvk3UT.SV"
    end

    return true, "SavedVariables structure looks sane"
end

local function checkFavoritesData()
    if type(Nvk3UT) ~= "table" then
        return nil, "Addon root missing; cannot inspect favorites data"
    end

    local data = Nvk3UT.FavoritesData
    if type(data) ~= "table" then
        return false, "FavoritesData module missing"
    end

    local required = { "InitSavedVars", "IsFavorited", "SetFavorited", "ToggleFavorited", "GetAllFavorites" }
    local missing = {}
    for _, fnName in ipairs(required) do
        if type(data[fnName]) ~= "function" then
            missing[#missing + 1] = fnName
        end
    end

    if #missing > 0 then
        return false, "FavoritesData missing API: " .. table.concat(missing, ", ")
    end

    local accountSV = rawget(_G, "Nvk3UT_Data_Favorites_Account")
    local characterSV = rawget(_G, "Nvk3UT_Data_Favorites_Characters")
    if accountSV == nil or characterSV == nil then
        return nil, "Favorites SavedVariables not initialized yet"
    end

    return true, "FavoritesData ready"
end

local function checkRecentData()
    if type(Nvk3UT) ~= "table" then
        return nil, "Addon root missing; cannot inspect recent data"
    end

    local data = Nvk3UT.RecentData
    if type(data) ~= "table" then
        return false, "RecentData module missing"
    end

    local required = { "InitSavedVars", "ListConfigured", "CountConfigured" }
    local missing = {}
    for _, fnName in ipairs(required) do
        if type(data[fnName]) ~= "function" then
            missing[#missing + 1] = fnName
        end
    end

    if #missing > 0 then
        return false, "RecentData missing API: " .. table.concat(missing, ", ")
    end

    local sv = rawget(_G, "Nvk3UT_Data_Recent")
    if type(sv) ~= "table" then
        return nil, "Recent SavedVariables not initialized yet"
    end

    return true, "RecentData ready"
end

local function summarize(results)
    _info(
        "SelfTest summary: passed=%d, skipped=%d, failed=%d",
        results.passed,
        results.skipped,
        results.failed
    )
    if results.failed > 0 then
        _error("SelfTest detected %d failing checks", results.failed)
    end
end

-- Main entry point: safe to call via Nvk3UT.SafeCall
function SelfTest.RunCoreSanityCheck()
    local results = _newResults()

    _info("Running core self tests...")

    _runCheck(results, "Environment", checkEnvironment)
    _runCheck(results, "Diagnostics", checkDiagnosticsModule)
    _runCheck(results, "Utils", checkUtilsModule)
    _runCheck(results, "AddonTable", checkAddonTable)
    _runCheck(results, "SavedVariables", checkSavedVariables)
    _runCheck(results, "FavoritesData", checkFavoritesData)
    _runCheck(results, "RecentData", checkRecentData)

    summarize(results)

    return results
end

-- Backward compatibility for legacy callers that used Nvk3UT.SelfTest.Run()
if not SelfTest.Run then
    function SelfTest.Run()
        local function execute()
            return SelfTest.RunCoreSanityCheck()
        end

        if Nvk3UT and type(Nvk3UT.SafeCall) == "function" then
            return Nvk3UT.SafeCall(execute)
        end

        local ok, result = pcall(execute)
        if not ok then
            _error("SelfTest execution failed: %s", tostring(result))
            return nil
        end

        return result
    end
end

-- If the addon root already exists (e.g., in reload scenarios), attach immediately.
if type(Nvk3UT) == "table" then
    SelfTest.AttachToRoot(Nvk3UT)
end

return SelfTest
