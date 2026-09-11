-- Chain: who is out there, and which of them you want to know about.
--
-- Two things that only make sense together. A list of players worth watching
-- for - kill on sight, by name or by whole guild - and the watching itself.
--
-- The detection is not clever and does not need to be. The client tells you
-- about a player the moment a nameplate appears, the moment your mouse passes
-- over one, the moment you target one, and every time one of them casts
-- anything within range of the combat log. None of those is special on its
-- own; the sum of them is how somebody is seen before you see them.
--
-- Nothing here scans, probes or asks the server anything. It reads what the
-- client already put on your screen.

local ADDON, BT = ...
local C = BT.COL

-- How long a sighting counts as "nearby", and how long before the same person
-- is worth shouting about again. The second one matters more than it looks:
-- without it, one rogue stood at a flight point produces an alert a second.
local NEARBY = 60
local REALERT = 120

--------------------------------------------------------------------------
-- The list
--------------------------------------------------------------------------
function BT.KOSKey(name)
  if type(name) ~= "string" then return nil end
  local short = BT.ShortName(name)
  return short and short ~= "" and short or nil
end

-- Kill on sight, by name. The note is yours and goes nowhere.
function BT.AddKOS(name, note)
  local key = BT.KOSKey(name)
  if not key then return nil end
  ChainDB.kos = ChainDB.kos or {}
  local e = ChainDB.kos[key] or { at = time() }
  e.name = key
  if note ~= nil then e.note = (note ~= "") and note or nil end
  ChainDB.kos[key] = e
  if BT.RenderWindow then BT.RenderWindow() end
  if BT.RefreshPlates then BT.RefreshPlates() end
  if BT.RefreshNearby then BT.RefreshNearby() end
  return e
end

function BT.RemoveKOS(name)
  local key = BT.KOSKey(name)
  if not key or not ChainDB.kos then return false end
  local had = ChainDB.kos[key] ~= nil
  ChainDB.kos[key] = nil
  if BT.RenderWindow then BT.RenderWindow() end
  if BT.RefreshPlates then BT.RefreshPlates() end
  if BT.RefreshNearby then BT.RefreshNearby() end
  return had
end

-- A whole guild at once, which is usually how it actually goes
function BT.AddKOSGuild(guild, note)
  if type(guild) ~= "string" or guild == "" then return nil end
  ChainDB.kosGuilds = ChainDB.kosGuilds or {}
  local e = ChainDB.kosGuilds[guild] or { at = time() }
  e.guild = guild
  if note ~= nil then e.note = (note ~= "") and note or nil end
  ChainDB.kosGuilds[guild] = e
  if BT.RenderWindow then BT.RenderWindow() end
  if BT.RefreshPlates then BT.RefreshPlates() end
  if BT.RefreshNearby then BT.RefreshNearby() end
  return e
end

function BT.RemoveKOSGuild(guild)
  if not guild or not ChainDB.kosGuilds then return false end
  local had = ChainDB.kosGuilds[guild] ~= nil
  ChainDB.kosGuilds[guild] = nil
  if BT.RenderWindow then BT.RenderWindow() end
  if BT.RefreshPlates then BT.RefreshPlates() end
  if BT.RefreshNearby then BT.RefreshNearby() end
  return had
end

-- Is this one worth an alarm? Returns why, so the alert can say so rather
-- than leaving you to remember which of them you marked and when.
function BT.IsKOS(name, guild)
  local key = BT.KOSKey(name)
  if key and ChainDB.kos and ChainDB.kos[key] then
    return "named", ChainDB.kos[key].note
  end
  if guild and ChainDB.kosGuilds and ChainDB.kosGuilds[guild] then
    return "guild", ChainDB.kosGuilds[guild].note
  end
  return nil
end

function BT.KOSList()
  local out = {}
  for _, e in pairs(ChainDB.kos or {}) do table.insert(out, e) end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

function BT.KOSGuildList()
  local out = {}
  for _, e in pairs(ChainDB.kosGuilds or {}) do table.insert(out, e) end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

--------------------------------------------------------------------------
-- Who has been seen
--------------------------------------------------------------------------
-- Kept in the account-wide database so a name you met on one character is a
-- name you know on the next. Capped, because a busy world PvP evening puts
-- hundreds of people through here.
local MAX_SEEN = 400

