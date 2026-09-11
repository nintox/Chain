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
  if info.level and info.level > 0 then
    -- seeing them settles it, whatever an ability suggested
    e.level, e.levelGuess = info.level, nil
  end
  e.guild = info.guild or e.guild
  e.faction = info.faction or e.faction
  e.race = info.race or e.race
  if info.stealth ~= nil then e.stealth = info.stealth end
  e.zone = info.zone or (GetRealZoneText and GetRealZoneText()) or e.zone
  -- where you were standing when you saw them. Not where they were - there is
  -- no way to know that - but close enough to go back and look.
  if BT.MyPosition then
    local _, px, py = BT.MyPosition()
    if px and py then e.x, e.y = px, py end
  end
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
  if e.class then what = what .. " " .. BT.ClassLabel(e.class) end
  if why == "guild" and e.guild then what = what .. "  <" .. e.guild .. ">" end
  if note then what = what .. "  " .. note end

  if why then
    BT.EnemyBanner(C.bad .. "KOS   " .. what .. C.off, true)
    if ChainDB.enemySound and BT.Beep then BT.Beep("out") end
    -- and tell the people who can do something about it, if you asked us to
    if ChainDB.announceKOS then BT.AnnounceSighting(e) end
  else
    BT.EnemyBanner(C.warn .. what .. C.off, false)
  end
end

-- Somebody stealthed, in the middle of the screen.
--
-- This one gets its own alert and its own place, because it is the only
-- sighting where knowing is the whole of the advantage. A rogue you have seen
-- is a rogue who has lost the opening, and the top of the screen is where you
-- are not looking when you are being opened on.
--
-- A stealthed player is spotted the moment the client renders them at all -
-- a nameplate, a target, a combat-log line - which in practice means they are
-- already close, or they have just broken stealth on somebody.
local sframe
function BT.StealthBanner(text)
  if not sframe then
    sframe = CreateFrame("Frame", "ChainStealthBanner", UIParent)
    sframe:SetSize(560, 40)
    -- above the middle, clear of the cast bar and clear of the reset banner
    sframe:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    sframe:SetFrameStrata("FULLSCREEN_DIALOG")
    sframe.fs = sframe:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    sframe.fs:SetPoint("CENTER")
    sframe.t = 0
    sframe:SetScript("OnUpdate", function(self, elapsed)
      self.t = self.t + elapsed
      -- a hard pulse: this is the one alert that is allowed to be rude
      self.fs:SetAlpha(0.45 + 0.55 * math.abs(math.sin(self.t * 5)))
      local grow = 1 + 0.05 * math.max(0, 1 - self.t * 2)
      self.fs:SetScale(grow)
      if self.t > 8 then self:Hide() end
    end)
    sframe:Hide()
  end
  sframe.fs:SetText(text)
  sframe.t = 0
  sframe:Show()
  return sframe
end
BT.stealthBanner = function() return sframe end

function BT.StealthAlert(e)
  if ChainDB.stealthAlert == false then return end
  if not e or not e.name then return end
  ChainDB.stealthQuiet = ChainDB.stealthQuiet or {}
  if (time() - (ChainDB.stealthQuiet[e.name] or 0)) < REALERT then return end
  ChainDB.stealthQuiet[e.name] = time()

  local why = BT.IsKOS(e.name, e.guild)
  local what = e.name
  if e.level and e.level > 0 then what = what .. "  " .. e.level end
  if e.class then what = what .. "  " .. BT.ClassLabel(e.class) end
  BT.StealthBanner((why and C.bad or C.warn) .. "STEALTH   " .. what
    .. (why and "   KOS" or "") .. C.off)
  if BT.Beep then BT.Beep("out") end
  return true
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
  -- Stealth is read from the aura list rather than guessed from the class: a
  -- rogue standing in front of you is not the same news as a rogue who is
  -- still stealthed, and half the ones who matter are druids anyway.
  local stealth = BT.IsStealthed and BT.IsStealthed(unit) or nil
  local e = BT.NoteEnemy(name, { level = level, class = class, guild = guild,
                                 faction = faction, how = how,
                                 stealth = stealth })
  if stealth and e then BT.StealthAlert(e) end
  return e
end

-- Every unit the client will actually hand us a level for. The combat log
-- reaches furthest but carries no level; these carry one, and between them
-- they cover most of the people you are in a fight with rather than only the
-- one you happen to be pointing at.
local SCAN = {
  "target", "targettarget", "mouseover", "mouseovertarget",
  "focus", "focustarget", "pettarget",
}
function BT.ScanUnits(how)
  if not ChainDB.watchEnemies then return 0 end
  local n = 0
  for _, u in ipairs(SCAN) do
    if BT.NoteUnit(u, how or "seen") then n = n + 1 end
  end
  -- and whoever the rest of the group is swinging at
  local party = (IsInRaid and IsInRaid()) and "raid" or "party"
  local size = (party == "raid") and 40 or 4
  for i = 1, size do
    if BT.NoteUnit(party .. i .. "target", how or "group's target") then
      n = n + 1
    end
  end
  return n
end

