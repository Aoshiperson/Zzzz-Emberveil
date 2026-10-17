--[[
  AutoVendor.lua —— 独立版，无需命令，始终开启
  功能：自动出售灰色装备 + 自动修理
--]]

-- ============================================================
-- 输出（整行统一颜色，避免默认黑字看不见）
-- ============================================================

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("AutoVendor: " .. msg, 0.2, 1, 0.6)
end

-- ============================================================
-- 工具函数
-- ============================================================

local BAG_IDS = { 0, 1, 2, 3, 4 }
local SELL_INTERVAL = 0.15
local MONEY_SETTLE_SECONDS = 1.25

local function FormatMoney(amount)
  amount = tonumber(amount) or 0
  if amount < 0 then amount = 0 end
  local gold = math.floor(amount / 10000)
  local silver = math.floor((amount % 10000) / 100)
  local copper = amount % 100
  return gold .. "金 " .. silver .. "银 " .. copper .. "铜"
end

local function IsGreyItem(bag, slot)
  local link = GetContainerItemLink(bag, slot)
  if type(link) ~= "string" or link == "" then
    return false
  end
  local texture, count, locked, quality = GetContainerItemInfo(bag, slot)
  if locked then return false end
  return tonumber(quality) == 0
end

-- ============================================================
-- 出售状态
-- ============================================================

local sellFrame = CreateFrame("Frame", "AutoVendorSellFrame", UIParent)
sellFrame:Hide()

local merchantOpen = false
local selling = false
local settling = false
local processed = {}
local startMoney = 0
local bestEarned = 0
local soldCount = 0
local nextTick = 0
local settleDeadline = 0

local function UpdateEarned()
  local earned = (tonumber(GetMoney()) or startMoney) - startMoney
  if earned < 0 then earned = 0 end
  if earned > bestEarned then bestEarned = earned end
  return bestEarned
end

local function NextGreyItem()
  for bagIndex = 1, #BAG_IDS do
    local bag = BAG_IDS[bagIndex]
    local slots = tonumber(GetContainerNumSlots(bag)) or 0
    for slot = 1, slots do
      local key = bag .. ":" .. slot
      if not processed[key] and IsGreyItem(bag, slot) then
        processed[key] = true
        return bag, slot
      end
    end
  end
  return nil, nil
end

local function ResetSelling()
  sellFrame:Hide()
  selling = false
  settling = false
  processed = {}
  soldCount = 0
  startMoney = 0
  bestEarned = 0
  nextTick = 0
  settleDeadline = 0
end

local TryRepair

local function FinishSelling(announce, continueToRepair)
  if announce and soldCount > 0 then
    UpdateEarned()
    Print("卖出 " .. soldCount .. " 件，获得 " .. FormatMoney(bestEarned))
  end
  ResetSelling()
  if continueToRepair and merchantOpen and TryRepair then
    TryRepair()
  end
end

local function BeginMoneySettle()
  if soldCount <= 0 then
    FinishSelling(false, true)
    return
  end
  selling = false
  settling = true
  settleDeadline = GetTime() + MONEY_SETTLE_SECONDS
  UpdateEarned()
end

local function ProcessSelling()
  local now = GetTime()
  UpdateEarned()

  if settling then
    if now >= settleDeadline then
      FinishSelling(true, true)
    end
    return
  end

  if not selling then
    FinishSelling(false, true)
    return
  end

  if not merchantOpen then
    BeginMoneySettle()
    return
  end

  if now < nextTick then return end
  nextTick = now + SELL_INTERVAL

  local bag, slot = NextGreyItem()
  if bag == nil or slot == nil then
    BeginMoneySettle()
    return
  end

  ClearCursor()
  UseContainerItem(bag, slot)
  soldCount = soldCount + 1
end

local function StartSelling()
  if not merchantOpen then return end
  startMoney = tonumber(GetMoney()) or 0
  bestEarned = 0
  processed = {}
  soldCount = 0
  nextTick = 0
  settleDeadline = 0
  selling = true
  settling = false
  sellFrame:SetScript("OnUpdate", ProcessSelling)
  sellFrame:Show()
end

-- ============================================================
-- 修理
-- ============================================================

local repairAttempted = false

TryRepair = function()
  if repairAttempted or not merchantOpen then return end
  repairAttempted = true

  if not CanMerchantRepair() then return end

  local cost, canRepair = GetRepairAllCost()
  cost = tonumber(cost) or 0
  if cost <= 0 or not canRepair then return end

  if (tonumber(GetMoney()) or 0) < cost then return end

  RepairAllItems()
  Print("已修理，花费 " .. FormatMoney(cost))
end

-- ============================================================
-- 事件
-- ============================================================

local function ResolveEvent(a, b)
  if type(a) == "string" then return a end
  if type(b) == "string" then return b end
  if type(event) == "string" then return event end
  return nil
end

local function HandleEvent(eventName)
  if eventName == "MERCHANT_SHOW" then
    merchantOpen = true
    repairAttempted = false
    StartSelling()
  elseif eventName == "MERCHANT_CLOSED" then
    merchantOpen = false
    repairAttempted = false
    if selling then BeginMoneySettle() end
  end
end

-- ============================================================
-- 入口
-- ============================================================

local events = CreateFrame("Frame", "AutoVendorEventFrame", UIParent)
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:SetScript("OnEvent", function(a, b)
  HandleEvent(ResolveEvent(a, b))
end)

Print("Loaded")
