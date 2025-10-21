Nvk3UT = Nvk3UT or {}
local T = {}
Nvk3UT.Tooltips = T

local U = Nvk3UT and Nvk3UT.Utils

T.name = "Nvk3UT_Tooltips"
T.enabled = true

local SUMMARY_FONT = "ZoFontGameSmall"
local SUMMARY_COLOR = ZO_SELECTED_TEXT
local NVK3_DONE = 84003
local Comp = Nvk3UT and Nvk3UT.CompletedData

local function EnsureTooltipPools()
  if not AchievementTooltip then
    return
  end

  if not AchievementTooltip.nvk3utStatusBarPool then
    local pool = ZO_ControlPool:New("ZO_AchievementsStatusBar", AchievementTooltip, "Nvk3UT_StatusBar")
    pool:SetCustomFactoryBehavior(function(control)
      control.label = control:GetNamedChild("Label")
      control.progress = control:GetNamedChild("Progress")
      ZO_StatusBar_SetGradientColor(control, ZO_XP_BAR_GRADIENT_COLORS)
      local l = control:GetNamedChild("BGLeft")
      if l then
        l:SetDrawLevel(2)
      end
      local r = control:GetNamedChild("BGRight")
      if r then
        r:SetDrawLevel(2)
      end
      local m = control:GetNamedChild("BGMiddle")
      if m then
        m:SetDrawLevel(2)
      end
    end)
    AchievementTooltip.nvk3utStatusBarPool = pool
  end

  if not AchievementTooltip.nvk3utRowPool then
    AchievementTooltip.nvk3utRowPool = ZO_ObjectPool:New(function()
      local row = CreateControl(nil, AchievementTooltip, CT_CONTROL)
      row:SetHeight(28)
      return row
    end, function(row)
      if row then
        row:SetHidden(true)
        row:ClearAnchors()
        row:SetParent(AchievementTooltip)
      end
    end)
  end

  if not AchievementTooltip._nvk3ut_onCleared then
    ZO_PreHookHandler(AchievementTooltip, "OnCleared", function()
      if AchievementTooltip.nvk3utStatusBarPool then
        AchievementTooltip.nvk3utStatusBarPool:ReleaseAllObjects()
      end
      if AchievementTooltip.nvk3utRowPool then
        AchievementTooltip.nvk3utRowPool:ReleaseAllObjects()
      end
      return false
    end)
    AchievementTooltip._nvk3ut_onCleared = true
  end
end

local function AddStatusBar()
  EnsureTooltipPools()
  local pool = AchievementTooltip.nvk3utStatusBarPool
  local bar = pool:AcquireObject()
  AchievementTooltip:AddControl(bar)
  bar:SetAnchor(CENTER)
  return bar
end

local function AcquireRow()
  EnsureTooltipPools()
  local row = AchievementTooltip.nvk3utRowPool:AcquireObject()
  AchievementTooltip:AddControl(row)
  row:SetHidden(false)
  row:ClearAnchors()
  row:SetAnchor(CENTER)
  return row
end

local function AddBarToRow(row, side, name, earned, total)
  local bar = AchievementTooltip.nvk3utStatusBarPool:AcquireObject()
  bar:SetParent(row)
  bar:ClearAnchors()
  if side == "left" then
    bar:SetAnchor(TOPLEFT, row, TOPLEFT, 0, 0)
    bar:SetAnchor(BOTTOMRIGHT, row, CENTER, -6, 0)
  else
    bar:SetAnchor(TOPLEFT, row, CENTER, 6, 0)
    bar:SetAnchor(BOTTOMRIGHT, row, BOTTOMRIGHT, 0, 0)
  end
  bar:SetMinMax(0, total or 0)
  bar:SetValue(earned or 0)
  bar.label:SetColor(ZO_SELECTED_TEXT:UnpackRGB())
  bar.label:SetText(name or "")
  bar.progress:SetText(string.format("%i/%i", tonumber(earned) or 0, tonumber(total) or 0))
  return bar
end

local function GetACH()
  return (SYSTEMS and SYSTEMS.GetObject and SYSTEMS:GetObject("achievements")) or ACHIEVEMENTS or ZO_Achievements
end

local function ControlToNode(tree, ctrl)
  if not ctrl then
    return nil
  end
  if ctrl.node then
    return ctrl.node
  end
  local c = ctrl
  for _ = 1, 4 do
    if not c then
      break
    end
    if tree and tree.GetNodeByControl then
      local n = tree:GetNodeByControl(c)
      if n then
        return n
      end
    end
    c = c:GetParent()
  end
  return nil
