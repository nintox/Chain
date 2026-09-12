-- Chain: frames and latency, in the corner of your eye.
--
-- Two numbers and nothing else. The point of putting them on screen rather
-- than leaving them behind a keybind is that you see them change without
-- looking for them - a run that suddenly feels heavy is usually one of these
-- two, and knowing which one takes a glance rather than a diagnosis.
--
-- The colours are the whole feature. A number you have to compare against a
-- remembered threshold is a number you read; a number that turns orange is a
-- number you notice.

local ADDON, BT = ...
local C = BT.COL

-- Frames: sixty is the old target, thirty is playable, fifteen is a
-- slideshow. Latency: a hundred is good anywhere, three hundred is where
-- casting starts to feel like posting a letter.
local FPS_GOOD, FPS_OK, FPS_BAD = 55, 30, 15
local MS_GOOD, MS_OK, MS_BAD = 100, 200, 300

local meter
-- A plain local, not a field on the frame: a widget answers any name you ask
-- it for with a function, so meter.dragging would read as "yes" for ever.
local dragging = false

local function Grade(value, good, ok, bad, lowerIsBetter)
  if not value then return C.dim end
  if lowerIsBetter then
    if value <= good then return C.good end
    if value <= ok then return "|cffe6cc80" end
    if value <= bad then return C.warn end
    return C.bad
  end
  if value >= good then return C.good end
  if value >= ok then return "|cffe6cc80" end
  if value >= bad then return C.warn end
  return C.bad
end

function BT.MeterScale()
  return math.max(0.6, math.min(2, tonumber(ChainDB.meterScale) or 1))
end

-- What the client will tell us. Latency is the client's own figure and it
-- only refreshes it every thirty seconds or so - that is the game, not us,
-- and the tooltip says so rather than leaving you to wonder why it sits still.
function BT.MeterStats()
  local fps = GetFramerate and GetFramerate() or nil
  if fps then fps = math.floor(fps + 0.5) end
  local home, world
  if GetNetStats then
    local _, _, h, w = GetNetStats()
    home, world = tonumber(h), tonumber(w)
  end
  -- world latency is the one that decides whether a spell goes off; home is
  -- chat and the auction house. The bigger of the two is what you feel.
  local ms = world or home
  if home and world then ms = math.max(home, world) end
  return fps, ms, home, world
end

function BT.MeterText()
  local fps, ms = BT.MeterStats()
  local out = {}
  if ChainDB.meterFPS ~= false then
    out[#out + 1] = Grade(fps, FPS_GOOD, FPS_OK, FPS_BAD, false)
      .. (fps and tostring(fps) or "--") .. C.off .. C.dim .. " fps" .. C.off
  end
  if ChainDB.meterPing ~= false then
    out[#out + 1] = Grade(ms, MS_GOOD, MS_OK, MS_BAD, true)
      .. (ms and tostring(ms) or "--") .. C.off .. C.dim .. " ms" .. C.off
  end
  return table.concat(out, "   ")
end

local function Tooltip(self)
  if not GameTooltip then return end
  local fps, ms, home, world = BT.MeterStats()
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(BT.NAME, 1, 0.82, 0)
  GameTooltip:AddDoubleLine("frames", fps and (fps .. " fps") or "?",
                            0.7, 0.7, 0.7, 1, 1, 1)
  if world then
    GameTooltip:AddDoubleLine("world", world .. " ms", 0.7, 0.7, 0.7, 1, 1, 1)
  end
  if home then
    GameTooltip:AddDoubleLine("home", home .. " ms", 0.7, 0.7, 0.7, 1, 1, 1)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("world latency is what decides whether a spell goes off; "
    .. "home is chat and the auction house", 0.5, 0.5, 0.5, true)
  GameTooltip:AddLine("the client only works latency out every thirty seconds, "
    .. "so it sits still between times", 0.5, 0.5, 0.5, true)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Drag to move, right-click for the rest", 0.4, 0.7, 1)
  GameTooltip:Show()
end

-- Never while it is under the cursor. The readout refreshes once a second,
-- and re-applying the anchor mid-drag pulls the frame out of your hand - the
-- same thing that made the nearby list impossible to place.
local function Anchor()
  if not meter or dragging then return end
  local pos = ChainDB.meterPos
  meter:ClearAllPoints()
  if not pos then
    -- Where it belongs until you say otherwise: under the minimap, which is
    -- where everybody's eye already goes for this sort of number.
    local map = _G.Minimap
    if map then
      meter:SetPoint("TOP", map, "BOTTOM", 0, -6)
      return
    end
    meter:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -220)
    return
  end
  -- screen pixels, converted through the frame's own scale on the way out
  local sc = (meter.GetEffectiveScale and meter:GetEffectiveScale()) or 1
  if sc <= 0 then sc = 1 end
  meter:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x / sc, pos.y / sc)