-- Is that unit stealthed right now? The buff is the honest signal; there is
-- no API that simply says so.
local STEALTH_SPELLS = {
  ["Stealth"] = true, ["Prowl"] = true, ["Shadowmeld"] = true,
  ["Invisibility"] = true, ["Lesser Invisibility"] = true,
}
function BT.IsStealthed(unit)
  if not unit or not UnitAura then return nil end
  for i = 1, 40 do
    local name = UnitAura(unit, i, "HELPFUL")
    if not name then break end
    if STEALTH_SPELLS[name] then return true end
  end
  return nil
end

-- The combat log reaches further than anything else: somebody casting two
-- rooms away is in it. It carries a name and whether they are hostile, and
-- nothing else, which is why the nameplate's level is never overwritten.
local HOSTILE = 0x00000040          -- COMBATLOG_OBJECT_REACTION_HOSTILE
local PLAYER_TYPE = 0x00000400      -- COMBATLOG_OBJECT_TYPE_PLAYER

local function IsPlayerGUID(guid)
  return type(guid) == "string" and guid:sub(1, 7) == "Player-"
end

-- What an ability tells you about whoever used it.
--
-- A spell rank cannot be cast below the level it is learned at, so seeing one
-- puts a floor under somebody you have never laid eyes on. It is a floor and
-- nothing more - a level 60 casting Rank 1 Frostbolt still reads as 4+ - so
-- it is stored as a guess and shown with a "+" rather than pretending to be
-- the level.
--
-- The table is Spy's. It is read from its global if Spy is loaded, exactly
-- the way Nova Instance Tracker's count is read: nothing is copied, nothing
-- is shipped, and if Spy is not there this simply does nothing. Building our
-- own is three thousand rows of game data and a job of its own.
function BT.AbilityInfo(spellId)
  if not spellId then return nil end
  local list = _G.Spy_AbilityList
  if type(list) ~= "table" then return nil end
  local a = list[spellId]
  if type(a) ~= "table" then return nil end
  return a.level, a.class, a.race
end

function BT.HasAbilityData()
  return type(_G.Spy_AbilityList) == "table"
end

function BT.NoteCombatLogUnit(guid, name, flags, spellId)
  if not ChainDB.watchEnemies then return end
  if not IsPlayerGUID(guid) or not name then return end
  if not bit or not flags then return end
  if bit.band(flags, PLAYER_TYPE) == 0 then return end
  if bit.band(flags, HOSTILE) == 0 then return end

  -- The combat log itself carries no class, which is why everyone found this
  -- way used to sit in the list as a grey name with a question mark. The GUID
  -- is enough to ask the client, though: it knows the class and race of any
  -- player it has seen, whether or not they are on screen now. Level it does
  -- not know, and that stays a question mark honestly rather than guessed.
  local class, race
  if GetPlayerInfoByGUID then
    local _, englishClass, _, englishRace = GetPlayerInfoByGUID(guid)
    if englishClass and englishClass ~= "" then class = englishClass end
    if englishRace and englishRace ~= "" then race = englishRace end
  end
  -- and what the ability they just used says about them
  local lvl, aClass, aRace
  if spellId then lvl, aClass, aRace = BT.AbilityInfo(spellId) end

  BT.NoteEnemy(name, { how = "combat log", class = class or aClass,
                       race = race or aRace })
  -- the level is its own step: it is a floor rather than a fact, and it may
  -- only ever be raised
  if lvl then BT.NoteAbilityLevel(name, lvl) end
end

-- A floor only rises. Two abilities seen, the higher one wins; and a level we
-- actually saw with our own eyes always beats a guess.
function BT.NoteAbilityLevel(name, lvl)
  local key = BT.KOSKey(name)
  local e = key and ChainDB.enemies and ChainDB.enemies[key]
  if not e or not lvl or lvl <= 0 then return nil end
  if e.level and not e.levelGuess then return nil end       -- seen beats guessed
  if e.level and e.level >= lvl then return nil end
  e.level, e.levelGuess = lvl, true
  if BT.RefreshNearby then BT.RefreshNearby() end
  return lvl
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
    BT.ScanUnits("seen")
  elseif event == "UNIT_TARGET" then
    BT.ScanUnits("group's target")
  elseif event == "UNIT_FACTION" then
    BT.NoteUnit(arg1, "faction")
  end
end)
for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
                     "UPDATE_MOUSEOVER_UNIT",
                     "PLAYER_TARGET_CHANGED", "UNIT_FACTION",
                     "UNIT_TARGET" }) do
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

local NEAR_ROWS = 8          -- the default; ChainDB.nearbyRows overrides it
local NEAR_W    = 176        -- and ChainDB.nearbyWidth overrides this
local RIGHT_W   = 74         -- room kept for "45 Warrior" on the right
local NEAR_MAX  = 20         -- as many row frames as we ever build
local ROW_H     = 14

-- How many rows to actually show, and which way the list grows from where you
-- put it. Both are yours: a list that grows down is wrong if you have parked
-- it at the bottom of the screen.
local function NearRows()
  return math.max(1, math.min(NEAR_MAX, math.floor(ChainDB.nearbyRows or NEAR_ROWS)))
end
local function GrowUp() return ChainDB.nearbyGrow == "up" end
-- Bigger than the game's default small font, because this is read at a glance
-- in the two seconds before a fight rather than studied.
local function NearScale()
  return math.max(0.7, math.min(2, tonumber(ChainDB.nearbyScale) or 1.15))
