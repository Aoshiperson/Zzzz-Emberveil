--[[
  AutoQuest.lua —— 独立版
  接受任务 / 交付任务 可以分别开关
--]]

local AutoQuest = {
  apiOk = true,
  acceptEnabled = true,
  turnInEnabled = true,
}

-- ============================================================
-- 能力检测
-- ============================================================

local REQUIRED_API = {
  "CreateFrame", "GetGossipAvailableQuests", "SelectGossipAvailableQuest",
  "GetNumAvailableQuests", "SelectAvailableQuest", "AcceptQuest",
  "IsQuestCompletable", "CompleteQuest", "GetNumQuestChoices",
  "GetQuestReward", "IsShiftKeyDown",
}

local missingApi = {}
local i
for i = 1, table.getn(REQUIRED_API) do
  if type(getglobal(REQUIRED_API[i])) ~= "function" then
    table.insert(missingApi, REQUIRED_API[i])
  end
end

if table.getn(missingApi) > 0 then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000AutoQuest: 缺失API，自动化不可用: " ..
    table.concat(missingApi, ", ") .. "|r")
  AutoQuest.apiOk = false
  AutoQuest.acceptEnabled = false
  AutoQuest.turnInEnabled = false
end

-- ============================================================
-- 任务文字瞬间显示
-- ============================================================

local FAST_CPS = 1000000
local previousFade, ownsFade = nil, false
local previousCPS, ownsCPS = nil, false

local function EnableInstantText()
  if type(QUEST_FADING_DISABLE) == "string" then
    if not ownsFade then
      previousFade = QUEST_FADING_DISABLE
      ownsFade = true
    end
    QUEST_FADING_DISABLE = "1"
    return true
  end
  if type(QUEST_DESCRIPTION_GRADIENT_CPS) == "number" then
    if not ownsCPS then
      previousCPS = QUEST_DESCRIPTION_GRADIENT_CPS
      ownsCPS = true
    end
    QUEST_DESCRIPTION_GRADIENT_CPS = FAST_CPS
    return true
  end
  return false
end

-- ============================================================
-- 事件解析（多形态兼容）
-- ============================================================

local function ResolveEvent(a, b)
  if type(a) == "string" then return a end
  if type(b) == "string" then return b end
  if type(event) == "string" then return event end
  return nil
end

local function ShiftBypass()
  local ok, down = pcall(IsShiftKeyDown)
  return ok and down and true or false
end

-- ============================================================
-- 状态机：交付任务这条链单独维护，跟接受任务不共用
-- ============================================================

local phase = "idle"
local manual = false
local progressHandled = false
local rewardHandled = false
local rewardGuardShown = false

local function ResetTurnInState(newPhase)
  phase = newPhase or "idle"
  manual = false
  progressHandled = false
  rewardHandled = false
  rewardGuardShown = false
end

-- ============================================================
-- 接受任务：GOSSIP_SHOW / QUEST_GREETING / QUEST_DETAIL
-- ============================================================

local function HandleGossipShow()
  if not AutoQuest.acceptEnabled then return end
  if ShiftBypass() then return end
  local list = { GetGossipAvailableQuests() }
  local count = math.floor(table.getn(list) / 2)
  if count == 1 then
    SelectGossipAvailableQuest(1)
  end
end

local function HandleQuestGreeting()
  if not AutoQuest.acceptEnabled then return end
  if ShiftBypass() then return end
  local count = tonumber(GetNumAvailableQuests()) or 0
  if count == 1 then
    SelectAvailableQuest(1)
  end
end

local function HandleQuestDetail()
  -- 交付链的状态无论如何都要重置，避免残留上一次交互的状态
  ResetTurnInState("idle")

  if not AutoQuest.acceptEnabled then return end
  if ShiftBypass() then return end
  AcceptQuest()
end

-- ============================================================
-- 交付任务：QUEST_PROGRESS / QUEST_COMPLETE
-- ============================================================

local function HandleQuestProgress()
  if phase ~= "progress" then
    ResetTurnInState("progress")
    manual = ShiftBypass()
  elseif ShiftBypass() then
    manual = true
  end

  if not AutoQuest.turnInEnabled then return end
  if manual or progressHandled then return end
  if IsQuestCompletable() then
    progressHandled = true
    CompleteQuest()
  end