end

function BT.BuildMeter()
  if meter then return meter end
  meter = CreateFrame("Frame", "ChainMeter", UIParent)
  meter:SetSize(110, 18)
  meter:SetScale(BT.MeterScale())
  Anchor()
  meter:SetMovable(true)
  meter:EnableMouse(true)
  meter:SetClampedToScreen(true)
  meter:RegisterForDrag("LeftButton")
  meter:SetScript("OnDragStart", function(self)
    if ChainDB.meterLocked then return end
    dragging = true
    self:StartMoving()
  end)
  meter:SetScript("OnDragStop", function(self)
    if not dragging then return end
    self:StopMovingOrSizing()
    dragging = false
    if self:GetLeft() then
      local sc = (self.GetEffectiveScale and self:GetEffectiveScale()) or 1
      if sc <= 0 then sc = 1 end
      ChainDB.meterPos = { x = self:GetLeft() * sc, y = self:GetTop() * sc }
    end
    Anchor()
  end)
  meter:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then BT.MeterMenu() end
  end)

  meter.bg = meter:CreateTexture(nil, "BACKGROUND")
  meter.bg:SetAllPoints()
  if meter.bg.SetColorTexture then meter.bg:SetColorTexture(0, 0, 0, 0.45) end

  meter.fs = meter:CreateFontString(nil, "OVERLAY", "ChainFontNormalSmall")
  meter.fs:SetPoint("CENTER")

  meter:SetScript("OnEnter", Tooltip)
  meter:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  -- Once a second. Frames move faster than that, but a number that flickers
  -- is a number you cannot read, and the client only recomputes latency every
  -- thirty seconds anyway.
  meter.t = 0
  meter:SetScript("OnUpdate", function(self, elapsed)
    self.t = self.t + (elapsed or 0)
    if self.t < 1 then return end
    self.t = 0
    BT.RefreshMeter()
  end)
  meter:Hide()
  return meter
end

function BT.RefreshMeter()
  if ChainDB.meter ~= true then
    if meter then meter:Hide() end
    return
  end
  BT.BuildMeter()
  local txt = BT.MeterText()
  meter.fs:SetText(txt)
  -- Size and position are left alone while you are holding it: a box that
  -- grows under the cursor drifts away from where you are putting it.
  if not dragging then
    meter:SetScale(BT.MeterScale())
    -- as wide as what is in it, so turning one of the two off does not leave
    -- a black bar where it used to be
    local w = (meter.fs.GetStringWidth and meter.fs:GetStringWidth()) or 60
    meter:SetWidth(math.max(40, w + 14))
    Anchor()
  end
  meter:Show()
  return meter
end

function BT.ToggleMeter(on)
  if on == nil then on = not (ChainDB.meter == true) end
  ChainDB.meter = on and true or false
  BT.RefreshMeter()
  return ChainDB.meter
end

function BT.SetMeterScale(v)
  v = tonumber(v)
  if not v then return BT.MeterScale() end
  ChainDB.meterScale = math.max(0.6, math.min(2, v))
  if meter then
    meter:SetScale(ChainDB.meterScale)
    Anchor()
  end
  return ChainDB.meterScale
end

function BT.MeterMenu()
  if not BT.ShowNearbyMenu then return nil end
  return BT.ShowNearbyMenu(nil, {
    { text = ChainDB.meterLocked
             and (C.warn .. "Locked" .. C.off .. C.dim .. " - unlock" .. C.off)
             or (C.dim .. "Unlocked" .. C.off .. " - lock"),
      fn = function() ChainDB.meterLocked = not ChainDB.meterLocked end },
    { text = "Size" .. C.dim .. "  " .. math.floor(BT.MeterScale() * 100)
             .. "%  - bigger" .. C.off,
      fn = function()
        local steps = { 0.8, 1, 1.2, 1.5 }
        local now, at = BT.MeterScale(), 1
        for i, v in ipairs(steps) do if math.abs(v - now) < 0.02 then at = i end end
        BT.SetMeterScale(steps[(at % #steps) + 1])
      end },
    { text = (ChainDB.meterFPS ~= false) and "Hide the frames" or "Show the frames",
      fn = function()
        ChainDB.meterFPS = (ChainDB.meterFPS == false) or nil
        BT.RefreshMeter()
      end },
    { text = (ChainDB.meterPing ~= false) and "Hide the latency" or "Show the latency",
      fn = function()
        ChainDB.meterPing = (ChainDB.meterPing == false) or nil
        BT.RefreshMeter()
      end },
    { text = "Back under the minimap", fn = function()
        ChainDB.meterPos = nil
        Anchor()
      end },
    { text = "Hide it", fn = function() BT.ToggleMeter(false) end },
  }, meter)
end

BT.meterFrame = function() return meter end
function BT.MeterDragging() return dragging end