end

local function SetStatusBar(name, earned, total)
  local bar = AddStatusBar()
  bar:SetMinMax(0, total or 0)
  bar:SetValue(earned or 0)
  bar.label:SetColor(ZO_SELECTED_TEXT:UnpackRGB())
  bar.label:SetText(name or "")
  bar.progress:SetText(string.format("%i/%i", tonumber(earned) or 0, tonumber(total) or 0))
end

local function ShowCategoryTooltip(data)
  EnsureTooltipPools()
  local ACH = GetACH()
  if not ACH or not ACH.GetCategoryIndicesFromData then
    return
  end
  local categoryIndex, subcategoryIndex = ACH:GetCategoryIndicesFromData(data)
  local numTop = GetNumAchievementCategories()
  if type(categoryIndex) ~= "number" or categoryIndex < 1 or categoryIndex > numTop then
    return
  end

  AchievementTooltip.nvk3utStatusBarPool:ReleaseAllObjects()
  AchievementTooltip.nvk3utRowPool:ReleaseAllObjects()

  local numSub, _, generalEarned, generalTotal = select(2, GetAchievementCategoryInfo(categoryIndex))
  for i = 1, numSub do
    local e, t = select(3, GetAchievementSubCategoryInfo(categoryIndex, i))
    generalEarned = (generalEarned or 0) - (e or 0)
    generalTotal = (generalTotal or 0) - (t or 0)
  end
  if (generalTotal or 0) > 0 then
    SetStatusBar(GetString(SI_JOURNAL_PROGRESS_CATEGORY_GENERAL), generalEarned or 0, generalTotal or 0)
  end
  for i = 1, numSub do
    local name, _, e, t = GetAchievementSubCategoryInfo(categoryIndex, i)
    SetStatusBar(zo_strformat("<<1>>", name or ""), e or 0, t or 0)
  end
end

function ShowSummaryTooltip()
  ClearTooltip(AchievementTooltip)
  InitializeTooltip(AchievementTooltip, AchievementJournal, TOPRIGHT, 0, -104, TOPLEFT)

  local lines = {}
  local numTop = GetNumAchievementCategories()
  for i = 1, numTop do
    local name, numSub, _, earned, total = GetAchievementCategoryInfo(i)
    if name and name ~= "" then
      local percent = (total and total > 0) and zo_round((earned or 0) * 100 / total) or 0
      -- category icon
      local icon = GetAchievementCategoryKeyboardIcons and GetAchievementCategoryKeyboardIcons(i)
      local iconTag = icon and string.format("|t32:32:%s|t ", icon) or ""
      lines[#lines + 1] = string.format(
        "%s%s |cfafafa(%s/%s – %d%%)|r",
        iconTag,
        zo_strformat("<<1>>", name),
        ZO_CommaDelimitNumber(earned or 0),
        ZO_CommaDelimitNumber(total or 0),
        percent
      )
    end
  end

  if #lines > 0 then
    local text = table.concat(lines, "\n")
    local r, g, b = ZO_SELECTED_TEXT:UnpackRGB()
    local _, label = AchievementTooltip:AddLine(text, "", r, g, b, LEFT, MODIFY_TEXT_TYPE_NONE, TEXT_ALIGN_LEFT, false)
    if label then
      -- use small ESO font; single label => minimal inter-line spacing
      label:SetFont("$(MEDIUM_FONT)|$(KB_12)|soft-shadow-none")
      label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
      label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
      label:SetPixelRoundingEnabled(false)
    end
  end
end

-- Completed tooltips (root and subcategory)

