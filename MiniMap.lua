--============================================================
-- 配置区：所有可调整的数值集中在这里，方便统一修改
--============================================================
local CONFIG = {
  mapSize        = 118,  -- 小地图控件本身的像素尺寸
  clusterExtra   = 18,   -- 容器比地图多出的高度，给区域文字留空间
  arrowSize      = 20,   -- 玩家箭头独立缩放大小
  offsetX        = 200,  -- 相对屏幕右上角的水平偏移
  offsetY        = 250,  -- 相对屏幕右上角的垂直偏移
  zoneOffsetY    = 2,    -- 区域文字距地图顶部的间距
}

-- 需要隐藏的暴雪原生小地图装饰控件
local HIDDEN_DECORATIONS = {
  "MinimapBorder",
  "MinimapBorderTop",
  "MinimapBackdrop",
  "MinimapZoomIn",
  "MinimapZoomOut",
  "MinimapNorthTag",
  "MiniMapWorldMapButton",
  "GameTimeFrame",
  "MinimapZoneTextButton",
  "MinimapCloseButton",
  "MiniMapCloseButton",
  "MinimapToggleButton",
}

-- 触发区域文字刷新的事件
local ZONE_EVENTS = {
  "MINIMAP_ZONE_CHANGED",
  "ZONE_CHANGED",
  "ZONE_CHANGED_INDOORS",
  "ZONE_CHANGED_NEW_AREA",
}

--============================================================
-- 共享状态：跨函数使用的控件引用
--============================================================
local minimapZone

--============================================================
-- 工具函数
--============================================================
local function HideFrame(frame)
  if frame and frame.Hide then frame:Hide() end
end

local function HideAllDecorations()
  for _, name in ipairs(HIDDEN_DECORATIONS) do
    HideFrame(getglobal(name))
  end
end

--============================================================
-- 区域名称显示
--============================================================
local function UpdateZoneName()
  if not minimapZone then return end

  local zone = ""
  if type(GetMinimapZoneText) == "function" then
    zone = GetMinimapZoneText() or ""
  end
  if zone == "" and type(GetZoneText) == "function" then
    zone = GetZoneText() or ""
  end

  minimapZone:SetText(zone)
end

local function CreateZoneText(parent)
  local zone = parent:CreateFontString("PotatoUIMinimapZone", "OVERLAY", "GameFontNormalSmall")
  zone:SetPoint("BOTTOM", Minimap, "TOP", 0, CONFIG.zoneOffsetY)
  zone:SetWidth(CONFIG.mapSize)
  zone:SetJustifyH("CENTER")
  zone:SetTextColor(1, .82, .2)
  if zone.SetShadowOffset then zone:SetShadowOffset(1, -1) end
  if zone.SetShadowColor then zone:SetShadowColor(0, 0, 0, 1) end
  return zone
end

local function RegisterZoneEvents()
  local events = CreateFrame("Frame", "PotatoUIMinimapEvents")
  for _, event in ipairs(ZONE_EVENTS) do
    events:RegisterEvent(event)
  end
  events:SetScript("OnEvent", UpdateZoneName)
end

--============================================================
-- 缩放（滚轮 & 玩家箭头）
--============================================================
local function HandleMouseWheel()
  local delta = tonumber(arg1) or 0
  if delta == 0 then return end

  -- Prefer the native handlers so Emberveil can keep its indoor/outdoor zoom
  -- state in sync. Some client builds omit them, so retain a direct fallback.
  if delta > 0 and type(Minimap_ZoomIn) == "function" then
    Minimap_ZoomIn()
    return
  elseif delta < 0 and type(Minimap_ZoomOut) == "function" then
    Minimap_ZoomOut()
    return
  end

  if not Minimap or not Minimap.GetZoom or not Minimap.SetZoom then return end
  local zoom = tonumber(Minimap:GetZoom()) or 0
  zoom = delta > 0 and math.min(5, zoom + 1) or math.max(0, zoom - 1)
  Minimap:SetZoom(zoom)
end

local function ResizePlayerArrow(size)
  size = tonumber(size) or CONFIG.arrowSize
  local arrow = MinimapPlayerFrame or MinimapCompassTexture
  if arrow and arrow.SetWidth and arrow.SetHeight then
    arrow:SetWidth(size)
    arrow:SetHeight(size)
    return true
  end
  return false
end

--============================================================
-- 布局：容器与地图本体的定位、尺寸
--============================================================
local function LayoutMinimapCluster()
  if not MinimapCluster then return end
  MinimapCluster:ClearAllPoints()
  MinimapCluster:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", CONFIG.offsetX, CONFIG.offsetY)
  MinimapCluster:SetWidth(CONFIG.mapSize)
  MinimapCluster:SetHeight(CONFIG.mapSize + CONFIG.clusterExtra)
end

local function LayoutMinimap()
  Minimap:ClearAllPoints()
  Minimap:SetPoint("TOP", MinimapCluster or UIParent, "TOP", 0, -14)
  Minimap:SetWidth(CONFIG.mapSize)
  Minimap:SetHeight(CONFIG.mapSize)
  Minimap:EnableMouse(true)
  Minimap:EnableMouseWheel(1)
  Minimap:SetScript("OnMouseWheel", HandleMouseWheel)

  -- Retain the native circular render that works in Emberveil, but strip all
  -- of Blizzard's surrounding artwork and controls.
  if Minimap.SetMaskTexture then
    Minimap:SetMaskTexture("Textures\\MinimapMask")
  end
end

--============================================================
-- 初始化逻辑
--============================================================
local function SetupMinimap()
  if not Minimap then return end

  HideAllDecorations()
  LayoutMinimapCluster()
  LayoutMinimap()
  ResizePlayerArrow(CONFIG.arrowSize)

  minimapZone = CreateZoneText(MinimapCluster or UIParent)
  RegisterZoneEvents()
  UpdateZoneName()  -- 初始化时立即刷新一次，避免文字初始为空
end

--============================================================
-- 入口：等玩家真正进入游戏世界（登录、reload UI、传送后都会触发）
-- 只执行一次即可，执行完立即取消监听
--============================================================
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function()
  SetupMinimap()
  initFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")
end)