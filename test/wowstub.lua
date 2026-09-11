-- A small fake WoW client: enough API for the addon to load and run headless.
local S = {}
_G.S = S

S.now = 1700000000
S.level = 20
S.xp = 0
S.xpMax = 23200
S.rested = nil
S.party = {}
S.zone = "Stormwind City"
S.inInstance = false
S.quests = {}
S.units = {}

function time() return S.now end
function date(fmt, t) return os.date(fmt, t) end
function strsplit(sep, str)
  local out = {}
  for piece in tostring(str):gmatch("([^" .. sep .. "]*)") do table.insert(out, piece) end
  -- gmatch with an empty-allowed pattern yields blanks; rebuild properly
  out = {}
  local pattern = "([^" .. sep .. "]*)" .. sep .. "?"
  for piece in tostring(str):gmatch(pattern) do table.insert(out, piece) end
  return table.unpack(out)
end
function Ambiguate(name) return (name:match("^[^%-]+")) end

function UnitLevel(u)
  if u == "player" then return S.level end
  if S.units[u] then return S.units[u].level end
  local i = tonumber(tostring(u):match("party(%d)"))
  return (i and S.party[i]) and S.party[i].lvl or 0
end
function UnitName(u)
  if u == "player" then return "Tester" end
  if S.units[u] then return S.units[u].name end
  if u == "NPC" then return S.tradeTarget end
  local i = tonumber(tostring(u):match("party(%d)"))
  return (i and S.party[i]) and S.party[i].name or nil
end
function UnitExists(u)
  if S.units[u] then return true end
  local i = tonumber(tostring(u):match("party(%d)"))
  return (i and S.party[i]) and true or false
end
function UnitIsGroupLeader(u)
  local i = tonumber(tostring(u):match("party(%d)"))
  return (i and S.party[i]) and (S.party[i].lead or false) or false
end
function IsInGroup() return #S.party > 0 end
function UnitXP() return S.xp end
function UnitXPMax() return S.xpMax end
function GetXPExhaustion() return S.rested end
function UnitGUID() return S.guid end
function IsInInstance() return S.inInstance, S.inInstance and "party" or "none" end
S.map = nil
function GetInstanceInfo()
  return S.zone, S.inInstance and "party" or "none", 1, "", 5, 0, false, S.map
end
function GetRealZoneText() return S.zone end
function GetZoneText() return S.zone end
function GetNumQuestLogEntries() return #S.quests end
function GetQuestLogTitle(i)
  local q = S.quests[i]
  if not q then return nil end
  -- title, level, suggestedGroup, isHeader, isCollapsed, isComplete
  return q.title, q.level, nil, false, nil, q.done and 1 or nil
end
-- how many levels below you still count as green; grey starts one under it
S.greenRange = 5
function GetQuestGreenRange() return S.greenRange end
function SelectQuestLogEntry(i) S.selected = i end
function GetQuestLogSelection() return S.selected end
function GetQuestLogRewardXP() return (S.quests[S.selected] or {}).xp or 0 end
S.playerMoney, S.targetMoney, S.tradeTarget = 0, 0, nil
function GetPlayerTradeMoney() return S.playerMoney end
function GetTargetTradeMoney() return S.targetMoney end
ERR_TRADE_COMPLETE = "Trade complete."
-- which sound, not just how many: the reset alert plays a different one
-- depending on which side of the portal you are standing on
S.soundLog = {}
function PlaySound(id)
  S.sounds = (S.sounds or 0) + 1
  table.insert(S.soundLog, "kit:" .. tostring(id))
end
function PlaySoundFile(f)
  S.sounds = (S.sounds or 0) + 1
  table.insert(S.soundLog, "file:" .. tostring(f))
