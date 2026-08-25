--[[
  ActionBars.lua —— 独立版（从 PotatoUI 剥离，去除框架依赖）
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

local hiddenNames = {
  -- gryphons and action-bar artwork
  "MainMenuBarLeftEndCap", "MainMenuBarRightEndCap",
  "MainMenuBarTexture0", "MainMenuBarTexture1",
  "MainMenuBarTexture2", "MainMenuBarTexture3",
  "MainMenuBarPageNumber", "MainMenuBarPageUpButton", "MainMenuBarPageDownButton",

  -- experience, reputation and performance chrome
  "MainMenuExpBar", "ExhaustionTick", "MainMenuBarMaxLevelBar",
  "MainMenuBarOverlayFrame", "ReputationWatchBar",
  "MainMenuBarPerformanceBarFrame", "MainMenuBarPerformanceBar",

  -- micro menu
  "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton",
  "QuestLogMicroButton", "SocialsMicroButton", "WorldMapMicroButton",
  "MainMenuMicroButton", "HelpMicroButton",

  -- original bag strip
  "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot",
  "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton",
}

-- ============================================================
-- 通用 UI 工具（原来由 PotatoUI 核心提供，这里内联）
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

-- ============================================================
-- 动作槽位解析
-- ============================================================

local StyleActionButton

local function ResolvePrimaryAction(button)
  local buttonID = button and button:GetID()
  if not buttonID then return nil end

  -- In Vanilla clients forms are stored after the six normal action pages.
  -- Emberveil does not reliably update CURRENT_ACTIONBAR_PAGE after buttons
  -- get reparented, so resolve the active bonus page directly.
  local bonusOffset = 0
  if type(GetBonusBarOffset) == "function" then
    bonusOffset = tonumber(GetBonusBarOffset()) or 0
  end

  -- Emberveil can leave the bonus offset stuck briefly after a rogue breaks
  -- stealth. The form state changes reliably, so do not keep routing clicks
  -- to slots 73-84 once the rogue has returned to form zero.
  local _, class
  if type(UnitClass) == "function" then _, class = UnitClass("player") end
  if class == "ROGUE" and bonusOffset > 0 and type(GetShapeshiftForm) == "function" then
    local ok, activeForm = pcall(GetShapeshiftForm)
    if ok and activeForm ~= nil and (tonumber(activeForm) or 0) == 0 then
      bonusOffset = 0
    end
  end
  if bonusOffset > 0 then
    local normalPages = tonumber(NUM_ACTIONBAR_PAGES) or 6
    return buttonID + (normalPages + bonusOffset - 1) * 12
  end

  local page = tonumber(CURRENT_ACTIONBAR_PAGE) or 1
  if page < 1 or page > (tonumber(NUM_ACTIONBAR_PAGES) or 6) then page = 1 end
  return buttonID + (page - 1) * 12
end

-- ============================================================
-- 挂钩原生 API
-- ============================================================

local function InstallActionResolvers()
  if actionResolversInstalled then return end
  actionResolversInstalled = true

  -- Emberveil currently resolves MultiBarBottomLeft buttons as slots 1-12,
  -- duplicating the primary row. Honour our explicit slot mapping in both
  -- resolver variants used by original 1.12 FrameXML.
  local originalActionResolver = ActionButton_GetPagedID
  ActionButton_GetPagedID = function(button)
    local activeButton = button or this
    if activeButton and activeButton.ActionBarsAction then
      return activeButton.ActionBarsAction
    end
    if activeButton and activeButton.ActionBarsPrimaryAction then
      return ResolvePrimaryAction(activeButton)
    end
    if originalActionResolver then return originalActionResolver(button) end
    return activeButton and activeButton:GetID()
  end

  local originalMultiResolver = MultiActionButton_GetPagedID
  MultiActionButton_GetPagedID = function(button)
    local activeButton = button or this
    if activeButton and activeButton.ActionBarsAction then
      return activeButton.ActionBarsAction
    end
    if originalMultiResolver then return originalMultiResolver(button) end
    return activeButton and activeButton:GetID()
  end

  -- Vanilla key bindings normally divert to BonusActionButton while the
  -- native bonus controller is shown. We keep that controller alive for
  -- state updates but display ActionButton instead, so dispatch bindings
  -- through the visible button and the same resolver used by mouse clicks.
  local originalActionButtonDown = ActionButtonDown
  if type(originalActionButtonDown) == "function" then
    ActionButtonDown = function(id)
      local activeButton = getglobal("ActionButton" .. tostring(id or ""))
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
    ActionButtonUp = function(id, onSelf)
      local activeButton = getglobal("ActionButton" .. tostring(id or ""))
      if not activeButton or not activeButton.ActionBarsPrimaryAction then
        return originalActionButtonUp(id, onSelf)
      end
      if activeButton:GetButtonState() ~= "PUSHED" then return end
      activeButton:SetButtonState("NORMAL")
      if MacroFrame_SaveMacro then MacroFrame_SaveMacro() end
      local action = ResolvePrimaryAction(activeButton)
      if action and type(UseAction) == "function" then UseAction(action, 0, onSelf) end
      if action and type(IsCurrentAction) == "function" and IsCurrentAction(action) then
        activeButton:SetChecked(1)
      else
        activeButton:SetChecked(0)
      end
    end
  end
end

local function RefreshActionButtons()
  local previousThis = this
  local i
  for i = 1, 12 do
    local button = getglobal("ActionButton" .. i)
    if button then
      -- Emberveil's input bridge may read this cached field directly instead
      -- of calling ActionButton_GetPagedID. Keep it synchronized on every
      -- page/form refresh so leaving stealth restores slots 1-12.
      button.action = ResolvePrimaryAction(button)
      this = button
      if type(ActionButton_Update) == "function" then pcall(ActionButton_Update) end
      if type(ActionButton_UpdateUsable) == "function" then pcall(ActionButton_UpdateUsable) end
      if type(ActionButton_UpdateCooldown) == "function" then pcall(ActionButton_UpdateCooldown) end
    end

    local bottomLeftButton = getglobal("MultiBarBottomLeftButton" .. i)
    if bottomLeftButton then
      this = bottomLeftButton
      if type(MultiActionButton_Update) == "function" then
        pcall(MultiActionButton_Update)
      elseif type(ActionButton_Update) == "function" then
        pcall(ActionButton_Update)
      end
    end

    local bottomRightButton = getglobal("MultiBarBottomRightButton" .. i)
    if bottomRightButton then
      this = bottomRightButton
      if type(MultiActionButton_Update) == "function" then
        pcall(MultiActionButton_Update)
      elseif type(ActionButton_Update) == "function" then
        pcall(ActionButton_Update)
      end
    end
  end
  this = previousThis
end

-- ============================================================
-- 辅助动作条（姿态/变形形态 + 宠物）
-- ============================================================

local function PositionAuxiliaryBars()
  if not auxiliaryPanel then
    local panel = CreateFrame("Frame", "ActionBarsAuxiliaryPanel", UIParent)
    panel:SetWidth(362)
    panel:SetHeight(38)
    panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 18, 18)
    panel:SetFrameStrata("MEDIUM")
    panel:SetFrameLevel(4)
    auxiliaryPanel = panel
  end
  local panel = auxiliaryPanel

  local function PlaceAuxiliaryButtons(prefix, visibleCount, row)
    local i
    for i = 1, 10 do
      local button = getglobal(prefix .. i)
      if button then
        button:SetParent(panel)
        button:SetWidth(34)
        button:SetHeight(34)
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

  local hasPet
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
  local events = CreateFrame("Frame", "ActionBarsPageEvents")
  -- Some Emberveil builds expose a slightly different subset of the old
  -- FrameXML events. Register each defensively so one absent alias cannot
  -- prevent this addon from loading.
  pcall(events.RegisterEvent, events, "UPDATE_BONUS_ACTIONBAR")
  pcall(events.RegisterEvent, events, "ACTIONBAR_PAGE_CHANGED")
  pcall(events.RegisterEvent, events, "UPDATE_SHAPESHIFT_FORM")
  pcall(events.RegisterEvent, events, "UPDATE_SHAPESHIFT_FORMS")
  pcall(events.RegisterEvent, events, "PLAYER_AURAS_CHANGED")
  pcall(events.RegisterEvent, events, "PLAYER_ENTER_COMBAT")
  pcall(events.RegisterEvent, events, "PLAYER_LEAVE_COMBAT")
  pcall(events.RegisterEvent, events, "ACTIONBAR_SLOT_CHANGED")
  pcall(events.RegisterEvent, events, "PET_BAR_UPDATE")
  pcall(events.RegisterEvent, events, "UNIT_PET")

  local function RefreshAfterClientUpdate()
    this.refreshElapsed = (this.refreshElapsed or 0) + (arg1 or 0)
    this.refreshRemaining = (this.refreshRemaining or 0) - (arg1 or 0)
    if this.refreshElapsed >= .05 or this.refreshRemaining <= 0 then
      this.refreshElapsed = 0
      RefreshActionButtons()
      PositionAuxiliaryBars()
    end
    if this.refreshRemaining <= 0 then this:SetScript("OnUpdate", nil) end
  end
  events:SetScript("OnEvent", function()
    -- Refresh throughout the short native bonus-bar transition. Emberveil can
    -- publish the aura/form, bonus offset and cached action ID on different
    -- frames when stealth ends through an attack.
    RefreshActionButtons()
    PositionAuxiliaryBars()
    this.refreshElapsed = 0
    this.refreshRemaining = .75
    this:SetScript("OnUpdate", RefreshAfterClientUpdate)
  end)
  actionPageEvents = events
end

-- ============================================================
-- 按钮样式与摆放
-- ============================================================

StyleActionButton = function(button)
  if not button or button.ActionBarsStyled then return end
  button.ActionBarsStyled = true
  button:SetWidth(34)
  button:SetHeight(34)

  local normal = button:GetNormalTexture()
  if normal then normal:SetAlpha(0) end

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
  border:SetBackdropColor(.02, .025, .03, .96)
  border:SetBackdropBorderColor(.14, .18, .2, 1)
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
-- 经验条
-- ============================================================

local function UpdateXPBar()
  local bar = xpBar
  if not bar then return end

  local current = UnitXP("player") or 0
  local maximum = UnitXPMax("player") or 0
  local level = UnitLevel("player") or 0
  local rested = 0
  if type(GetXPExhaustion) == "function" then rested = GetXPExhaustion() or 0 end
  local resting
  if type(IsResting) == "function" then
    local ok, value = pcall(IsResting)
    resting = ok and (value == true or value == 1 or value == "1")
  end

  if resting then
    bar:SetStatusBarColor(.18, .48, .92)
    bar:SetBackdropBorderColor(.35, .62, 1, 1)
  else
    bar:SetStatusBarColor(.38, .28, .78)
    bar:SetBackdropBorderColor(.18, .22, .28, 1)
  end

  if maximum > 0 then
    local percent = math.floor(current / maximum * 100)
    bar:SetMinMaxValues(0, maximum)
    bar:SetValue(current)
    if resting and rested > 0 then
      bar.text:SetText("Level " .. level .. "  -  " .. percent .. "%  |cff66aaffResting  -  Rested " .. rested .. "|r")
    elseif resting then
      bar.text:SetText("Level " .. level .. "  -  " .. percent .. "%  |cff66aaffResting|r")
    elseif rested > 0 then
      bar.text:SetText("Level " .. level .. "  -  " .. percent .. "%  |cff66aaffRested " .. rested .. "|r")
    else
      bar.text:SetText("Level " .. level .. "  -  " .. percent .. "%")
    end
  else
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    if resting then
      bar.text:SetText("Level " .. level .. "  -  Maximum Level  |cff66aaffResting|r")
    else
      bar.text:SetText("Level " .. level .. "  -  Maximum Level")
    end
  end

  bar.current = current
  bar.maximum = maximum
  bar.rested = rested
  bar.resting = resting
end

local function SetupXPBar()
  if xpBar then return end

  local parent = actionPanel or UIParent
  local bar = CreateFrame("StatusBar", "ActionBarsXPBar", parent)
  bar:SetWidth(442)
  bar:SetHeight(12)
  if actionPanel then
    bar:SetPoint("TOP", actionPanel, "BOTTOM", 0, -4)
  else
    bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 18)
  end
  bar:SetStatusBarTexture(statusbarTexture)
  bar:SetStatusBarColor(.38, .28, .78)
  bar:SetFrameLevel((parent:GetFrameLevel() or 1) + 3)
  bar:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 8,
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  bar:SetBackdropColor(.025, .03, .04, .8)
  bar:SetBackdropBorderColor(.18, .22, .28, 1)

  bar.background = bar:CreateTexture(nil, "BACKGROUND")
  bar.background:SetAllPoints()
  bar.background:SetTexture(statusbarTexture)
  bar.background:SetVertexColor(.035, .04, .055, .9)

  bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)

  bar:EnableMouse(true)
  bar:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("Experience")
    if this.maximum and this.maximum > 0 then
      GameTooltip:AddLine(this.current .. " / " .. this.maximum, 1, 1, 1)
      if this.rested and this.rested > 0 then
        GameTooltip:AddLine("Rested: " .. this.rested, .4, .65, 1)
      end
    else
      GameTooltip:AddLine("Maximum level", 1, .82, .2)
    end
    if this.resting then GameTooltip:AddLine("Currently resting", .4, .65, 1) end
    GameTooltip:Show()
  end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)

  local events = CreateFrame("Frame", "ActionBarsXPEvents")
  events:RegisterEvent("PLAYER_XP_UPDATE")
  events:RegisterEvent("UPDATE_EXHAUSTION")
  events:RegisterEvent("PLAYER_LEVEL_UP")
  events:RegisterEvent("PLAYER_ENTERING_WORLD")
  pcall(events.RegisterEvent, events, "PLAYER_UPDATE_RESTING")
  events:SetScript("OnEvent", UpdateXPBar)

  xpBar = bar
  UpdateXPBar()