function BT.NoteEnemy(name, info)
  if not ChainDB.watchEnemies then return nil end
  local key = BT.KOSKey(name)
  if not key then return nil end
  if key == BT.ShortName(UnitName and UnitName("player") or "") then return nil end

  ChainDB.enemies = ChainDB.enemies or {}
  local e = ChainDB.enemies[key]
  local now = time()
  local fresh = (not e) or ((now - (e.at or 0)) > NEARBY)
  e = e or { name = key, first = now, n = 0 }
  info = info or {}
  -- only ever fill in; a nameplate knows the level, the combat log does not,
  -- and the combat log must not erase what the nameplate told us
  e.class = info.class or e.class
  e.level = (info.level and info.level > 0) and info.level or e.level
  e.guild = info.guild or e.guild
  e.faction = info.faction or e.faction
  e.zone = info.zone or (GetRealZoneText and GetRealZoneText()) or e.zone
  e.how = info.how or e.how
  e.at = now
  e.n = (e.n or 0) + 1
  ChainDB.enemies[key] = e

  -- trim the oldest when it gets long
  local n = 0
  for _ in pairs(ChainDB.enemies) do n = n + 1 end
  if n > MAX_SEEN then
    local oldestKey, oldest
    for k, v in pairs(ChainDB.enemies) do
      if not oldest or (v.at or 0) < oldest then oldestKey, oldest = k, v.at or 0 end
    end
    if oldestKey then ChainDB.enemies[oldestKey] = nil end
  end

  if fresh then BT.EnemyAlert(e) end
  return e
end

-- Everyone seen lately, newest first
function BT.Nearby(within)
  local cut = time() - (within or NEARBY)
  local out = {}
  for _, e in pairs(ChainDB.enemies or {}) do
    if (e.at or 0) >= cut then table.insert(out, e) end
  end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

function BT.SeenList()
  local out = {}
  for _, e in pairs(ChainDB.enemies or {}) do table.insert(out, e) end
  table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
  return out
end

function BT.ForgetEnemies()
  ChainDB.enemies = {}
  if BT.RenderWindow then BT.RenderWindow() end
end

--------------------------------------------------------------------------
-- Saying so
--------------------------------------------------------------------------
function BT.EnemyAlert(e)
  local why, note = BT.IsKOS(e.name, e.guild)
  -- Ordinary players are only worth a line if you asked for it; the ones you
  -- marked are worth one whether or not you did.
  if not why and not ChainDB.alertEveryone then return end
  if ChainDB.enemyQuiet and (time() - (ChainDB.enemyQuiet[e.name] or 0)) < REALERT then
    return
  end
  ChainDB.enemyQuiet = ChainDB.enemyQuiet or {}
  ChainDB.enemyQuiet[e.name] = time()

  local what = e.name
  if e.level and e.level > 0 then what = what .. " " .. e.level end
  if e.class then what = what .. " " .. e.class end
  if why == "guild" and e.guild then what = what .. "  <" .. e.guild .. ">" end
  if note then what = what .. "  " .. note end

  if why then
    BT.EnemyBanner(C.bad .. "KOS   " .. what .. C.off, true)
    if ChainDB.enemySound and BT.Beep then BT.Beep("out") end
  else
    BT.EnemyBanner(C.warn .. what .. C.off, false)
  end
end

-- Its own line on screen rather than the reset banner's. A reset and a rogue
-- behind you are both worth saying, and neither should silence the other.
local eframe
function BT.EnemyBanner(text, loud)
  if not eframe then
    eframe = CreateFrame("Frame", "ChainEnemyBanner", UIParent)
    eframe:SetSize(520, 22)
    eframe:SetPoint("TOP", UIParent, "TOP", 0, -160)
    eframe:SetFrameStrata("HIGH")
    eframe.fs = eframe:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    eframe.fs:SetPoint("CENTER")
    eframe.t = 0
    eframe:SetScript("OnUpdate", function(self, elapsed)
      self.t = self.t + elapsed
      -- the marked ones pulse and stay twice as long. A line that behaves the
      -- same whether it is a passing stranger or the man who has killed you
      -- four times is a line you learn to ignore.
      if self.loud then
        local pulse = 0.6 + 0.4 * math.abs(math.sin(self.t * 4))
        self.fs:SetAlpha(pulse)
        if self.t > 12 then self:Hide() end
      else
        self.fs:SetAlpha(1)
        if self.t > 6 then self:Hide() end
      end
    end)
    eframe:Hide()
  end
  eframe.fs:SetText(text)
  eframe.t = 0
  eframe.loud = loud and true or false
  eframe:Show()
