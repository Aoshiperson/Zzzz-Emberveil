--[[
  AutoVendor.lua —— 独立版，无需命令，始终开启
  参考 EmberveilQoL/modules/vendor.lua 重构
  功能：自动出售灰色装备 + 自动修理
--]]

local AutoVendor = {
  sellEnabled = true,
  repairEnabled = true,
}

-- ============================================================
-- 能力检测
-- ============================================================

local SELL_REQUIRED = {
  "GetContainerNumSlots", "GetContainerItemLink", "GetContainerItemInfo",
  "UseContainerItem", "ClearCursor", "GetMoney", "GetTime",
}

local REPAIR_REQUIRED = {
  "CanMerchantRepair", "GetRepairAllCost", "RepairAllItems", "GetMoney",
}

local function MissingNames(list)
  local missing = {}
  local i
  for i = 1, table.getn(list) do
    if type(getglobal(list[i])) ~= "function" then
      table.insert(missing, list[i])
    end
  end
  return missing
end

local missingSell = MissingNames(SELL_REQUIRED)
if table.getn(missingSell) > 0 then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000AutoVendor: 自动出售缺失API: " ..
    table.concat(missingSell, ", ") .. "|r")
  AutoVendor.sellEnabled = false
end

local missingRepair = MissingNames(REPAIR_REQUIRED)
if table.getn(missingRepair) > 0 then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000AutoVendor: 自动修理缺失API: " ..
    table.concat(missingRepair, ", ") .. "|r")
  AutoVendor.repairEnabled = false
end

-- ============================================================
-- 工具函数
-- ============================================================

local BAG_IDS = { 0, 1, 2, 3, 4 }
local SELL_INTERVAL = 0.15
local MONEY_SETTLE_SECONDS = 1.25

local function Now()
  local ok, value = pcall(GetTime)
  return (ok and tonumber(value)) or 0
end

local function FormatMoney(amount)
  amount = tonumber(amount) or 0
  if amount < 0 then amount = 0 end
  local gold = math.floor(amount / 10000)
  local silver = math.floor(math.mod(amount, 10000) / 100)
  local copper = math.mod(amount, 100)
  return gold .. "金 " .. silver .. "银 " .. copper .. "铜"
end

local function IsGreyItem(bag, slot)
  local linkOk, link = pcall(GetContainerItemLink, bag, slot)
  if not linkOk or type(link) ~= "string" or link == "" then
    return false
  end
  local infoOk, texture, count, locked, quality = pcall(GetContainerItemInfo, bag, slot)
  if not infoOk or locked then return false end
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
local startGold = 0
local bestEarned = 0
local soldCount = 0
local nextTick = 0
local settleDeadline = 0

local function UpdateEarned()
  local ok, currentGold = pcall(GetMoney)
  currentGold = (ok and tonumber(currentGold)) or startGold
  local earned = currentGold - startGold
  if earned < 0 then earned = 0 end
  if earned > bestEarned then bestEarned = earned end
  return bestEarned
end

local function NextGreyItem()
  local bagIndex
  for bagIndex = 1, table.getn(BAG_IDS) do
    local bag = BAG_IDS[bagIndex]
    local ok, slots = pcall(GetContainerNumSlots, bag)
    slots = (ok and tonumber(slots)) or 0
    local slot
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
  startGold = 0
  bestEarned = 0
  nextTick = 0
  settleDeadline = 0
end

local TryRepair

local function FinishSelling(announce, continueToRepair)
  if announce and soldCount > 0 then
    UpdateEarned()
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AutoVendor:|r 卖出 " .. soldCount ..
      " 件，获得 " .. FormatMoney(bestEarned))
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
  settleDeadline = Now() + MONEY_SETTLE_SECONDS
  UpdateEarned()
end

local function ProcessSelling()
  if not AutoVendor.sellEnabled then
    FinishSelling(false, true)
    return
  end

  local now = Now()
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

  if not IsGreyItem(bag, slot) then return end

  pcall(ClearCursor)
  local soldOk = pcall(UseContainerItem, bag, slot)
  if soldOk then soldCount = soldCount + 1 end
end

local function StartSelling()
  if not AutoVendor.sellEnabled or not merchantOpen then return end
  local ok, money = pcall(GetMoney)
  startGold = (ok and tonumber(money)) or 0
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
  if not AutoVendor.repairEnabled or repairAttempted or not merchantOpen then
    return
  end
  repairAttempted = true

  local canMerchantOk, canMerchant = pcall(CanMerchantRepair)
  if not canMerchantOk or not canMerchant then return end

  local costOk, cost, canRepair = pcall(GetRepairAllCost)
  cost = (costOk and tonumber(cost)) or 0
  if not costOk or cost <= 0 or not canRepair then return end

  local moneyOk, money = pcall(GetMoney)
  money = (moneyOk and tonumber(money)) or 0
  if not moneyOk or money < cost then return end

  local callOk = pcall(RepairAllItems)
  if not callOk then return end

  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AutoVendor:|r 已修理，花费 " .. FormatMoney(cost))
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

    if AutoVendor.sellEnabled then
      StartSelling()
    else
      TryRepair()
    end
  elseif eventName == "MERCHANT_CLOSED" then
    merchantOpen = false
    repairAttempted = false
    if selling then BeginMoneySettle() end
  end
end

-- ============================================================
-- 入口：不等待事件，直接执行
-- ============================================================

local events = CreateFrame("Frame", "AutoVendorEventFrame", UIParent)
pcall(events.RegisterEvent, events, "MERCHANT_SHOW")
pcall(events.RegisterEvent, events, "MERCHANT_CLOSED")
events:SetScript("OnEvent", function(a, b)
  HandleEvent(ResolveEvent(a, b))
end)

DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AutoVendor: Loaded|r")