end

local function NearWidth()
  return math.max(120, math.min(420, math.floor(ChainDB.nearbyWidth or NEAR_W)))
end
local nearby

local CLASS_COLOUR = {
  WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 },
  HUNTER  = { 0.67, 0.83, 0.45 }, ROGUE   = { 1.00, 0.96, 0.41 },
  PRIEST  = { 1.00, 1.00, 1.00 }, SHAMAN  = { 0.00, 0.44, 0.87 },
  MAGE    = { 0.41, 0.80, 0.94 }, WARLOCK = { 0.58, 0.51, 0.79 },
  DRUID   = { 1.00, 0.49, 0.04 }
}

-- The class in words, short enough for a narrow row. The client's own
-- localised name where there is one, so a Norwegian client says what a
-- Norwegian player expects.
local CLASS_SHORT = {
  WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter",
  ROGUE = "Rogue", PRIEST = "Priest", SHAMAN = "Shaman",
  MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid"
}
function BT.ClassLabel(class)
  if not class then return "?" end
  local loc = _G.LOCALIZED_CLASS_NAMES_MALE
  if loc and loc[class] then return loc[class] end
  return CLASS_SHORT[class] or class
end

--------------------------------------------------------------------------
-- Who beat whom
--------------------------------------------------------------------------
-- The one piece of history about another player that is genuinely yours: the
-- server will not tell you anything about them, but it will tell you who
-- stopped moving. Kills you or your group made, and deaths they caused.
--
-- A death is credited to whoever hit you last, inside a short window. It is
-- not perfect - in a five-man gank the killing blow is arbitrary - but it is
-- the same thing you would remember yourself, and it is the number you
-- actually want when the name comes past again.
local LAST_HIT = 15

function BT.NoteFight(sub, src, srcName, srcFlags, dst, dstName, dstFlags)
  if not sub or not bit then return end
  local myGUID = UnitGUID and UnitGUID("player") or nil

  -- somebody hit us: remember who, so a death can be blamed on them
  if dst and myGUID and dst == myGUID and src and src ~= myGUID
     and srcName and srcFlags
     and bit.band(srcFlags, PLAYER_TYPE) ~= 0
     and bit.band(srcFlags, HOSTILE) ~= 0 then
    local key = BT.KOSKey(srcName)
    if key then BT.lastHitBy, BT.lastHitAt = key, time() end
  end

  if sub ~= "PARTY_KILL" and sub ~= "UNIT_DIED" then return end

  if sub == "PARTY_KILL" then
    -- you or your group killed them
    if not dstName or not dstFlags then return end
    if bit.band(dstFlags, PLAYER_TYPE) == 0 then return end
    if bit.band(dstFlags, HOSTILE) == 0 then return end
    local key = BT.KOSKey(dstName)
    local e = key and ChainDB.enemies and ChainDB.enemies[key]
    if e then
      e.wins = (e.wins or 0) + 1
      e.lastFight = time()
      if BT.RefreshNearby then BT.RefreshNearby() end
    end
    return
  end

  -- UNIT_DIED on us: blame whoever hit us last, if it was recent
  if not myGUID or dst ~= myGUID then return end
  if not BT.lastHitBy or (time() - (BT.lastHitAt or 0)) > LAST_HIT then return end
  local e = ChainDB.enemies and ChainDB.enemies[BT.lastHitBy]
  if e then
    e.losses = (e.losses or 0) + 1
    e.lastFight = time()
    if BT.RefreshNearby then BT.RefreshNearby() end
  end
  BT.lastHitBy = nil
end

--------------------------------------------------------------------------
-- Telling your own side
--------------------------------------------------------------------------
-- There was a /who lookup here, to fill in the levels that sit at "??". It is
-- gone, because it could never have worked: /who only ever returns players of
-- your own faction, and everybody in this list is on the other one. A button
-- that looks like a feature and quietly does nothing is worse than no button.
--
-- The same goes for whispering them. Cross-faction whispers do not exist.
--
-- What you *can* do is tell your own side, which is the useful half anyway:
-- a name, a level if you have one, a class, and where you are standing.
function BT.MyPosition()
  local zone = (GetRealZoneText and GetRealZoneText())
            or (GetZoneText and GetZoneText()) or nil
  local sub = GetSubZoneText and GetSubZoneText() or nil
  if sub == "" then sub = nil end
  local x, y
  if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
    local id = C_Map.GetBestMapForUnit("player")
    if id then
      local pos = C_Map.GetPlayerMapPosition(id, "player")
      if pos and pos.GetXY then
        local px, py = pos:GetXY()
        if px and py and (px > 0 or py > 0) then x, y = px * 100, py * 100 end
      end
    end
  end
  return zone, x, y, sub
end

-- Where it goes. "auto" is the right answer almost always: the people who can
-- do something about it are whoever you are actually with.
function BT.SightChannel(pref)
  pref = pref or ChainDB.sightChannel or "auto"
  if pref ~= "auto" then return pref:upper() end
  if IsInRaid and IsInRaid() then return "RAID" end
  if IsInGroup and IsInGroup() then return "PARTY" end
  if IsInGuild and IsInGuild() then return "GUILD" end
  return "SAY"
