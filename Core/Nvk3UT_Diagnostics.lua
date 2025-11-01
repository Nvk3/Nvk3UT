Nvk3UT = Nvk3UT or {}

Nvk3UT_Diagnostics = Nvk3UT_Diagnostics or {}

local Diagnostics = Nvk3UT_Diagnostics

local LOG = LibDebugLogger and LibDebugLogger("Nvk3UT")

local defaultDebugEnabled = false
if Diagnostics.debugEnabled ~= nil then
    defaultDebugEnabled = Diagnostics.debugEnabled and true or false
elseif type(Nvk3UT) == "table" and Nvk3UT.debugEnabled ~= nil then
    defaultDebugEnabled = Nvk3UT.debugEnabled and true or false
end

Diagnostics.debugEnabled = defaultDebugEnabled

local isAttachedToRoot = false

local function ensureRoot()
    if isAttachedToRoot then
        return
    end

    local root = rawget(_G, "Nvk3UT")
    if type(root) ~= "table" then
        return
    end

    root.Diagnostics = root.Diagnostics or Diagnostics
    root.LogDebug = Diagnostics.LogDebug or root.LogDebug
    root.LogInfo = Diagnostics.LogInfo or root.LogInfo
    root.LogWarn = Diagnostics.LogWarn or root.LogWarn
    root.LogError = Diagnostics.LogError or root.LogError
    root.Debug = root.Debug or root.LogDebug
    root.Info = root.Info or root.LogInfo
    root.Warn = root.Warn or root.LogWarn
    root.Error = root.Error or root.LogError

    isAttachedToRoot = true
end

function Diagnostics.AttachToRoot(root)
    if type(root) ~= "table" then
        return
    end

    root.Diagnostics = root.Diagnostics or Diagnostics
    root.LogDebug = Diagnostics.LogDebug or root.LogDebug
    root.LogInfo = Diagnostics.LogInfo or root.LogInfo
    root.LogWarn = Diagnostics.LogWarn or root.LogWarn
    root.LogError = Diagnostics.LogError or root.LogError
    root.Debug = root.Debug or root.LogDebug
    root.Info = root.Info or root.LogInfo
    root.Warn = root.Warn or root.LogWarn
    root.Error = root.Error or root.LogError
    isAttachedToRoot = true
end

local function _fmt(fmt, ...)
    if fmt == nil then
        return ""
    end

    local ok, message = pcall(string.format, tostring(fmt), ...)
    if ok then
        return message
    end

    return tostring(fmt)
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
    if type(Nvk3UT) == "table" then
        Nvk3UT.debugEnabled = Diagnostics.debugEnabled
    end
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
        if type(Nvk3UT) == "table" then
            Nvk3UT.debugEnabled = Diagnostics.debugEnabled
        end
    end

    -- TODO: wire additional diagnostics verbosity flags once SavedVariables schema is finalized.
end

local function logDebugMessage(message)
    if LOG and LOG.Debug then
        LOG:Debug(message)
        return
    end

    _print("Nvk3UT DEBUG", message)
end

local function logInfoMessage(message)
    if LOG and LOG.Info then
        LOG:Info(message)
        return
    end

    _print("Nvk3UT INFO", message)
end

local function logWarnMessage(message)
    if LOG and LOG.Warn then
        LOG:Warn(message)
        return
    end

    _print("Nvk3UT WARN", message)
end

local function logErrorMessage(message)
    if LOG and LOG.Error then
        LOG:Error(message)
        return
    end

    _print("Nvk3UT ERROR", message)
end

function Diagnostics.LogDebug(fmt, ...)
    if not Diagnostics.debugEnabled then
        return
    end

    ensureRoot()
    logDebugMessage(_fmt(fmt, ...))
end

function Diagnostics.LogInfo(fmt, ...)
    ensureRoot()
    logInfoMessage(_fmt(fmt, ...))
end

function Diagnostics.LogWarn(fmt, ...)
    ensureRoot()
    logWarnMessage(_fmt(fmt, ...))
end

function Diagnostics.LogError(fmt, ...)
    ensureRoot()
    logErrorMessage(_fmt(fmt, ...))
end

function Diagnostics.Debug(fmt, ...)
    Diagnostics.LogDebug(fmt, ...)
end

function Diagnostics.Warn(fmt, ...)
    Diagnostics.LogWarn(fmt, ...)
end

function Diagnostics.Error(fmt, ...)
    Diagnostics.LogError(fmt, ...)
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
    Nvk3UT.LogDebug = Diagnostics.LogDebug
    Nvk3UT.LogInfo = Diagnostics.LogInfo
    Nvk3UT.LogWarn = Diagnostics.LogWarn
    Nvk3UT.LogError = Diagnostics.LogError
    Nvk3UT.Debug = Nvk3UT.LogDebug
    Nvk3UT.Info = Nvk3UT.LogInfo
    Nvk3UT.Warn = Nvk3UT.LogWarn
    Nvk3UT.Error = Nvk3UT.LogError
end

if Debug == nil then
    function Debug(fmt, ...)
        return Diagnostics.LogDebug(fmt, ...)
    end
end

if LogError == nil then
    function LogError(fmt, ...)
        return Diagnostics.LogError(fmt, ...)
    end
end

return Diagnostics
