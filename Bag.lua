--[[
  BagButtons.lua —— 独立文件
  背包按钮自定义位置/大小，仅在打开背包时显示
--]]

local BAG_CONFIG = {
  size    = 30,
  spacing = 4,
  point   = "BOTTOMRIGHT",
  x       = -10,
  y       = 60,
}

local BAG_BUTTON_NAMES = {
  "MainMenuBarBackpackButton",
  "CharacterBag0Slot",
  "CharacterBag1Slot",
  "CharacterBag2Slot",
  "CharacterBag3Slot",
  "KeyRingButton",
}

local bagButtonsPositioned = false

local function LayoutBagButtons()
  if bagButtonsPositioned then return end
  bagButtonsPositioned = true

  local column = 0
  local i
  for i = 1, table.getn(BAG_BUTTON_NAMES) do
    local button = getglobal(BAG_BUTTON_NAMES[i])
    if button then
      pcall(button.SetWidth, button, BAG_CONFIG.size)
      pcall(button.SetHeight, button, BAG_CONFIG.size)
      button:ClearAllPoints()
      button:SetPoint(BAG_CONFIG.point, UIParent, BAG_CONFIG.point,
                      BAG_CONFIG.x - column * (BAG_CONFIG.size + BAG_CONFIG.spacing), BAG_CONFIG.y)
      column = column + 1
    end
  end
end

local function IsAnyContainerFrameShown()
  local frameCount = tonumber(getglobal("NUM_CONTAINER_FRAMES")) or 13
  local i
  for i = 1, frameCount do
    local frame = getglobal("ContainerFrame" .. i)
    if frame and frame:IsShown() then
      return true
    end
  end
  return false
end

local function UpdateBagButtonVisibility()
  local shown = IsAnyContainerFrameShown()
  local i
  for i = 1, table.getn(BAG_BUTTON_NAMES) do
    local button = getglobal(BAG_BUTTON_NAMES[i])
    if button then
      if shown then button:Show() else button:Hide() end
    end
  end
end

local function SetupBagButtonEvents()
  LayoutBagButtons()

  local events = CreateFrame("Frame")
  pcall(events.RegisterEvent, events, "BAG_OPEN")
  pcall(events.RegisterEvent, events, "BAG_CLOSED")
  pcall(events.RegisterEvent, events, "PLAYER_ENTERING_WORLD")
  events:SetScript("OnEvent", UpdateBagButtonVisibility)

  UpdateBagButtonVisibility()
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_ENTERING_WORLD")
bootstrap:SetScript("OnEvent", function()
  pcall(function() bootstrap:UnregisterEvent("PLAYER_ENTERING_WORLD") end)
  pcall(SetupBagButtonEvents)
end)