local function ShowCompletedRootTooltip(node)
  if not Comp then
    return
  end
  AchievementTooltip.nvk3utStatusBarPool:ReleaseAllObjects()
  AchievementTooltip.nvk3utRowPool:ReleaseAllObjects()

  local lines = {}
  if node and node.GetChildren and node:GetChildren() then
    for _, child in pairs(node:GetChildren()) do
      local d = child:GetData()
      if d and d.subcategoryIndex then
        local name = d.name or d.text or (d.categoryData and d.categoryData.name) or ""
        local _, points = Comp.SummaryCountAndPointsForKey(d.subcategoryIndex)
        lines[#lines + 1] =
          string.format("%s |cfafafa(%s Punkte)|r", zo_strformat("<<1>>", name), ZO_CommaDelimitNumber(points or 0))
      end
    end
  else
    -- Fallback to CompletedData list if no node children available
    if Comp.GetSubcategoryList then
      local names, keys = Comp.GetSubcategoryList()
      if names and keys then
        for i = 1, #keys do
          local _, points = Comp.SummaryCountAndPointsForKey(keys[i])
          lines[#lines + 1] = string.format(
            "%s |cfafafa(%s Punkte)|r",
            zo_strformat("<<1>>", names[i] or ""),
            ZO_CommaDelimitNumber(points or 0)
          )
        end
      end
    end
  end

  if #lines > 0 then
    local text = table.concat(lines, "\n")
    local r, g, b = ZO_SELECTED_TEXT:UnpackRGB()
    local _, label = AchievementTooltip:AddLine(text, "", r, g, b, LEFT, MODIFY_TEXT_TYPE_NONE, TEXT_ALIGN_LEFT, false)
    if label then
      label:SetFont("$(MEDIUM_FONT)|$(KB_12)|soft-shadow-none")
      label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
      label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
      label:SetPixelRoundingEnabled(false)
    end
  end
end

local function ShowCompletedSubTooltip(data)
  if not Comp or not data or not data.subcategoryIndex then
    return
  end
  local names, keys = Comp.GetSubcategoryList()
  local labelText = ""
  if names and keys then
    for i = 1, #keys do
      if keys[i] == data.subcategoryIndex then
        labelText = zo_strformat("<<1>>", names[i] or "")
        break
      end
    end
  end
  local _, points = Comp.SummaryCountAndPointsForKey(data.subcategoryIndex)
  local line = string.format("%s |cfafafa(%s Punkte)|r", labelText, ZO_CommaDelimitNumber(points or 0))
  local r, g, b = ZO_SELECTED_TEXT:UnpackRGB()
  local _, lbl = AchievementTooltip:AddLine(line, "", r, g, b, LEFT, MODIFY_TEXT_TYPE_NONE, TEXT_ALIGN_LEFT, false)
  if lbl then
    lbl:SetFont("$(MEDIUM_FONT)|$(KB_12)|soft-shadow-none")
    lbl:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    lbl:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    lbl:SetPixelRoundingEnabled(false)
  end
end

local function ShowChildrenTooltip(node)
  EnsureTooltipPools()
  AchievementTooltip.nvk3utStatusBarPool:ReleaseAllObjects()
  AchievementTooltip.nvk3utRowPool:ReleaseAllObjects()

  if not node then
    return
  end
  local ACH = GetACH()
  if not ACH then
    return
  end
  local children = node:GetChildren()
  if not children then
    return
  end
  for _, child in ipairs(children) do
    local data = child:GetData()
    local idx = ACH.GetCategoryIndicesFromData and ACH:GetCategoryIndicesFromData(data)
    if idx then
      local name, _, _, e, t = GetAchievementCategoryInfo(idx)
      SetStatusBar(zo_strformat("<<1>>", name or ""), e or 0, t or 0)
    end
  end
end

local function AttachHoverToLabel(tree, parentControl, label, MouseEnter, MouseExit)
  if not label or label._nvk3ut_tip then
    return
  end
  ZO_PreHookHandler(label, "OnMouseEnter", function()
    MouseEnter(parentControl)
  end)
  ZO_PreHookHandler(label, "OnMouseExit", function()
    MouseExit(parentControl)
  end)
  label:SetMouseEnabled(true)
  label._nvk3ut_tip = true
end

local function HookHandlers(tree, control)
  if not control or control._nvk3ut_tip then
    return
  end

  local function MouseEnter(ctrl)
    if not T.enabled then
      return
    end
    local node = ControlToNode(tree, ctrl)
    local data = node and node:GetData()
    if not data then
      return
    end

    if Nvk3UT and Nvk3UT.TryCustomCategoryTooltip and Nvk3UT.TryCustomCategoryTooltip(ctrl, data) then
      return
    end

    ClearTooltip(AchievementTooltip)
    InitializeTooltip(AchievementTooltip, ctrl, TOPRIGHT, 0, -104, TOPLEFT)

    local name = data.name or data.text or (data.categoryData and data.categoryData.name)
    local isSummary = data.summary or (name == GetString(SI_JOURNAL_PROGRESS_CATEGORY_SUMMARY))
    if data.isNvkCompleted or data.isNvkFavorites or data.isNvkRecent or data.isNvkTodo then
      isSummary = false
    end
    if U and U.d then
      U.d(
        "[TT][Hover]",
        "name=",
        tostring(name),
        " C/F/R/T=",
        tostring(data.isNvkCompleted),
        "/",
        tostring(data.isNvkFavorites),
        "/",
        tostring(data.isNvkRecent),
        "/",
        tostring(data.isNvkTodo),
        " isSummary=",
        tostring(isSummary)
      )
    end

    if isSummary then
      if U and U.d then
        U.d("[TT] Summary")
      end
      ShowSummaryTooltip()
    else
      local isCompletedRoot = (data.isNvkCompleted == true)
        or (data.categoryIndex == NVK3_DONE)
        or (data.categoryId == NVK3_DONE)
        or (data.id == NVK3_DONE)
        or (data.categoryData and ((data.categoryData.id == NVK3_DONE) or (data.categoryData.index == NVK3_DONE)))
        or (name == "Abgeschlossen") -- fallback by label (DE)

      if isCompletedRoot then
        if data.subcategoryIndex then
          if U and U.d then
            U.d("[TT] Completed SUB")
          end
          ShowCompletedSubTooltip(data)
        else
          if U and U.d then
            U.d("[TT] Completed ROOT")
          end
          ShowCompletedRootTooltip(node)
        end
      else
        local ACH = GetACH()
        local idx = ACH and ACH.GetCategoryIndicesFromData and ACH:GetCategoryIndicesFromData(data)
        if idx then
          if U and U.d then
            U.d("[TT] Category")
          end
          ShowCategoryTooltip(data)
        else
          if U and U.d then
            U.d("[TT] Children")
          end
          ShowChildrenTooltip(node)
        end
      end
    end
  end

  local function MouseExit(ctrl)
    ClearTooltip(AchievementTooltip)
  end

  ZO_PreHookHandler(control, "OnMouseEnter", MouseEnter)
  ZO_PreHookHandler(control, "OnMouseExit", MouseExit)
  control:SetMouseEnabled(true)
  control._nvk3ut_tip = true

  -- Also hook the text label
  if control.GetNamedChild then
    local lbl = control:GetNamedChild("Text") or control:GetNamedChild("Label") or control:GetNamedChild("Name")
    if lbl then
      AttachHoverToLabel(tree, control, lbl, MouseEnter, MouseExit)
    end
  end
end

local function HookExisting(tree)
  local root = tree and tree.rootNode
  if root and root:GetChildren() then
    for _, node in pairs(root:GetChildren()) do
      local control = node:GetControl()
      HookHandlers(tree, control)
    end
  end
  -- Depth-first to catch subnodes too
  if tree and tree.DepthFirstIterator and root then
    for node in tree:DepthFirstIterator(root) do
      HookHandlers(tree, node:GetControl())
    end
  end
end

local function HookTemplates(tree)
  if not tree or not tree.templateInfo then
    return
  end
  local function setup(node, control, data, open)
    HookHandlers(tree, control)
  end
  for _, info in pairs(tree.templateInfo) do
    if info and info.setupFunction then
      SecurePostHook(info, "setupFunction", setup)
    end
  end
end

function T.HookNow()
  local ACH = GetACH()
  if not ACH or not ACH.categoryTree then
    return
  end
  local tree = ACH.categoryTree
  HookTemplates(tree)
  HookExisting(tree)
end

local function HookSceneAndEvents()
  local scene = SCENE_MANAGER and SCENE_MANAGER:GetScene("achievements")
  if scene then
    scene:RegisterCallback("StateChange", function(_, newState)
      if newState == SCENE_SHOWING or newState == SCENE_SHOWN then
        T.HookNow()
      end
    end)
  end
  EVENT_MANAGER:RegisterForEvent(T.name .. "_PA", EVENT_PLAYER_ACTIVATED, function()
    EVENT_MANAGER:UnregisterForEvent(T.name .. "_PA", EVENT_PLAYER_ACTIVATED)
    T.HookNow()
    zo_callLater(function()
      T.HookNow()
    end, 500)
    zo_callLater(function()
      T.HookNow()
    end, 2000)
  end)
  zo_callLater(function()
    if Nvk3UT and Nvk3UT.RebuildSelected and SecurePostHook then
      SecurePostHook(Nvk3UT, "RebuildSelected", function()
        T.HookNow()
      end)
    end
  end, 1000)
end

function T.Enable(v)
  T.enabled = (v == nil) and true or (v and true or false)
  if not T.enabled then
    ClearTooltip(AchievementTooltip)
  end
end

function T.Init()
  local sv = Nvk3UT and Nvk3UT.sv
  if sv then
    sv.features = sv.features or {}
    if sv.features.tooltips == nil then
      sv.features.tooltips = true
    end
    T.enabled = (sv.features.tooltips ~= false)
  end
  HookSceneAndEvents()
  T.HookNow()
end

Nvk3UT = Nvk3UT or {}

local function _nvkGetData(control, fallback)
  if fallback ~= nil then
    return fallback
  end
  if control and control.data then
    return control.data
  end
  if control and control.node and control.node.data then
    return control.node.data
  end
  local parent = control and control.GetParent and control:GetParent()
  if parent and parent.node and parent.node.data then
    return parent.node.data
  end
  return nil
end

local function _nvkTooltipHeader(tt, text)
  tt:AddLine(text or "", "ZoFontGameLargeBold")
  ZO_Tooltip_AddDivider(tt)
end

local function _nvkTooltipRow(tt, leftText, rightText)
  leftText = tostring(leftText or "")
  rightText = tostring(rightText or "")
  tt:AddLine(zo_strformat("<<1>>   |cAAAAAA<<2>>|r", leftText, rightText), "ZoFontGameSmall")
end

local function _nvkInitializeCategoryTooltip(control)
  local tooltip = AchievementTooltip
  if not tooltip or not control or not control.GetCenter then
    return nil
  end

  ClearTooltip(tooltip)
  if tooltip.SetClampedToScreen then
    tooltip:SetClampedToScreen(true)
  end
  if InformationTooltip and InformationTooltip.SetClampedToScreen then
    InformationTooltip:SetClampedToScreen(true)
  end

  local controlCenterX = select(1, control:GetCenter())
  local referenceX
  local parent = control.GetParent and control:GetParent()

  while parent and parent.GetCenter do
    if parent.GetWidth and parent:GetWidth() > 0 then
      referenceX = select(1, parent:GetCenter())
      break
    end
    parent = parent.GetParent and parent:GetParent()
  end

  if not referenceX and AchievementJournal and AchievementJournal.GetCenter then
    referenceX = select(1, AchievementJournal:GetCenter())
  end

  if not referenceX and GuiRoot and GuiRoot.GetCenter then
    referenceX = select(1, GuiRoot:GetCenter())
  end

  local tooltipPoint = TOPLEFT
  local relativePoint = TOPRIGHT

  if referenceX and controlCenterX and controlCenterX >= referenceX then
    tooltipPoint = TOPRIGHT
    relativePoint = TOPLEFT
  end

  InitializeTooltip(tooltip, control, tooltipPoint, 0, -104, relativePoint)

  return tooltip
end

local function _nvkApplySummaryLabelStyle(label)
  if not label then
    return
  end
  label:SetFont("$(MEDIUM_FONT)|$(KB_12)|soft-shadow-none")
  label:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
  label:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
  label:SetPixelRoundingEnabled(false)
end

local function _nvkShowSummaryText(control, text)
  if not text or text == "" then
    return
  end

  local tooltip = _nvkInitializeCategoryTooltip(control)
  if not tooltip then
    return
  end

  tooltip:ClearLines()
  local r, g, b = ZO_SELECTED_TEXT:UnpackRGB()
  local _, label = tooltip:AddLine(text, "", r, g, b, LEFT, MODIFY_TEXT_TYPE_NONE, TEXT_ALIGN_LEFT, false)
  if label then
    _nvkApplySummaryLabelStyle(label)
  end
end

local function _nvkInitTooltip(control)
  local tt = AchievementTooltip or InformationTooltip
  InitializeTooltip(tt, control, BOTTOM, 0, -10)
  tt:ClearLines()
  return tt
end

local function _nvkGetMod(modA, modB)
  local ok, mod = pcall(function()
    if _G[modA] then
      return _G[modA]
    end
    if _G[modB] then
      return _G[modB]
    end
    if Nvk3UT and Nvk3UT[modA] then
      return Nvk3UT[modA]
    end
    if Nvk3UT and Nvk3UT[modB] then
      return Nvk3UT[modB]
    end
    return nil
  end)
  if ok then
    return mod
  end
  return nil
end

local function _nvkCountFavorites()
  local Fav = _nvkGetMod("FavoritesData", "Favorites")
  if Fav and type(Fav.Count) == "function" then
    local ok, n = pcall(Fav.Count)
    if ok and tonumber(n) then
      return n
    end
  end
  if Fav and type(Fav.Iterate) == "function" then
    local ok, it, s, var = pcall(Fav.Iterate)
    if ok and it then
      local c = 0
      while true do
        local k, v = it(s, var)
        var = k
        if k == nil then
          break
        end
        c = c + 1
      end
      return c
    end
  end
  local sv = Nvk3UT and Nvk3UT.sv
  local pool = sv and (sv.favorites or sv.favs)
  if type(pool) == "table" then
    local c = 0
    for _ in pairs(pool) do
      c = c + 1
    end
    return c
  end
  return 0
end

local function _nvkRenderFavorites(control)
  local tooltip = _nvkInitializeCategoryTooltip(control)
  if not tooltip then
    return
  end
  local n = _nvkCountFavorites()
  local title = (GetString and GetString(SI_NAMED_FRIENDS_LIST_FAVOURITES_HEADER)) or "Favoriten"
  local line = string.format("%s |cfafafa(%s)|r", zo_strformat("<<1>>", title), ZO_CommaDelimitNumber(n or 0))
  local r, g, b = ZO_SELECTED_TEXT:UnpackRGB()
  local _, lbl = tooltip:AddLine(line, "", r, g, b, LEFT, MODIFY_TEXT_TYPE_NONE, TEXT_ALIGN_LEFT, false)
  if lbl then
    lbl:SetFont("$(MEDIUM_FONT)|$(KB_12)|soft-shadow-none")
    lbl:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    lbl:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    lbl:SetPixelRoundingEnabled(false)
  end
end

local function _nvkCountRecent()
  local Rec = _nvkGetMod("RecentData", "Recent")
  if Rec and type(Rec.CountConfigured) == "function" then
    local ok, n = pcall(Rec.CountConfigured)
    if ok and tonumber(n) then
      return n
    end
  end
  if Rec and type(Rec.List) == "function" then
    local ok, list = pcall(Rec.List)
    if ok and type(list) == "table" then
      return #list
    end
  end
  local sv = Nvk3UT and Nvk3UT.sv
  local lst = sv and (sv.recent or sv.recentList)
  if type(lst) == "table" then
    return #lst
  end
  return 0
end

local function _nvkRenderRecent(control)
  local tooltip = _nvkInitializeCategoryTooltip(control)
  if not tooltip then
    return
  end
  local n = _nvkCountRecent()
  local title = (GetString and GetString(SI_GAMEPAD_NOTIFICATIONS_CATEGORY_RECENT)) or "Kürzlich"
  local line = string.format("%s |cfafafa(%s)|r", zo_strformat("<<1>>", title), ZO_CommaDelimitNumber(n or 0))
  local r, g, b = ZO_SELECTED_TEXT:UnpackRGB()
  local _, lbl = tooltip:AddLine(line, "", r, g, b, LEFT, MODIFY_TEXT_TYPE_NONE, TEXT_ALIGN_LEFT, false)
  if lbl then
    lbl:SetFont("$(MEDIUM_FONT)|$(KB_12)|soft-shadow-none")
    lbl:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    lbl:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
    lbl:SetPixelRoundingEnabled(false)
  end
end

local function _nvkGetCompletedSubs()
  local Comp = _nvkGetMod("CompletedData", "Completed")
  if Comp and type(Comp.GetSubcategoryList) == "function" then
    local ok, names, keys = pcall(Comp.GetSubcategoryList)
    if ok and type(names) == "table" and type(keys) == "table" then
      return names, keys, Comp
    end
  end
  return {}, {}, nil
end

local function _nvkCompletedPointsForKey(Comp, key)
  if not Comp then
    return 0
  end
  if type(Comp.SummaryCountAndPointsForKey) == "function" then
    local ok, a, b = pcall(Comp.SummaryCountAndPointsForKey, key)
    if ok then
      if tonumber(b) then
        return b
      end
      if tonumber(a) then
        return a
      end
    end
  end
  if type(Comp.PointsForSubcategory) == "function" then
    local ok, p = pcall(Comp.PointsForSubcategory, key)
    if ok and tonumber(p) then
      return p
    end
  end
  return 0
end

local function _nvkRenderCompleted(control)
  local tooltip = _nvkInitializeCategoryTooltip(control)
  if not tooltip then
    return
  end
  local node = control and control.node
  if node == nil and control and control.GetParent then
    local p = control:GetParent()
    if p and p.node then
      node = p.node
    end
  end
  if ShowCompletedRootTooltip then
    ShowCompletedRootTooltip(node)
  end
end

local function _nvkGetTodoSubs()
  local Todo = _nvkGetMod("TodoData", "Todo")
  if Todo and type(Todo.GetSubcategoryList) == "function" then
    local ok, names, keys, topIds = pcall(Todo.GetSubcategoryList)
    if ok and type(names) == "table" and type(keys) == "table" then
      return names, keys, topIds, Todo
    end
  end
  return {}, {}, nil, nil
end

local function _nvkTodoPointsForSub(Todo, key)
  if not Todo then
    return 0
  end
  if type(Todo.PointsForSubcategory) == "function" then
    local ok, p = pcall(Todo.PointsForSubcategory, key)
    if ok and tonumber(p) then
      return p
    end
  end
  local Comp = _nvkGetMod("CompletedData", "Completed")
  if Comp and type(Comp.SummaryCountAndPointsForKey) == "function" then
    local ok, a, b = pcall(Comp.SummaryCountAndPointsForKey, key)
    if ok then
      if tonumber(b) then
        return b
      end
      if tonumber(a) then
        return a
      end
    end
  end
  return 0
end

local function _nvkMaxPointsForTop(topId, Todo)
  if Todo and type(Todo.MaxPointsForTopCategory) == "function" then
    local ok, m = pcall(Todo.MaxPointsForTopCategory, topId)
    if ok and tonumber(m) then
      return m
    end
  end
  if type(GetAchievementCategoryInfo) == "function" and tonumber(topId) then
    local ok, _n, _subs, _ach, _earned, total = pcall(GetAchievementCategoryInfo, topId)
    if ok and tonumber(total) then
      return total
    end
  end
  return 0
end

local function _nvkRenderTodo(control)
  local tooltip = _nvkInitializeCategoryTooltip(control)
  if not tooltip then
    return
  end
  local names, keys, topIds, Todo = _nvkGetTodoSubs()
  local lines = {}
  for i = 1, (keys and #keys or 0) do
    local name = names[i] or "—"
    local pts = _nvkTodoPointsForSub(Todo, keys[i])
    local maxTop = 0
    if type(topIds) == "table" then
      maxTop = _nvkMaxPointsForTop(topIds[i], Todo)
    end
    if maxTop and maxTop > 0 then
      lines[#lines + 1] = string.format(
        "%s |cfafafa(%s / %s)|r",
        zo_strformat("<<1>>", name),
        ZO_CommaDelimitNumber(pts or 0),
        ZO_CommaDelimitNumber(maxTop or 0)
      )
    else
      lines[#lines + 1] =
        string.format("%s |cfafafa(%s)|r", zo_strformat("<<1>>", name), ZO_CommaDelimitNumber(pts or 0))
    end
  end
  if #lines > 0 then
    local text = table.concat(lines, "\n")
    local r, g, b = ZO_SELECTED_TEXT:UnpackRGB()
    local _, lbl = tooltip:AddLine(text, "", r, g, b, LEFT, MODIFY_TEXT_TYPE_NONE, TEXT_ALIGN_LEFT, false)
    if lbl then
      lbl:SetFont("$(MEDIUM_FONT)|$(KB_12)|soft-shadow-none")
      lbl:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
      lbl:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
      lbl:SetPixelRoundingEnabled(false)
    end
  end
end

function Nvk3UT.TryCustomCategoryTooltip(control, data)
  data = _nvkGetData(control, data)
  if not data then
    return false
  end

  local summaryText = data.nvkSummaryTooltipText
  if type(summaryText) == "string" and summaryText ~= "" then
    _nvkShowSummaryText(control, summaryText)
    return true
  end

  if data.isNvkFavorites then
    _nvkRenderFavorites(control)
    return true
  end
  if data.isNvkRecent then
    _nvkRenderRecent(control)
    return true
  end
  if data.isNvkTodo then
    _nvkRenderTodo(control)
    return true
  end
  if data.isNvkCompleted then
    _nvkRenderCompleted(control)
    return true
  end

  return false
end