end

--------------------------------------------------------------------------
-- The watching
--------------------------------------------------------------------------
-- A unit token the client handed us: a nameplate, your target, your mouse.
-- Everything worth knowing is readable at that moment and nowhere else, so it
-- is all taken at once.
function BT.NoteUnit(unit, how)
  if not unit or not UnitExists or not UnitExists(unit) then return end
  if not UnitIsPlayer or not UnitIsPlayer(unit) then return end
  if UnitIsUnit and UnitIsUnit(unit, "player") then return end
  -- hostile only: the point is the other faction, not the people you are
  -- standing in a city with
  if UnitCanAttack and not UnitCanAttack("player", unit) then return end
  if UnitIsFriend and UnitIsFriend("player", unit) then return end

  local name = UnitName(unit)
  if not name then return end
  local level = UnitLevel and UnitLevel(unit) or nil
  local _, class = UnitClass and UnitClass(unit) or nil, nil
  if UnitClass then _, class = UnitClass(unit) end
  local guild = GetGuildInfo and GetGuildInfo(unit) or nil
  local faction = UnitFactionGroup and UnitFactionGroup(unit) or nil
  return BT.NoteEnemy(name, { level = level, class = class, guild = guild,
                              faction = faction, how = how })
end

-- The combat log reaches further than anything else: somebody casting two
-- rooms away is in it. It carries a name and whether they are hostile, and
-- nothing else, which is why the nameplate's level is never overwritten.
local HOSTILE = 0x00000040          -- COMBATLOG_OBJECT_REACTION_HOSTILE
local PLAYER_TYPE = 0x00000400      -- COMBATLOG_OBJECT_TYPE_PLAYER

local function IsPlayerGUID(guid)
  return type(guid) == "string" and guid:sub(1, 7) == "Player-"
end

function BT.NoteCombatLogUnit(guid, name, flags)
  if not ChainDB.watchEnemies then return end
  if not IsPlayerGUID(guid) or not name then return end
  if not bit or not flags then return end
  if bit.band(flags, PLAYER_TYPE) == 0 then return end
  if bit.band(flags, HOSTILE) == 0 then return end
  BT.NoteEnemy(name, { how = "combat log" })
end

local f = CreateFrame("Frame", "ChainEnemyFrame")
BT.enemyFrame = f
f:SetScript("OnEvent", function(_, event, arg1)
  if not ChainDB or not ChainDB.watchEnemies then return end
  if event == "NAME_PLATE_UNIT_ADDED" then
    BT.NoteUnit(arg1, "nameplate")
    if BT.MarkPlate then BT.MarkPlate(arg1) end
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    if BT.UnmarkPlate then BT.UnmarkPlate(arg1) end
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    BT.NoteUnit("mouseover", "mouseover")
  elseif event == "PLAYER_TARGET_CHANGED" then
    BT.NoteUnit("target", "target")
  elseif event == "UNIT_FACTION" then
    BT.NoteUnit(arg1, "faction")
  end
end)
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
                     "UPDATE_MOUSEOVER_UNIT",
                     "PLAYER_TARGET_CHANGED", "UNIT_FACTION" }) do
  f:RegisterEvent(e)
end

--------------------------------------------------------------------------
-- The list on screen
--------------------------------------------------------------------------
-- The tab is for reading afterwards. This is for right now: who is close
-- enough to matter, in the order they turned up, small enough to live in a
-- corner and be glanced at rather than read.
--
-- Everything the client told us is on the tooltip instead of in the row.
-- A row you have to parse is a row you look away from, and looking away is
-- the thing this is meant to stop.

local NEAR_ROWS = 8
local nearby

