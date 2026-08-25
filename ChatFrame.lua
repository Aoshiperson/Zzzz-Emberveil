-- =====================================================================
-- Backdrop helpers
-- =====================================================================

local CHAT_FONT_SIZE = 13

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
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
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
    print("|cffff0000ChatFrame: ChatFrame1 not available|r")
    return
  end
  ChatFrame1:ClearAllPoints()
  ChatFrame1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 18, 40)
  ChatFrame1:SetWidth(400)
  ChatFrame1:SetHeight(180)
end

local function PositionChatEditBox()
  if not (ChatFrameEditBox and ChatFrame1) then return end

  ChatFrameEditBox:SetParent(ChatFrame1)
  ChatFrameEditBox:SetFrameStrata("DIALOG")
  ChatFrameEditBox:ClearAllPoints()
  ChatFrameEditBox:SetPoint("BOTTOMLEFT", ChatFrame1, "TOPLEFT", 0, 4)
  ChatFrameEditBox:SetPoint("BOTTOMRIGHT", ChatFrame1, "TOPRIGHT", 0, 4)
  ChatFrameEditBox:SetHeight(22)
end

local function ApplyChatFontSize()
  if not ChatFrame1 then
    print("|cffff0000ChatFrame: ChatFrame1 not available|r")
    return
  end
  local fontPath, _, fontFlags = ChatFrame1:GetFont()
  ChatFrame1:SetFont(fontPath or STANDARD_TEXT_FONT, CHAT_FONT_SIZE, fontFlags)
end

local function StyleDefaultChatFrame()
  if not ChatFrame1 then 
    print("|cffff0000ChatFrame: ChatFrame1 not initialized yet|r")
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
  events:RegisterEvent("PLAYER_LOGIN")
  
  -- 使用闭包而不是依赖 self 参数
  -- 这解决了某些环境中 self 为 nil 的问题
  events:SetScript("OnEvent", function()
    pcall(function()
      events:UnregisterEvent("PLAYER_LOGIN")
    end)
    pcall(StyleDefaultChatFrame)
  end)
  
  print("|cffff00ffChatFrame: Loaded successfully|r")
else
  print("|cffff0000ChatFrame: Failed to create events frame|r")
end