end

local function HandleQuestComplete()
  if phase == "progress" then
    phase = "complete"
  elseif phase ~= "complete" then
    ResetTurnInState("complete")
    manual = ShiftBypass()
  end
  if ShiftBypass() then manual = true end

  if not AutoQuest.turnInEnabled then return end
  if manual or rewardHandled then return end

  local choices = tonumber(GetNumQuestChoices()) or 0
  if choices > 1 then
    if not rewardGuardShown then
      DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00AutoQuest: 多个奖励可选，需要手动选择|r")
      rewardGuardShown = true
    end
    return
  end

  rewardHandled = true
  if choices == 1 then
    GetQuestReward(1)
  else
    GetQuestReward()
  end
end

-- ============================================================
-- 事件分发
-- ============================================================

local QUEST_EVENTS = {
  "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
}

local function OnEvent(a, b)
  if not AutoQuest.apiOk then return end
  local eventName = ResolveEvent(a, b)
  if not eventName then return end

  if eventName == "GOSSIP_SHOW" then HandleGossipShow()
  elseif eventName == "QUEST_GREETING" then HandleQuestGreeting()
  elseif eventName == "QUEST_DETAIL" then HandleQuestDetail()
  elseif eventName == "QUEST_PROGRESS" then HandleQuestProgress()
  elseif eventName == "QUEST_COMPLETE" then HandleQuestComplete()
  end
end

-- ============================================================
-- 斜杠命令：分开控制接受 / 交付
-- ============================================================

local function PrintStatus()
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AutoQuest:|r 接受任务 " ..
    (AutoQuest.acceptEnabled and "开启" or "关闭") .. "  |  交付任务 " ..
    (AutoQuest.turnInEnabled and "开启" or "关闭") .. "（按住Shift可临时手动接管单次交互）")
end

SLASH_AUTOQUEST1 = "/autoquest"
SlashCmdList["AUTOQUEST"] = function(msg)
  local args = {}
  for word in string.gfind(msg or "", "%S+") do
    table.insert(args, string.lower(word))
  end
  local cmd, value = args[1], args[2]

  if cmd == "accept" then
    if value == "on" then
      AutoQuest.acceptEnabled = true
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AutoQuest:|r 接受任务 已开启")
    elseif value == "off" then
      AutoQuest.acceptEnabled = false
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AutoQuest:|r 接受任务 已关闭")
    else
      PrintStatus()
    end
  elseif cmd == "turnin" then
    if value == "on" then
      AutoQuest.turnInEnabled = true
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AutoQuest:|r 交付任务 已开启")
    elseif value == "off" then
      AutoQuest.turnInEnabled = false
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AutoQuest:|r 交付任务 已关闭")
    else
      PrintStatus()
    end
  elseif cmd == "on" then
    AutoQuest.acceptEnabled = true
    AutoQuest.turnInEnabled = true
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AutoQuest:|r 接受+交付 已全部开启")
  elseif cmd == "off" then
    AutoQuest.acceptEnabled = false
    AutoQuest.turnInEnabled = false
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AutoQuest:|r 接受+交付 已全部关闭")
  else
    PrintStatus()
    DEFAULT_CHAT_FRAME:AddMessage("用法: /autoquest accept on|off | /autoquest turnin on|off | /autoquest on|off")
  end
end

-- ============================================================
-- 入口
-- ============================================================

local function Setup()
  if not AutoQuest.apiOk then return end

  if not EnableInstantText() then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00AutoQuest: 无法关闭任务文字渐显动画，继续运行但体验可能变慢|r")
  end

  local frame = CreateFrame("Frame", "AutoQuestFrame", UIParent)
  local index
  for index = 1, table.getn(QUEST_EVENTS) do
    pcall(frame.RegisterEvent, frame, QUEST_EVENTS[index])
  end
  frame:SetScript("OnEvent", OnEvent)

  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AutoQuest: Loaded|r")
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("PLAYER_ENTERING_WORLD")
bootstrap:SetScript("OnEvent", function()
  pcall(function() bootstrap:UnregisterEvent("PLAYER_ENTERING_WORLD") end)
  pcall(Setup)
end)