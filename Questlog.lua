--[[
  Questlog_2.lua —— 修复错位与自适应优化版
--]]

local WIDTH_EXPANDED = 676

local function SetupDualWidth()
  local frame = getglobal("QuestLogFrame")
  local detail = getglobal("QuestLogDetailScrollFrame")

  if not frame or not detail then return end

  -- 强制设定主窗口和背景宽度，防止错位
  pcall(frame.SetWidth, frame, WIDTH_EXPANDED)
  pcall(detail.Show, detail)
  detail.uuiUserHidden = nil

  -- 尝试调整背景材质（如果存在）
  if QuestLogDetailFrameBackdrop then
    pcall(QuestLogDetailFrameBackdrop.SetWidth, QuestLogDetailFrameBackdrop, WIDTH_EXPANDED)
  end

  local originalOnShow = detail:GetScript("OnShow")
  detail:SetScript("OnShow", function()
    if originalOnShow then originalOnShow() end
    pcall(frame.SetWidth, frame, WIDTH_EXPANDED)
  end)

  local originalOnHide = detail:GetScript("OnHide")
  detail:SetScript("OnHide", function()
    if originalOnHide then originalOnHide() end
    pcall(detail.Show, detail)
    pcall(frame.SetWidth, frame, WIDTH_EXPANDED)
  end)

  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff00ffQuestLogDualWidth: 双栏已自适应调整|r")
  end
end

local function HideQuestWatch()
  local watch = getglobal("QuestWatchFrame")
  if watch then
    watch:Hide()
    watch:SetAlpha(0)
    pcall(watch.EnableMouse, watch, false)
    if type(watch.HookScript) == "function" then
      pcall(watch.HookScript, watch, "OnShow", function() watch:Hide() end)
    end
  end
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_ENTERING_WORLD")
bootstrap:SetScript("OnEvent", function()
  pcall(function() bootstrap:UnregisterEvent("PLAYER_ENTERING_WORLD") end)
  pcall(SetupDualWidth)
  -- 如果你希望保留小地图下方的任务追踪框，请把下面这行前面的 "--" 去掉（取消注释）
  -- HideQuestWatch()
end)
