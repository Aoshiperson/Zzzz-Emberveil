--[[
  ActionBars.lua —— 独立精简版
  来源：从 UnrealUI (modules/actionbar.lua) 抽取核心逻辑重构，去除框架依赖
  不含：设置面板、可拖拽、10条动作条、Classic贴图皮肤、AZERTY键盘映射

  已验证保留的关键修复：
    - CURRENT_ACTIONBAR_PAGE 不可靠，自己解析当前页
    - 冷却用 GetTime() 连续读数，不用估算，reload后依然准
    - GCD（公共冷却）单独识别，不会跟真实长冷却混淆
    - print() 已确认失效，全部用 DEFAULT_CHAT_FRAME:AddMessage
    - SetFont 在已绑定Font对象的FontString上不生效，此文件不碰字体加载
    - 隐藏原生按钮走 Hide()+EnableMouse(false)，不做"只隐藏视觉保留骨架"
      那套处理（那套只用于原版目标框体家族，动作条本来就是直接Hide()）

  已知未处理：
    - 32位时间溢出修正（极端长时间运行冷却计时可能跳变，遇到再加）
--]]

-- ============================================================
-- 配置表：想改布局/位置/大小，直接改这里的数字
-- ============================================================

local CONFIG = {
  buttonSize    = 34,
  buttonSpacing = 2,

  showKeybind  = true,
  showMacro    = true,
  showCount    = true,
  showCooldown = true,
  showGCD      = true,

  bars = {
    [1] = { enabled = true,  point = "BOTTOM", x = 0,   y = 18,  label = "主条(跟随翻页)" },
    [2] = { enabled = true,  point = "BOTTOM", x = 0,   y = 58,  label = "MultiBarRight"       },
    [3] = { enabled = false, point = "BOTTOM", x = 0,   y = 98,  label = "MultiBarLeft"        },
    [4] = { enabled = true,  point = "BOTTOMRIGHT", x = -14, y = 18, label = "MultiBarBottomRight" },
    [5] = { enabled = false, point = "BOTTOMLEFT",  x = 14,  y = 18, label = "MultiBarBottomLeft"  },
  },
}

local BAR_SLOT_BASE = {
  [2] = 24,  -- MultiBarRight:       25-36
  [3] = 36,  -- MultiBarLeft:        37-48
  [4] = 48,  -- MultiBarBottomRight: 49-60
  [5] = 60,  -- MultiBarBottomLeft:  61-72
}

local SLOTS_PER_BAR = 12
local GCD_THRESHOLD = 2
local CD_TICK = 0.1

local CD_COLOR = {
  normal = { 1, 1, 1 },
  low    = { 1, 0.2, 0.2 },
}

local COLOR = {
  usable     = { 1.00, 1.00, 1.00, 1.00 },
  oom        = { 0.40, 0.40, 1.00, 1.00 },
  unusable   = { 0.35, 0.35, 0.35, 1.00 },
  outOfRange = { 1.00, 0.10, 0.10, 1.00 },
  cooldown   = { 1.00, 0.20, 0.20, 1.00 },
}

-- ============================================================
-- 工具函数
-- ============================================================

local function Report(msg)
  DEFAULT_CHAT_FRAME:AddMessage(msg)
end

local apiFnCache = {}
local function ResolveApiFn(name)
  local cached = apiFnCache[name]
  if cached ~= nil then
    if cached == false then return nil end
    return cached
  end
  local fn = getglobal(name)
  if type(fn) == "function" then
    apiFnCache[name] = fn
    return fn
  end
  apiFnCache[name] = false
  return nil
end

local function Call(name, a, b, c)
  local fn = ResolveApiFn(name)
  if not fn then return nil end
  local ok, r1, r2, r3 = pcall(fn, a, b, c)
  if not ok then return nil end
  return r1, r2, r3
end

local function Has(name)
  return ResolveApiFn(name) and true or false
end

-- ============================================================
-- 槽位解析
-- ============================================================

local function ActivePage()
  local page = tonumber(getglobal("CURRENT_ACTIONBAR_PAGE")) or 1
  local pages = tonumber(getglobal("NUM_ACTIONBAR_PAGES")) or 6
  local offset = tonumber(Call("GetBonusBarOffset")) or 0
  if page == 1 and offset ~= 0 then return pages + offset end
  if page < 1 then return 1 end
  return page
end

local function SlotFor(bar, index)
  if bar == 1 then
    return (ActivePage() - 1) * SLOTS_PER_BAR + index
  end
  return (BAR_SLOT_BASE[bar] or (bar - 1) * SLOTS_PER_BAR) + index
end

