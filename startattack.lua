-- StartAttack（自动攻击）Emberveil 精简版
local autoAttack, autoShot = false, false
local lastCall = 0 -- 防止短时间重复触发

local function NeedTab()
	return UnitExists("target") and (not UnitIsPlayer("target"))
		and (UnitIsDead("target") or not UnitCanAttack("player", "target"))
end

local function Locked()
	local now = GetTime()
	if now - lastCall < 0.15 then return true end
	lastCall = now
	return false
end

function AutoAttack()
	if NeedTab() then TargetNearestEnemy() end
	if not (UnitExists("target") and UnitCanAttack("player", "target")
		and not UnitIsDead("target")) then return end
	if autoAttack or Locked() then return end
	AttackTarget()
end

function StopAttack()
	if autoAttack and not Locked() then
		AttackTarget()
		autoAttack = false
	end
end

SLASH_NBATTACK1 = "/startattack"
SLASH_NBATTACK2 = "/attack"
SLASH_NBATTACK3 = "/自动攻击"
SLASH_NBATTACK4 = "/攻击"
SlashCmdList["NBATTACK"] = function() AutoAttack() end

SLASH_NBSTOPATTACK1 = "/stopattack"
SLASH_NBSTOPATTACK2 = "/停止攻击"
SlashCmdList["NBSTOPATTACK"] = function() StopAttack() end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTER_COMBAT")
f:RegisterEvent("PLAYER_LEAVE_COMBAT")
--f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:RegisterEvent("START_AUTOREPEAT_SPELL")
f:RegisterEvent("STOP_AUTOREPEAT_SPELL")
f:SetScript("OnEvent", function(a1, a2)
	local ev = event or a2
	if ev == "PLAYER_ENTER_COMBAT" then
		autoAttack = true
	elseif ev == "PLAYER_LEAVE_COMBAT" or ev == "PLAYER_TARGET_CHANGED" then
		autoAttack = false
	elseif ev == "START_AUTOREPEAT_SPELL" then
		autoShot = true
	elseif ev == "STOP_AUTOREPEAT_SPELL" then
		autoShot = false
	end
end)
