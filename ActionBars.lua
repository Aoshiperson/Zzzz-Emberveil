--[[
  ActionBars.lua v3

  修复：确保两行动作条都正确显示
  - ActionButton 1-12（第一行）
  - MultiBarBottomLeftButton 1-12（第二行）
  - MultiBarBottomRightButton 1-12（右下角）
--]]

-- ============================================================
-- 配置 / 运行期状态
-- ============================================================

local statusbarTexture = "Interface\\TargetingFrame\\UI-StatusBar"

local actionPanel = nil
local utilityActionPanel = nil
local auxiliaryPanel = nil
local xpBar = nil
local actionPageEvents = nil
local actionResolversInstalled = false
local bagPanel = nil
local bagEvents = nil

local BUTTON_SIZE = 34
local BUTTONS_PER_PAGE = 12
local DEFAULT_ACTIONBAR_PAGES = 6

-- 需要隐藏的原生动作条元素：鹰头装饰、经验/声望/性能条、
-- 微章菜单等
local HIDDEN_FRAME_NAMES = {
  "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
  "MainMenuBarTexture0", "MainMenuBarTexture1",
  "MainMenuBarTexture2", "MainMenuBarTexture3",
  "MainMenuBarPageNumber", "MainMenuBarPageUpButton", "MainMenuBarPageDownButton",

  "MainMenuExpBar", "ExhaustionTick", "MainMenuBarMaxLevelBar",
  "MainMenuBarOverlayFrame", "ReputationWatchBar",
  "MainMenuBarPerformanceBarFrame", "MainMenuBarPerformanceBar",

  "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
  "QuestLogMicroButton", "SocialsMicroButton", "WorldMapMicroButton",
  "MainMenuMicroButton", "HelpMicroButton",
}

-- 背包按钮不永久隐藏：打开背包时显示在右下角，关闭时自动隐藏。
local BAG_BUTTON_NAMES = {
  "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
  "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton",
}

-- ============================================================
-- 通用 UI 工具
-- ============================================================

local function HideFrame(frame)
  if not frame then return end
  frame:Hide()
  frame:SetAlpha(0)
  frame:EnableMouse(false)
end

local function CreatePanel(name, parent, level)
  local panel = CreateFrame("Frame", name, parent or UIParent)
  panel:SetFrameStrata("MEDIUM")
  panel:SetFrameLevel(level or 1)
  panel:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  return panel
end

local function StyleActionButton(button)
  if not button or button.ActionBarsStyled then return end
  button.ActionBarsStyled = true
  button:SetWidth(BUTTON_SIZE)
  button:SetHeight(BUTTON_SIZE)

  local normalTexture = button:GetNormalTexture()
  if normalTexture then normalTexture:SetAlpha(0) end

  local border = CreateFrame("Frame", nil, button)
  border:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
  border:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
  border:SetFrameLevel(math.max(0, button:GetFrameLevel() - 1))
  border:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  border:SetBackdropColor(0.02, 0.025, 0.03, 0.96)
  border:SetBackdropBorderColor(0.14, 0.18, 0.2, 1)
  button.ActionBarsBorder = border
end

local function PlaceButton(button, panel, column, row)
  if not button then return end
  button:SetParent(panel)
  button:ClearAllPoints()
  button:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 5 + (column - 1) * 36, 5 + row * 36)
  StyleActionButton(button)
  button:Show()
end

-- ============================================================
-- 动作槽位解析
-- ============================================================

local function ResolvePrimaryAction(button)
  local buttonID = button and button:GetID()
  if not buttonID then return nil end

  local bonusOffset = 0
  if type(GetBonusBarOffset) == "function" then
    bonusOffset = tonumber(GetBonusBarOffset()) or 0
  end

  local _, class
  if type(UnitClass) == "function" then
    _, class = UnitClass("player")
  end
  if class == "ROGUE" and bonusOffset > 0 and type(GetShapeshiftForm) == "function" then
    local ok, activeForm = pcall(GetShapeshiftForm)
    if ok and activeForm ~= nil and (tonumber(activeForm) or 0) == 0 then
      bonusOffset = 0
    end
  end

  if bonusOffset > 0 then
    local normalPages = tonumber(NUM_ACTIONBAR_PAGES) or DEFAULT_ACTIONBAR_PAGES
    return buttonID + (normalPages + bonusOffset - 1) * BUTTONS_PER_PAGE
  end

  local maxPages = tonumber(NUM_ACTIONBAR_PAGES) or DEFAULT_ACTIONBAR_PAGES
  local page = tonumber(CURRENT_ACTIONBAR_PAGE) or 1
  if page < 1 or page > maxPages then page = 1 end
  return buttonID + (page - 1) * BUTTONS_PER_PAGE
