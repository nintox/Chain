-- Chain: the live half. Watches the game, decides when a run starts
-- and ends, and writes one record per finished run into the log.

local ADDON, BT = ...
local K = BT.K

BT.CHAR_DEFAULTS = {
  run = nil,          -- the run in progress
  session = nil,      -- this stint's experience
  entrySeq = 0,
  instId = {},        -- last known instance id per zone (legacy)
  seenInst = {},      -- every instance id entered lately, and when
  buckets = {},       -- experience per minute, for xp/h
  lastBy = nil,       -- the booster you last ran with
  lastZone = nil,
  lastEnd = nil,
  lastGain = nil,
  levelAt = nil,      -- when this level started, for "this level 15m"
  resetAt = nil, resetZone = nil, resetBy = nil
}

local frame = CreateFrame("Frame", "ChainFrame")
BT.frame = frame

--------------------------------------------------------------------------
-- Small helpers over the live game state
--------------------------------------------------------------------------
-- Returns the zone name and, more importantly, the instance id. The id is
-- what actually identifies a dungeon; the name is localised and Blizzard
-- renames places under us.
function BT.InDungeon()
  local inside, kind = IsInInstance()
  if not inside then return nil end
  if kind ~= "party" and kind ~= "raid" then return nil end
  local zone, map
  if GetInstanceInfo then
    local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    if name and name ~= "" then zone = name end
    map = tonumber(instanceID)
  end
  if not zone or zone == "" then zone = GetRealZoneText() end
  if not zone or zone == "" then zone = GetZoneText() end
  if not zone or zone == "" then return nil end
  return zone, map
end

function BT.CurrentZone()
  local c = ChainCharDB
  if c.run then return c.run.zone, c.run.map end
  return c.lastZone, c.lastMap
end

-- A dungeon run is not automatically a boost. A normal group is people within
-- a few levels of each other; a boost is somebody far above you doing the
-- killing. Highest level wins, and group leadership only breaks a tie between
-- equals - the leader is often a boostie, not the booster.
function BT.Booster()
  if not (IsInGroup and IsInGroup()) then return nil end
  if not (UnitExists and UnitName) then return nil end
  local my = UnitLevel("player") or 0
  local name, level, isLead
  for i = 1, 4 do
    local u = "party" .. i
    if UnitExists(u) then
      local lvl = UnitLevel(u) or 0
      local lead = UnitIsGroupLeader and UnitIsGroupLeader(u) or false
      if lvl >= my + K.BOOST_GAP then
        if not level or lvl > level or (lvl == level and lead and not isLead) then
          level, name, isLead = lvl, UnitName(u), lead
        end
      end
    end
  end
  return name and BT.ShortName(name) or nil
end

-- Who is boosting right now, for stats purposes
function BT.CurrentBooster()
  local c = ChainCharDB
  if c.run then return c.run.by end
  -- outside a run: whoever is in the group now, else the last one you ran
  -- with, so the plan you look at in town is still priced for him
  return BT.Booster() or c.lastBy
end

-- Are we boosting right now? Inside a run it is whatever the run started as;
-- in a group it is the group; on your own it is the route, which is planned
-- and priced as a boost.
function BT.CurrentBoost()
  local c = ChainCharDB
  if c.run then return c.run.by ~= nil end
  if IsInGroup and IsInGroup() then return BT.Booster() ~= nil end
  return true
end

-- Which step a run here belongs to. Several steps can share one instance
-- (the three wings of Dire Maul), so the step you are on wins if it matches.
function BT.StepFor(map, zone)
  local list = BT.DungeonsFor(map, zone)
  if not list or not list[1] then return nil end
  local _, e = BT.Stage()
  if e then
    for _, d in ipairs(list) do
      if d.id == e.id then return e.id end
    end
  end
  return list[1].id
end

--------------------------------------------------------------------------
-- Experience accounting
--------------------------------------------------------------------------
-- Remember what this client says a level costs, and say something once if it
-- disagrees with the built-in table - that means the forecast for levels you
-- have not reached yet is an estimate until you get there.
function BT.LearnXP()
  local lvl, mx = UnitLevel("player"), UnitXPMax("player")
  if not lvl or not mx or mx <= 0 or lvl >= BT.MAX_LEVEL then return end
  if ChainDB.xpReal[lvl] == mx then BT.pendingXP = nil return end
  -- At the moment you level, the client can report the new level while the
  -- bar still holds the old maximum. Waiting for the same pair twice means we
  -- never write down that half-updated state.
  local p = BT.pendingXP
  if not p or p.lvl ~= lvl or p.mx ~= mx then
    BT.pendingXP = { lvl = lvl, mx = mx }
    return
  end
  BT.pendingXP = nil
  ChainDB.xpReal[lvl] = mx
  local book = BT.XP[lvl]
  if book and book > 0 and math.abs(mx / book - 1) > 0.02 and not BT.warnedXP then
    BT.warnedXP = true
    print(BT.COL.warn .. BT.NAME .. ":|r this client's experience table is not "
      .. "the one built in (level " .. lvl .. " wants " .. BT.N(mx) .. ", not "
      .. BT.N(book) .. "). Forecasts past your current level are estimates "
      .. "until it has seen those levels.")
  end
end

function BT.Delta()
  local c = ChainCharDB
  local xp, mx = UnitXP("player") or 0, UnitXPMax("player") or 0
  local last, lastMax = c.lastXP, c.lastMax
  c.lastXP, c.lastMax = xp, mx
  if not last then return 0 end
  if mx ~= lastMax then
    -- levelled: the rest of the old bar plus whatever is on the new one
    return math.max(0, (lastMax or 0) - last) + xp
  end
  return math.max(0, xp - last)
end

function BT.AddXP(d)
  if not d or d <= 0 then return end
  local c = ChainCharDB
  local m = math.floor(time() / 60)
  c.buckets[tostring(m)] = (c.buckets[tostring(m)] or 0) + d
  for key in pairs(c.buckets) do
    local km = tonumber(key)
    if not km or km < m - 59 then c.buckets[key] = nil end
  end
  -- a long gap ends the session the same way logging out does
  if not c.session or (c.lastGain and (time() - c.lastGain) > K.SESSION_GAP) then
    c.session = { start = time(), xp = 0 }
  end
  c.session.xp = (c.session.xp or 0) + d
  c.lastGain = time()
end

