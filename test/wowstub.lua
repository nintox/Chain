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
  if u == "target" and S.guid then return true end
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
-- whether the target is still breathing. The run code refuses to read an
-- instance id off a corpse - a mob you dragged along in the target frame is
-- from the wing you just left - and a stub that never answers would let that
-- go untested.
function UnitIsDead(unit)
  return (unit == "target") and (S.targetDead == true) or false
end
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
-- who you are with, for anything that picks a chat channel
-- in a guild by default: that is the ordinary case, and the share tests
-- were written before anything asked
-- The client owns the loot sentences; anything that reads them has to build
-- its patterns from these rather than from English written out by hand.
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM = "%s receives loot: %s."
LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
LOOT_ITEM_CREATED_SELF = "You create: %s."
LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
GOLD_AMOUNT, SILVER_AMOUNT, COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
YOU_LOOT_MONEY = "You loot %s"

-- [id] = { name, quality, sellPrice }
-- the loot window: which corpse each slot belongs to
S.lootSlots = {}
function GetNumLootItems() return #S.lootSlots end
function GetLootSourceInfo(slot) return S.lootSlots[slot] end

S.items = {}
function GetItemInfo(link)
  local id = tonumber(tostring(link):match("|Hitem:(%d+)")) or tonumber(link)
  local it = id and S.items[id]
  if not it then return nil end
  return it.name, link, it.quality, 1, 1, "", "", 1, "", "", it.price
end

S.fps, S.msHome, S.msWorld = 60, 40, 40
function GetFramerate() return S.fps end
function GetNetStats() return 0, 0, S.msHome, S.msWorld end

S.maxLevel = 60
function GetMaxPlayerLevel() return S.maxLevel end

S.inCombat, S.shiftDown = false, false
function InCombatLockdown() return S.inCombat end
function IsShiftKeyDown() return S.shiftDown end

S.inRaid, S.inGuild = false, true
function IsInRaid() return S.inRaid end
function IsInGuild() return S.inGuild end

-- where you are standing, for anything that reports a position
S.mapPos = nil
C_Map = {
  GetBestMapForUnit = function() return S.mapPos and 1 or nil end,
  GetPlayerMapPosition = function()
    if not S.mapPos then return nil end
    return { GetXY = function() return S.mapPos[1], S.mapPos[2] end }
  end,
}
function GetSubZoneText() return S.subZone or "" end

S.auras = {}          -- [token] = { "Stealth", ... }
function UnitAura(unit, i)
  local a = S.auras[unit]
  return a and a[i] or nil
end

-- /who, the only way an addon can learn a level it never saw
S.whoResults = {}
S.whoSent = nil
C_FriendList = {
  SetWhoToUI = function(v) S.whoToUI = v end,
  SendWho = function(q) S.whoSent = q end,
  GetNumWhoResults = function() return #S.whoResults end,
  GetWhoInfo = function(i) return S.whoResults[i] end,
}

S.guids = {}
function GetPlayerInfoByGUID(guid)
  local g = S.guids[guid]
  if not g then return nil end
  return g.class, g.class, g.race, g.race, g.sex, g.name, g.realm
end

-- what the addon said in chat, so a test can read it back. Still printed:
-- the suite's own output is the transcript of a session.
S.printed = {}
S.mouseOver = nil

-- Sekund sidan spelet starta, slik spelet gjer det. S.uptime er handtaket.
S.uptime = 1000
function GetTime() return S.uptime end

function wipe(t)
  for k in pairs(t) do t[k] = nil end
  return t
end

-- Font-objekt. Eit font-objekt er delt av alle strengane som brukar det, så
-- å byte ansikt på eit av dei endrar alt som er skrive i det - og det er heile
-- poenget med at addonen har sine eigne fem.
local fontMeta = {}
fontMeta.__index = fontMeta
function fontMeta:SetFont(path, size, flags)
  self.path, self.size, self.flags = path, size, flags
end
function fontMeta:GetFont() return self.path, self.size, self.flags end
function fontMeta:SetFontObject(o)
  if o and o.GetFont then self.path, self.size, self.flags = o:GetFont() end
end
function CreateFont(name)
  local o = setmetatable({ fontName = name }, fontMeta)
  _G[name] = o
  return o