end

function BT.SightingText(e)
  if not e or not e.name then return nil end
  local who = e.name
  if e.level and e.level > 0 then who = who .. " " .. e.level end
  if e.class then who = who .. " " .. BT.ClassLabel(e.class) end
  if e.guild then who = who .. " <" .. e.guild .. ">" end
  if BT.IsKOS(e.name, e.guild) then who = who .. " [KOS]" end

  local zone, x, y, sub = BT.MyPosition()
  local where = sub or zone
  if where and zone and sub then where = sub .. ", " .. zone end
  local txt = who
  if where then txt = txt .. " - " .. where end
  if x and y then txt = txt .. string.format(" (%.0f, %.0f)", x, y) end
  return txt
end

-- Throttled per player, like the banner: the same rogue running past three
-- times is one line in party chat, not three.
function BT.AnnounceSighting(e, chan, force)
  if not e or not SendChatMessage then return nil end
  ChainDB.sightQuiet = ChainDB.sightQuiet or {}
  if not force and (time() - (ChainDB.sightQuiet[e.name] or 0)) < REALERT then
    return nil
  end
  local text = BT.SightingText(e)
  if not text then return nil end
  chan = chan or BT.SightChannel()
  ChainDB.sightQuiet[e.name] = time()
  SendChatMessage("Spotted: " .. text, chan)
  return text, chan
end

local function RowTooltip(self)
  local e = self.rec
  if not e then return end
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:AddLine(e.name, 1, 0.82, 0)

  if e.guild then GameTooltip:AddLine(e.guild, 0.6, 0.9, 0.6) end
  -- "Level 45 Orc Warrior", the way the game says it everywhere else
  local bits = {}
  if e.level and e.level > 0 then
    table.insert(bits, "Level " .. e.level .. (e.levelGuess and "+" or ""))
  else table.insert(bits, "Level unknown") end
  if e.race then table.insert(bits, e.race) end
  if e.class then table.insert(bits, BT.ClassLabel(e.class)) end
  GameTooltip:AddLine(table.concat(bits, " "), 1, 1, 1)
  if e.faction then GameTooltip:AddLine(e.faction, 0.7, 0.7, 0.7) end

  -- Your own score against them. Nobody else can tell you this, which is
  -- exactly why it is worth keeping.
  if (e.wins or 0) > 0 or (e.losses or 0) > 0 then
    GameTooltip:AddDoubleLine("you " .. (e.wins or 0) .. "  -  " .. (e.losses or 0)
      .. " them",
      (e.losses or 0) > (e.wins or 0) and "he is winning" or
      (e.wins or 0) > (e.losses or 0) and "you are winning" or "even",
      (e.wins or 0) >= (e.losses or 0) and 0.4 or 1,
      (e.wins or 0) >= (e.losses or 0) and 1 or 0.4, 0.4,
      0.7, 0.7, 0.7)
  end

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
    GameTooltip:AddDoubleLine("in", e.zone
      .. ((e.x and e.y) and string.format("  (%.0f, %.0f)", e.x, e.y) or ""),
      0.7, 0.7, 0.7, 1, 1, 1)
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
  if e.stealth then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("was stealthed when spotted", 0.7, 0.5, 1)
  end
  GameTooltip:AddLine(" ")
  if e.levelGuess then
    GameTooltip:AddLine("at least that - from an ability they used",
                        0.5, 0.5, 0.5)
  elseif not e.level or e.level <= 0 then
    GameTooltip:AddLine("no level: you have not actually seen them yet",
                        0.5, 0.5, 0.5)
  end
  GameTooltip:AddLine(why and "Click: clear the mark" or "Click: mark kill on sight",
                      0.4, 0.7, 1)
  GameTooltip:AddLine("Right-click: note, call out, and the rest", 0.4, 0.7, 1)
  GameTooltip:Show()
end

-- Where the frame hangs. Always absolute against the screen's bottom-left
-- corner, anchored by its top when the list grows down and by its bottom when
-- it grows up - so the edge you parked stays put and the list grows away from
-- it rather than dragging the whole box about.
-- A plain local, not a field on the frame. A widget answers any name you ask
-- it for with a function, so nearby.dragging reads as "yes" forever - which is
-- the same trap the bar's tick list fell into.
local dragging = false
local sizing = false

local function AnchorNearby()
  if not nearby then return end
  -- Never while it is under the cursor. The list refreshes on a timer, and
  -- re-applying the anchor mid-drag yanks the frame out from under the mouse
  -- a few times a second - which is exactly what "it jumps about and will not
  -- sit still" is.
  if dragging or sizing then return end
  local pos = ChainDB.nearbyPos or {}
  nearby:ClearAllPoints()
  nearby:SetPoint(GrowUp() and "BOTTOMLEFT" or "TOPLEFT",
                  UIParent, "BOTTOMLEFT", pos.x or 900, pos.y or 500)
end