-- ============================================================
-- 挂钩原生 API（未经文档确认，装之前先测存在性）
-- ============================================================

local resolversInstalled = false

local function InstallActionResolvers()
  if resolversInstalled then return end
  resolversInstalled = true

  local missing = {}

  local originalActionResolver = ActionButton_GetPagedID
  if type(originalActionResolver) ~= "function" then table.insert(missing, "ActionButton_GetPagedID") end
  ActionButton_GetPagedID = function(button)
    local b = button or this
    if b and b.uuiSlot then return b.uuiSlot end
    if originalActionResolver then return originalActionResolver(button) end
    return b and b:GetID()
  end

  local originalMultiResolver = MultiActionButton_GetPagedID
  if type(originalMultiResolver) ~= "function" then table.insert(missing, "MultiActionButton_GetPagedID") end
  MultiActionButton_GetPagedID = function(button)
    local b = button or this
    if b and b.uuiSlot then return b.uuiSlot end
    if originalMultiResolver then return originalMultiResolver(button) end
    return b and b:GetID()
  end

  if #missing > 0 then
    Report("|cffffaa00ActionBars: 以下FrameXML函数缺失: " .. table.concat(missing, ", ") .. "|r")
  end
end

-- ============================================================
-- 光标状态
-- ============================================================

local function CursorHoldsAction()
  if Call("CursorHasItem") then return true end
  if Call("CursorHasSpell") then return true end
  if Call("CursorHasMacro") then return true end
  return false
end

-- ============================================================
-- 按钮点击/拖拽
-- ============================================================

local function OnButtonClick(button)
  local slot = button.uuiSlot
  if CursorHoldsAction() then
    Call("PickupAction", slot)
    return
  end
  Call("UseAction", slot)
end

local function OnButtonDragStart(button)
  Call("PickupAction", button.uuiSlot)
end

local function OnButtonReceiveDrag(button)
  Call("PlaceAction", button.uuiSlot)
end

local function ShowTooltip(button)
  local tooltip = GameTooltip
  if not tooltip then return end
  pcall(tooltip.SetOwner, tooltip, button, "ANCHOR_RIGHT")
  if not pcall(tooltip.SetAction, tooltip, button.uuiSlot) then
    pcall(tooltip.Hide, tooltip)
  end
end

local function HideTooltip()
  if GameTooltip then pcall(GameTooltip.Hide, GameTooltip) end
end

-- ============================================================
-- 冷却计算
-- ============================================================

local function CooldownRemaining(start, duration)
  local now = tonumber(Call("GetTime")) or 0
  if start <= now then
    return duration - (now - start)
  end
  return nil
end

local function FormatCooldown(remaining)
  if remaining >= 60 then
    return string.format("%dm", math.floor(remaining / 60)), CD_COLOR.normal
  elseif remaining >= 10 then
    return string.format("%d", math.floor(remaining)), CD_COLOR.normal
  else
    return string.format("%.1f", remaining), CD_COLOR.low
  end
end

local gcdStart, gcdDuration

local function NoteGCD(slot, start, duration)
  if not CONFIG.showGCD then return end
  if start <= 0 or duration <= 0 or duration >= GCD_THRESHOLD then return end
  if Call("IsConsumableAction", slot) then return end
  gcdStart, gcdDuration = start, duration
end

-- ============================================================
-- 按钮状态刷新
-- ============================================================

local function UpdateSlot(button)
  local slot = button.uuiSlot
  local texture = Call("GetActionTexture", slot)
  if type(texture) == "string" and texture ~= "" then
    pcall(button.uuiIcon.SetTexture, button.uuiIcon, texture)
    button.uuiIcon:Show()
    button.uuiEmpty = false
  else
    pcall(button.uuiIcon.SetTexture, button.uuiIcon, nil)
    button.uuiIcon:Hide()
    button.uuiEmpty = true
  end

  if CONFIG.showCount and button.uuiCount then
    local n = tonumber(Call("GetActionCount", slot))
    if n and n > 0 then
      button.uuiCount:SetText(tostring(n))
      button.uuiCount:Show()
    else
      button.uuiCount:SetText("")
      button.uuiCount:Hide()
    end
  end

  if CONFIG.showMacro and button.uuiMacro then
    local macro = Call("GetActionText", slot)
    if type(macro) == "string" and macro ~= "" then
      button.uuiMacro:SetText(macro)
      button.uuiMacro:Show()
    else
      button.uuiMacro:SetText("")
      button.uuiMacro:Hide()
    end
  end

  if CONFIG.showKeybind and button.uuiKeybind then
    local prefix = button.uuiBindingPrefix
    local key = prefix and Call("GetBindingKey", prefix .. button.uuiIndex)
    if type(key) == "string" and key ~= "" then
      button.uuiKeybind:SetText(key)
      button.uuiKeybind:Show()
    else
      button.uuiKeybind:SetText("")
      button.uuiKeybind:Hide()
    end
  end