end

-- ============================================================
-- 挂钩原生 API
-- ============================================================

local function InstallActionResolvers()
  if actionResolversInstalled then return end
  actionResolversInstalled = true

  local originalActionResolver = ActionButton_GetPagedID
  _G.ActionButton_GetPagedID = function(button)
    if button and button.ActionBarsAction then
      return button.ActionBarsAction
    end
    if button and button.ActionBarsPrimaryAction then
      return ResolvePrimaryAction(button)
    end
    if originalActionResolver then return originalActionResolver(button) end
    return button and button:GetID()
  end

  local originalMultiResolver = MultiActionButton_GetPagedID
  _G.MultiActionButton_GetPagedID = function(button)
    if button and button.ActionBarsAction then
      return button.ActionBarsAction
    end
    if originalMultiResolver then return originalMultiResolver(button) end
    return button and button:GetID()
  end

  local originalActionButtonDown = ActionButtonDown
  if type(originalActionButtonDown) == "function" then
    _G.ActionButtonDown = function(id)
      local activeButton = _G["ActionButton" .. tostring(id or "")]
      if not activeButton or not activeButton.ActionBarsPrimaryAction then
        return originalActionButtonDown(id)
      end
      if activeButton:GetButtonState() == "NORMAL" then
        activeButton:SetButtonState("PUSHED")
      end
    end
  end

  local originalActionButtonUp = ActionButtonUp
  if type(originalActionButtonUp) == "function" then
    _G.ActionButtonUp = function(id, onSelf)
      local activeButton = _G["ActionButton" .. tostring(id or "")]
      if not activeButton or not activeButton.ActionBarsPrimaryAction then
        return originalActionButtonUp(id, onSelf)
      end
      if activeButton:GetButtonState() ~= "PUSHED" then return end
      activeButton:SetButtonState("NORMAL")
      if MacroFrame_SaveMacro then MacroFrame_SaveMacro() end

      local action = ResolvePrimaryAction(activeButton)
      if action and type(UseAction) == "function" then
        UseAction(action, 0, onSelf)
      end
      if action and type(IsCurrentAction) == "function" and IsCurrentAction(action) then
        activeButton:SetChecked(1)
      else
        activeButton:SetChecked(0)
      end
    end
  end
end

local function RefreshActionButtons()
  local function RefreshMultiButton(prefix, index)
    local multiButton = _G[prefix .. index]
    if not multiButton then return end
    if type(MultiActionButton_Update) == "function" then
      pcall(MultiActionButton_Update, multiButton)
    elseif type(ActionButton_Update) == "function" then
      pcall(ActionButton_Update, multiButton)
    end
  end

  for i = 1, BUTTONS_PER_PAGE do
    local button = _G["ActionButton" .. i]
    if button then
      button.action = ResolvePrimaryAction(button)
      if type(ActionButton_Update) == "function" then pcall(ActionButton_Update, button) end
      if type(ActionButton_UpdateUsable) == "function" then pcall(ActionButton_UpdateUsable, button) end
      if type(ActionButton_UpdateCooldown) == "function" then pcall(ActionButton_UpdateCooldown, button) end
    end

    RefreshMultiButton("MultiBarBottomLeftButton", i)
    RefreshMultiButton("MultiBarBottomRightButton", i)
  end
end

-- ============================================================
-- 辅助动作条（姿态/变形形态 + 宠物）
-- ============================================================

