-- Chain: the button on the minimap.
--
-- Through LibDBIcon rather than a frame of our own. The hand-rolled one
-- worked perfectly well and drew the same icon in the same place, but every
-- button-collecting addon on the screen - MinimapButtonButton, the various
-- button bars - looks for LibDBIcon buttons and complains about anything
-- else. Being right about the pixels is worth less than being the shape the
-- rest of the ecosystem expects.
--
-- What is ours is still ours: the tooltip and what the three clicks do. The
-- library supplies the frame, the dragging, the position and the fact that
-- other addons can find it.
--
-- Libs/ is other people's code, carried the way every WoW addon carries it.
-- LibStub and LibDataBroker are public domain; CallbackHandler and LibDBIcon
-- are Ace3-family libraries, embedded in several hundred addons for the same
-- reason they are embedded here.

local ADDON, BT = ...
local C = BT.COL

local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
local Icon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)

local function Tooltip(tip)
  if not tip or not tip.AddLine then return end
  tip:AddLine(BT.NAME, 1, 0.82, 0)

  -- the two things you would open the window to find out
  local count, freeOne = BT.Lockout()
  local limit = ChainDB.limit or BT.K.LIMIT
  local lockTxt = count .. "/" .. limit
  if freeOne and count > 0 then lockTxt = lockTxt .. "  +1 in " .. BT.T(freeOne) end
  tip:AddDoubleLine("instances this hour", lockTxt, 0.7, 0.7, 0.7,
    (count >= limit) and 1 or 0.4, (count >= limit) and 0.4 or 1, 0.4)

  local _, step = BT.Stage()
  if step then
    local _, _, remain = BT.StageSpan()
    tip:AddDoubleLine("on", step.label .. "  to " .. step.to,
                      0.7, 0.7, 0.7, 1, 1, 1)
    if remain then
      tip:AddDoubleLine("left in this step", BT.N(remain) .. " xp",
                        0.7, 0.7, 0.7, 1, 1, 1)
    end
  end

  -- and the two that only matter sometimes, which is why they are not always
  -- on the line
  local near = BT.Nearby and #BT.Nearby() or 0
  if near > 0 then
    tip:AddDoubleLine("players nearby", tostring(near), 0.7, 0.7, 0.7, 1, 0.6, 0.3)
  end
  if BT.PvPState then
    local s = BT.PvPState()
    if (s.honor or 0) > 0 then
      tip:AddDoubleLine("honor this week", BT.N(s.honor) .. "  -> " .. s.newRankName,
                        0.7, 0.7, 0.7, 1, 1, 1)
    end
  end

  local zone, _, by, inside = BT.ResetReady()
  if zone then
    tip:AddLine(" ")
    tip:AddLine((BT.Short(zone) or zone) .. " reset"
      .. (by and (" by " .. by) or "")
      .. (inside and " - zone out" or " - go in"), 0.4, 1, 0.4)
  end

  tip:AddLine(" ")
  tip:AddLine("Left-click: the window", 0.4, 0.7, 1)
  tip:AddLine("Right-click: settings", 0.4, 0.7, 1)
  tip:AddLine("Middle-click: show or hide the bar", 0.4, 0.7, 1)
end

function BT.BuildMinimap()
  if not LDB or not Icon then return nil end
  if BT.minimapObject then return BT.minimapObject end

  BT.minimapObject = LDB:NewDataObject(ADDON, {
    type = "launcher",
    text = BT.NAME,
    icon = "Interface\\AddOns\\" .. ADDON .. "\\minimap",
    OnClick = function(_, button)
      if button == "RightButton" then BT.ToggleOptions()
      elseif button == "MiddleButton" then BT.ToggleBar()
      else BT.ToggleWindow() end
    end,
    OnTooltipShow = Tooltip
  })

  -- LibDBIcon keeps the position itself, in whatever table we hand it
  ChainDB.minimapIcon = ChainDB.minimapIcon or { hide = false }
  Icon:Register(ADDON, BT.minimapObject, ChainDB.minimapIcon)
  return BT.minimapObject
end

-- Shown unless you have said otherwise. An addon nobody can find is an addon
-- nobody uses, and not everybody types slash commands.
function BT.RefreshMinimap()
  if not LDB or not Icon then return end
  BT.BuildMinimap()
  ChainDB.minimapIcon = ChainDB.minimapIcon or { hide = false }
  ChainDB.minimapIcon.hide = (ChainDB.minimap == false)
  if ChainDB.minimapIcon.hide then Icon:Hide(ADDON) else Icon:Show(ADDON) end
end

function BT.ToggleMinimap()
  ChainDB.minimap = (ChainDB.minimap == false)
  BT.RefreshMinimap()
  return ChainDB.minimap
end
