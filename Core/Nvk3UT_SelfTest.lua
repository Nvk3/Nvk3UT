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

    local ui = sv.ui
    local features = sv.features
    local host = sv.host
    local ac = sv.ac

    local missing = {}
    if type(ui) ~= "table" then
        missing[#missing + 1] = "ui"
    end
    if type(features) ~= "table" then
        missing[#missing + 1] = "features"
    end
    if type(host) ~= "table" then
        missing[#missing + 1] = "host"
    end
    if type(ac) ~= "table" then
        missing[#missing + 1] = "ac"
    end

    if #missing > 0 then
        return false, "SavedVariables missing tables: " .. table.concat(missing, ", ")
    end

    local facade = rawget(Nvk3UT, "sv")
    if type(facade) ~= "table" then
        return false, "Legacy alias Nvk3UT.sv missing"
    end

    if facade.General == nil or facade.Settings == nil then
        return false, "SavedVariables facade missing legacy tables"
    end

    local characterSV = rawget(Nvk3UT, "SVCharacter")
    if characterSV == nil then
        return nil, "Character SavedVariables not initialized yet"
    end

    if type(characterSV) ~= "table" then
        return false, "Nvk3UT.SVCharacter is not a table"
    end

    local quests = characterSV.quests
    if type(quests) ~= "table" then
        return false, "Character quests table missing"
    end

    local state = quests.state
    if state ~= nil and type(state) ~= "table" then
        return false, "Character quests.state malformed"
    end

    local function validateCollapseMap(map, label)
        if map == nil then
            return true
        end
        if type(map) ~= "table" then
            return false, label .. " collapse map not a table"
        end
        for key, value in pairs(map) do
            local numeric = tonumber(key)
            if not (numeric and numeric > 0) then
                return false, string.format("%s collapse key %s is not numeric", label, tostring(key))
            end
            if value ~= true then
                return false, string.format("%s collapse entry for %s must be true", label, tostring(key))
            end
        end
        return true
    end

    local okZones, zonesError = validateCollapseMap(state and state.zones, "zones")
    if not okZones then
        return false, zonesError
    end

    local okQuests, questsError = validateCollapseMap(state and state.quests, "quests")
    if not okQuests then
        return false, questsError
    end

    local flags = quests.flags
    if flags ~= nil and type(flags) ~= "table" then
        return false, "Character quests.flags malformed"
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

    local repo = Nvk3UT_StateRepo_Achievements or (Nvk3UT and Nvk3UT.AchievementRepo)
    if repo and repo.AC_Fav_List then
        repo.AC_Fav_List()
    else
        return nil, "Achievement repository not initialised"
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

    local repo = Nvk3UT_StateRepo_Achievements or (Nvk3UT and Nvk3UT.AchievementRepo)
    if not (repo and repo.AC_Recent_GetStorage) then
        return nil, "Achievement repository not initialised"
    end

    local storage = repo.AC_Recent_GetStorage(true)
    if type(storage) ~= "table" then
        return nil, "Recent storage not initialised"
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