local function PositionAuxiliaryBars()
  if not auxiliaryPanel then
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetWidth(362)
    panel:SetHeight(38)
    panel:SetFrameStrata("MEDIUM")
    panel:SetFrameLevel(4)

    local halfwayToRightEdge = (UIParent:GetWidth() or 1024) / 4
    panel:SetPoint("BOTTOM", UIParent, "BOTTOM", halfwayToRightEdge, 18)

    auxiliaryPanel = panel
  end
  local panel = auxiliaryPanel

  local function PlaceAuxiliaryButtons(prefix, visibleCount, row)
    for i = 1, 10 do
      local button = _G[prefix .. i]
      if button then
        button:SetParent(panel)
        button:SetWidth(BUTTON_SIZE)
        button:SetHeight(BUTTON_SIZE)
        button:ClearAllPoints()
        button:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 2 + (i - 1) * 36, 2 + row * 36)
        StyleActionButton(button)
        if i <= visibleCount then button:Show() else button:Hide() end
      end
    end
  end

  local formCount = 0
  if type(GetNumShapeshiftForms) == "function" then
    formCount = tonumber(GetNumShapeshiftForms()) or 0
  end
  if ShapeshiftBarFrame then
    ShapeshiftBarFrame:SetAlpha(0)
    ShapeshiftBarFrame:EnableMouse(false)
    PlaceAuxiliaryButtons("ShapeshiftButton", formCount, 0)
  end

  local hasPet = false
  if type(HasPetUI) == "function" then
    local petUI = HasPetUI()
    hasPet = petUI == true or petUI == 1 or petUI == "1"
  end
  if not hasPet and type(UnitExists) == "function" then
    local petExists = UnitExists("pet")
    hasPet = petExists == true or petExists == 1 or petExists == "1"
  end
  if PetActionBarFrame then
    PetActionBarFrame:SetAlpha(0)
    PetActionBarFrame:EnableMouse(false)
    PlaceAuxiliaryButtons("PetActionButton", hasPet and 10 or 0, formCount > 0 and 1 or 0)
  end

  local panelHeight = (hasPet and formCount > 0) and 74 or 38
  panel:SetWidth(362)
  panel:SetHeight(panelHeight)
end

local function SetupActionPageEvents()
  if actionPageEvents then return end

  local events = CreateFrame("Frame", nil)

  local EVENT_NAMES = {
    "UPDATE_BONUS_ACTIONBAR", "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS",
    "PLAYER_AURAS_CHANGED", "PLAYER_ENTER_COMBAT", "PLAYER_LEAVE_COMBAT",
    "ACTIONBAR_SLOT_CHANGED", "PET_BAR_UPDATE", "UNIT_PET",
  }
  for _, eventName in ipairs(EVENT_NAMES) do
    pcall(events.RegisterEvent, events, eventName)
  end

  local REFRESH_WINDOW = 0.75
  local REFRESH_INTERVAL = 0.05

  local function OnUpdateDuringTransition(frame, elapsed)
    frame.refreshElapsed = (frame.refreshElapsed or 0) + (elapsed or 0)
    frame.refreshRemaining = (frame.refreshRemaining or 0) - (elapsed or 0)
    if frame.refreshElapsed >= REFRESH_INTERVAL or frame.refreshRemaining <= 0 then
      frame.refreshElapsed = 0
      RefreshActionButtons()
      PositionAuxiliaryBars()
    end
    if frame.refreshRemaining <= 0 then
      frame:SetScript("OnUpdate", nil)
    end
  end

  events:SetScript("OnEvent", function()
    RefreshActionButtons()
    PositionAuxiliaryBars()
    events.refreshElapsed = 0
    events.refreshRemaining = REFRESH_WINDOW
    events:SetScript("OnUpdate", OnUpdateDuringTransition)
  end)

  actionPageEvents = events
end

-- ============================================================
-- 背包按钮（打开背包时显示在右下角，关闭时隐藏）
-- ============================================================

local function IsAnyContainerFrameShown()
  local frameCount = tonumber(NUM_CONTAINER_FRAMES) or 13
  for i = 1, frameCount do
    local frame = _G["ContainerFrame" .. i]
    if frame and frame:IsShown() then
      return true
    end
  end
  return false
end

local function UpdateBagPanelVisibility()
  if not bagPanel then return end
  if IsAnyContainerFrameShown() then
    bagPanel:Show()
  else
    bagPanel:Hide()
  end