end

local function UpdateUsable(button)
  if button.uuiEmpty then return end
  local slot = button.uuiSlot
  local color = COLOR.usable

  if button.uuiCdActive then
    color = COLOR.cooldown
  else
    local hasRange = true
    if Has("ActionHasRange") then
      hasRange = Call("ActionHasRange", slot) and true or false
    end
    if hasRange then
      local inRange = Call("IsActionInRange", slot)
      if tonumber(inRange) == 0 or inRange == false then
        color = COLOR.outOfRange
      end
    end
    if color == COLOR.usable then
      local usable, oom = Call("IsUsableAction", slot)
      if oom and oom ~= 0 then
        color = COLOR.oom
      elseif usable ~= nil and (usable == false or usable == 0) then
        color = COLOR.unusable
      end
    end
  end

  pcall(button.uuiIcon.SetVertexColor, button.uuiIcon, color[1], color[2], color[3], color[4])
end

local function UpdateCooldown(button)
  local slot = button.uuiSlot
  local start, duration, enable = Call("GetActionCooldown", slot)
  start = tonumber(start) or 0
  duration = tonumber(duration) or 0
  enable = tonumber(enable)

  if button.uuiCooldown and type(CooldownFrame_SetTimer) == "function" then
    pcall(CooldownFrame_SetTimer, button.uuiCooldown, start, duration, enable or 1)
  end

  if enable == nil or enable > 0 then NoteGCD(slot, start, duration) end

  button.uuiCdStart = start
  button.uuiCdDuration = duration
  button.uuiCdActive = (start > 0 and duration >= GCD_THRESHOLD
                        and (enable == nil or enable > 0)) and true or false

  if not CONFIG.showCooldown or not button.uuiCooldownText then return end
  local remaining = button.uuiCdActive and CooldownRemaining(start, duration)
  if not remaining or remaining <= 0 then
    button.uuiCooldownText:SetText("")
    button.uuiCooldownText:Hide()
    return
  end
  local text, color = FormatCooldown(remaining)
  button.uuiCooldownText:SetText(text)
  pcall(button.uuiCooldownText.SetTextColor, button.uuiCooldownText, color[1], color[2], color[3])
  button.uuiCooldownText:Show()
end

local function FullUpdate(button)
  UpdateSlot(button)
  UpdateCooldown(button)
  UpdateUsable(button)
end

-- ============================================================
-- 按钮创建
-- ============================================================

local function CreateButton(bar, index, parent)
  local name = "SimpleActionBar" .. bar .. "Button" .. index
  local button = CreateFrame("Button", name, parent)
  button.uuiBar = bar
  button.uuiIndex = index
  button.uuiBindingPrefix = (bar == 2) and "MULTIACTIONBAR3BUTTON"
                          or (bar == 3) and "MULTIACTIONBAR4BUTTON"
                          or (bar == 4) and "MULTIACTIONBAR2BUTTON"
                          or (bar == 5) and "MULTIACTIONBAR1BUTTON"
                          or nil

  button:SetWidth(CONFIG.buttonSize)
  button:SetHeight(CONFIG.buttonSize)
  pcall(button.EnableMouse, button, true)
  pcall(button.RegisterForClicks, button, "LeftButtonUp", "RightButtonUp")
  pcall(button.RegisterForDrag, button, "LeftButton")

  button:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 9,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  button:SetBackdropColor(0.02, 0.025, 0.03, 0.9)
  button:SetBackdropBorderColor(0.25, 0.28, 0.3, 1)

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
  icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  button.uuiIcon = icon

  button.uuiKeybind = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  button.uuiKeybind:SetPoint("TOPRIGHT", button, "TOPRIGHT", -2, -2)

  button.uuiCount = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  button.uuiCount:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)

  button.uuiMacro = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  button.uuiMacro:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
  button.uuiMacro:SetWidth(CONFIG.buttonSize - 6)

  local ok, cooldown = pcall(CreateFrame, "Model", name .. "Cooldown", button, "CooldownFrameTemplate")
  if ok and cooldown and type(CooldownFrame_SetTimer) == "function" then
    pcall(cooldown.SetAllPoints, cooldown, button)
    button.uuiCooldown = cooldown
  end

  button.uuiCooldownText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  button.uuiCooldownText:SetPoint("CENTER", button, "CENTER", 0, 0)

  button:SetScript("OnClick", function() OnButtonClick(button) end)
  button:SetScript("OnDragStart", function() OnButtonDragStart(button) end)
  button:SetScript("OnReceiveDrag", function() OnButtonReceiveDrag(button) end)
  button:SetScript("OnEnter", function() ShowTooltip(button) end)
  button:SetScript("OnLeave", function() HideTooltip() end)

  return button
