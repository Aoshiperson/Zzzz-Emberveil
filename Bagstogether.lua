local busy = false

local function OpenOthers()
  for i = 1, 4 do OpenBag(i) end
end

local function CloseOthers()
  for i = 1, 4 do CloseBag(i) end
end

local origOpen = OpenBackpack
OpenBackpack = function()
  origOpen()
  if busy then return end
  busy = true
  OpenOthers()
  busy = false
end

local origClose = CloseBackpack
CloseBackpack = function()
  origClose()
  if busy then return end
  busy = true
  CloseOthers()
  busy = false
end

local origToggle = ToggleBackpack
ToggleBackpack = function()
  origToggle()
  if busy then return end
  busy = true
  if IsBagOpen(0) then OpenOthers() else CloseOthers() end
  busy = false
end
