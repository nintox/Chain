-- Level Tracker: the button on the minimap.
--
-- Hand-rolled rather than LibDBIcon, for the same reason as everything else
-- here: no libraries to ship, none to keep up to date, and nothing that stops
-- working when somebody else's addon updates. It is a hundred lines, and all
-- of it is visible.
--
-- Left-click opens the window, right-click the settings, and dragging moves
-- it around the edge. Where you leave it is remembered.

local ADDON, BT = ...
local C = BT.COL

local button
local RADIUS = 80          -- the default round minimap's edge, in points

-- The game runs Lua 5.1, where the two-argument arctangent is math.atan2.
-- Newer Lua folded it into math.atan, and the tests run on whichever one the
-- machine has, so take the one that is there.
local atan2 = math.atan2 or math.atan

local function Place()
  if not button then return end
  local angle = math.rad(ChainDB.minimapAngle or 205)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER",
                  math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end
BT.PlaceMinimap = Place

-- Where the cursor is, as an angle from the middle of the minimap. Scale has
-- to be divided out or the button runs away from the pointer on any UI scale
-- other than one.
local function AngleAtCursor()
  local mx, my = Minimap:GetCenter()
  if not mx then return nil end
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  cx, cy = cx / scale, cy / scale
  return math.deg(atan2(cy - my, cx - mx))
end

local function Tooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(BT.NAME, 1, 0.82, 0)

  -- the two things you would open the window to find out
  local count, freeOne, _, _, _ = BT.Lockout()
  local limit = ChainDB.limit or BT.K.LIMIT
  local lockTxt = count .. "/" .. limit
  if freeOne and count > 0 then lockTxt = lockTxt .. "  +1 in " .. BT.T(freeOne) end
  GameTooltip:AddDoubleLine("instances this hour", lockTxt, 0.7, 0.7, 0.7,
    (count >= limit) and 1 or 0.4, (count >= limit) and 0.4 or 1, 0.4)

  local _, step = BT.Stage()
  if step then
    local _, _, remain = BT.StageSpan()
    GameTooltip:AddDoubleLine("on", step.label .. "  to " .. step.to,
                              0.7, 0.7, 0.7, 1, 1, 1)
    if remain then
      GameTooltip:AddDoubleLine("left in this step", BT.N(remain) .. " xp",
                                0.7, 0.7, 0.7, 1, 1, 1)
    end
  end

  local zone, _, by, inside = BT.ResetReady()
  if zone then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine((BT.Short(zone) or zone) .. " reset"
      .. (by and (" by " .. by) or "")
      .. (inside and " - zone out" or " - go in"), 0.4, 1, 0.4)
  end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Left-click: the window", 0.4, 0.7, 1)
  GameTooltip:AddLine("Right-click: settings", 0.4, 0.7, 1)
  GameTooltip:AddLine("Middle-click: show or hide the bar", 0.4, 0.7, 1)
  GameTooltip:AddLine("Drag: move it round the edge", 0.4, 0.7, 1)
  GameTooltip:Show()
end

function BT.BuildMinimap()
  if button then return button end
  if not Minimap then return nil end

  button = CreateFrame("Button", "ChainMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetMovable(true)

  -- the face, inset so the ring frames it the way every other minimap button
  -- on the screen is framed
  button.icon = button:CreateTexture(nil, "BACKGROUND")
  button.icon:SetSize(20, 20)
  button.icon:SetPoint("CENTER", 0, 1)
  button.icon:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\minimap.tga")

  -- Blizzard's own ring, so it sits among the others without looking foreign
  button.ring = button:CreateTexture(nil, "OVERLAY")
  button.ring:SetSize(53, 53)
  button.ring:SetPoint("TOPLEFT")
  button.ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

  button.glow = button:CreateTexture(nil, "HIGHLIGHT")
  button.glow:SetAllPoints()
  button.glow:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  button:SetScript("OnEnter", Tooltip)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  button:SetScript("OnDragStart", function(self)
    self.dragging = true
    GameTooltip:Hide()
    self:SetScript("OnUpdate", function()
      local a = AngleAtCursor()
      if a then
        ChainDB.minimapAngle = a
        Place()
      end
    end)
  end)
  button:SetScript("OnDragStop", function(self)
    self.dragging = nil
    self:SetScript("OnUpdate", nil)
  end)

  button:SetScript("OnClick", function(_, click)
    if click == "RightButton" then
      BT.ToggleOptions()
    elseif click == "MiddleButton" then
      BT.ToggleBar()
    else
      BT.ToggleWindow()
    end
  end)

  Place()
  return button
end

-- Shown unless you have said otherwise. An addon nobody can find is an addon
-- nobody uses, and not everybody types slash commands.
function BT.RefreshMinimap()
  if ChainDB.minimap == false then
    if button then button:Hide() end
    return
  end
  if not button then BT.BuildMinimap() end
  if button then
    Place()
    button:Show()
  end
end

function BT.ToggleMinimap()
  ChainDB.minimap = (ChainDB.minimap == false)
  BT.RefreshMinimap()
  return ChainDB.minimap
end