local CLASS_COLOUR = {
  WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 },
  HUNTER  = { 0.67, 0.83, 0.45 }, ROGUE   = { 1.00, 0.96, 0.41 },
  PRIEST  = { 1.00, 1.00, 1.00 }, SHAMAN  = { 0.00, 0.44, 0.87 },
  MAGE    = { 0.41, 0.80, 0.94 }, WARLOCK = { 0.58, 0.51, 0.79 },
  DRUID   = { 1.00, 0.49, 0.04 }
}

local function RowTooltip(self)
  local e = self.rec
  if not e then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(e.name, 1, 0.82, 0)

  local line = ""
  if e.level and e.level > 0 then line = "level " .. e.level
  else line = "level unknown" end
  if e.class then line = line .. "  " .. e.class end
  GameTooltip:AddLine(line, 1, 1, 1)
  if e.guild then GameTooltip:AddLine("<" .. e.guild .. ">", 0.7, 0.7, 0.7) end
  if e.faction then GameTooltip:AddLine(e.faction, 0.7, 0.7, 0.7) end

  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("last seen", BT.T(time() - (e.at or time())) .. " ago",
                            0.7, 0.7, 0.7, 1, 1, 1)
  GameTooltip:AddDoubleLine("seen", (e.n or 1) .. " time"
    .. ((e.n or 1) == 1 and "" or "s"), 0.7, 0.7, 0.7, 1, 1, 1)
  if e.first then
    GameTooltip:AddDoubleLine("first met", BT.T(time() - e.first) .. " ago",
                              0.7, 0.7, 0.7, 1, 1, 1)
  end
  if e.zone then
    GameTooltip:AddDoubleLine("in", e.zone, 0.7, 0.7, 0.7, 1, 1, 1)
  end
  if e.how then
    GameTooltip:AddDoubleLine("spotted by", e.how, 0.7, 0.7, 0.7, 0.6, 0.6, 0.6)
  end

  local why, note = BT.IsKOS(e.name, e.guild)
  if why then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(why == "guild" and "marked through his guild"
                                        or "marked by name", 1, 0.3, 0.3)
    if note then GameTooltip:AddLine(note, 1, 1, 1, true) end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(why and "Click: clear the mark" or "Click: mark kill on sight",
                      0.4, 0.7, 1)
  GameTooltip:Show()
end

function BT.BuildNearby()
  if nearby then return nearby end
  nearby = CreateFrame("Frame", "ChainNearby", UIParent)
  nearby:SetSize(176, 22 + NEAR_ROWS * 14)
  local pos = ChainDB.nearbyPos
  if pos then
    nearby:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER",
                    pos.x or 0, pos.y or 0)
  else
    nearby:SetPoint("RIGHT", UIParent, "RIGHT", -220, 120)
  end
  nearby:SetMovable(true)
  nearby:EnableMouse(true)
  nearby:RegisterForDrag("LeftButton")
  nearby:SetScript("OnDragStart", nearby.StartMoving)
  nearby:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint()
    ChainDB.nearbyPos = { point = point, x = x, y = y }
  end)

  nearby.bg = nearby:CreateTexture(nil, "BACKGROUND")
  nearby.bg:SetAllPoints()
  if nearby.bg.SetColorTexture then
    nearby.bg:SetColorTexture(0, 0, 0, 0.55)
  else
    nearby.bg:SetTexture(0, 0, 0, 0.55)
  end

  nearby.title = nearby:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nearby.title:SetPoint("TOPLEFT", 6, -5)

  nearby.rows = {}
  for i = 1, NEAR_ROWS do
    local row = CreateFrame("Button", nil, nearby)
    row:SetSize(164, 13)
    row:SetPoint("TOPLEFT", 6, -20 - (i - 1) * 14)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWidth(120)
    row.lvl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.lvl:SetPoint("RIGHT", 0, 0)
    row.lvl:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
      local e = self.rec
      if not e then return end
      local why = BT.IsKOS(e.name, e.guild)
      if why == "named" then BT.RemoveKOS(e.name)
      elseif why == "guild" then BT.RemoveKOSGuild(e.guild)
      else BT.AddKOS(e.name) end
      BT.RefreshNearby()
      RowTooltip(self)
    end)
    row:Hide()
    nearby.rows[i] = row
  end
  nearby:Hide()
  return nearby