end
function S.LastSound() return S.soundLog[#S.soundLog] end
SOUNDKIT = { RAID_WARNING = 1, READY_CHECK = 2, UI_LEGENDARY_LOOT_TOAST = 3,
             ALARM_CLOCK_WARNING_3 = 4, AUCTION_WINDOW_OPEN = 5 }
INSTANCE_RESET_SUCCESS = "%s has been reset."
INSTANCE_RESET_FAILED = "Cannot reset %s.  There are players still inside the instance."
INSTANCE_RESET_FAILED_ZONING = "Cannot reset %s.  There are players in your party attempting to zone into an instance."
INSTANCE_RESET_FAILED_OFFLINE = "Cannot reset %s.  There are players offline in your party."
S.said = {}
function SendChatMessage(msg, ch) table.insert(S.said, ch .. ": " .. msg) end
function IsInRaid() return false end
function IsInGuild() return true end
S.channels, S.sent = {}, {}
function JoinTemporaryChannel(name) S.channels[name] = 7 end
function LeaveChannelByName(name) S.channels[name] = nil end
function GetChannelName(name) return S.channels[name] or 0 end
-- number, name, disabled per channel, exactly as the client returns it
-- the client names the city channels after the zone you are standing in
S.channelList = { 1, "General - Stormwind City", false, 2, "Trade - City", false,
                  4, "LookingForGroup", false, 5, "ChainData", false }
function GetChannelList() return table.unpack(S.channelList) end
S.channelFrames = {}
function ChatFrame_RemoveChannel(f, name)
  if S.channelFrames[name] == f then S.channelFrames[name] = nil end
end
function ChatFrame_AddChannel(f, name)
  -- the combat log window refuses channels in some builds; the stub can be
  -- told to behave that way so the fallback is exercised
  if S.refuseFrame and S.refuseFrame == f then return end
  S.channelFrames[name] = f
end
function ChatFrame_ContainsChannel(f, name) return S.channelFrames[name] == f end
NUM_CHAT_WINDOWS = 2
ChatFrame1, ChatFrame2 = { name = "General" }, { name = "Combat Log" }
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, msg, ch, target)
    table.insert(S.sent, { prefix = prefix, msg = msg, ch = ch, target = target })
  end
}
S.timers = {}
C_Timer = { After = function(delay, fn) table.insert(S.timers, fn) end }
-- run everything the addon has scheduled, up to a sane limit
function S.RunTimers(max)
  local ran = 0
  while #S.timers > 0 and ran < (max or 200) do
    local fn = table.remove(S.timers, 1)
    fn()
    ran = ran + 1
  end
  return ran
end
function ResetInstances() S.resets = (S.resets or 0) + 1 end
S.screenshots = 0
function Screenshot() S.screenshots = S.screenshots + 1 end
-- the client keeps saying "on" after a reload while the file is closed; the
-- stub records every toggle so a test can see the reopen happen
S.chatlog = false
S.chatlogToggles = {}
function LoggingChat(v)
  if v ~= nil then
    S.chatlog = v
    table.insert(S.chatlogToggles, v and "on" or "off")
  end
  return S.chatlog
end
-- other players, for the enemy watch
S.units = {}          -- [token] = { name, level, class, guild, hostile, faction }
function UnitIsPlayer(u) return S.units[u] ~= nil end
function UnitIsUnit(a, b) return a == b end
function UnitCanAttack(_, u) return (S.units[u] or {}).hostile and true or false end
function UnitIsFriend(_, u) return not ((S.units[u] or {}).hostile) end
function UnitClass(u)
  local x = S.units[u]
  if not x then return nil end
  return x.class, x.class