end
for name, size in pairs({ GameFontNormal = 12, GameFontNormalSmall = 10,
                          GameFontNormalLarge = 16, GameFontHighlightSmall = 10,
                          GameFontDisableSmall = 10 }) do
  _G[name] = setmetatable({ fontName = name, path = "Fonts\\FRIZQT__.TTF",
                            size = size, flags = "" }, fontMeta)
end
local realPrint = print
function print(...)
  local bits = {}
  for i = 1, select("#", ...) do bits[i] = tostring((select(i, ...))) end
  local line = table.concat(bits, " ")
  table.insert(S.printed, (line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
  realPrint(...)
end
function S.Said(pattern)
  for _, line in ipairs(S.printed) do
    if line:find(pattern) then return line end
  end
  return nil
end

SlashCmdList = {}
function StaticPopup_Show() end
S.whispered = {}
DEFAULT_CHAT_FRAME = {}
function ChatFrame_SendTell(name) table.insert(S.whispered, name) end
function ChatFrame_OpenChat(text) table.insert(S.whispered, text) end
S.chatLinks = {}
function IsModifiedClick(what) return (what == "CHATLINK") and (S.shiftDown == true) or false end
function ChatEdit_InsertLink(link) table.insert(S.chatLinks, link) return true end
-- The tooltip records what it was told, so a test can read it back. Anything
-- we did not bother to implement is still a no-op.
S.tip = {}
local tipMeta = { __index = function() return function() end end }
GameTooltip = setmetatable({
  SetOwner = function(self) S.tip = {} end,
  -- the client's own item tooltip. Recorded as one line naming the item, so a
  -- test can tell "we asked the game for the real tooltip" from "we wrote the
  -- name out ourselves".
  SetHyperlink = function(self, link)
    table.insert(S.tip, "[hyperlink] " .. tostring(link or ""))
  end,
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
  if type(k) ~= "string" then return nil end
  -- Only names that look like the client's own API get the no-op treatment.
  -- Every method WoW puts on a widget is PascalCase, and every field an addon
  -- hangs off one is not - so a lowercase name that was never set reads as
  -- nil, the way it does in the game.
  --
  -- This distinction has caught three real bugs: a nil check on `bar.ticks`,
  -- one on `nearby.dragging` and one on `row.rec`, each of which was true
  -- forever here and nil in the game. A stub that is wrong in a direction the
  -- client is not is worse than no stub.
  local first = k:sub(1, 1)
  if first ~= first:upper() or first == "_" then return nil end
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
function frameMeta:HookScript(name, fn) self.__scripts[name] = fn end
function frameMeta:SetAttribute(k, v)
  self.__attrs = self.__attrs or {}
  self.__attrs[k] = v
end
function frameMeta:GetAttribute(k) return self.__attrs and self.__attrs[k] end
-- Kvar peikaren er. S.mouseOver er ramma han står over, om nokon.
function frameMeta:IsMouseOver() return S.mouseOver == self end
-- Kva klikk knappen er meld på for. Ein secure knapp som berre er meld på
-- for "LeftButtonUp" gjer ingenting på denne klienten, så det er verdt å
-- kunne sjekke.
function frameMeta:RegisterForClicks(...) self.__clicks = { ... } end
function frameMeta:ClicksFor()
  return table.concat(self.__clicks or {}, ",")
end
function frameMeta:GetScript(name) return self.__scripts[name] end
-- Show og Hide køyrer OnShow/OnHide, slik spelet gjer. Utan det kan ein
-- ikkje teste noko som heng på at eit vindauge blir opna eller lukka.
function frameMeta:Show()
  local was = self.__shown
  self.__shown = true
  local fn = not was and self.__scripts and self.__scripts.OnShow
  if fn then fn(self) end
end
function frameMeta:Hide()
  local was = self.__shown
  self.__shown = false
  local fn = was and self.__scripts and self.__scripts.OnHide
  if fn then fn(self) end
end
function frameMeta:IsShown() return self.__shown end
function frameMeta:IsVisible() return self.__shown end
function frameMeta:GetWidth() return self.__w or 380 end
function frameMeta:GetHeight() return self.__h or 24 end
function frameMeta:SetSize(w, h) self.__w, self.__h = w, h end
function frameMeta:SetWidth(w) self.__w = w end
function frameMeta:SetHeight(h) self.__h = h end
-- The real client hands back the anchors you actually set, and code that
-- re-lays-out a panel reads them - so the stub has to as well, or the layout
-- pass is never exercised.
function frameMeta:GetPoint(i)
  local p = self.__points and self.__points[i or 1]
  if not p then return "CENTER", nil, "CENTER", 0, 0 end
  return p.point, p.rel, p.relPoint or p.point, p.x or 0, p.y or 0
end
function frameMeta:SetText(v) self.__text = v end
function frameMeta:SetTexture(v, g, b, a)
  if type(v) == "number" then self.__alpha = a else self.__tex = v end
end
function frameMeta:SetColorTexture(r, g, b, a) self.__alpha = a end
function frameMeta:SetFrameStrata(v) self.__strata = v end
function frameMeta:GetTexture() return self.__tex end
function frameMeta:GetText() return self.__text or "" end
-- rough but monotonic: enough for the layout to make the same decisions.
-- S.charW er kor brei ein bokstav er - eit anna ansikt er eit anna tal, og
-- det er heile grunnen til at baren må måle i staden for å hugse.
S.charW = 6
function frameMeta:GetStringWidth()
  local t = tostring(self.__text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  return #t * (S.charW or 6)
end
function frameMeta:SetShown(v) self.__shown = v and true or false end
function frameMeta:SetChecked(v) self.__checked = v end
function frameMeta:GetChecked() return self.__checked end
function frameMeta:HasFocus() return false end
function frameMeta:RegisterEvent(e)
  self.__events = self.__events or {}
  self.__events[e] = true
end
-- Enough of a screen position for code that reads where a frame ended up
-- after the user dragged it. A test moves a frame by setting __left/__top.
function frameMeta:GetLeft()
  if self.__left then return self.__left end
  local p = self.__points and self.__points[1]
  return p and p.x or 0
end
function frameMeta:GetTop()
  if self.__top then return self.__top end
  local p = self.__points and self.__points[1]
  return p and p.y or 0
end
function frameMeta:GetBottom() return (self:GetTop() or 0) - (self:GetHeight() or 0) end
function frameMeta:SetScale(v) self.__scale = v end
function frameMeta:GetScale() return self.__scale or 1 end
function frameMeta:GetEffectiveScale() return self.__scale or 1 end
function frameMeta:StartMoving() self.__moving = true end
function frameMeta:StopMovingOrSizing() self.__moving = false end

function frameMeta:CreateTexture() return newObject("Texture", self) end
function frameMeta:CreateFontString() return newObject("FontString", self) end
-- Frames and regions are two different lists in the real API, and code that
-- walks a panel has to ask for both. Keeping them separate here is what makes
-- forgetting one of them show up in a test.
local function isRegion(o)
  return o.__kind == "Texture" or o.__kind == "FontString"
end
function frameMeta:GetChildren()
  local out = {}
  for _, c in ipairs(self.__children or {}) do
    if not isRegion(c) then table.insert(out, c) end
  end
  return table.unpack(out)
end
function frameMeta:GetRegions()
  local out = {}
  for _, c in ipairs(self.__children or {}) do
    if isRegion(c) then table.insert(out, c) end
  end
  return table.unpack(out)
end
function frameMeta:GetParent() return self.__parent end

function CreateFrame(kind, name, parent, template)
  local f = newObject(kind, parent)
  -- A second tooltip is a real thing an addon can make, and its lines are as
  -- much a part of what the user sees as GameTooltip's. It records into the
  -- same buffer, so S.TipText() covers both columns.
  if kind == "GameTooltip" then
    f.AddLine = function(_, text) table.insert(S.tip, tostring(text or "")) end
    f.AddDoubleLine = function(_, l, r)
      table.insert(S.tip, tostring(l or "") .. "\t" .. tostring(r or ""))
    end
    f.SetHyperlink = function(_, link)
      table.insert(S.tip, "[hyperlink] " .. tostring(link or ""))
    end
    f.ClearLines = function() end
    f.SetOwner = function() end
  end
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
