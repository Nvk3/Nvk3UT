-- Core/Nvk3UT_Diagnostics.lua
-- Centralized logging / diagnostics for Nvk3UT.
-- Loads before Core, so it cannot assume that the global addon table exists
-- at file scope. All access to Nvk3UT therefore happens via guarded helpers.
--
-- TODO: Once the refactor introduces a finalized Core bootstrap, make sure
-- Core/Nvk3UT_Core.lua calls Nvk3UT_Diagnostics.AttachToRoot(Nvk3UT) during
-- OnAddonLoaded so the Diagnostics module is reachable via Nvk3UT.Diagnostics.

Nvk3UT_Diagnostics = Nvk3UT_Diagnostics or {}

local Diagnostics = Nvk3UT_Diagnostics

Diagnostics.debugEnabled = (Diagnostics.debugEnabled ~= nil) and Diagnostics.debugEnabled or true

local isAttachedToRoot = false

local function ensureRoot()
    if isAttachedToRoot then
        return
    end

    local root = rawget(_G, "Nvk3UT")
    if type(root) == "table" then
        root.Diagnostics = root.Diagnostics or Diagnostics
        isAttachedToRoot = true
    end
end

function Diagnostics.AttachToRoot(root)
    if type(root) ~= "table" then
        return
    end

    root.Diagnostics = root.Diagnostics or Diagnostics
    isAttachedToRoot = true
end

local function _fmt(fmt, ...)
    if fmt == nil then
        return ""
    end

    return string.format(tostring(fmt), ...)
end

local function _print(level, msg)
    local output = string.format("[%s] %s", level, msg)

    if d then
        d(output)
    else
        print(output)
    end
end

function Diagnostics.SetDebugEnabled(enabled)
    Diagnostics.debugEnabled = not not enabled
end

function Diagnostics.IsDebugEnabled()
    return Diagnostics.debugEnabled == true
end

function Diagnostics.SyncFromSavedVariables(sv)
    if type(sv) ~= "table" then
        return
    end

    if sv.debugEnabled ~= nil then
        Diagnostics.debugEnabled = not not sv.debugEnabled
    end

    -- TODO: wire additional diagnostics verbosity flags once SavedVariables schema is finalized.
end

function Diagnostics.Debug(fmt, ...)
    if not Diagnostics.debugEnabled then
        return
    end

    ensureRoot()
    _print("Nvk3UT DEBUG", _fmt(fmt, ...))
end

function Diagnostics.Warn(fmt, ...)
    ensureRoot()
    _print("Nvk3UT WARN", _fmt(fmt, ...))
end

function Diagnostics.Error(fmt, ...)
    ensureRoot()
    _print("Nvk3UT ERROR", _fmt(fmt, ...))
end

function Diagnostics.SelfTest()
    ensureRoot()
    _print("Nvk3UT DEBUG", _fmt("SelfTest: ZO_Achievements available = %s", tostring(ZO_Achievements ~= nil)))
    _print("Nvk3UT DEBUG", _fmt("SelfTest: categoryTree available = %s", tostring(ZO_Achievements and ZO_Achievements.categoryTree ~= nil)))
    _print("Nvk3UT DEBUG", _fmt("SelfTest: LibAddonMenu2 available = %s", tostring(LibAddonMenu2 ~= nil)))
end

function Diagnostics.SystemTest()
    ensureRoot()

    local ach = SYSTEMS and SYSTEMS.GetObject and SYSTEMS:GetObject("achievements")
    _print("Nvk3UT DEBUG", _fmt("SystemTest: SYSTEMS achievements available = %s", tostring(ach ~= nil)))

    if ach then
        _print("Nvk3UT DEBUG", _fmt("SystemTest: ach.categoryTree available = %s", tostring(ach.categoryTree ~= nil)))
        _print("Nvk3UT DEBUG", _fmt("SystemTest: ach.control available = %s", tostring(ach.control ~= nil)))
    end
end

-- Backward compatibility -------------------------------------------------------
if type(Nvk3UT) == "table" then
    Nvk3UT.Diagnostics = Nvk3UT.Diagnostics or Diagnostics
end

if Debug == nil then
    function Debug(fmt, ...)
        return Diagnostics.Debug(fmt, ...)
    end
end

if LogError == nil then
    function LogError(fmt, ...)
        return Diagnostics.Error(fmt, ...)
    end
end

return Diagnostics