-- Read back in UIParent's units. The ratio is one today, because the list
-- hangs off UIParent and has no scale of its own - but mixing a frame's own
-- coordinates with a parent's anchor is the bug that turns up the day either
-- of those stops being true.
local function SaveNearbyPos()
  if not nearby or not nearby.GetLeft or not nearby:GetLeft() then return end
  local r = 1
  if nearby.GetEffectiveScale and UIParent and UIParent.GetEffectiveScale then
    local mine = nearby:GetEffectiveScale() or 1
    local theirs = UIParent:GetEffectiveScale() or 1
    if theirs > 0 then r = mine / theirs end
  end
  ChainDB.nearbyPos = {
    x = nearby:GetLeft() * r,
    y = (GrowUp() and nearby:GetBottom() or nearby:GetTop()) * r
  }
end

-- Dragging is started from anywhere on the list, not only from the thin strip
-- of background the rows leave uncovered. The rows fill almost the whole box,
-- so "grab it and move it" meant finding two pixels of title bar.
local function BeginDrag()
  if not nearby or ChainDB.nearbyLocked then return end
  dragging = true
  nearby:StartMoving()
end

local function EndDrag()
  if not nearby or not dragging then return end
  nearby:StopMovingOrSizing()
  dragging = false
  SaveNearbyPos()
  AnchorNearby()
end
function BT.NearbyDragging() return dragging end

function BT.ResetNearbyPos()
  ChainDB.nearbyPos = nil
  AnchorNearby()
  return true
end

-- Switching direction must not make the box jump: take the edge that is about
-- to become the anchor from where the frame is standing right now.
function BT.SetNearbyGrow(dir)
  dir = (dir == "up") and "up" or "down"
  if nearby and nearby.GetLeft and nearby:GetLeft() then
    ChainDB.nearbyPos = {
      x = nearby:GetLeft(),
      y = (dir == "up") and nearby:GetBottom() or nearby:GetTop()
    }
  end
  ChainDB.nearbyGrow = dir
  AnchorNearby()
  BT.RefreshNearby()
  return dir
end

function BT.ToggleNearbyLock()
  ChainDB.nearbyLocked = not ChainDB.nearbyLocked
  return ChainDB.nearbyLocked
end

function BT.SetNearbyScale(v)
  v = tonumber(v)
  if not v then return NearScale() end
  ChainDB.nearbyScale = math.max(0.7, math.min(2, v))
  if nearby then nearby:SetScale(ChainDB.nearbyScale) end
  BT.RefreshNearby()
  return ChainDB.nearbyScale
end

function BT.SetNearbyRows(n)
  n = tonumber(n)
  if not n then return NearRows() end
  ChainDB.nearbyRows = math.max(1, math.min(NEAR_MAX, math.floor(n)))
  BT.RefreshNearby()
  return ChainDB.nearbyRows
end

--------------------------------------------------------------------------
-- The little menu on right-click
--------------------------------------------------------------------------
-- Hand-rolled rather than the game's dropdown: three items, no library, and
-- it cannot be broken by another addon replacing UIDropDownMenu.
local menu
local MENU_MAX = 9
local function BuildMenu()
  if menu then return menu end
  menu = CreateFrame("Frame", "ChainNearbyMenu", UIParent)
  menu:SetSize(172, 8 + MENU_MAX * 18)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu.edge = menu:CreateTexture(nil, "BACKGROUND")
  menu.edge:SetPoint("TOPLEFT", -1, 1)
  menu.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  menu.bg = menu:CreateTexture(nil, "BACKGROUND")
  menu.bg:SetAllPoints()
  if menu.bg.SetColorTexture then
    menu.edge:SetColorTexture(0.3, 0.3, 0.35, 1)
    menu.bg:SetColorTexture(0.05, 0.05, 0.06, 0.98)
  end
  menu.bg:SetDrawLayer("BACKGROUND", 2)
  menu:EnableMouse(true)

  menu.head = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  menu.head:SetPoint("TOPLEFT", 8, -5)
  menu.head:SetJustifyH("LEFT")

  menu.items = {}
  for i = 1, MENU_MAX do
    local b = CreateFrame("Button", nil, menu)
    b:SetSize(164, 18)
    b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 18)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    if b.bg.SetColorTexture then b.bg:SetColorTexture(0, 0, 0, 0) end
    b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.fs:SetPoint("LEFT", 6, 0)
    b.fs:SetJustifyH("LEFT")
    b:SetScript("OnEnter", function(self)
      if self.bg.SetColorTexture then self.bg:SetColorTexture(0.25, 0.25, 0.35, 0.9) end
    end)
    b:SetScript("OnLeave", function(self)
      if self.bg.SetColorTexture then self.bg:SetColorTexture(0, 0, 0, 0) end
    end)
    menu.items[i] = b
  end
  menu:Hide()
  return menu
end

-- One menu, whatever it was opened on. Items are {text, fn}; a nil entry is a
-- gap, which is how the player's own actions are kept apart from the list's.
local function ShowMenu(title, items, anchorTo)
  BuildMenu()
  local top = 4
  if title then
    menu.head:SetText(title)
    menu.head:Show()
    top = 22
  else
    menu.head:Hide()
  end
  local n = 0
  for _, it in ipairs(items) do
    if n >= MENU_MAX then break end
    n = n + 1
    local b = menu.items[n]
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 4, -top - (n - 1) * 18)
    if it.gap then
      b.fs:SetText(C.dim .. "................." .. C.off)
      b:SetScript("OnClick", nil)
      b:EnableMouse(false)
    else
      b.fs:SetText(it.text)
      b:EnableMouse(true)
      b:SetScript("OnClick", function()
        it.fn()
        menu:Hide()
      end)
    end
    b:Show()
  end
  for i = n + 1, MENU_MAX do menu.items[i]:Hide() end
  menu:SetHeight(top + n * 18 + 4)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchorTo or nearby, "BOTTOMLEFT", 0, -2)
  menu:Show()
  return menu