end
function GetGuildInfo(u) return (S.units[u] or {}).guild end
bit = bit or { band = function(a, b) return ((a // b) % 2 == 1) and b or 0 end }

-- LibStub and the two libraries the minimap button goes through. Stubbed
-- rather than loaded: what is worth testing is our contract with them - the
-- object we hand over and what our own callbacks do - not somebody else's
-- library, which has its own tests.
S.ldbObjects = {}
S.iconRegistered = {}
S.iconHidden = {}
local libs = {
  ["LibDataBroker-1.1"] = {
    NewDataObject = function(_, name, obj)
      S.ldbObjects[name] = obj
      return obj
    end
  },
  ["LibDBIcon-1.0"] = {
    Register = function(_, name, obj, db)
      S.iconRegistered[name] = { obj = obj, db = db }
    end,
    Hide = function(_, name) S.iconHidden[name] = true end,
    Show = function(_, name) S.iconHidden[name] = false end
  }
}
LibStub = { GetLibrary = function(_, name) return libs[name] end }

-- nameplates, so a mark can be hung on one
S.plates = {}                  -- [unit] = frame
C_NamePlate = {
  GetNamePlateForUnit = function(unit) return S.plates[unit] end,
  GetNamePlates = function()
    local out = {}
    for unit, f in pairs(S.plates) do
      f.namePlateUnitToken = unit
      table.insert(out, f)
    end
    return out
  end
}

-- the honour system
S.pvpRank = 0            -- 0 = unranked; the API offsets by four
S.pvpProgress = 0
S.weekHonor, S.weekKills = 0, 0
S.lastHonor, S.lastKills, S.standing = 0, 0, nil
function UnitPVPRank() return (S.pvpRank > 0) and (S.pvpRank + 4) or 0 end
function GetPVPRankInfo(idx) return "Rank " .. tostring((idx or 4) - 4), (idx or 4) - 4 end
function GetPVPRankProgress() return S.pvpProgress end
function GetPVPThisWeekStats() return S.weekKills, S.weekHonor end
function GetPVPLastWeekStats() return S.lastKills, S.lastHonor, S.standing end
function UnitFactionGroup() return "Alliance" end

YES, NO = "Yes", "No"
StaticPopupDialogs = {}
-- The client knows the class and race of any player it has seen, from the
-- GUID alone - which is how somebody found only in the combat log gets a
-- colour instead of a grey question mark.
S.guids = {}
function GetPlayerInfoByGUID(guid)
  local g = S.guids[guid]
  if not g then return nil end
  return g.class, g.class, g.race, g.race, g.sex, g.name, g.realm
end

SlashCmdList = {}
function StaticPopup_Show() end
S.whispered = {}
DEFAULT_CHAT_FRAME = {}
function ChatFrame_SendTell(name) table.insert(S.whispered, name) end
function ChatFrame_OpenChat(text) table.insert(S.whispered, text) end
-- The tooltip records what it was told, so a test can read it back. Anything
-- we did not bother to implement is still a no-op.
S.tip = {}
local tipMeta = { __index = function() return function() end end }
GameTooltip = setmetatable({
  SetOwner = function(self) S.tip = {} end,
  AddLine = function(self, text) table.insert(S.tip, tostring(text or "")) end,
  AddDoubleLine = function(self, left, right)
    table.insert(S.tip, tostring(left or "") .. "\t" .. tostring(right or ""))
  end,
  Show = function() end,
  Hide = function() end
}, tipMeta)
-- everything the tooltip was told, colour codes stripped, as one string
function S.TipText()
  local t = table.concat(S.tip, "\n")
  t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return t
end

--------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------
local frameMeta = {}
frameMeta.__index = function(t, k)
  local fn = rawget(frameMeta, k)
  if fn then return fn end
  -- our own bookkeeping fields are plain data, not methods
  if type(k) == "string" and k:sub(1, 2) == "__" then return nil end
  -- any widget method we did not bother to implement is a no-op
  return function() end
end

local function newObject(kind, parent)
  local o = setmetatable({ __kind = kind, __shown = true, __scripts = {},
                           __children = {}, __points = {}, __parent = parent },
                         frameMeta)
  if parent and parent.__children then table.insert(parent.__children, o) end
  return o
end

-- Anchors are recorded rather than ignored, so a test can work out whether a
-- widget was placed outside the frame it belongs to. Both shapes are used in
-- the addon: SetPoint(point, x, y) and SetPoint(point, rel, relPoint, x, y).
function frameMeta:SetPoint(point, a, b, c, d)
  local rel, relPoint, x, y
  if type(a) == "number" then
    rel, relPoint, x, y = self.__parent, point, a, b
  else
    rel, relPoint, x, y = a, b, c or 0, d or 0
  end
  table.insert(self.__points, { point = point, rel = rel, relPoint = relPoint,
                                x = x or 0, y = y or 0 })
end
function frameMeta:GetPoints() return self.__points end
function frameMeta:ClearAllPoints() self.__points = {} end

function frameMeta:SetScript(name, fn) self.__scripts[name] = fn end
function frameMeta:GetScript(name) return self.__scripts[name] end
function frameMeta:Show() self.__shown = true end
function frameMeta:Hide() self.__shown = false end
function frameMeta:IsShown() return self.__shown end
function frameMeta:IsVisible() return self.__shown end
function frameMeta:GetWidth() return self.__w or 380 end
function frameMeta:GetHeight() return self.__h or 24 end
function frameMeta:SetSize(w, h) self.__w, self.__h = w, h end
function frameMeta:SetWidth(w) self.__w = w end
function frameMeta:SetHeight(h) self.__h = h end
function frameMeta:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function frameMeta:SetText(v) self.__text = v end
function frameMeta:GetText() return self.__text or "" end
-- rough but monotonic: enough for the layout to make the same decisions
function frameMeta:GetStringWidth()
  local t = tostring(self.__text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return #t * 6
end
function frameMeta:SetShown(v) self.__shown = v and true or false end
function frameMeta:SetChecked(v) self.__checked = v end
function frameMeta:GetChecked() return self.__checked end
function frameMeta:HasFocus() return false end
function frameMeta:RegisterEvent(e)
  self.__events = self.__events or {}
  self.__events[e] = true
end
function frameMeta:CreateTexture() return newObject("Texture", self) end
function frameMeta:CreateFontString() return newObject("FontString", self) end
function frameMeta:GetChildren() return table.unpack(self.__children) end
function frameMeta:GetParent() return self.__parent end

function CreateFrame(kind, name, parent, template)
  local f = newObject(kind, parent)
  if name then _G[name] = f end
  return f
end
UIParent = newObject("Frame")
-- the minimap, enough of it for a button to hang off
Minimap = newObject("Frame")
Minimap.__w, Minimap.__h = 140, 140
function Minimap:GetCenter() return 600, 400 end
function Minimap:GetEffectiveScale() return 1 end
S.cursor = { 600, 480 }
function GetCursorPosition() return S.cursor[1], S.cursor[2] end

function S.Fire(frame, event, ...)
  local fn = frame.__scripts.OnEvent
  if fn then fn(frame, event, ...) end
end

function S.Reset()
  S.party = {}
  S.zone = "Stormwind City"
  S.inInstance = false
  S.guid = nil
end

return S