end

-- ============================================================
-- 动作条创建
-- ============================================================

local bars = {}

local function CreateBar(barIndex)
  local spec = CONFIG.bars[barIndex]
  if not spec or not spec.enabled then return end

  local frame = CreateFrame("Frame", "SimpleActionBar" .. barIndex, UIParent)
  frame:SetPoint(spec.point, UIParent, spec.point, spec.x, spec.y)

  local buttons = {}
  local i
  for i = 1, SLOTS_PER_BAR do
    local button = CreateButton(barIndex, i, frame)
    button:ClearAllPoints()
    button:SetPoint("LEFT", frame, "LEFT", (i - 1) * (CONFIG.buttonSize + CONFIG.buttonSpacing), 0)
    buttons[i] = button
  end

  frame:SetWidth(SLOTS_PER_BAR * (CONFIG.buttonSize + CONFIG.buttonSpacing))
  frame:SetHeight(CONFIG.buttonSize)

  bars[barIndex] = { frame = frame, buttons = buttons }
end

local function RefreshSlot(button)
  button.uuiSlot = SlotFor(button.uuiBar, button.uuiIndex)
  FullUpdate(button)
end

local function RefreshAll()
  local bar, entry
  for bar, entry in pairs(bars) do
    local i
    for i = 1, table.getn(entry.buttons) do
      RefreshSlot(entry.buttons[i])
    end
  end
end

-- ============================================================
-- 隐藏原生条（保留原生对象存在，Hide()+关闭鼠标响应）
-- ============================================================

local HIDDEN_FRAMES = {
  "MainMenuBar", "MainMenuBarArtFrame",
  "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
  "MultiBarRight", "MultiBarLeft", "MultiBarBottomLeft", "MultiBarBottomRight",
}

local NATIVE_BUTTON_PREFIXES = {
  "ActionButton",
  "MultiBarRightButton",
  "MultiBarLeftButton",
  "MultiBarBottomRightButton",
  "MultiBarBottomLeftButton",
}

local function HideNativeBars()
  local i
  for i = 1, table.getn(HIDDEN_FRAMES) do
    local frame = getglobal(HIDDEN_FRAMES[i])
    if frame then
      frame:Hide()
      frame:SetAlpha(0)
      pcall(frame.EnableMouse, frame, false)
    end
  end

  local prefixIndex, slotIndex
  for prefixIndex = 1, table.getn(NATIVE_BUTTON_PREFIXES) do
    local prefix = NATIVE_BUTTON_PREFIXES[prefixIndex]
    for slotIndex = 1, SLOTS_PER_BAR do
      local button = getglobal(prefix .. slotIndex)
      if button then
        pcall(button.EnableMouse, button, false)
      end
    end
  end
end

-- ============================================================
-- 定时刷新
-- ============================================================

local cdTimer = 0
local function OnUpdateCooldownText(elapsed)
  cdTimer = cdTimer + (elapsed or 0)
  if cdTimer < CD_TICK then return end
  cdTimer = 0
  local bar, entry
  for bar, entry in pairs(bars) do
    local i
    for i = 1, table.getn(entry.buttons) do
      UpdateCooldown(entry.buttons[i])
    end
  end
end

-- ============================================================
-- 入口
-- ============================================================

local function Setup()
  InstallActionResolvers()
  HideNativeBars()

  local i
  for i = 1, 5 do
    CreateBar(i)
  end

  RefreshAll()

  local events = CreateFrame("Frame")
  pcall(events.RegisterEvent, events, "ACTIONBAR_SLOT_CHANGED")
  pcall(events.RegisterEvent, events, "ACTIONBAR_PAGE_CHANGED")
  pcall(events.RegisterEvent, events, "UPDATE_BONUS_ACTIONBAR")
  pcall(events.RegisterEvent, events, "PLAYER_ENTER_COMBAT")
  pcall(events.RegisterEvent, events, "PLAYER_LEAVE_COMBAT")
  events:SetScript("OnEvent", RefreshAll)
  events:SetScript("OnUpdate", OnUpdateCooldownText)
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_ENTERING_WORLD")
bootstrap:SetScript("OnEvent", function()
  pcall(function() bootstrap:UnregisterEvent("PLAYER_ENTERING_WORLD") end)
  pcall(Setup)
end)

Report("|cffff00ffSimpleActionBars: Loaded|r")