end

function BT.RefreshNearby()
  if ChainDB.nearbyList == false or not ChainDB.watchEnemies then
    if nearby then nearby:Hide() end
    return
  end
  BT.BuildNearby()
  local list = BT.Nearby(ChainDB.nearbySeconds or NEARBY)
  if #list == 0 then
    nearby:Hide()
    return
  end
  nearby.title:SetText(C.warn .. #list .. " nearby" .. C.off)
  for i = 1, NEAR_ROWS do
    local row = nearby.rows[i]
    local e = list[i]
    if e then
      row.rec = e
      local col = e.class and CLASS_COLOUR[e.class] or { 0.8, 0.8, 0.8 }
      local why = BT.IsKOS(e.name, e.guild)
      row.name:SetText((why and "|cffff2020* |r" or "") .. e.name)
      row.name:SetTextColor(col[1], col[2], col[3])
      row.lvl:SetText((e.level and e.level > 0) and tostring(e.level) or "?")
      -- faded as the sighting gets old, so the top of the list is the one
      -- that is actually still there
      local age = time() - (e.at or time())
      local a = 1 - math.min(0.6, age / (ChainDB.nearbySeconds or NEARBY))
      row.name:SetAlpha(a)
      row.lvl:SetAlpha(a)
      row:Show()
    else
      row.rec = nil
      row:Hide()
    end
  end
  nearby:SetHeight(22 + math.min(NEAR_ROWS, #list) * 14)
  nearby:Show()
end

function BT.ToggleNearby()
  ChainDB.nearbyList = (ChainDB.nearbyList == false)
  BT.RefreshNearby()
  return ChainDB.nearbyList
end

-- The list has to fade on its own: somebody who walked away stops being
-- nearby without any event to say so.
local tick = 0
f:SetScript("OnUpdate", function(_, elapsed)
  tick = tick + elapsed
  if tick < 1 then return end
  tick = 0
  if BT.RefreshNearby then BT.RefreshNearby() end
end)

--------------------------------------------------------------------------
-- On the nameplate itself
--------------------------------------------------------------------------
-- A line at the top of the screen tells you somebody is here. It does not
-- tell you which of the four people in front of you it is. The mark does, and
-- it sits where you are already looking.
--
-- Attached to the nameplate the client hands us and taken off again when it
-- goes. Nothing is reparented, resized or hidden: the plate is Blizzard's and
-- whatever else you run is welcome to it.
local marks = {}

local function MarkFor(plate)
  if marks[plate] then return marks[plate] end
  local m = CreateFrame("Frame", nil, plate)
  m:SetSize(52, 16)
  m:SetPoint("BOTTOM", plate, "TOP", 0, 4)
  m:SetFrameStrata("HIGH")
  m.bg = m:CreateTexture(nil, "BACKGROUND")
  m.bg:SetAllPoints()
  if m.bg.SetColorTexture then m.bg:SetColorTexture(0.55, 0.05, 0.05, 0.85)
  else m.bg:SetTexture(0.55, 0.05, 0.05, 0.85) end
  m.fs = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  m.fs:SetPoint("CENTER")
  m.fs:SetText("|cffffffffKOS|r")
  marks[plate] = m
  return m
end

function BT.MarkPlate(unit)
  if not unit or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not plate then return end
  local name = UnitName and UnitName(unit)
  local guild = GetGuildInfo and GetGuildInfo(unit) or nil
  local why = name and BT.IsKOS(name, guild) or nil
  if why then
    local m = MarkFor(plate)
    m.fs:SetText(why == "guild" and "|cffffffffKOS|r" or "|cffffffffKOS|r")
    m:Show()
  elseif marks[plate] then
    marks[plate]:Hide()
  end
end

function BT.UnmarkPlate(unit)
  if not unit or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if plate and marks[plate] then marks[plate]:Hide() end
end

-- Marking somebody while his plate is already up should show immediately,
-- rather than the next time he walks away and comes back.
function BT.RefreshPlates()
  if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    if plate.namePlateUnitToken then BT.MarkPlate(plate.namePlateUnitToken) end
  end
end