end

-- ============================================================
-- 入口：接管原生动作条
-- ============================================================

local function SetupActionBars()
  InstallActionResolvers()

  for _, name in ipairs(hiddenNames) do
    HideFrame(getglobal(name))
  end

  local panel = CreatePanel("ActionBarsActionPanel", UIParent, 1)
  panel:SetWidth(442)
  panel:SetHeight(82)
  panel:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 18)
  panel:SetBackdropColor(0, 0, 0, 0)
  panel:SetBackdropBorderColor(0, 0, 0, 0)
  actionPanel = panel

  -- Emberveil leaves the second multi-action row partially off-screen when
  -- its original bar geometry is active. Give slots 49-60 a compact panel
  -- of their own at bottom-right instead.
  local utilityPanel = CreatePanel("ActionBarsUtilityActionPanel", UIParent, 1)
  utilityPanel:SetWidth(442)
  utilityPanel:SetHeight(44)
  utilityPanel:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -14, 14)
  utilityPanel:SetBackdropColor(0, 0, 0, 0)
  utilityPanel:SetBackdropBorderColor(0, 0, 0, 0)
  utilityActionPanel = utilityPanel

  local i
  for i = 1, 12 do
    local primaryButton = getglobal("ActionButton" .. i)
    if primaryButton then primaryButton.ActionBarsPrimaryAction = true end
    PlaceButton(primaryButton, panel, i, 0)

    local upperButton = getglobal("MultiBarBottomLeftButton" .. i)
    if upperButton then
      upperButton.ActionBarsAction = 60 + i
      upperButton.action = 60 + i
    end
    PlaceButton(upperButton, panel, i, 1)

    local utilityButton = getglobal("MultiBarBottomRightButton" .. i)
    if utilityButton then
      utilityButton.ActionBarsAction = 48 + i
      utilityButton.action = 48 + i
    end
    PlaceButton(utilityButton, utilityPanel, i, 0)
  end

  SetupActionPageEvents()
  RefreshActionButtons()

  -- The buttons now belong directly to this panel. Hide their old containers
  -- so Emberveil cannot draw a second native copy at the bottom of the screen.
  HideFrame(MainMenuBarArtFrame)
  HideFrame(MainMenuBar)
  if MultiBarBottomLeft then
    HideFrame(MultiBarBottomLeft)
  end
  if MultiBarBottomRight then
    HideFrame(MultiBarBottomRight)
  end

  -- Keep only the useful stance/form and pet buttons at bottom-left; the
  -- original controller frames remain invisible so their update code works.
  PositionAuxiliaryBars()
end

-- ============================================================
-- 入口：等玩家登录完成再接管动作条
-- ============================================================

local bootstrap = CreateFrame("Frame", nil, UIParent)
if bootstrap then
  bootstrap:RegisterEvent("PLAYER_ENTERING_WORLD")
  bootstrap:SetScript("OnEvent", function()
    pcall(function() bootstrap:UnregisterEvent("PLAYER_ENTERING_WORLD") end)
    pcall(SetupActionBars)
    pcall(SetupXPBar)
  end)
  DEFAULT_CHAT_FRAME:AddMessage("|cffff00ffActionBars: Loaded successfully|r")
else
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000ActionBars: Failed to create bootstrap frame|r")
end