end
BT.ShowNearbyMenu = ShowMenu

-- The list's own settings
local function ListItems()
  return {
    { text = GrowUp() and (C.good .. "Grows up" .. C.off .. C.dim .. " - flip" .. C.off)
                      or (C.good .. "Grows down" .. C.off .. C.dim .. " - flip" .. C.off),
      fn = function() BT.SetNearbyGrow(GrowUp() and "down" or "up") end },
    { text = ChainDB.nearbyLocked
             and (C.warn .. "Locked" .. C.off .. C.dim .. " - unlock" .. C.off)
             or (C.dim .. "Unlocked" .. C.off .. " - lock"),
      fn = function() BT.ToggleNearbyLock() end },
    { text = "Size" .. C.dim .. "  " .. math.floor(NearScale() * 100)
             .. "%  - bigger" .. C.off,
      fn = function()
        local steps = { 0.9, 1, 1.15, 1.3, 1.5 }
        local now, at = NearScale(), 1
        for i, v in ipairs(steps) do if math.abs(v - now) < 0.02 then at = i end end
        BT.SetNearbyScale(steps[(at % #steps) + 1])
      end },
    { text = "Back to the middle", fn = function() BT.ResetNearbyPos() end },
    { text = "Hide the list", fn = function() BT.ToggleNearby() end },
  }
end

function BT.NearbyMenu()
  return ShowMenu(nil, ListItems())
end

-- Right-click on somebody: everything you might actually want to do about
-- them, in one place. Marking is the first item because it is the reason the
-- list exists.
function BT.PlayerMenu(e, anchorTo)
  if not e then return BT.NearbyMenu() end
  local why = BT.IsKOS(e.name, e.guild)
  local items = {}

  if why == "named" then
    items[#items + 1] = { text = C.good .. "Unmark " .. e.name .. C.off,
                          fn = function() BT.RemoveKOS(e.name) BT.RefreshNearby() end }
  else
    items[#items + 1] = { text = C.bad .. "Kill on sight" .. C.off .. "  " .. e.name,
                          fn = function() BT.AddKOS(e.name) BT.RefreshNearby() end }
  end
  if e.guild then
    if why == "guild" then
      items[#items + 1] = { text = C.good .. "Unmark <" .. e.guild .. ">" .. C.off,
        fn = function() BT.RemoveKOSGuild(e.guild) BT.RefreshNearby() end }
    else
      items[#items + 1] = { text = C.bad .. "Mark the guild" .. C.off .. "  <" .. e.guild .. ">",
        fn = function() BT.AddKOSGuild(e.guild) BT.RefreshNearby() end }
    end
  end

  items[#items + 1] = { gap = true }
  -- Your own words about him. The reason you marked somebody is worth more
  -- than the mark: "ganks the SM entrance at 2am" is a plan, a red name is a
  -- colour. Never shared with anybody.
  local _, existing = BT.IsKOS(e.name, e.guild)
  items[#items + 1] = {
    text = (existing and existing ~= "")
           and (C.gold .. "Note" .. C.off .. "  " .. existing:sub(1, 18))
           or "Write a note",
    fn = function() BT.NotePopup(e) end }

  -- what the client will actually let an addon do about another player
  items[#items + 1] = { text = "Target", fn = function()
    if TargetUnit then pcall(TargetUnit, e.name) end
  end }
  -- No whisper and no /who: both are same-faction only, and everybody here is
  -- on the other side.
  local chan = BT.SightChannel()
  items[#items + 1] = { text = "Call it out" .. C.dim .. "  " .. chan:lower() .. C.off,
    fn = function() BT.AnnounceSighting(e, chan, true) end }
  if chan ~= "SAY" then
    items[#items + 1] = { text = "Call it out" .. C.dim .. "  say" .. C.off,
      fn = function() BT.AnnounceSighting(e, "SAY", true) end }
  end

  items[#items + 1] = { gap = true }
  for _, it in ipairs(ListItems()) do items[#items + 1] = it end
  return ShowMenu(e.name, items, anchorTo)
end

-- A one-line box to type in. Hand-rolled for the same reason as the menu:
-- three widgets, no library, and nothing that breaks when somebody else's
-- addon replaces the popup system.
local notePop
function BT.NotePopup(e)
  if not e then return nil end
  if not notePop then
    notePop = CreateFrame("Frame", "ChainNotePopup", UIParent)
    notePop:SetSize(320, 78)
    notePop:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    notePop:SetFrameStrata("FULLSCREEN_DIALOG")
    notePop:EnableMouse(true)
    notePop:SetMovable(true)
    notePop:RegisterForDrag("LeftButton")
    notePop:SetScript("OnDragStart", notePop.StartMoving)
    notePop:SetScript("OnDragStop", notePop.StopMovingOrSizing)
    notePop.edge = notePop:CreateTexture(nil, "BACKGROUND")
    notePop.edge:SetPoint("TOPLEFT", -1, 1)
    notePop.edge:SetPoint("BOTTOMRIGHT", 1, -1)
    notePop.bg = notePop:CreateTexture(nil, "BACKGROUND")
    notePop.bg:SetAllPoints()
    if notePop.bg.SetColorTexture then
      notePop.edge:SetColorTexture(0.3, 0.3, 0.35, 1)
      notePop.bg:SetColorTexture(0.05, 0.05, 0.06, 0.98)
    end
    notePop.bg:SetDrawLayer("BACKGROUND", 2)

    notePop.title = notePop:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notePop.title:SetPoint("TOPLEFT", 10, -8)
    notePop.hint = notePop:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    notePop.hint:SetPoint("TOPLEFT", 10, -26)
    notePop.hint:SetText("your own words, never shared")

    notePop.box = CreateFrame("EditBox", nil, notePop)
    notePop.box:SetSize(300, 20)
    notePop.box:SetPoint("TOPLEFT", 10, -42)
    notePop.box:SetAutoFocus(true)
    notePop.box:SetFontObject("GameFontHighlightSmall")
    notePop.box:SetMaxLetters(120)
    notePop.box.bg = notePop.box:CreateTexture(nil, "BACKGROUND")
    notePop.box.bg:SetAllPoints()
    if notePop.box.bg.SetColorTexture then
      notePop.box.bg:SetColorTexture(0.12, 0.12, 0.14, 0.9)
    end
    local function Save()
      local who = notePop.who
      if who then
        local text = notePop.box:GetText() or ""
        -- writing a note marks him: you do not write one about somebody you
        -- do not care about, and an unmarked note would never be seen again
        BT.AddKOS(who.name, text ~= "" and text or nil)
      end
      notePop.box:ClearFocus()
      notePop:Hide()
      if BT.RefreshNearby then BT.RefreshNearby() end
      if BT.RenderWindow then BT.RenderWindow() end
    end
    notePop.box:SetScript("OnEnterPressed", Save)
    notePop.box:SetScript("OnEscapePressed", function()
      notePop.box:ClearFocus()
      notePop:Hide()
    end)
    notePop.save = Save
  end
  notePop.who = e
  notePop.title:SetText(e.name)
  local _, existing = BT.IsKOS(e.name, e.guild)
  notePop.box:SetText(existing or "")
  notePop:Show()
  notePop.box:SetFocus()
  return notePop
end

function BT.BuildNearby()
  if nearby then return nearby end
  nearby = CreateFrame("Frame", "ChainNearby", UIParent)
  nearby:SetSize(NearWidth(), 22 + NearRows() * ROW_H)
  nearby:SetScale(NearScale())
  AnchorNearby()
  nearby:SetMovable(true)
  nearby:EnableMouse(true)
  nearby:RegisterForDrag("LeftButton")
  nearby:SetClampedToScreen(true)
  nearby:SetScript("OnDragStart", BeginDrag)
  nearby:SetScript("OnDragStop", EndDrag)

  -- Drag the corner to make it wider or taller. Width is what closes the gap
  -- between a short name and the class beside it; height is simply how many
  -- of them you want to see, so it is stored as a row count rather than as
  -- pixels and survives a change of font or scale.
  nearby:SetResizable(true)
  if nearby.SetResizeBounds then
    nearby:SetResizeBounds(120, 22 + ROW_H, 420, 22 + NEAR_MAX * ROW_H)
  elseif nearby.SetMinResize then
    nearby:SetMinResize(120, 22 + ROW_H)
    nearby:SetMaxResize(420, 22 + NEAR_MAX * ROW_H)
  end

  local grip = CreateFrame("Button", nil, nearby)
  grip:SetSize(12, 12)
  grip:SetFrameLevel((nearby:GetFrameLevel() or 1) + 5)
  grip.tex = grip:CreateTexture(nil, "OVERLAY")
  grip.tex:SetAllPoints()
  if grip.tex.SetColorTexture then grip.tex:SetColorTexture(1, 1, 1, 0.18) end
  grip:RegisterForDrag("LeftButton")
  grip:SetScript("OnDragStart", function()
    if ChainDB.nearbyLocked then return end
    sizing = true
    nearby:StartSizing(GrowUp() and "TOPRIGHT" or "BOTTOMRIGHT")
  end)
  grip:SetScript("OnDragStop", function()
    if not sizing then return end
    nearby:StopMovingOrSizing()
    sizing = false
    ChainDB.nearbyWidth = math.floor(nearby:GetWidth() or NEAR_W)
    -- height back into whole rows, so the box never ends on half a name
    local rows = math.floor(((nearby:GetHeight() or 0) - 22) / ROW_H + 0.5)
    ChainDB.nearbyRows = math.max(1, math.min(NEAR_MAX, rows))
    SaveNearbyPos()
    BT.RefreshNearby()
  end)
  nearby.grip = grip
  nearby:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then BT.NearbyMenu() end
  end)

  nearby.bg = nearby:CreateTexture(nil, "BACKGROUND")
  nearby.bg:SetAllPoints()
  if nearby.bg.SetColorTexture then
    nearby.bg:SetColorTexture(0, 0, 0, 0.55)
  else
    nearby.bg:SetTexture(0, 0, 0, 0.55)
  end

  nearby.title = nearby:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

  nearby.rows = {}
  for i = 1, NEAR_MAX do
    local row = CreateFrame("Button", nil, nearby)
    row:SetSize(NearWidth() - 12, 13)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    -- a row is part of the box: hold and move and the whole thing comes with
    -- you, while a click that does not move still marks him
    row:RegisterForDrag("LeftButton")
    row:SetScript("OnDragStart", BeginDrag)
    row:SetScript("OnDragStop", EndDrag)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWidth(NearWidth() - 12 - RIGHT_W)
    -- The class as a tint across the whole row rather than only on the name.
    -- A coloured word asks you to have the palette memorised and half of it is
    -- a shade apart; a coloured band you read at a glance.
    row.stripe = row:CreateTexture(nil, "BACKGROUND")
    row.stripe:SetAllPoints()
    -- level and class together on the right, the way the game writes it
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -2, 0)
    row.right:SetJustifyH("RIGHT")
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, button)
      if button == "RightButton" then BT.PlayerMenu(self.rec, self) return end
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

-- Title and rows both have to flip: growing up means the heading belongs at
-- the bottom, next to where the list starts.
local function LayoutNearby(shown)
  local up = GrowUp()
  nearby.title:ClearAllPoints()
  if up then
    nearby.title:SetPoint("BOTTOMLEFT", 6, 5)
  else
    nearby.title:SetPoint("TOPLEFT", 6, -5)
  end
  local w = NearWidth()
  nearby:SetScale(NearScale())
  if not sizing then nearby:SetWidth(w) end
  for i = 1, NEAR_MAX do
    local row = nearby.rows[i]
    row:SetWidth(w - 12)
    -- the name takes whatever the class does not need, so a wider box gives
    -- the name more room rather than opening a hole in the middle
    row.name:SetWidth(w - 12 - RIGHT_W)
    row:ClearAllPoints()
    if up then
      row:SetPoint("BOTTOMLEFT", 6, 20 + (i - 1) * ROW_H)
    else
      row:SetPoint("TOPLEFT", 6, -20 - (i - 1) * ROW_H)
    end
  end
  if nearby.grip then
    nearby.grip:ClearAllPoints()
    nearby.grip:SetPoint(GrowUp() and "TOPRIGHT" or "BOTTOMRIGHT", 0, 0)
  end

  -- and the height stays put while you are holding it: a box that grows or
  -- shrinks under the cursor drifts away from where you are putting it
  if not dragging and not sizing then
    nearby:SetHeight(22 + math.max(1, shown) * ROW_H)
  end
  AnchorNearby()
end

function BT.RefreshNearby()
  if ChainDB.nearbyList == false or not ChainDB.watchEnemies then
    if nearby then nearby:Hide() end
    if menu then menu:Hide() end
    return
  end
  BT.BuildNearby()
  local list = BT.Nearby(ChainDB.nearbySeconds or NEARBY)
  if #list == 0 then
    nearby:Hide()
    if menu then menu:Hide() end
    return
  end
  local want = NearRows()
  nearby.title:SetText(C.warn .. #list .. " nearby" .. C.off
    .. ((#list > want) and (C.dim .. "  (" .. want .. " shown)" .. C.off) or "")
    .. (ChainDB.nearbyLocked and (C.dim .. "  locked" .. C.off) or ""))
  for i = 1, NEAR_MAX do
    local row = nearby.rows[i]
    local e = (i <= want) and list[i] or nil
    if e then
      row.rec = e
      local col = e.class and CLASS_COLOUR[e.class] or { 0.7, 0.7, 0.7 }
      local why = BT.IsKOS(e.name, e.guild)
      -- faded as the sighting gets old, so the top of the list is the one
      -- that is actually still there
      local age = time() - (e.at or time())
      local a = 1 - math.min(0.6, age / (ChainDB.nearbySeconds or NEARBY))

      if row.stripe.SetColorTexture then
        -- marked ones go red whatever they play: that is the thing you need
        -- to see, and it beats knowing the class
        if why then row.stripe:SetColorTexture(0.55, 0.08, 0.08, 0.75 * a)
        else row.stripe:SetColorTexture(col[1] * 0.45, col[2] * 0.45,
                                        col[3] * 0.45, 0.7 * a) end
      end
      row.name:SetText((why and "|cffff4040!|r " or "")
        .. (e.stealth and "|cffb080ff~|r " or "") .. e.name)
      row.name:SetTextColor(1, 1, 1)
      row.right:SetText(((e.level and e.level > 0)
          and (e.level .. (e.levelGuess and "+" or "")) or "??")
        .. " " .. (e.class and BT.ClassLabel(e.class) or "?"))
      row.right:SetTextColor(col[1], col[2], col[3])
      row.name:SetAlpha(a)
      row.right:SetAlpha(a)
      row:Show()


    else
      row.rec = nil
      row:Hide()
    end
  end
  LayoutNearby(math.min(want, #list))
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
