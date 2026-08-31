-- =====================================================================
-- Backdrop helpers
-- =====================================================================

local CHAT_FONT_SIZE = 8

-- Seamless backdrop for large surfaces (chat panels).
-- UI-Tooltip-Background has a baked-in edge highlight, so tiling it across a
-- large frame shows visible white seam lines. ChatFrameBackground is a plain
-- seamless 16px tile (same as Blizzard chat frames / XH_OneBag).
local function set_chat_backdrop(frame, r, g, b, a)
  r, g, b, a = r or 0, g or 0, b or 0, a or .82
  frame:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 0,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  frame:SetBackdropColor(r, g, b, a)
  frame:SetBackdropBorderColor(.25, .25, .25, 1)
end

-- =====================================================================
-- Default chat frame styling
-- =====================================================================

local function HideChatTextures(i)
  for _, s in ipairs({ "UpButton", "DownButton", "BottomButton", "ResizeBottom" }) do
    local btn = _G["ChatFrame" .. i .. s]
    if btn then btn:Hide() end
  end

  local bg = _G["ChatFrame" .. i .. "Background"]
  if bg then
    bg:SetTexture(nil)
    bg:Hide()
  end

  for _, s in ipairs({ "TabLeft", "TabMiddle", "TabRight" }) do
    local t = _G["ChatFrame" .. i .. s]
    if t then t:SetAlpha(0) end
  end

  local tt = _G["ChatFrame" .. i .. "TabText"]
  if tt then tt:SetJustifyV("MIDDLE") end
end

local function PositionChatFrame()
  if not ChatFrame1 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000ChatFrame: ChatFrame1 not available|r")
    return
  end
  ChatFrame1:ClearAllPoints()
  ChatFrame1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 18, 30)
  ChatFrame1:SetWidth(320)
  ChatFrame1:SetHeight(160)
end

local function PositionChatEditBox()
  if not (ChatFrameEditBox and ChatFrame1) then return end

  ChatFrameEditBox:SetParent(ChatFrame1)
  ChatFrameEditBox:SetFrameStrata("DIALOG")
  ChatFrameEditBox:ClearAllPoints()
  ChatFrameEditBox:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 4)
  ChatFrameEditBox:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 0, 4)
  ChatFrameEditBox:SetHeight(20)
  ChatFrameEditBox:SetFont("Fonts\\FRIZQT__.TTF", CHAT_FONT_SIZE)
end

local function ApplyChatFontSize()
  if not ChatFrame1 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000ChatFrame: ChatFrame1 not available|r")
    return
  end
  ChatFrame1:SetFont("Fonts\\FRIZQT__.TTF", CHAT_FONT_SIZE)
  SetChatWindowSize(1, CHAT_FONT_SIZE)
end
local function StyleDefaultChatFrame()
  if not ChatFrame1 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000ChatFrame: ChatFrame1 not initialized yet|r")
    return
  end
  PositionChatFrame()
  set_chat_backdrop(ChatFrame1)
  HideChatTextures(1)
  PositionChatEditBox()
  ApplyChatFontSize()
end

-- =====================================================================
-- Init
-- =====================================================================

local events = CreateFrame("Frame")
if events then
  events:RegisterEvent("PLAYER_ENTERING_WORLD")

  events:SetScript("OnEvent", function()
    pcall(function()
      events:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end)
    pcall(StyleDefaultChatFrame)
  end)

  DEFAULT_CHAT_FRAME:AddMessage("|cffff00ffChatFrame: Loaded successfully|r")
else
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000ChatFrame: Failed to create events frame|r")
end