-- Minutes since the last experience gain, nil if none in the last hour
function BT.IdleMin()
  local c = ChainCharDB
  local m, last = math.floor(time() / 60), nil
  for key in pairs(c.buckets) do
    local km = tonumber(key)
    if km and km >= m - 59 and km <= m and (not last or km > last) then last = km end
  end
  if not last then return nil end
  return m - last
end

-- Experience per hour over the last hour. Breaks up to five minutes do not
-- count against you, but a long silence means there is no rate to report -
-- better no number than one claiming you ding in five minutes at the mailbox.
function BT.Rate()
  local c = ChainCharDB
  local m = math.floor(time() / 60)
  local mins, total = {}, 0
  for key, v in pairs(c.buckets) do
    local km = tonumber(key)
    if km and km >= m - 59 and km <= m then
      table.insert(mins, km)
      total = total + v
    end
  end
  if total <= 0 or #mins == 0 then return nil end
  table.sort(mins)
  local elapsed = 1
  for i = 2, #mins do
    local gap = mins[i] - mins[i - 1]
    if gap > 5 then gap = 5 end
    elapsed = elapsed + gap
  end
  local tail = m - mins[#mins]
  if tail > K.IDLE_MIN then return nil end
  if tail > 5 then tail = 5 end
  elapsed = elapsed + tail
  if elapsed < 1 then return nil end
  return total / elapsed * 60
end

--------------------------------------------------------------------------
-- Quests ready to hand in
--------------------------------------------------------------------------
-- A quest you have outlevelled is grey in the log and worth nothing to hand
-- in. Counting it told you there were four quests waiting and a level's worth
-- of experience in your bag when there were two and half that - which is the
-- sort of wrong that makes you plan around it.
--
-- The client knows where grey begins: GetQuestGreenRange is the number of
-- levels below you that still count as green, and grey starts one below that.
-- Where the call is missing, the table falls back on the same thresholds the
-- experience decay already uses.
function BT.QuestGrey(questLevel)
  if not questLevel or questLevel <= 0 then return false end
  local lvl = UnitLevel("player") or 1
  if GetQuestGreenRange then
    local range = GetQuestGreenRange()
    if range and range > 0 then return questLevel < (lvl - range) end
  end
  -- no such call on this client: the same threshold the experience decay uses
  return questLevel <= (BT.GreyLevel and BT.GreyLevel(lvl) or (lvl - 6))
end

function BT.ScanQuests()
  if not (GetNumQuestLogEntries and GetQuestLogTitle) then return end
  local now = time()
  if BT.questScan and (now - BT.questScan) < 2 then return end
  BT.questScan = now
  local total, count, grey = 0, 0, 0
  local n = GetNumQuestLogEntries()
  local selected = GetQuestLogSelection and GetQuestLogSelection() or nil
  for i = 1, n do
    local title, qLevel, _, isHeader, _, isComplete = GetQuestLogTitle(i)
    if title and not isHeader and isComplete == 1 then
      if BT.QuestGrey(qLevel) then
        -- counted separately: it is still a quest you can hand in, it is
        -- just not experience, and the difference is the whole point
        grey = grey + 1
      else
        count = count + 1
        if SelectQuestLogEntry and GetQuestLogRewardXP then
          SelectQuestLogEntry(i)
          total = total + (GetQuestLogRewardXP() or 0)
        end
      end
    end
  end
  if selected and SelectQuestLogEntry then SelectQuestLogEntry(selected) end
  BT.questXP, BT.questCount, BT.questGrey = total, count, grey
end

--------------------------------------------------------------------------
-- Instance identity and the five-per-hour limit
--------------------------------------------------------------------------
-- Creature-0-<server>-<instanceID>-<zone>-<npc>-<spawn>: field four is the
-- unique id of this instance and only changes when it is actually reset.
function BT.InstIdFrom(guid)
  if type(guid) ~= "string" then return nil end
  local kind, _, _, inst = strsplit("-", guid)
  if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
  return inst
end

function BT.NoteInstance(guid)
  local c = ChainCharDB
  local r = c.run
  if not r or r.instId then return end
  local id = BT.InstIdFrom(guid)
  if not id then return end
  r.instId = id

  -- Every instance we have been in lately, not just the last one per zone.
  -- Scarlet Monastery is four separate instances behind one name, and a
  -- Cathedral + Armory chain has two of them alive at the same time: with one
  -- slot per zone, walking back into the Cathedral looked like a new instance
  -- and the hourly count ran ahead of the truth.
  c.seenInst = c.seenInst or {}
  local now = time()
  for key, when in pairs(c.seenInst) do
    if now - when > 86400 then c.seenInst[key] = nil end
  end
  local before = c.seenInst[id]
  c.seenInst[id] = now
  c.instId[r.zone] = id                      -- kept for the older readers
  if before then
    -- walked back into an instance we already counted: it is not a new one
    r.reentry = true
    BT.DropEntry(r.entrySeq)
    r.entrySeq = nil
  end
end

-- The hourly cap is per character but the daily one is per account, so the
-- log lives account-wide and every entry remembers who walked in.
function BT.NoteEntry()
  local c = ChainCharDB
  c.entrySeq = (c.entrySeq or 0) + 1
  local seq = UnitName("player") .. ":" .. c.entrySeq
  local zone = BT.InDungeon()
  table.insert(ChainDB.entries, { t = time(), seq = seq,
                                         zone = zone,
                                         char = UnitName("player") })
  -- a day of the account-wide cap, with room to spare
  while #ChainDB.entries > 200 do table.remove(ChainDB.entries, 1) end
  -- the entry that takes you to the limit is the one the group needs to hear
  -- about, and the moment you zone in is when they are still deciding
  if BT.AnnounceLock then BT.AnnounceLock() end
  return seq
end

-- Called from the bar's own timer, a few times a minute. The lockout expires
-- on a clock nobody is watching, so somebody has to look.
local lastLockCheck = 0
function BT.PollLock()
  local now = time()
  if now - lastLockCheck < 5 then return end
  lastLockCheck = now
  BT.AnnounceLock()
end

function BT.DropEntry(seq)
  if not seq then return end
  local list = ChainDB.entries
  for i = #list, 1, -1 do
    if list[i].seq == seq then table.remove(list, i) return end
  end
end

--------------------------------------------------------------------------
-- Nova Instance Tracker: borrowed from, never depended on
--------------------------------------------------------------------------
-- The one thing NIT has that we cannot is the entries from before this addon
-- was installed. So we take them, once, into our own log - rather than
-- reading its data every time and being useless the day it is uninstalled.
--
-- Everything after that is ours: we see every zone-in ourselves. Running the
-- import again is safe, because an entry already in the log is recognised by
-- when it happened and who it happened to.
-- Every reset we were told about, newest first
function BT.ResetLog(sinceHours)
  local out = {}
  local cut = sinceHours and (time() - sinceHours * 3600) or nil
  for i = #(ChainDB.resets or {}), 1, -1 do
    local r = ChainDB.resets[i]
    if not cut or (r.at or 0) >= cut then table.insert(out, r) end
  end
  return out
end

function BT.ImportNIT()
  local NIT = _G.NIT
  if not NIT or not NIT.data or not NIT.data.instances then return 0 end
  local have = {}
  for _, e in ipairs(ChainDB.entries) do
    -- to the minute: two clocks agreeing to the second is not something to
    -- rely on, and nobody enters two instances in the same minute twice
    have[(e.char or "?") .. ":" .. math.floor((e.t or 0) / 60)] = true
  end
  local added = 0
  for _, inst in ipairs(NIT.data.instances) do
    local t = tonumber(inst.enteredTime)
    local who = inst.playerName or UnitName("player")
    if t and t > 0 then
      local key = (who or "?") .. ":" .. math.floor(t / 60)
      if not have[key] then
        have[key] = true
        added = added + 1
        table.insert(ChainDB.entries, {
          t = t, seq = "nit:" .. t .. ":" .. tostring(who),
          zone = inst.zone or inst.instanceName, char = who, from = "NIT"
        })
      end
    end
  end
  if added > 0 then
    table.sort(ChainDB.entries, function(a, b) return (a.t or 0) < (b.t or 0) end)
    while #ChainDB.entries > 400 do table.remove(ChainDB.entries, 1) end
  end
  return added
end

-- Every instance entry we know of, newest first, each with how long until it
-- stops counting against the five per hour. Our own log: NIT's history was
-- copied into it once, and everything since we saw ourselves.
function BT.InstanceLog()
  local out = {}
  for _, e in ipairs(ChainDB.entries) do
    table.insert(out, { t = e.t, zone = e.zone, char = e.char, nit = e.from == "NIT" })
  end
  table.sort(out, function(a, b) return (a.t or 0) > (b.t or 0) end)
  local now = time()
  for _, e in ipairs(out) do
    local age = now - (e.t or now)
    e.age = age
    e.left = (age < 3600) and (3600 - age) or 0
    e.counts = age < 3600
  end
  return out
end

-- Reading NIT's count live, for anyone who would rather trust it than us.
-- Off by default: our own log is complete once its history has been imported,
-- and an addon that stops working when another one is uninstalled is not
-- something to build on.
function BT.NITLockout()
  if not ChainDB.useNIT then return nil end
  local NIT = _G.NIT
  if not NIT or not NIT.data or not NIT.data.instances then return nil end
  local hour, day = time() - 3600, time() - 86400
  local count, oldest, newest, daily = 0, nil, nil, 0
  for _, inst in ipairs(NIT.data.instances) do
    local t = tonumber(inst.enteredTime)
    if t and t > day then daily = daily + 1 end
    if t and t > hour then
      count = count + 1
      if not oldest or t < oldest then oldest = t end
      if not newest or t > newest then newest = t end
    end
  end
  return count, oldest, newest, daily
end

-- Returns: hourly count for this character, seconds until one frees up,
-- seconds until all free, whether it came from NIT, and the account-wide
-- count for the last 24 hours.
function BT.Lockout()
  local nitCount, nitOldest, nitNewest, nitDaily = BT.NITLockout()
  local count, oldest, newest, daily
  if nitCount then
    count, oldest, newest, daily = nitCount, nitOldest, nitNewest, nitDaily
  else
    local hour, day = time() - 3600, time() - 86400
    local me = UnitName("player")
    count, daily = 0, 0
    for _, e in ipairs(ChainDB.entries) do
      local t = e.t or 0
      -- the daily cap counts every character on the account
      if t > day then daily = daily + 1 end
      -- the hourly one only counts this character
      if t > hour and (e.char == nil or e.char == me) then
        count = count + 1
        if not oldest or t < oldest then oldest = t end
        if not newest or t > newest then newest = t end
      end
    end
  end
  -- The game's own refusal beats our arithmetic. We only see zone-ins we
  -- were running for; it sees all of them, including the ones from a day the
  -- addon was off or from another computer.
  -- Not "BT.LockedByGame and BT.LockedByGame()": an `and` expression keeps
  -- only the first return value, so the second one came back nil and the
  -- correction silently did nothing.
  local lockedAt, missing
  if BT.LockedByGame then lockedAt, missing = BT.LockedByGame() end
  local fromGame = false
  if lockedAt and (missing or 0) > 0 then
    count = count + missing
    fromGame = true
    -- we cannot know when an instance we never saw expires. The one thing we
    -- do know is that it was entered before we were refused, so an hour after
    -- that refusal is the latest it can still be counting.
    local bound = math.max(0, 3600 - (time() - lockedAt))
    if not oldest or bound > math.max(0, 3600 - (time() - oldest)) then
      oldest = time() - (3600 - bound)
    end
    if not newest then newest = oldest end
  end
  if count == 0 then return 0, nil, nil, nitCount ~= nil, daily, false end
  local freeOne = oldest and math.max(0, 3600 - (time() - oldest)) or nil
  local freeAll = newest and math.max(0, 3600 - (time() - newest)) or nil
  return count, freeOne, freeAll, nitCount ~= nil, daily, fromGame
end

--------------------------------------------------------------------------
-- Reset detection
--------------------------------------------------------------------------
-- Built from the client's own strings so it works on any locale
local function Pattern(str)
  if type(str) ~= "string" then return nil end
  local p = str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  return "^" .. p:gsub("%%%%s", "(.+)") .. "$"
end

local resetPattern = Pattern(INSTANCE_RESET_SUCCESS)
-- A reset that did not happen is worth knowing about too. Standing at the
-- portal wondering why nothing is happening is the single most common way to
-- lose a few minutes in a boost chain, and the game already tells you why.
local failPatterns = {
  { Pattern(INSTANCE_RESET_FAILED), "someone is still inside" },
  { Pattern(INSTANCE_RESET_FAILED_ZONING), "someone is zoning in" },
  { Pattern(INSTANCE_RESET_FAILED_OFFLINE), "someone is offline" }
}

-- A reset means one of two opposite things depending on which side of the
-- portal you are standing on, and the whole point of a sound is that you do
-- not have to look. So there are two of them, and they are deliberately not
-- alike: the "get out" one is the urgent one.
BT.SOUNDS = {
  { key = "warning",  label = "Raid warning",
    kit = "RAID_WARNING",      file = "Sound\\Interface\\RaidWarning.ogg" },
  { key = "ready",    label = "Ready check",
    kit = "READY_CHECK",       file = "Sound\\Interface\\ReadyCheck.ogg" },
  { key = "levelup",  label = "Level up",
    kit = "UI_LEGENDARY_LOOT_TOAST",
    file = "Sound\\Interface\\LevelUp.ogg" },
  { key = "alarm",    label = "Alarm clock",
    kit = "ALARM_CLOCK_WARNING_3",
    file = "Sound\\Interface\\AlarmClockWarning3.ogg" },
  { key = "bell",     label = "Auction bell",
    kit = "AUCTION_WINDOW_OPEN",
    file = "Sound\\Interface\\AuctionWindowOpen.ogg" },
  { key = "murloc",   label = "Murloc",
    kit = nil,                 file = "Sound\\Creature\\Murloc\\mMurlocAggroOld.ogg" },
  { key = "none",     label = "Silent",  kit = nil, file = nil }
}

function BT.SoundByKey(key)
  for _, s in ipairs(BT.SOUNDS) do
    if s.key == key then return s end
  end
  return BT.SOUNDS[1]
end

-- which = "in" (go back in) or "out" (you are inside, leave)
local function Beep(which)
  local key = (which == "out") and (ChainDB.soundOut or "warning")
    or (ChainDB.soundIn or "levelup")
  local s = BT.SoundByKey(key)
  if not s or s.key == "none" then return end
  -- Master channel on purpose: it plays even with the game muted, which is
  -- the state you are most likely in when you have walked away.
  if s.kit and PlaySound and SOUNDKIT and SOUNDKIT[s.kit] then
    PlaySound(SOUNDKIT[s.kit], "Master")
  elseif s.file and PlaySoundFile then
    PlaySoundFile(s.file, "Master")
  elseif PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
  end
end
BT.Beep = Beep

-- Which of the two the situation calls for, asked fresh every time: walk out
-- of the portal between two repeats and the sound changes with you.
local function ResetSide()
  return (ChainCharDB and ChainCharDB.run) and "out" or "in"
end

-- An addon cannot reach your phone - there is no network in the Lua sandbox,
-- for anyone, ever. So the alert has to win in the room instead: repeated, on
-- the Master channel, and printed across the middle of the screen until you
-- actually do something about it.
function BT.FlagReset(zone, by)
  local c = ChainCharDB
  local prev = c.resetAt
  c.resetAt, c.resetZone, c.resetBy = time(), zone, BT.ShortName(by)
  -- the system message and NIT's party message often both arrive
  if prev and (time() - prev) <= 15 then return end
  -- A reset is worth keeping, not just reacting to: how many the group got
  -- through in an evening, who was doing the resetting, and how long the
  -- chain ran. It is our own record, and needs nobody else's addon.
  local db = ChainDB
  db.resets = db.resets or {}
  table.insert(db.resets, { at = time(), zone = zone,
                            by = BT.ShortName(by), char = UnitName("player") })
  while #db.resets > 300 do table.remove(db.resets, 1) end
  BT.Signal("reset", (BT.Short(zone) or zone or "instance") .. " is open")
  if not ChainDB.sound then return end
  Beep(ResetSide())
  local left = math.max(0, math.floor(ChainDB.soundRepeat or 1) - 1)
  if left > 0 and C_Timer and C_Timer.After then
    local n, at = left, c.resetAt
    local function again()
      -- stop the moment the situation is dealt with
      if n <= 0 or ChainCharDB.resetAt ~= at then return end
      if not BT.ResetReady() then return end
      n = n - 1
      Beep(ResetSide())
      C_Timer.After(2, again)
    end
    C_Timer.After(2, again)
  end
end

--------------------------------------------------------------------------
-- What the game itself says about your lockout
--------------------------------------------------------------------------
-- Counting zone-ins is an estimate: it misses anything entered on a day the
-- addon was off, on another computer, or before it was installed. The game
-- knows the real answer and says so at the portal - "you have entered too
-- many instances recently". That sentence is worth more than our arithmetic,
-- so when it arrives the count is corrected to it rather than argued with.
local LOCK_STRINGS = {
  _G.ERR_TRANSFER_ABORT_TOO_MANY_INSTANCES,
  _G.INSTANCE_LIMIT,
  "You have entered too many instances recently."
}

function BT.LooksLikeLockout(msg)
  if type(msg) ~= "string" then return false end
  local low = msg:lower()
  for _, s in ipairs(LOCK_STRINGS) do
    if type(s) == "string" and s ~= "" and low:find(s:lower(), 1, true) then
      return true
    end
  end
  -- the wording moves between clients and locales; the shape does not
  return low:find("too many instances", 1, true) ~= nil
end

-- The game refused us. Whatever we had counted, the truth is "at the limit".
function BT.NoteLockedOut()
  local c = ChainCharDB
  c.lockMissing = nil            -- so the count below is our own arithmetic
  c.lockedAt = time()
  local count = BT.Lockout()
  local limit = ChainDB.limit or K.LIMIT
  if count < limit then
    -- we are behind. Say so out loud rather than quietly showing 3/5 at a
    -- door that will not open.
    c.lockMissing = limit - count
    print(BT.COL.warn .. BT.NAME .. ":|r the game says you are at the limit, "
      .. "and I had counted " .. count .. "/" .. limit
      .. ". Using the game's answer - it has seen instances I have not.")
  else
    c.lockMissing = nil
  end
  if BT.AnnounceLock then BT.AnnounceLock(true) end
  if BT.Refresh then BT.Refresh() end
end

-- How many the game insists on, if it told us lately. The lockout it refers
-- to expires like any other: an hour after it was refused, at the latest.
function BT.LockedByGame()
  local c = ChainCharDB
  if not c.lockedAt then return nil end
  if (time() - c.lockedAt) > 3600 then
    c.lockedAt, c.lockMissing = nil, nil
    return nil
  end
  return c.lockedAt, c.lockMissing
end

function BT.NoteResetSystem(msg)
  if type(msg) ~= "string" then return end
  if BT.LooksLikeLockout(msg) then BT.NoteLockedOut() return end
  if resetPattern then
    local zone = msg:match(resetPattern)
    if zone then
      BT.FlagReset(zone, nil)
      BT.Announce(zone)
      return
    end
  end
  for _, f in ipairs(failPatterns) do
    if f[1] then
      local zone = msg:match(f[1])
      if zone then
        local c = ChainCharDB
        c.failAt, c.failZone, c.failWhy = time(), zone, f[2]
        return
      end
    end
  end
end

-- A failed reset you were told about in the last two minutes
function BT.ResetFailed()
  local c = ChainCharDB
  if not c.failAt or (time() - c.failAt) > 120 then return nil end
  -- a reset that then succeeded makes the failure stale
  if c.resetAt and c.resetAt >= c.failAt then return nil end
  return c.failZone, c.failWhy
end

-- Tell the group, so the boosties are not all waiting on somebody to say it.
-- Off by default: it is your chat, not ours.
local function Tell(text)
  if not (IsInGroup and IsInGroup()) then return false end
  if type(SendChatMessage) ~= "function" then return false end
  SendChatMessage(text, (IsInRaid and IsInRaid()) and "RAID" or "PARTY")
  return true
end

-- The group cannot see your lockout. They see you standing at the portal not
-- going in, and somebody asks, and you type it out - every single time. So
-- the addon says it instead: how many you are at, and how long until that
-- changes. Nobody has to ask and nobody has to guess.
--
-- Two lines, and only two: the one that says you are stuck, and the one that
-- says you are not any more. Anything in between is a countdown in party chat,
-- which is the fastest way to be asked to turn an addon off.
local LOCK_QUIET = 120

local function LockText()
  local count, freeOne = BT.Lockout()
  local limit = ChainDB.limit or K.LIMIT
  if count < limit then return nil, count, limit end
  return "locked " .. count .. "/" .. limit
    .. (freeOne and (" - free in " .. BT.T(freeOne)) or ""), count, limit
end

function BT.AnnounceLock(force)
  if not ChainDB.announceLock then return end
  local c = ChainCharDB
  local text, count, limit = LockText()
  if not text then
    -- out of it again: worth one line, but only if they were told you were in
    -- it, and only once
    if c.toldLocked then
      c.toldLocked = nil
      if count == limit - 1 then
        Tell("free again - " .. count .. "/" .. limit .. ", ready when you are")
      else
        Tell("free again - " .. count .. "/" .. limit)
      end
    end
    return
  end
  local now = time()
  if not force and c.toldLocked and (now - c.toldLocked) < LOCK_QUIET then return end
  if Tell(text) then c.toldLocked = now end
end

function BT.Announce(zone)
  if not ChainDB.announce then return end
  -- "go in" is the wrong thing to shout when you cannot. At the limit the
  -- group wants the other sentence: how long the wait is.
  local locked = LockText()
  if locked then
    -- not forced: a reset every twenty seconds is normal in a boost chain,
    -- and the group needs telling once, not once per attempt
    if ChainDB.announceLock then BT.AnnounceLock() end
    return
  end
  Tell((BT.Short(zone) or zone) .. " reset - go in")
end

-- Reset the instances you are locked to. Only the group leader can, and only
-- from outside, so the game will say no if either is untrue - which is what
-- the failure lines above are for.
function BT.DoReset()
  if BT.InDungeon() then
    print(BT.COL.warn .. BT.NAME .. ":|r you have to be outside the instance to reset it.")
    return
  end
  if type(ResetInstances) ~= "function" then
    print(BT.COL.warn .. BT.NAME .. ":|r this client does not let an addon reset instances.")
    return
  end
  ResetInstances()
end

function BT.NoteResetChat(msg, sender)
  if type(msg) ~= "string" then return end
  if not msg:lower():find("reset", 1, true) then return end
  BT.FlagReset(ChainCharDB.lastZone, sender)
end

-- A reset you have been told about, still fresh and not yet used.
-- Returns zone, age, who, inside
function BT.ResetReady()
  local c = ChainCharDB
  if not c.resetAt then return nil end
  local age = time() - c.resetAt
  local inside = c.run ~= nil
  -- Inside there is no timeout: you might be away from the keyboard when the
  -- leader resets, and the situation lasts until you actually leave. Outside
  -- it expires, because you are meant to walk straight back in.
  if not inside and age > 120 then return nil end
  return c.resetZone, age, c.resetBy, inside
end

--------------------------------------------------------------------------
-- Signalling out of the game
--------------------------------------------------------------------------
-- An addon has no network access, so it cannot notify your phone. What it can
-- do is leave a line in the chat log the game itself writes, and let a small
-- program outside WoW watch that file. The line goes to a channel only this
-- character is in, so nobody else ever sees it.
--
-- It has to be shown in *some* chat window, though: the client only writes to
-- the chat log what a chat frame displayed, so a channel removed from every
-- window is a channel that leaves no trace in the file. It is parked in the
-- Combat Log window instead, which nobody reads, and taken out of the rest.
local SIGNAL_PREFIX = "LTPUSH"

function BT.SignalChannel()
  local me = UnitName("player") or "x"
  return "LB" .. me:gsub("%W", "")
end

-- Which window the marker is parked in: the Combat Log if there is one, the
-- last window otherwise. Never the first - that is the one you read.
function BT.SignalFrame()
  local combat = _G.ChatFrame2
  if combat then return combat, 2 end
  local n = NUM_CHAT_WINDOWS or 2
  return _G["ChatFrame" .. n], n
end

-- The chat log stops at every /reload and every relog, and - this is the part
-- that cost an evening - the client goes on reporting it as ON afterwards
-- while the file sits closed. Asking for it again does nothing in that state;
-- switching it off and on again reopens the file. Once per session is enough.
function BT.EnsureChatLog()
  if not LoggingChat then return end
  if BT.chatLogArmed then return end
  BT.chatLogArmed = true
  if LoggingChat() then LoggingChat(false) end
  LoggingChat(true)
end

function BT.EnableSignal()
  if not ChainDB.logSignal then return end
  -- the log itself has to be running, or there is nothing to watch
  BT.EnsureChatLog()
  local name = BT.SignalChannel()
  local joined = GetChannelName and GetChannelName(name) > 0
  if not joined and JoinTemporaryChannel then JoinTemporaryChannel(name) end

  -- Shown in exactly one window, or the client logs nothing at all. The
  -- Combat Log is the polite place for it, but it is a special frame in some
  -- builds and can refuse, so the result is checked and the general window
  -- taken as the fallback: a line you can see beats a push you never get.
  local keep, keepIndex = BT.SignalFrame()
  if keep and ChatFrame_AddChannel then ChatFrame_AddChannel(keep, name) end
  if not BT.FrameHasSignal(keep) then
    keep, keepIndex = _G.ChatFrame1, 1
    if keep and ChatFrame_AddChannel then ChatFrame_AddChannel(keep, name) end
  end
  BT.signalFrameIndex = keepIndex
  if ChatFrame_RemoveChannel then
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
      local f = _G["ChatFrame" .. i]
      if f and i ~= keepIndex then ChatFrame_RemoveChannel(f, name) end
    end
  end
end

-- Is our channel actually in this window's list? Without it, nothing is
-- displayed, and what is not displayed is not written to the log.
function BT.FrameHasSignal(frame)
  if not frame then return false end
  local name = BT.SignalChannel()
  if ChatFrame_ContainsChannel then
    return ChatFrame_ContainsChannel(frame, name) and true or false
  end
  -- older clients: read the window's own list
  local list = frame.channelList
  if type(list) ~= "table" then return true end   -- cannot tell; assume it took
  for _, c in ipairs(list) do
    if type(c) == "string" and c:lower() == name:lower() then return true end
  end
  return false
end

-- Where the marker ended up, for /chain testpush and the settings line
function BT.SignalWhere()
  if not ChainDB.logSignal then return nil end
  local i = BT.signalFrameIndex
  if not i then return nil end
  local f = _G["ChatFrame" .. i]
  local label = (f and f.name) or ("window " .. i)
  return label, i
end

-- The client does not write the chat log line by line: it buffers, and the
-- buffer can sit there for ten minutes. Measured on a live session - a marker
-- written at 18:57 reached the file at 19:00, which is no use at all when the
-- whole point is "he has reset it, get back in".
--
-- Closing the log flushes it, so the marker is pushed out by switching
-- logging off and straight back on a second after writing it. Rate-limited,
-- because every toggle is a moment where an arriving line could fall between
-- two file handles.
-- Measured on the live client: the file grows in exact 49,152-byte steps, so
-- the chat log is block-buffered and a marker can sit in memory for ten
-- minutes. Turning logging off and straight back on in the same frame did not
-- shift it - the client evidently defers the close - so the two halves are
-- put a few frames apart, which gives it a chance to actually close the file
-- and flush what is in the buffer.
local FLUSH_GAP = 5
function BT.FlushChatLog()
  if not LoggingChat then return end
  local now = time()
  if BT.lastFlush and now - BT.lastFlush < FLUSH_GAP then return end
  BT.lastFlush = now
  LoggingChat(false)
  local function back() LoggingChat(true) BT.chatLogArmed = true end
  if C_Timer and C_Timer.After then C_Timer.After(0.4, back) else back() end
end

-- The chat log is buffered in 48 KiB blocks and nothing flushes it, so a
-- marker written now can reach the disk ten minutes later. A screenshot does
-- not wait: the client writes the file the moment it is asked. So the alert
-- that has to be instant is a file appearing in the Screenshots folder - one
-- for a ready check, two in quick succession for a reset - and the watcher
-- outside counts them, sends the push, and deletes them again.
--
-- It costs a flash and a "Screenshot captured" line. That is the whole price,
-- and it is the only way to be told in seconds rather than minutes.
function BT.Snap(n)
  if not ChainDB.snapSignal then return end
  if not Screenshot then return end
  local now = time()
  if BT.lastSnap and now - BT.lastSnap < 8 then return end
  BT.lastSnap = now
  Screenshot()
  if (n or 1) > 1 and C_Timer and C_Timer.After then
    for i = 2, n do C_Timer.After((i - 1) * 0.8, function() Screenshot() end) end
  end
end

-- kind is a bare word the watcher matches on; text is for a human to read
function BT.Signal(kind, text)
  -- the screenshot alert stands on its own: it works with the chat marker
  -- switched off, and it is the one that arrives in seconds
  BT.Snap(kind == "reset" and 2 or 1)
  if not ChainDB.logSignal then return end
  BT.EnableSignal()
  local id = GetChannelName and GetChannelName(BT.SignalChannel()) or 0
  if id <= 0 or not SendChatMessage then return end
  SendChatMessage(SIGNAL_PREFIX .. " " .. kind .. " " .. (text or ""),
                  "CHANNEL", nil, id)

  -- out of the buffer and into the file, where the watcher can see it
  if C_Timer and C_Timer.After then C_Timer.After(1, BT.FlushChatLog)
  else BT.FlushChatLog() end
end

--------------------------------------------------------------------------
-- Run lifecycle
--------------------------------------------------------------------------
-- `partial` marks a run we only saw the tail of - you logged in or reloaded
-- while already inside. It is measured and shown but never stored, because
-- half a run would drag every average down.
function BT.StartRun(zone, partial, map)
  local c = ChainCharDB
  local by = BT.Booster()
  local avg, n = BT.GroupInfo()
  c.run = {
    zone = zone, map = map, id = BT.StepFor(map, zone), by = by,
    xp = 0, k = 0, start = time(), entrySeq = BT.NoteEntry(),
    lvl = UnitLevel("player"), grp = n, grpAvg = avg,
    partial = partial or nil
  }
  c.resetAt = nil
  BT.NoteInstance(UnitGUID and UnitGUID("target") or nil)
end

function BT.EndRun()
  local c = ChainCharDB
  local r = c.run
  c.run = nil
  if not r then return end
  c.lastEnd = time()
  if c.resetAt then
    -- you were told to get out, and you did: the advice has just flipped to
    -- "go back in", so say so with the other sound rather than in silence
    c.resetAt = time()
    if ChainDB.sound then Beep("in") end
  end
  if r.entrySeq and not r.instId and (r.k or 0) == 0 and (r.xp or 0) == 0 then
    -- never saw a single unit, so no evidence we were really in there
    BT.DropEntry(r.entrySeq)
  end
  if (r.xp or 0) <= 0 then return end
  if r.partial then return end

  local rec = {
    at = r.start, t = math.max(0, time() - (r.start or time())),
    zone = r.zone, map = r.map, id = r.id, by = r.by,
    xp = r.xp, k = r.k or 0,
    lvl = r.lvl, grp = r.grp, grpAvg = r.grpAvg,
    reentry = r.reentry or nil,
    char = UnitName("player")
  }
  table.insert(ChainDB.runs, rec)
  while #ChainDB.runs > K.MAX_RUNS do table.remove(ChainDB.runs, 1) end
  BT.Touch()
  if r.by then c.lastBy = r.by end
  BT.lastRecord = rec
end

-- Check the zone and start or stop a run
function BT.Sync(partial)
  local c = ChainCharDB
  BT.LearnXP()
  c.lastXP, c.lastMax = UnitXP("player"), UnitXPMax("player")
  local zone, map = BT.InDungeon()
  if zone then
    local r = c.run
    if not r or r.zone ~= zone then
      BT.EndRun()
      BT.StartRun(zone, partial, map)
    elseif not r.by then
      -- the booster may have invited us after we zoned in
      local by = BT.Booster()
      if by then r.by = by end
    end
    c.lastZone, c.lastMap = zone, map
  else
    BT.EndRun()
  end
end

-- How far the run in progress deviates from the usual. Returns pace, overtime
function BT.RunDeviation(st)
  local r = ChainCharDB.run
  if not r or not st then return nil end
  local el = time() - (r.start or time())
  if el < 30 then return nil end
  local over = el - (st.t or 0)
  local dev
  if (st.t or 0) > 0 and (st.xp or 0) > 0 then
    local usual = st.xp / st.t
    if usual > 0 then dev = ((r.xp or 0) / el) / usual - 1 end
  end
  return dev, over, el
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------
-- Level Tracker, then LevelBar, now Chain. Returns the name it took the data
-- from, or nil if there was nothing to take.
--
-- Called twice on purpose. The saved variables of an old name only exist as
-- globals once that addon's own file has been read, and WoW loads addons
-- alphabetically: Chain comes before LevelBar, so at our own ADDON_LOADED the
-- old data is not there yet. PLAYER_LOGIN fires after every addon is up,
-- which is the first moment the question can honestly be answered.
function BT.AdoptOldNames()
  local from
  local mine = ChainDB
  local empty = (not mine) or ((#(mine.runs or {}) == 0)
    and (#(mine.trades or {}) == 0) and (#(mine.entries or {}) == 0)
    and not next(mine.boosters or {}))
  if empty then
    local old, name
    if _G.LevelBarDB then old, name = _G.LevelBarDB, "LevelBar"
    elseif _G.LevelTrackerDB then old, name = _G.LevelTrackerDB, "Level Tracker" end
    -- only if the old one actually holds something; an empty old database is
    -- not worth trading a working new one for
    if old and ((#(old.runs or {}) > 0) or (#(old.trades or {}) > 0)
                or (#(old.entries or {}) > 0) or next(old.boosters or {})) then
      ChainDB, from = old, name
    elseif old and not mine then
      ChainDB = old
    end
  end
  if not ChainCharDB or not next(ChainCharDB) then
    ChainCharDB = _G.LevelBarCharDB or _G.LevelTrackerCharDB or ChainCharDB
  end
  return from
end

function BT.SayAdopted(from)
  if not from then return end
  print(BT.COL.info .. BT.NAME .. ":|r carried over "
    .. #(ChainDB.runs or {}) .. " runs, "
    .. #(ChainDB.trades or {}) .. " trades and "
    .. #(ChainDB.entries or {}) .. " instance entries from " .. from .. ".")
end

local EVENTS = {
  "PLAYER_LOGIN",
  "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
  "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
  "COMBAT_LOG_EVENT_UNFILTERED", "CHAT_MSG_COMBAT_XP_GAIN",
  "CHAT_MSG_SYSTEM", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
  "GROUP_ROSTER_UPDATE", "QUEST_LOG_UPDATE", "READY_CHECK",
  -- the honour system: the counter only moves on the server's terms, so we
  -- ask what the week total is on every event that could have changed it
  "CHAT_MSG_COMBAT_HONOR_GAIN", "PLAYER_PVP_KILLS_CHANGED",
  "PLAYER_PVP_RANK_CHANGED", "UPDATE_FACTION"
}

function BT.OnEvent(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name ~= ADDON then return end

    -- Level Tracker, then LevelBar, now Chain. A new name means new saved
    -- variables, and an empty history is not what anyone wants from a rename,
    -- so the most recent set we can find is adopted once and then left alone.
    -- The .toc still declares every old name, which is the only reason they
    -- are here to be read at all.
    BT.adopted = BT.AdoptOldNames()

    ChainDB = BT.ApplyDefaults(ChainDB or {}, BT.DEFAULTS)
    ChainCharDB = BT.ApplyDefaults(ChainCharDB or {}, BT.CHAR_DEFAULTS)
    if BT.adopted then
      BT.SayAdopted(BT.adopted)
      BT.adopted = nil
    end
    -- The price box used to store whatever you typed as a per-run price, and
    -- nobody sells single runs. Anything sitting at pack = 1 came from that
    -- bug, so put it back on the pack size it was quoted for.
    if not ChainDB.packFixed then
      ChainDB.packFixed = true
      local pack = ChainDB.pack or 1
      local n = 0
      if pack > 1 then
        for _, b in pairs(ChainDB.boosters) do
          if (b.price or 0) > 0 and (b.pack or 1) == 1 then
            b.pack = pack
            n = n + 1
          end
        end
      end
      if n > 0 then
        print(BT.COL.info .. BT.NAME .. ":|r " .. n .. " booster price"
          .. (n == 1 and "" or "s") .. " now read as the price for " .. pack
          .. " runs, not one.")
      end
    end

    -- Runs recorded before the instance-id work have no step on them, because
    -- the name they were filed under did not match the table. Give them one
    -- now rather than leaving that history stranded.
    local fixed = 0
    for _, r in ipairs(ChainDB.runs) do
      if not r.id then
        local list = BT.DungeonsFor(r.map, r.zone)
        if list and list[1] then r.id = list[1].id fixed = fixed + 1 end
      end
    end
    if fixed > 0 then
      BT.Touch()
      print(BT.COL.info .. BT.NAME .. ":|r matched " .. fixed
        .. " older run" .. (fixed == 1 and "" or "s") .. " to the right instance.")
    end
    -- entries used to live per character; the daily cap needs them pooled
    if ChainCharDB.entries then
      for _, e in ipairs(ChainCharDB.entries) do
        e.char = e.char or UnitName("player")
        e.seq = tostring(e.seq)
        table.insert(ChainDB.entries, e)
      end
      ChainCharDB.entries = nil
      table.sort(ChainDB.entries, function(a, b) return (a.t or 0) < (b.t or 0) end)
    end
    -- first run: pre-fill the route so the options are not an empty page
    if not ChainDB.seeded then
      ChainDB.seeded = true
      for _, d in ipairs(BT.DUNGEONS) do
        ChainDB.route[d.id] = ChainDB.route[d.id]
          or { on = false, from = d.lo, to = d.hi, gold = 0 }
      end
    end
    -- "Use Nova Instance Tracker" meant "read its log instead of ours", and
    -- it was on by default. It now means "trust its live count over ours",
    -- which is a different question and a much smaller one - so the old
    -- answer is not carried over as if it were an answer to the new one.
    if not ChainDB.nitReframed then
      ChainDB.nitReframed = true
      if ChainDB.useNIT then
        ChainDB.useNIT = false
        print(BT.COL.info .. BT.NAME .. ":|r the instance log is its own now - "
          .. "NIT's history has been copied into it and the count no longer "
          .. "comes from NIT. Settings has a switch if you want it back.")
      end
    end
    -- Take NIT's history into our own log, once per session. It is the only
    -- thing it has that we cannot see for ourselves, and once it is ours the
    -- addon keeps working the day NIT is uninstalled.
    if BT.ImportNIT then
      local added = BT.ImportNIT()
      if added > 0 then
        print(BT.COL.info .. BT.NAME .. ":|r took " .. added .. " instance entr"
          .. (added == 1 and "y" or "ies") .. " from Nova Instance Tracker "
          .. "into its own log. They are ours now - NIT is not needed for it.")
      end
    end
    -- first run on a character: the level has to have started sometime
    ChainCharDB.levelAt = ChainCharDB.levelAt or time()
    for _, e in ipairs(EVENTS) do frame:RegisterEvent(e) end
    if BT.InitUI then BT.InitUI() end
    if BT.InitOptions then BT.InitOptions() end
    -- the minimap exists by the time the addon loads, so the button can go
    -- straight on rather than waiting for the first frame
    if BT.RefreshMinimap then BT.RefreshMinimap() end
    return
  end

  if event == "PLAYER_LOGIN" then
    -- every addon is loaded by now, so the old saved variables are finally
    -- readable. This is the attempt that actually finds them.
    if BT.PollHonor then BT.PollHonor() end
    local from = BT.AdoptOldNames()
    if from then
      ChainDB = BT.ApplyDefaults(ChainDB or {}, BT.DEFAULTS)
      ChainCharDB = BT.ApplyDefaults(ChainCharDB or {}, BT.CHAR_DEFAULTS)
      BT.Touch()
      BT.SayAdopted(from)
      print(BT.COL.info .. BT.NAME .. ":|r you can turn the old addon off now - "
        .. "the history is Chain's.")
      if BT.Refresh then BT.Refresh() end
    end
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    -- This fires on every loading screen, not only at login: walking into the
    -- instance and walking back out both raise it. Throwing the run away here
    -- discarded it on the way out, one step before it would have been stored,
    -- so nothing ever reached the history.
    local isLogin, isReload = ...
    if isLogin or isReload then
      -- only here have we really missed the start of whatever is going on
      ChainCharDB.run = nil
      BT.Sync(true)
      -- a reload closes the chat log and drops the marker channel; both have
      -- to be put back or the phone goes quiet without saying so
      BT.chatLogArmed = nil
      if ChainDB.logSignal then
        if C_Timer and C_Timer.After then C_Timer.After(8, BT.EnableSignal)
        else BT.EnableSignal() end
      end
    else
      BT.Sync()
    end
    BT.ScanQuests()
  elseif event == "PLAYER_LEVEL_UP" or event == "PLAYER_XP_UPDATE" then
    if event == "PLAYER_LEVEL_UP" then ChainCharDB.levelAt = time() end
    -- both fire on a level; Delta() reads the bar so the second one is a
    -- no-op rather than a double count
    BT.LearnXP()
    local d = BT.Delta()
    if d > 0 then
      BT.AddXP(d)
      local r = ChainCharDB.run
      if r then
        r.xp = (r.xp or 0) + d
        if not r.instId and UnitGUID then BT.NoteInstance(UnitGUID("target")) end
      end
    end
    BT.ScanQuests()
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    -- This fires many times a second in a pull. We only want one thing from
    -- it - the instance id out of a nearby unit's GUID - and once we have it
    -- there is nothing left to do, so return before any redraw.
    local r = ChainCharDB.run
    local watching = ChainDB.watchEnemies and BT.NoteCombatLogUnit
    if (not r or r.instId) and not watching then return end
    if CombatLogGetCurrentEventInfo then
      local _, _, _, src, srcName, srcFlags, _, dst, dstName, dstFlags =
        CombatLogGetCurrentEventInfo()
      if r and not r.instId then
        BT.NoteInstance(src)
        if not r.instId then BT.NoteInstance(dst) end
      end
      -- the combat log reaches further than any nameplate: somebody casting
      -- two rooms away is in it
      if watching then
        BT.NoteCombatLogUnit(src, srcName, srcFlags)
        BT.NoteCombatLogUnit(dst, dstName, dstFlags)
      end
    end
    return
  elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
    local r = ChainCharDB.run
    if r then r.k = (r.k or 0) + 1 end
  elseif event == "CHAT_MSG_SYSTEM" then
    BT.NoteResetSystem(...)
  elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER"
      or event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
    local msg, sender = ...
    BT.NoteResetChat(msg, sender)
  elseif event == "READY_CHECK" then
    -- Blizzard's own popup and sound already handle this in the room. The only
    -- thing missing is that it never reaches your phone, so all we add is the
    -- marker line for the watcher script.
    local who = ...
    BT.readyCheckAt = time()
    BT.readyCheckBy = who and BT.ShortName(who) or nil
    BT.Signal("readycheck", (BT.readyCheckBy or "someone") .. " started a ready check")
  elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN"
      or event == "PLAYER_PVP_KILLS_CHANGED"
      or event == "PLAYER_PVP_RANK_CHANGED" or event == "UPDATE_FACTION" then
    if BT.PollHonor then BT.PollHonor() end
  elseif event == "QUEST_LOG_UPDATE" then
    BT.ScanQuests()
  else
    BT.Sync()
    BT.ScanQuests()
  end
  if BT.Refresh then BT.Refresh() end
  if BT.RenderWindow then BT.RenderWindow() end
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", BT.OnEvent)