end

local function PositionBagButtons()
  if not bagPanel then
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetFrameStrata("MEDIUM")
    panel:SetFrameLevel(4)
    panel:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -14, 66)
    bagPanel = panel

    local column = 0
    for _, name in ipairs(BAG_BUTTON_NAMES) do
      local button = _G[name]
      if button then
        button:SetParent(panel)
        button:ClearAllPoints()
        button:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -column * 32, 0)
        button:Show()
        column = column + 1
      end
    end
    panel:SetWidth(math.max(1, column * 32))
    panel:SetHeight(32)
  end

  UpdateBagPanelVisibility()
end

local function SetupBagEvents()
  if bagEvents then return end

  local events = CreateFrame("Frame", nil)
  events:RegisterEvent("BAG_OPEN")
  events:RegisterEvent("BAG_CLOSED")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  
  events:SetScript("OnEvent", function()
    UpdateBagPanelVisibility()
  end)

  bagEvents = events
end

-- ============================================================
-- 经验条
-- ============================================================

local function FormatXPText(level, percent, resting, rested)
  local text = "Level " .. level
  if percent then
    text = text .. "  -  " .. percent .. "%"
  else
    text = text .. "  -  Maximum Level"
  end

  if resting and rested and rested > 0 then
    text = text .. "  |cff66aaffResting  -  Rested " .. rested .. "|r"
  elseif resting then
    text = text .. "  |cff66aaffResting|r"
  elseif rested and rested > 0 then
    text = text .. "  |cff66aaffRested " .. rested .. "|r"
  end

  return text
end

local function UpdateXPBar()
  local bar = xpBar
  if not bar then return end

  local current = UnitXP("player") or 0
  local maximum = UnitXPMax("player") or 0
  local level = UnitLevel("player") or 0

  local rested = 0
  if type(GetXPExhaustion) == "function" then
    rested = GetXPExhaustion() or 0
  end

  local resting = false
  if type(IsResting) == "function" then
    local ok, value = pcall(IsResting)
    resting = ok and (value == true or value == 1 or value == "1")
  end

  if resting then
    bar:SetStatusBarColor(0.18, 0.48, 0.92)
    bar:SetBackdropBorderColor(0.35, 0.62, 1, 1)
  else
    bar:SetStatusBarColor(0.38, 0.28, 0.78)
    bar:SetBackdropBorderColor(0.18, 0.22, 0.28, 1)
  end

  if maximum > 0 then
    local percent = math.floor(current / maximum * 100)
    bar:SetMinMaxValues(0, maximum)
    bar:SetValue(current)
    bar.text:SetText(FormatXPText(level, percent, resting, rested))
  else
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    bar.text:SetText(FormatXPText(level, nil, resting, rested))
  end

  bar.current = current
  bar.maximum = maximum
  bar.rested = rested
  bar.resting = resting
end

