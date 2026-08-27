--[[
  QuestLogDualWidth.lua —— 独立版
  功能1：任务日志双宽（打开即展开，不需要额外点击）
  功能2：隐藏原生任务追踪框（QuestWatchFrame，小地图下方那个任务列表）

  来源：从 UnrealUI (modules/questlog.lua) 抽取重构
  不含：字体重新上色、原生装饰条纹清除、任务追踪记忆、可拖拽移动

  核心原理（双宽为什么单纯 SetWidth 不够）：
    QuestLogFrame 内部有个独立的详情面板对象
    （QuestLogDetailScrollFrame），默认隐藏。真正的双宽 = 同步做两件事：
      1. 窗口宽度从 340（单栏）改成 676（双栏）
      2. 显示详情面板，填满新增出来的空间
--]]

local WIDTH_COLLAPSED = 340
local WIDTH_EXPANDED  = 676

local frame, detail

-- ============================================================
-- 功能1：双宽
-- ============================================================

local function SetupDualWidth()
  frame = getglobal("QuestLogFrame")
  detail = getglobal("QuestLogDetailScrollFrame")

  if not frame then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000QuestLogDualWidth: QuestLogFrame 不存在|r")
    return
  end
  if not detail then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000QuestLogDualWidth: QuestLogDetailScrollFrame 不存在，双宽功能无法使用|r")
    return
  end

  pcall(frame.SetWidth, frame, WIDTH_EXPANDED)
  pcall(detail.Show, detail)
  detail.uuiUserHidden = nil

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

  DEFAULT_CHAT_FRAME:AddMessage("|cffff00ffQuestLogDualWidth: 双宽已启用|r")
end

-- ============================================================
-- 功能2：隐藏原生任务追踪框
-- ============================================================

local function HideQuestWatch()
  local watch = getglobal("QuestWatchFrame")
  if not watch then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000QuestLogDualWidth: QuestWatchFrame 不存在|r")
    return
  end

  watch:Hide()
  watch:SetAlpha(0)
  pcall(watch.EnableMouse, watch, false)

  -- 防止原生逻辑在任务更新时把它重新弹出来
  if type(watch.HookScript) == "function" then
    pcall(watch.HookScript, watch, "OnShow", function() watch:Hide() end)
  end

  DEFAULT_CHAT_FRAME:AddMessage("|cffff00ffQuestLogDualWidth: 任务追踪框已隐藏|r")
end

-- ============================================================
-- 入口
-- ============================================================

local function Setup()
  SetupDualWidth()
  HideQuestWatch()
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_ENTERING_WORLD")
bootstrap:SetScript("OnEvent", function()
  pcall(function() bootstrap:UnregisterEvent("PLAYER_ENTERING_WORLD") end)
  pcall(Setup)
end)