local function SetupXPBar()
  if xpBar then return end

  local parent = actionPanel or UIParent
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetWidth(442)
  bar:SetHeight(12)
  if actionPanel then
    bar:SetPoint("TOP", actionPanel, "BOTTOM", 0, -4)
  else
    bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 18)
  end
  bar:SetStatusBarTexture(statusbarTexture)
  bar:SetStatusBarColor(0.38, 0.28, 0.78)
  bar:SetFrameLevel((parent:GetFrameLevel() or 1) + 3)
  bar:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  bar:SetBackdropColor(0.025, 0.03, 0.04, 0.8)
  bar:SetBackdropBorderColor(0.18, 0.22, 0.28, 1)

  bar.background = bar:CreateTexture(nil, "BACKGROUND")
  bar.background:SetAllPoints()
  bar.background:SetTexture(statusbarTexture)
  bar.background:SetVertexColor(0.035, 0.04, 0.055, 0.9)

  bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)

  bar:EnableMouse(true)
  bar:SetScript("OnEnter", function(frame)
    GameTooltip:SetOwner(frame, "ANCHOR_TOP")
    GameTooltip:SetText("Experience")
    if frame.maximum and frame.maximum > 0 then
      GameTooltip:AddLine(frame.current .. " / " .. frame.maximum, 1, 1, 1)
      if frame.rested and frame.rested > 0 then
        GameTooltip:AddLine("Rested: " .. frame.rested, 0.4, 0.65, 1)
      end
    else
      GameTooltip:AddLine("Maximum level", 1, 0.82, 0.2)
    end
    if frame.resting then
      GameTooltip:AddLine("Currently resting", 0.4, 0.65, 1)
    end
    GameTooltip:Show()
  end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local events = CreateFrame("Frame", nil)
  events:RegisterEvent("PLAYER_XP_UPDATE")
  events:RegisterEvent("UPDATE_EXHAUSTION")
  events:RegisterEvent("PLAYER_LEVEL_UP")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  pcall(events.RegisterEvent, events, "PLAYER_UPDATE_RESTING")
  
  events:SetScript("OnEvent", function()
    UpdateXPBar()
  end)

  xpBar = bar
  UpdateXPBar()
end

-- ============================================================
-- 入口：接管原生动作条
-- ============================================================

local function SetupActionBars()
  InstallActionResolvers()

  for _, name in ipairs(HIDDEN_FRAME_NAMES) do
    HideFrame(_G[name])
  end

  local panel = CreatePanel(nil, UIParent, 1)
  panel:SetWidth(442)
  panel:SetHeight(82)
  panel:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 18)
  panel:SetBackdropColor(0, 0, 0, 0)
  panel:SetBackdropBorderColor(0, 0, 0, 0)
  actionPanel = panel

  local utilityPanel = CreatePanel(nil, UIParent, 1)
  utilityPanel:SetWidth(442)
  utilityPanel:SetHeight(44)
  utilityPanel:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -14, 14)
  utilityPanel:SetBackdropColor(0, 0, 0, 0)
  utilityPanel:SetBackdropBorderColor(0, 0, 0, 0)
  utilityActionPanel = utilityPanel

  -- 第一行：ActionButton 1-12 （主动作条）
  for i = 1, BUTTONS_PER_PAGE do
    local primaryButton = _G["ActionButton" .. i]
    if primaryButton then
      primaryButton.ActionBarsPrimaryAction = true
    end
    PlaceButton(primaryButton, panel, i, 0)
  end

  -- 第二行：MultiBarBottomLeftButton 1-12 （上层按钮）
  for i = 1, BUTTONS_PER_PAGE do
    local upperButton = _G["MultiBarBottomLeftButton" .. i]
    if upperButton then
      upperButton.ActionBarsAction = 60 + i
      upperButton.action = 60 + i
    end
    PlaceButton(upperButton, panel, i, 1)
  end

  -- 右下角：MultiBarBottomRightButton 1-12 （实用按钮）
  for i = 1, BUTTONS_PER_PAGE do
    local utilityButton = _G["MultiBarBottomRightButton" .. i]
    if utilityButton then
      utilityButton.ActionBarsAction = 48 + i
      utilityButton.action = 48 + i
    end
    PlaceButton(utilityButton, utilityPanel, i, 0)
  end

  SetupActionPageEvents()
  RefreshActionButtons()

  -- 隐藏原生动作条框架（但不影响已重新父级化的按钮）
  HideFrame(MainMenuBarArtFrame)
  HideFrame(MainMenuBar)
  -- 注：MultiBarBottomLeft 和 MultiBarBottomRight 的按钮已被重新父级化
  -- 所以隐藏这些框架不会影响按钮显示

  PositionAuxiliaryBars()
  PositionBagButtons()
  SetupBagEvents()
end

-- ============================================================
-- 入口：等玩家登录完成再接管动作条
-- ============================================================

local bootstrap = CreateFrame("Frame", nil, UIParent)
if bootstrap then
  bootstrap:RegisterEvent("PLAYER_LOGIN")
  
  bootstrap:SetScript("OnEvent", function()
    pcall(function()
      bootstrap:UnregisterEvent("PLAYER_LOGIN")
    end)
    pcall(SetupActionBars)
    pcall(SetupXPBar)
  end)
  
  print("|cffff00ffActionBars v3: Loaded successfully|r")
else
  print("|cffff0000ActionBars: Failed to create bootstrap frame|r")
end
